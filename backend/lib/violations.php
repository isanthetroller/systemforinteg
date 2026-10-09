<?php
/**
 * SecurePark - Violations
 *
 * The ONLY place where violation holds and their resolution are decided.
 *
 * Rules (as in the traditional campus process; there are no warnings and no strike counter):
 *   - A Violation is issued to a registered vehicle by a guard or an administrator.
 *   - While a Violation is pending the vehicle is on HOLD: it cannot enter and it cannot leave
 *     campus (is_banned = 1, registration Suspended, a Held security incident is opened).
 *   - Only an administrator can resolve it (written notes required, e.g. "Cleared at the Security
 *     Office") or dismiss it (issued by mistake). When the vehicle has no other pending Violation,
 *     the hold is lifted and the registration restored.
 *   - VIP vehicles are exempt.
 *
 * Older databases may still hold 'Warning' rows from the retired strike system. They are history
 * only: they never block anything and are not listed.
 */

require_once __DIR__ . '/records.php';

function violationPresetTypes() {
    return [
        'Overnight / Unauthorized Overtime Parking',
        'Unauthorized Driver at Helm',
        'Expired Campus Registration Sticker',
        'Reckless / Prohibited Driving on Campus',
        'Parking in Fire Lane / Restricted Zone',
        'Refusal of Inspection / Gate Bypass',
        'Other',
    ];
}

