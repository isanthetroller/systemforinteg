<?php
/** Confirmation tickets bind a scan to a staff member and an exact shared-state snapshot. */
require_once __DIR__ . '/records.php';
require_once __DIR__ . '/vehicles.php';
require_once __DIR__ . '/releases.php';
require_once __DIR__ . '/campus.php';
require_once __DIR__ . '/gate_policy.php';

function movementRevision($pdo, $plate) {
    $s = $pdo->prepare("SELECT COALESCE(MAX(`id`), 0) FROM `gate_logs` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `action` IN ('Entry Recorded', 'Exit Approved')");
    $s->execute([normalizePlate($plate)]);
    return (int)$s->fetchColumn();
}

function movementCheckpoint($actor) {
    return trim((string)($actor['gate_assigned'] ?? '')) ?: 'Security checkpoint';
}

function movementInside($row, $type, $pdo = null) {
    if ($type === 'vehicle' && $pdo) return vehicleRecordedInside($pdo, $row);
    return $type === 'vehicle' ? $row['status'] === 'Inside Campus'
        : !empty($row['entry_time']) && empty($row['exit_time']);
}

function issueMovementTicket($pdo, $actor, $row, $type, $lookupMethod = 'qr', $checkpoint = null, $clientRef = null) {
    $inside = movementInside($row, $type, $pdo);
    $snapshot = [
        'v' => 1, 'actor' => (int)$actor['id'], 'type' => $type, 'id' => (int)$row['id'],
        'plate' => $row['plate_number'], 'inside' => $inside,
        'revision' => movementRevision($pdo, $row['plate_number']),
        'pass' => $type === 'vehicle' ? ($row['pass_id'] ?? '') : $row['pass_code'],
        'lookup' => $lookupMethod === 'manual' ? 'manual' : 'qr',
        'checkpoint' => gatePolicy($pdo, $actor, $checkpoint, $inside ? 'Egress' : 'Ingress')['checkpoint'], 'expires' => time() + 300,
        'ref' => $clientRef ?? ('mv-' . bin2hex(random_bytes(20))),
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
        lockGatePolicy($pdo);
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
            return movementResult($log, true, $row, $s['type'], $pdo);
        }
        $policy = gatePolicy($pdo, $actor, $s['checkpoint'], $s['inside'] ? 'Egress' : 'Ingress');
        if ($policy['checkpoint'] !== $s['checkpoint']) throw new MovementFailure(409, 'CHECKPOINT_CHANGED', 'Your assigned checkpoint changed. Scan again.');
        if ($error = gateDirectionError($policy, $s['inside'] ? 'Egress' : 'Ingress')) throw new MovementFailure(403, 'GATE_DIRECTION_DENIED', $error);
        if ($s['expires'] < time()) throw new MovementFailure(409, 'SCAN_EXPIRED', 'This scan has expired. Scan the pass again.');
        if (!$row) throw new MovementFailure(404, 'NOT_FOUND', 'This record is no longer available.');
        $inside = movementInside($row, $s['type'], $pdo);
        if ($inside !== $s['inside'] || movementRevision($pdo, $row['plate_number']) !== $s['revision'] || normalizePlate($row['plate_number']) !== normalizePlate($s['plate'])) {
            throw new MovementFailure(409, 'STALE_SCAN', 'Another transaction changed this vehicle. Scan the pass again to see its current status.');
        }
        $currentPass = $s['type'] === 'vehicle' ? ($row['pass_id'] ?? '') : $row['pass_code'];
        if ($currentPass !== $s['pass']) throw new MovementFailure(409, 'PASS_CHANGED', 'This pass was replaced. Scan the current pass.');
        $release = null;
        if ($s['type'] === 'vehicle' && $inside && vehicleIsOnHold($pdo, $row)) {
            $release = activeExitRelease($pdo, $row['id']);
        }
        $hold = $pdo->prepare("SELECT `id` FROM `security_incidents` WHERE (REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? OR `reason` LIKE ? OR `notes` LIKE ?) AND `status` = 'Held' LIMIT 1");
        $passMatch = $s['type'] === 'visitor' ? '%' . $row['pass_code'] . '%' : 'movement-no-visitor-pass';
        $hold->execute([normalizePlate($row['plate_number']), $passMatch, $passMatch]);
        if ($hold->fetchColumn() && !$release) throw new MovementFailure(403, 'SECURITY_HOLD', 'This vehicle is on a security hold. Contact an administrator.');
        $today = date('Y-m-d');
        $driverName = '';
        $relationship = '';
        $notes = 'Guard confirmed automatic ' . ($inside ? 'OUT' : 'IN') . ' movement';
        if ($s['type'] === 'vehicle') {
            if (!$release && ((int)$row['is_banned'] || $row['status'] === 'Blocked / Alert' || $row['registration_status'] !== 'Active')) {
                throw new MovementFailure(403, 'ACCESS_DENIED', 'The vehicle is blocked or its registration is inactive. Contact an administrator.');
            }
            if (!$inside && vehiclePassExpired($row, $today)) throw new MovementFailure(403, 'EXPIRED', 'This vehicle pass has expired.');
            if (!$inside && (int)($row['is_retired'] ?? 0)) throw new MovementFailure(403, 'RETIRED', 'This vehicle was retired. Register the current vehicle before entry.');
            if (!$inside && ($row['payment_status'] ?? 'Paid') === 'Unpaid') throw new MovementFailure(403, 'UNPAID', 'Pay the registration fee before entry.');
            if ($release) $notes .= ' | One-time exit release: ' . $release['reason'];
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
            validateVisitorMovement($pdo, $row, $inside ? 'Egress' : 'Ingress', $data);
            $items = visitorPassItems($pdo, $row['id']);
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
            'lookupMethod' => $s['lookup'] ?? 'qr',
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
        if ($release && !consumeExitRelease($pdo, $release, gateActorLabel($actor))) {
            throw new MovementFailure(409, 'RELEASE_USED', 'The exit release was already used. Scan the pass again.');
        }
        // Queue the notice in the same transaction, so a retry cannot omit or duplicate it.
        if ($s['type'] === 'vehicle') {
            noticeVehiclePassage($pdo, $row, $inside ? 'Egress' : 'Ingress', $s['checkpoint'], $driverName, $relationship, $at, gateActorLabel($actor), $id);
        }
        movementEnd($pdo, true);
        return movementResult($log, false);
    } catch (Throwable $e) {
        movementEnd($pdo, false);
        throw $e;
    }
}

