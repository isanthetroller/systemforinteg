<?php
/**
 * SecurePark - Shared writers for gate logs and security incidents
 * Used by verify.php (automatic denials) and the violations library.
 */

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/qr.php';
require_once __DIR__ . '/notices.php';

/**
 * Inserts a gate_logs row. $f keys: plate, vehicleType, ownerName, driverName,
 * driverRelationship, verifiedDriverName, gatePoint, action, gateType, status, notes.
 * Returns the new log id.
 */
function recordGateLog($pdo, $actor, array $f) {
    $gateType = $f['gateType'] ?? 'Ingress';
    $columns = ['plate_number', 'vehicle_type', 'owner_name', 'driver_name', 'driver_relationship', 'verified_driver_name',
        'gate_point', 'action', 'gate_type', 'status', 'guard_name', 'logged_by_user_id', 'notes', 'logged_at'];
    $values = [
        normalizePlateForLog($f['plate'] ?? 'UNKNOWN'),
        $f['vehicleType'] ?? null,
        $f['ownerName'] ?? null,
        $f['driverName'] ?? 'Unverified',
        $f['driverRelationship'] ?? 'Unverified',
        $f['verifiedDriverName'] ?? null,
        $f['gatePoint'] ?? defaultGatePoint($gateType),
        $f['action'],
        $gateType,
        $f['status'] ?? ($gateType === 'Egress' ? 'Exited' : 'Inside Campus'),
        gateActorLabel($actor),
        actorUserId($actor),
        $f['notes'] ?? '',
        $f['loggedAt'] ?? date('Y-m-d H:i:s'),
    ];
    // Offline sync / retries: the device's reference makes a resend harmless, syncedAt marks late arrivals
    if (!empty($f['clientRef'])) {
        $columns[] = 'client_ref';
        $values[] = $f['clientRef'];
    }
    if (!empty($f['syncedAt'])) {
        $columns[] = 'synced_at';
        $values[] = $f['syncedAt'];
    }
    $marks = implode(', ', array_fill(0, count($columns), '?'));
    $stmt = $pdo->prepare("INSERT INTO `gate_logs` (`" . implode('`, `', $columns) . "`) VALUES ({$marks})");
    $stmt->execute($values);
    return (int)$pdo->lastInsertId();
}

/**
 * Opens a 'Held' security incident. $f keys: plate, vehicleType, ownerName, ownerRole,
 * driverName, driverRelationship, reason, gatePoint, notes.
 * Set $dedupeMinutes to skip creating a duplicate Held case with the same plate + reason.
 * Returns ['id' => int, 'caseNumber' => string, 'duplicate' => bool].
 */
