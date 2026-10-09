<?php
/** Confirmation tickets bind a scan to a staff member and an exact shared-state snapshot. */
require_once __DIR__ . '/records.php';
require_once __DIR__ . '/vehicles.php';

function movementRevision($pdo, $plate) {
    $s = $pdo->prepare("SELECT COALESCE(MAX(`id`), 0) FROM `gate_logs` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `action` IN ('Entry Recorded', 'Exit Approved')");
    $s->execute([normalizePlate($plate)]);
    return (int)$s->fetchColumn();
}

function movementCheckpoint($actor) {
    return trim((string)($actor['gate_assigned'] ?? '')) ?: 'Security checkpoint';
}

function movementInside($row, $type) {
    return $type === 'vehicle' ? $row['status'] === 'Inside Campus'
        : !empty($row['entry_time']) && empty($row['exit_time']);
}

function issueMovementTicket($pdo, $actor, $row, $type) {
    $inside = movementInside($row, $type);
    $snapshot = [
        'v' => 1, 'actor' => (int)$actor['id'], 'type' => $type, 'id' => (int)$row['id'],
        'plate' => $row['plate_number'], 'inside' => $inside,
        'revision' => movementRevision($pdo, $row['plate_number']),
        'pass' => $type === 'vehicle' ? ($row['pass_id'] ?? '') : $row['pass_code'],
        'checkpoint' => movementCheckpoint($actor), 'expires' => time() + 300,
        'ref' => 'mv-' . bin2hex(random_bytes(20)),
    ];
    $encoded = rtrim(strtr(base64_encode(json_encode($snapshot)), '+/', '-_'), '=');
    $ticket = $encoded . '.' . hash_hmac('sha256', 'movement:' . $encoded, SP_QR_SECRET);
    return ['ticket' => $ticket, 'clientRef' => $snapshot['ref'], 'currentStatus' => $inside ? 'INSIDE' : 'OUTSIDE',
        'suggestedAction' => $inside ? 'OUT' : 'IN', 'checkpoint' => $snapshot['checkpoint'],
        'expiresAt' => $snapshot['expires']];
}

class MovementFailure extends RuntimeException {
    public $httpStatus;
    public $errorCode;
    public function __construct($status, $code, $message) {
        parent::__construct($message);
        $this->httpStatus = $status;
        $this->errorCode = $code;
    }
}

function readMovementTicket($ticket, $actor) {
    $parts = explode('.', (string)$ticket);
    if (count($parts) !== 2 || !hash_equals(hash_hmac('sha256', 'movement:' . $parts[0], SP_QR_SECRET), $parts[1])) {
        throw new MovementFailure(400, 'INVALID_CONFIRMATION', 'This confirmation is invalid. Scan the pass again.');
    }
    $s = json_decode(base64_decode(strtr($parts[0], '-_', '+/'), true), true);
    if (!is_array($s) || ($s['v'] ?? null) !== 1 || !in_array($s['type'] ?? '', ['vehicle', 'visitor'], true)) {
        throw new MovementFailure(400, 'INVALID_CONFIRMATION', 'Scan the pass again.');
    }
    if ((int)$s['actor'] !== (int)$actor['id']) {
        throw new MovementFailure(403, 'WRONG_GUARD', 'This scan belongs to another guard. Scan the pass with your own account.');
    }
    return $s;
}

/** PDO does not track transactions started with SQLite BEGIN IMMEDIATE. */
function movementBegin($pdo) {
    if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite') {
        $pdo->exec('PRAGMA busy_timeout = 5000');
        $pdo->exec('BEGIN IMMEDIATE');
    } else {
        $pdo->exec('SET TRANSACTION ISOLATION LEVEL READ COMMITTED');
        $pdo->beginTransaction();
    }
}
function movementEnd($pdo, $commit) {
    if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite') $pdo->exec($commit ? 'COMMIT' : 'ROLLBACK');
    elseif ($pdo->inTransaction()) $commit ? $pdo->commit() : $pdo->rollBack();
}

