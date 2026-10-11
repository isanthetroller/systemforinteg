<?php
/** Physical custody and access restrictions are separate facts. */
require_once __DIR__ . '/campus.php';

function vehicleStanding($pdo, $vehicle) {
    $inside = vehicleRecordedInside($pdo, $vehicle);
    $q = $pdo->prepare("SELECT COUNT(*) FROM `security_incidents` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `status` = 'Held'");
    $q->execute([normalizePlate($vehicle['plate_number'])]);
    $incidents = (int)$q->fetchColumn();
    $q = $pdo->prepare("SELECT COUNT(*) FROM `vehicle_violations` WHERE `vehicle_id` = ? AND `severity` = 'Violation' AND `status` = 'Pending'");
    $q->execute([$vehicle['id']]);
    $violations = (int)$q->fetchColumn();
    $held = $incidents > 0 || $violations > 0 || !empty($vehicle['is_banned']) || $vehicle['status'] === 'Blocked / Alert';
    $entry = [];
    if ($held) $entry[] = 'Unresolved security hold';
    if (($vehicle['registration_status'] ?? 'Active') !== 'Active') $entry[] = 'Registration inactive';
    $exit = $entry;
    if (!empty($vehicle['is_retired'])) $entry[] = 'Vehicle retired';
    if (($vehicle['payment_status'] ?? 'Paid') === 'Unpaid') $entry[] = 'Registration fee unpaid';
    if (vehiclePassExpired($vehicle, date('Y-m-d'))) $entry[] = 'Pass expired';
    $q = $pdo->prepare("SELECT `expires_at` FROM `exit_releases` WHERE `vehicle_id` = ? AND `used_at` IS NULL AND `expires_at` > ? ORDER BY `id` DESC LIMIT 1");
    $q->execute([$vehicle['id'], date('Y-m-d H:i:s')]);
    $release = $inside && $held ? ($q->fetchColumn() ?: null) : null;
    if ($release) $exit = [];
    return ['isInside' => $inside, 'onHold' => $held, 'pendingViolations' => $violations,
        'heldIncidents' => $incidents, 'entryBlockers' => $entry, 'exitBlockers' => $exit,
        'releaseEligible' => $inside && $held, 'exitReleaseExpiresAt' => $release];
}

/** Convert a legacy standing label back to its physical state, without inventing a passage. */
function restoreVehiclePresence($pdo, $vehicle) {
    if ($vehicle['status'] !== 'Blocked / Alert') return;
    $state = vehicleRecordedInside($pdo, $vehicle) ? 'Inside Campus' : 'Outside';
    $pdo->prepare("UPDATE `vehicles` SET `status` = ? WHERE `id` = ?")->execute([$state, $vehicle['id']]);
}

function caseStandingMessage($pdo, $plate) {
    $q = $pdo->prepare("SELECT * FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? ORDER BY `is_retired`, `id` DESC LIMIT 1");
    $q->execute([normalizePlate($plate)]);
    if ($vehicle = $q->fetch()) {
        $standing = vehicleStanding($pdo, $vehicle);
        $blockers = array_values(array_unique(array_merge($standing['entryBlockers'], $standing['exitBlockers'])));
        return $blockers ? 'Remaining restrictions: ' . implode('; ', $blockers) . '. Check the pass before passage.'
            : 'No remaining registration or case restrictions. The guard must still verify the pass, driver and gate direction.';
    }
    $q = $pdo->prepare("SELECT COUNT(*) FROM `security_incidents` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `status` = 'Held'");
    $q->execute([normalizePlate($plate)]);
    return (int)$q->fetchColumn() > 0 ? 'Another security hold remains. Contact the Security Office.'
        : 'Check the current visitor pass before passage; closing a case does not reactivate a revoked or completed pass.';
}