/** Shared validation for all online visitor movement writers. */
function validateVisitorMovement($pdo, $pass, $direction, array $data) {
    $inside = !empty($pass['entry_time']) && empty($pass['exit_time']);
    if (($direction === 'Egress') !== $inside) throw new MovementFailure(409, 'VISITOR_STATE_MISMATCH', $direction === 'Egress' ? 'Visitor has no active entry. Check the movement records.' : 'Visitor is already inside campus.');
    $today = date('Y-m-d');
    if ($pass['status'] !== 'Active' || !empty($pass['exit_time']) || $pass['valid_date'] > $today || (!$inside && $pass['valid_date'] !== $today)) {
        throw new MovementFailure(403, 'VISITOR_PASS_INACTIVE', 'This visitor pass is not active for this movement.');
    }
    $q = $pdo->prepare("SELECT COUNT(*) FROM `security_incidents` WHERE `status` = 'Held' AND (REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? OR `reason` LIKE ? OR `notes` LIKE ?)");
    $q->execute([normalizePlate($pass['plate_number']), '%' . $pass['pass_code'] . '%', '%' . $pass['pass_code'] . '%']);
    if ($q->fetchColumn()) throw new MovementFailure(403, 'SECURITY_HOLD', 'This visitor has an unresolved security hold. Contact an administrator.');
    if (visitorPassItems($pdo, $pass['id']) && empty($data['items_verified'])) throw new MovementFailure(400, 'ITEMS_CHECK_REQUIRED', 'Check every declared item before confirming.');
}

/** Legacy transport now uses the same transaction and checks as the signed scanner. */
function confirmVisitorCheckout($pdo, $actor, array $data) {
    $code = trim((string)($data['passId'] ?? $data['pass_code'] ?? ''));
    $plate = trim((string)($data['plateNumber'] ?? $data['plate'] ?? ''));
    if ($code === '' && $plate === '') throw new MovementFailure(400, 'PASS_REQUIRED', 'Provide a visitor pass or plate.');
    $q = $pdo->prepare($code !== '' ? "SELECT * FROM `visitor_passes` WHERE `pass_code` = ? LIMIT 1"
        : "SELECT * FROM `visitor_passes` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? ORDER BY `id` DESC LIMIT 1");
    $q->execute([$code !== '' ? $code : normalizePlate($plate)]);
    $pass = $q->fetch();
    if (!$pass) throw new MovementFailure(404, 'NOT_FOUND', 'Visitor pass not found.');
    if ($plate !== '' && normalizePlate($plate) !== normalizePlate($pass['plate_number'])) throw new MovementFailure(400, 'PLATE_MISMATCH', 'The plate does not match this visitor pass.');
    if (empty($pass['entry_time'])) throw new MovementFailure(409, 'VISITOR_STATE_MISMATCH', 'Visitor has no recorded entry. Check the movement records.');
    $ticket = issueMovementTicket($pdo, $actor, $pass, 'visitor', 'manual', $data['checkpoint'] ?? $data['gatePoint'] ?? 'Gate 2', 'visitor-exit-' . $pass['id']);
    if (!empty($pass['exit_time'])) {
        $q = $pdo->prepare("SELECT `id` FROM `gate_logs` WHERE `client_ref` = ?");
        $q->execute(['visitor-exit-' . $pass['id']]);
        if (!$q->fetchColumn()) throw new MovementFailure(409, 'VISITOR_ALREADY_EXITED', 'This visitor already exited. Review its existing gate record.');
    }
    $result = confirmMovement($pdo, $actor, ['ticket' => $ticket['ticket'], 'items_verified' => $data['items_verified'] ?? false]);
    return $result + ['passId' => $pass['pass_code'], 'exitTime' => $result['loggedAt'], 'status' => 'Revoked'];
}

function movementResult($log, $duplicate, $row = null, $type = 'vehicle', $pdo = null) {
    $out = $log['action'] === 'Exit Approved';
    $recordedStatus = $out ? 'OUTSIDE' : 'INSIDE';
    $currentStatus = $row ? (movementInside($row, $type, $pdo) ? 'INSIDE' : 'OUTSIDE') : $recordedStatus;
    return ['id' => (int)$log['id'], 'duplicate' => $duplicate, 'plateNumber' => $log['plate_number'],
        'action' => $out ? 'OUT' : 'IN', 'currentStatus' => $currentStatus, 'recordedStatus' => $recordedStatus,
        'checkpoint' => $log['gate_point'], 'guardName' => $log['guard_name'], 'loggedAt' => $log['logged_at']];
}
