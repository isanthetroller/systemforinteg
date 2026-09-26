<?php
/**
 * SecurePark - Violations & 3-Strike Engine
 *
 * The ONLY place where strikes, bans and their resolution are decided.
 *
 * Rules (agreed with the security office):
 *   - Every Warning (manual or overnight detection) is one strike.
 *   - The 3rd strike automatically creates a Violation "3-Strike Policy Enforced",
 *     bans the vehicle (is_banned = 1, registration Suspended) and opens a Held incident.
 *   - A manually issued Violation (e.g. reckless driving) bans the vehicle immediately.
 *   - Resolving a Violation needs written notes. When the vehicle has no other pending
 *     Violation, the ban is lifted, registration restored and strikes reset to 0
 *     (the pending strike warnings are marked "Cleared by violation #X").
 *   - Dismissing (issued by mistake) removes a warning's strike / lifts a violation's ban.
 *   - "Reset Strikes & Lift Suspension" clears everything for a vehicle at once.
 */

require_once __DIR__ . '/records.php';

const SP_STRIKE_LIMIT = 3;
const SP_STRIKE_VIOLATION_TYPE = '3-Strike Policy Enforced';

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
    $stmt = $pdo->prepare("SELECT * FROM `vehicle_violations` WHERE `id` = ? LIMIT 1");
    $stmt->execute([(int)$id]);
    return $stmt->fetch() ?: null;
}

function refetchVehicle($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ? LIMIT 1");
    $stmt->execute([(int)$vehicleId]);
    return $stmt->fetch();
}