function openSecurityIncident($pdo, $actor, array $f, $dedupeMinutes = 0) {
    $plate = normalizePlateForLog($f['plate'] ?? 'UNKNOWN');
    $reason = $f['reason'] ?? 'Security Verification';

    if ($dedupeMinutes > 0) {
        $stmt = $pdo->prepare("SELECT `id`, `case_number` FROM `security_incidents`
            WHERE `plate_number` = ? AND `reason` = ? AND `status` = 'Held' AND `reported_at` >= ?
            ORDER BY `id` DESC LIMIT 1");
        $stmt->execute([$plate, $reason, date('Y-m-d H:i:s', time() - $dedupeMinutes * 60)]);
        if ($row = $stmt->fetch()) {
            return ['id' => (int)$row['id'], 'caseNumber' => $row['case_number'], 'duplicate' => true];
        }
    }

    $caseNumber = newCaseNumber($pdo);
    $extraColumns = !empty($f['clientRef']) ? ', `client_ref`' : '';
    $extraMarks = !empty($f['clientRef']) ? ', ?' : '';
    $stmt = $pdo->prepare("INSERT INTO `security_incidents` (
        `case_number`, `plate_number`, `vehicle_type`, `owner_name`, `owner_role`, `driver_name`,
        `driver_relationship`, `reason`, `gate_point`, `officer`, `logged_by_user_id`, `status`, `notes`, `reported_at`{$extraColumns}
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Held', ?, ?{$extraMarks})");
    $stmt->execute(array_merge([
        $caseNumber,
        $plate,
        $f['vehicleType'] ?? null,
        $f['ownerName'] ?? null,
        $f['ownerRole'] ?? null,
        $f['driverName'] ?? 'Unknown',
        $f['driverRelationship'] ?? null,
        $reason,
        $f['gatePoint'] ?? 'Gate 1 (Main Ingress)',
        gateActorLabel($actor),
        actorUserId($actor),
        $f['notes'] ?? '',
        $f['reportedAt'] ?? date('Y-m-d H:i:s'),
    ], !empty($f['clientRef']) ? [$f['clientRef']] : []));
    $incidentId = (int)$pdo->lastInsertId();
    // Callers that block a vehicle at the gate pass 'notifyOwner' => true; internal review cases and violation holds do not
    // (a violation sends its own notice).
    if (!empty($f['notifyOwner'])) {
        noticeVehicleBlocked($pdo, $f['plate'] ?? '', $reason, $f['gatePoint'] ?? 'Gate 1 (Main Ingress)', $caseNumber, $incidentId);
    }
    return ['id' => $incidentId, 'caseNumber' => $caseNumber, 'duplicate' => false];
}

/**
 * The refused passage (Entry / Exit Denied) that raised an incident, so the owner can play its gate clip.
 * Matched by plate within 10 minutes of the case being opened; null when the case was not raised at a gate.
 */
function incidentLogId($pdo, $r) {
    $at = strtotime($r['reported_at']);
    if (!$at) return null;
    $stmt = $pdo->prepare("SELECT `id` FROM `gate_logs`
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ?
          AND `action` IN ('Entry Denied', 'Exit Denied') AND `logged_at` BETWEEN ? AND ?
        ORDER BY `id` DESC LIMIT 1");
    $stmt->execute([normalizePlate($r['plate_number']), date('Y-m-d H:i:s', $at - 600), date('Y-m-d H:i:s', $at + 600)]);
    $id = $stmt->fetchColumn();
    return $id === false ? null : (int)$id;
}

function newCaseNumber($pdo) {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for ($attempt = 0; $attempt < 5; $attempt++) {
        $suffix = '';
        for ($i = 0; $i < 5; $i++) $suffix .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        $case = 'CASE-' . date('Ymd') . '-' . $suffix;
        $stmt = $pdo->prepare("SELECT 1 FROM `security_incidents` WHERE `case_number` = ?");
        $stmt->execute([$case]);
        if (!$stmt->fetch()) return $case;
    }
    return 'CASE-' . date('Ymd-His') . '-' . bin2hex(random_bytes(3));
}

function gateActorLabel($actor) {
    return !empty($actor['is_scanner']) ? 'Mobile Scanner' : actorLabel($actor);
}

function defaultGatePoint($gateType) {
    return $gateType === 'Egress' ? 'Gate 2 (Main Egress)' : 'Gate 1 (Main Ingress)';
}

function normalizePlateForLog($plate) {
    $plate = strtoupper(trim((string)$plate));
    return $plate === '' ? 'UNKNOWN' : substr($plate, 0, 20);
}

/**
 * The four gate actions a log may carry, and the mapping of legacy / free-text names onto them.
 */
function gateActions() {
    return ['Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied'];
}

function normalizeGateAction($action) {
    if (in_array($action, gateActions(), true)) return $action;
    $legacy = [
        'Flagged & Held' => 'Entry Denied',
        'Blocked' => 'Entry Denied',
        'Entry Blocked' => 'Entry Denied',
        'Exit Recorded' => 'Exit Approved',
    ];
    return $legacy[$action] ?? null;
}

/**
 * True when a table has the column. Lets code that depends on a newer migration degrade gracefully
 * (for example the live database before migration 006 has been run).
 */
function columnExists($pdo, $table, $column) {
    static $cache = [];
    $key = "{$table}.{$column}";
    if (isset($cache[$key])) return $cache[$key];
    try {
        if ($GLOBALS['db_driver'] === 'sqlite') {
            $found = false;
            foreach ($pdo->query("PRAGMA table_info(`{$table}`)")->fetchAll() as $c) {
                if ($c['name'] === $column) $found = true;
            }
        } else {
            $stmt = $pdo->prepare("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?");
            $stmt->execute([$table, $column]);
            $found = (int)$stmt->fetchColumn() > 0;
        }
    } catch (Exception $e) {
        $found = false;
    }
    return $cache[$key] = $found;
}