function fetchViolation($pdo, $id) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicle_violations` WHERE `id` = ? AND `severity` = 'Violation' LIMIT 1");
    $stmt->execute([(int)$id]);
    return $stmt->fetch() ?: null;
}

function refetchVehicle($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ? LIMIT 1");
    $stmt->execute([(int)$vehicleId]);
    return $stmt->fetch();
}

function insertViolation($pdo, $actorLabel, $actorId, $vehicle, $type, $description, $incidentId = null) {
    $stmt = $pdo->prepare("INSERT INTO `vehicle_violations`
        (`vehicle_id`, `plate_number`, `violation_type`, `description`, `severity`, `logged_by`, `logged_by_user_id`,
         `status`, `counts_as_strike`, `incident_id`, `created_at`)
        VALUES (?, ?, ?, ?, 'Violation', ?, ?, 'Pending', 0, ?, ?)");
    $stmt->execute([
        $vehicle['id'], $vehicle['plate_number'], $type, $description,
        $actorLabel, $actorId, $incidentId, date('Y-m-d H:i:s', spNow()),
    ]);
    return (int)$pdo->lastInsertId();
}

/**
 * Puts the vehicle on hold and opens a Held incident. Returns the incident array.
 */
function holdVehicle($pdo, $actor, $vehicle, $reason, $notes) {
    $pdo->prepare("UPDATE `vehicles` SET `is_banned` = 1, `registration_status` = 'Suspended' WHERE `id` = ?")
        ->execute([$vehicle['id']]);
    return openSecurityIncident($pdo, $actor, [
        'plate' => $vehicle['plate_number'],
        'vehicleType' => $vehicle['vehicle_type'],
        'ownerName' => $vehicle['owner_name'],
        'ownerRole' => $vehicle['owner_role'],
        'driverName' => $vehicle['owner_name'],
        'driverRelationship' => 'Registered Owner',
        'reason' => $reason,
        'gatePoint' => $vehicle['last_gate_point'] ?: 'Campus Security Office',
        'notes' => $notes,
    ]);
}

/**
 * Issues a Violation: the vehicle is on hold (no entry, no exit) until it is resolved.
 */
function issueViolation($pdo, $actor, $vehicle, $type, $notes) {
    if (isVipVehicle($vehicle)) {
        throw new RuntimeException('VIP vehicles are exempt from violations.');
    }
    $label = gateActorLabel($actor);
    $incident = holdVehicle($pdo, $actor, $vehicle, $type, "Violation issued by {$label}: " . ($notes ?: $type));
    $id = insertViolation($pdo, $label, actorUserId($actor), $vehicle, $type, $notes, $incident['id']);
    queueOwnerNotice($pdo, $vehicle, 'Violation', "Violation: {$type}",
        "A violation was recorded against your vehicle {$vehicle['plate_number']}. Until it is resolved by the Security Office, the vehicle cannot enter or leave campus.
"
        . "Violation: {$type}
"
        . ($notes !== '' ? "Notes: {$notes}
" : '')
        . "Time: " . date('M j, Y g:i A', spNow()) . "
"
        . "Vehicle: " . trim(($vehicle['make_model_color'] ?: $vehicle['vehicle_type'])) . "
"
        . "Case number: " . ($incident['caseNumber'] ?? ('V' . $id)),
        ['violationId' => $id, 'incidentId' => $incident['id']]);
    return ['violationId' => $id, 'incident' => $incident];
}

function closeViolationRow($pdo, $id, $status, $admin, $notes) {
    $stmt = $pdo->prepare("UPDATE `vehicle_violations`
        SET `status` = ?, `resolved_at` = ?, `resolved_by` = ?, `resolution_notes` = ?
        WHERE `id` = ?");
    $stmt->execute([$status, date('Y-m-d H:i:s', spNow()), actorLabel($admin), $notes, $id]);
}

function closeIncident($pdo, $incidentId, $admin, $notes) {
    if (!$incidentId) return;
    $stmt = $pdo->prepare("SELECT `notes`, `status` FROM `security_incidents` WHERE `id` = ?");
    $stmt->execute([$incidentId]);
    $row = $stmt->fetch();
    if (!$row || $row['status'] !== 'Held') return;
    $entry = ' [Resolved by ' . actorLabel($admin) . ' on ' . date('Y-m-d H:i') . ": {$notes}]";
    $pdo->prepare("UPDATE `security_incidents` SET `status` = 'Resolved', `resolved_at` = ?, `notes` = ? WHERE `id` = ?")
        ->execute([date('Y-m-d H:i:s', spNow()), ($row['notes'] ?? '') . $entry, $incidentId]);
}

function pendingViolationCount($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM `vehicle_violations` WHERE `vehicle_id` = ? AND `severity` = 'Violation' AND `status` = 'Pending'");
    $stmt->execute([$vehicleId]);
    return (int)$stmt->fetchColumn();
}

/**
 * Lifts the hold and restores the registration.
 */
function liftHold($pdo, $vehicleId) {
    $pdo->prepare("UPDATE `vehicles` SET `is_banned` = 0, `registration_status` = 'Active',
        `status` = CASE WHEN `status` = 'Blocked / Alert' THEN 'Outside' ELSE `status` END WHERE `id` = ?")
        ->execute([$vehicleId]);
}

/**
 * Resolves a Violation (notes required). Lifts the hold when no other Violation is still pending.
 */
function resolveViolation($pdo, $admin, $violation, $notes) {
    closeViolationRow($pdo, $violation['id'], 'Resolved', $admin, $notes);
    closeIncident($pdo, $violation['incident_id'], $admin, $notes);
    $lifted = false;
    if (pendingViolationCount($pdo, $violation['vehicle_id']) === 0) {
        liftHold($pdo, $violation['vehicle_id']);
        $lifted = true;
    }
    return ['holdLifted' => $lifted];
}

/**
 * Dismisses a Violation issued by mistake. Lifts the hold when nothing else is pending.
 */
function dismissViolation($pdo, $admin, $violation, $notes) {
    closeViolationRow($pdo, $violation['id'], 'Dismissed', $admin, $notes);
    closeIncident($pdo, $violation['incident_id'], $admin, "Dismissed: {$notes}");
    $lifted = false;
    if (pendingViolationCount($pdo, $violation['vehicle_id']) === 0) {
        liftHold($pdo, $violation['vehicle_id']);
        $lifted = true;
    }
    return ['holdLifted' => $lifted];
}