function insertViolation($pdo, $actorLabel, $actorId, $vehicle, $type, $description, $severity, $countsAsStrike, $incidentId = null) {
    $stmt = $pdo->prepare("INSERT INTO `vehicle_violations`
        (`vehicle_id`, `plate_number`, `violation_type`, `description`, `severity`, `logged_by`, `logged_by_user_id`,
         `status`, `counts_as_strike`, `incident_id`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?, ?, ?)");
    $stmt->execute([
        $vehicle['id'], $vehicle['plate_number'], $type, $description, $severity,
        $actorLabel, $actorId, $countsAsStrike ? 1 : 0, $incidentId, date('Y-m-d H:i:s', spNow()),
    ]);
    return (int)$pdo->lastInsertId();
}

/**
 * Bans the vehicle and opens a Held incident. Returns the incident array.
 */
function banVehicle($pdo, $actor, $vehicle, $reason, $notes) {
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
 * Records a Warning (one strike). On the 3rd strike the vehicle is banned automatically.
 * Returns ['violationId', 'strikes', 'banned', 'autoViolationId', 'incident'].
 */
function addWarning($pdo, $actor, $vehicle, $type, $notes) {
    $label = gateActorLabel($actor);
    $warningId = insertViolation($pdo, $label, actorUserId($actor), $vehicle, $type, $notes, 'Warning', true);

    $pdo->prepare("UPDATE `vehicles` SET `warning_count` = `warning_count` + 1 WHERE `id` = ?")->execute([$vehicle['id']]);
    $vehicle = refetchVehicle($pdo, $vehicle['id']);
    $strikes = (int)$vehicle['warning_count'];

    $autoId = null;
    $incident = null;
    if ($strikes >= SP_STRIKE_LIMIT && (int)$vehicle['is_banned'] === 0) {
        $system = ['id' => null, 'full_name' => 'System (3-Strike Policy)', 'badge_number' => null];
        $summary = "Strike {$strikes} of " . SP_STRIKE_LIMIT . " reached (latest: {$type}). Gate access blocked until an administrator resolves this violation.";
        $incident = banVehicle($pdo, $system, $vehicle, SP_STRIKE_VIOLATION_TYPE, $summary);
        $autoId = insertViolation($pdo, 'System (3-Strike Policy)', null, $vehicle, SP_STRIKE_VIOLATION_TYPE, $summary, 'Violation', false, $incident['id']);
    }

    return [
        'violationId' => $warningId,
        'strikes' => $strikes,
        'banned' => $autoId !== null || (int)$vehicle['is_banned'] === 1,
        'autoViolationId' => $autoId,
        'incident' => $incident,
    ];
}

/**
 * Records a manual Violation: immediate ban + Held incident.
 */
function issueViolation($pdo, $actor, $vehicle, $type, $notes) {
    $label = gateActorLabel($actor);
    $incident = banVehicle($pdo, $actor, $vehicle, $type, "Violation issued by {$label}: " . ($notes ?: $type));
    $id = insertViolation($pdo, $label, actorUserId($actor), $vehicle, $type, $notes, 'Violation', false, $incident['id']);
    $vehicle = refetchVehicle($pdo, $vehicle['id']);
    return [
        'violationId' => $id,
        'strikes' => (int)$vehicle['warning_count'],
        'banned' => true,
        'autoViolationId' => null,
        'incident' => $incident,
    ];
}

function closeViolationRow($pdo, $id, $status, $admin, $notes, $clearedBy = null) {
    $stmt = $pdo->prepare("UPDATE `vehicle_violations`
        SET `status` = ?, `resolved_at` = ?, `resolved_by` = ?, `resolution_notes` = ?, `cleared_by_violation_id` = ?
        WHERE `id` = ?");
    $stmt->execute([$status, date('Y-m-d H:i:s', spNow()), actorLabel($admin), $notes, $clearedBy, $id]);
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
 * Lifts the ban and restores registration. When $resetStrikes, pending strike
 * warnings are cleared and the counter goes back to 0.
 */
function liftBan($pdo, $admin, $vehicleId, $notes, $resetStrikes, $clearedByViolationId = null) {
    if ($resetStrikes) {
        $stmt = $pdo->prepare("SELECT `id` FROM `vehicle_violations` WHERE `vehicle_id` = ? AND `severity` = 'Warning' AND `status` = 'Pending'");
        $stmt->execute([$vehicleId]);
        $clearNote = $clearedByViolationId ? "Cleared by violation #{$clearedByViolationId}: {$notes}" : "Cleared by strike reset: {$notes}";
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $wid) {
            closeViolationRow($pdo, $wid, 'Resolved', $admin, $clearNote, $clearedByViolationId);
        }
        $pdo->prepare("UPDATE `vehicles` SET `warning_count` = 0 WHERE `id` = ?")->execute([$vehicleId]);
    }
    $pdo->prepare("UPDATE `vehicles` SET `is_banned` = 0, `registration_status` = 'Active',
        `status` = CASE WHEN `status` = 'Blocked / Alert' THEN 'Outside' ELSE `status` END WHERE `id` = ?")
        ->execute([$vehicleId]);
}

/**
 * Resolves a Violation (notes required). Lifts the ban and resets strikes when no
 * other Violation is still pending for the vehicle.
 */
function resolveViolation($pdo, $admin, $violation, $notes) {
    closeViolationRow($pdo, $violation['id'], 'Resolved', $admin, $notes);
    closeIncident($pdo, $violation['incident_id'], $admin, $notes);
    $lifted = false;
    if (pendingViolationCount($pdo, $violation['vehicle_id']) === 0) {
        liftBan($pdo, $admin, $violation['vehicle_id'], $notes, true, $violation['id']);
        $lifted = true;
    }
    return ['banLifted' => $lifted];
}

/**
 * Dismisses a record issued by mistake. A pending strike warning gives its strike back;
 * a dismissed violation lifts the ban (strikes are kept) if nothing else is pending.
 */
function dismissViolation($pdo, $admin, $violation, $notes) {
    closeViolationRow($pdo, $violation['id'], 'Dismissed', $admin, $notes);
    $lifted = false;
    if ($violation['severity'] === 'Warning') {
        if ((int)$violation['counts_as_strike'] === 1) {
            $pdo->prepare("UPDATE `vehicles` SET `warning_count` = CASE WHEN `warning_count` > 0 THEN `warning_count` - 1 ELSE 0 END WHERE `id` = ?")
                ->execute([$violation['vehicle_id']]);
        }
    } else {
        closeIncident($pdo, $violation['incident_id'], $admin, "Dismissed: {$notes}");
        if (pendingViolationCount($pdo, $violation['vehicle_id']) === 0) {
            liftBan($pdo, $admin, $violation['vehicle_id'], $notes, false);
            $lifted = true;
        }
    }
    return ['banLifted' => $lifted];
}

/**
 * "Reset Strikes & Lift Suspension": resolves every pending record of the vehicle.
 */
function resetStrikes($pdo, $admin, $vehicle, $notes) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicle_violations` WHERE `vehicle_id` = ? AND `severity` = 'Violation' AND `status` = 'Pending'");
    $stmt->execute([$vehicle['id']]);
    foreach ($stmt->fetchAll() as $v) {
        closeViolationRow($pdo, $v['id'], 'Resolved', $admin, "Strike reset: {$notes}");
        closeIncident($pdo, $v['incident_id'], $admin, "Strike reset: {$notes}");
    }
    liftBan($pdo, $admin, $vehicle['id'], $notes, true);
    return ['banLifted' => true];
}