function confirmMovement($pdo, $actor, array $data) {
    $s = readMovementTicket($data['ticket'] ?? '', $actor);
    if (!columnExists($pdo, 'gate_logs', 'client_ref')) {
        throw new MovementFailure(503, 'MIGRATION_REQUIRED', 'The server needs the existing offline-sync migration before confirmations can be saved.');
    }
    movementBegin($pdo);
    try {
        $table = $s['type'] === 'vehicle' ? 'vehicles' : 'visitor_passes';
        $lock = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql' ? ' FOR UPDATE' : '';
        $q = $pdo->prepare("SELECT * FROM `{$table}` WHERE `id` = ?" . $lock);
        $q->execute([$s['id']]);
        $row = $q->fetch();
        // Retry detection precedes expiry/state checks: a lost reply must not create another movement.
        $dup = $pdo->prepare("SELECT * FROM `gate_logs` WHERE `client_ref` = ?");
        $dup->execute([$s['ref']]);
        if ($log = $dup->fetch()) {
            movementEnd($pdo, true);
            return movementResult($log, true, $row, $s['type']);
        }
        if ($s['expires'] < time()) throw new MovementFailure(409, 'SCAN_EXPIRED', 'This scan has expired. Scan the pass again.');
        if (!$row) throw new MovementFailure(404, 'NOT_FOUND', 'This record is no longer available.');
        $inside = movementInside($row, $s['type']);
        if ($inside !== $s['inside'] || movementRevision($pdo, $row['plate_number']) !== $s['revision'] || normalizePlate($row['plate_number']) !== normalizePlate($s['plate'])) {
            throw new MovementFailure(409, 'STALE_SCAN', 'Another transaction changed this vehicle. Scan the pass again to see its current status.');
        }
        $currentPass = $s['type'] === 'vehicle' ? ($row['pass_id'] ?? '') : $row['pass_code'];
        if ($currentPass !== $s['pass']) throw new MovementFailure(409, 'PASS_CHANGED', 'This pass was replaced. Scan the current pass.');
        $hold = $pdo->prepare("SELECT `id` FROM `security_incidents` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `status` = 'Held' LIMIT 1");
        $hold->execute([normalizePlate($row['plate_number'])]);
        if ($hold->fetchColumn()) throw new MovementFailure(403, 'SECURITY_HOLD', 'This vehicle is on a security hold. Contact an administrator.');
        $today = date('Y-m-d');
        $driverName = '';
        $relationship = '';
        $notes = 'Guard confirmed automatic ' . ($inside ? 'OUT' : 'IN') . ' movement';
        if ($s['type'] === 'vehicle') {
            if ((int)$row['is_banned'] || $row['status'] === 'Blocked / Alert' || $row['registration_status'] !== 'Active') {
                throw new MovementFailure(403, 'ACCESS_DENIED', 'The vehicle is blocked or its registration is inactive. Contact an administrator.');
            }
            if (!empty($row['pass_valid_until']) && $row['pass_valid_until'] < $today) throw new MovementFailure(403, 'EXPIRED', 'This vehicle pass has expired.');
            if (isVipVehicle($row)) {
                $driverName = $row['owner_name'];
                $relationship = 'VIP (driver not checked)';
                $notes .= ' | VIP pass';
            } else {
                $driver = $pdo->prepare("SELECT * FROM `authorized_drivers` WHERE `id` = ? AND `vehicle_id` = ?");
                $driver->execute([(int)($data['driver_id'] ?? 0), $row['id']]);
                $d = $driver->fetch();
                if (!$d) throw new MovementFailure(400, 'DRIVER_CONFIRMATION_REQUIRED', 'Select an authorized driver before confirming.');
                $driverName = $d['full_name'];
                $relationship = $d['relationship'];
            }
        } else {
            if ($row['status'] !== 'Active' || !empty($row['exit_time']) || $row['valid_date'] > $today || (!$inside && $row['valid_date'] !== $today)) {
                throw new MovementFailure(403, 'VISITOR_PASS_INACTIVE', 'This visitor pass is not active for this movement.');
            }
            $items = visitorPassItems($pdo, $row['id']);
            if ($items && empty($data['items_verified'])) throw new MovementFailure(400, 'ITEMS_CHECK_REQUIRED', 'Check every declared item before confirming.');
            if ($items) $notes .= ' | Items checked ' . ($inside ? 'out: ' : 'in: ') . visitorItemsSummary($items);
            $driverName = $row['visitor_name'];
            $relationship = 'Visitor (Day Pass)';
        }
        $at = date('Y-m-d H:i:s');
        $id = recordGateLog($pdo, $actor, [
            'plate' => $row['plate_number'], 'vehicleType' => $row['vehicle_type'] ?? 'Visitor Vehicle',
            'ownerName' => $row['owner_name'] ?? $row['visitor_name'], 'driverName' => $driverName,
            'driverRelationship' => $relationship, 'verifiedDriverName' => $relationship === 'VIP (driver not checked)' ? null : $driverName,
            'gatePoint' => $s['checkpoint'], 'action' => $inside ? 'Exit Approved' : 'Entry Recorded',
            'gateType' => $inside ? 'Egress' : 'Ingress', 'status' => $inside ? 'Exited' : 'Inside Campus',
            'notes' => $notes, 'clientRef' => $s['ref'], 'loggedAt' => $at,
        ]);
        if ($s['type'] === 'vehicle') {
            $update = $pdo->prepare("UPDATE `vehicles` SET `status` = ?, `last_gate_point` = ?, `last_entry_time` = CASE WHEN ? = 1 THEN `last_entry_time` ELSE ? END WHERE `id` = ?");
            $update->execute([$inside ? 'Outside' : 'Inside Campus', $s['checkpoint'], $inside ? 1 : 0, $at, $row['id']]);
        } elseif ($inside) {
            $pdo->prepare("UPDATE `visitor_passes` SET `exit_time` = ?, `status` = 'Revoked' WHERE `id` = ?")->execute([$at, $row['id']]);
        } else {
            $pdo->prepare("UPDATE `visitor_passes` SET `entry_time` = ? WHERE `id` = ?")->execute([$at, $row['id']]);
        }
        $q = $pdo->prepare("SELECT * FROM `gate_logs` WHERE `id` = ?");
        $q->execute([$id]);
        $log = $q->fetch();
        movementEnd($pdo, true);
        return movementResult($log, false);
    } catch (Throwable $e) {
        movementEnd($pdo, false);
        throw $e;
    }
}

function movementResult($log, $duplicate, $row = null, $type = 'vehicle') {
    $out = $log['action'] === 'Exit Approved';
    $recordedStatus = $out ? 'OUTSIDE' : 'INSIDE';
    $currentStatus = $row ? (movementInside($row, $type) ? 'INSIDE' : 'OUTSIDE') : $recordedStatus;
    return ['id' => (int)$log['id'], 'duplicate' => $duplicate, 'plateNumber' => $log['plate_number'],
        'action' => $out ? 'OUT' : 'IN', 'currentStatus' => $currentStatus, 'recordedStatus' => $recordedStatus,
        'checkpoint' => $log['gate_point'], 'guardName' => $log['guard_name'], 'loggedAt' => $log['logged_at']];
}
