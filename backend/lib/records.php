<?php
/**
 * SecurePark - Shared writers for gate logs and security incidents
 * Used by verify.php (automatic denials) and the violations / strike engine.
 */

require_once __DIR__ . '/auth.php';

/**
 * Inserts a gate_logs row. $f keys: plate, vehicleType, ownerName, driverName,
 * driverRelationship, verifiedDriverName, gatePoint, action, gateType, status, notes.
 * Returns the new log id.
 */
function recordGateLog($pdo, $actor, array $f) {
    $gateType = $f['gateType'] ?? 'Ingress';
    $stmt = $pdo->prepare("INSERT INTO `gate_logs` (
        `plate_number`, `vehicle_type`, `owner_name`, `driver_name`, `driver_relationship`, `verified_driver_name`,
        `gate_point`, `action`, `gate_type`, `status`, `guard_name`, `logged_by_user_id`, `notes`, `logged_at`
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([
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
        date('Y-m-d H:i:s'),
    ]);
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
    $stmt = $pdo->prepare("INSERT INTO `security_incidents` (
        `case_number`, `plate_number`, `vehicle_type`, `owner_name`, `owner_role`, `driver_name`,
        `driver_relationship`, `reason`, `gate_point`, `officer`, `logged_by_user_id`, `status`, `notes`, `reported_at`
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Held', ?, ?)");
    $stmt->execute([
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
        date('Y-m-d H:i:s'),
    ]);
    return ['id' => (int)$pdo->lastInsertId(), 'caseNumber' => $caseNumber, 'duplicate' => false];
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
