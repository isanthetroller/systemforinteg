<?php
/**
 * SecurePark - One-time exit release for a vehicle on hold
 *
 * A vehicle with an unresolved violation cannot leave campus. If someone is stuck inside (an emergency, a guard's
 * mistake), an ADMINISTRATOR can release ONE exit with a written reason. The release expires after
 * `exit_release_minutes` (default 30) and works once; the vehicle stays on hold afterwards and cannot come back in.
 * Everything is logged.
 */

require_once __DIR__ . '/violations.php';
require_once __DIR__ . '/settings.php';
require_once __DIR__ . '/audit.php';

function activeExitRelease($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT * FROM `exit_releases` WHERE `vehicle_id` = ? AND `used_at` IS NULL AND `expires_at` > ? ORDER BY `id` DESC LIMIT 1");
    $stmt->execute([(int)$vehicleId, date('Y-m-d H:i:s')]);
    return $stmt->fetch() ?: null;
}

function vehicleIsOnHold($pdo, $vehicle) {
    if ((int)$vehicle['is_banned'] === 1 || $vehicle['status'] === 'Blocked / Alert') return true;
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM `security_incidents` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `status` = 'Held'");
    $stmt->execute([normalizePlate($vehicle['plate_number'])]);
    return (int)$stmt->fetchColumn() > 0;
}

function createExitRelease($pdo, $admin, $vehicle, $reason) {
    $minutes = (int)spSetting($pdo, 'exit_release_minutes');
    $expires = date('Y-m-d H:i:s', time() + $minutes * 60);
    $pdo->prepare("INSERT INTO `exit_releases` (`vehicle_id`, `plate_number`, `reason`, `released_by_user_id`, `released_by_label`, `expires_at`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?)")
        ->execute([$vehicle['id'], $vehicle['plate_number'], $reason, actorUserId($admin), actorLabel($admin), $expires, date('Y-m-d H:i:s')]);
    $id = (int)$pdo->lastInsertId();
    auditLog($pdo, $admin, 'exit.release', ['entityType' => 'vehicle', 'entityId' => (int)$vehicle['id'], 'plate' => $vehicle['plate_number'],
        'detail' => "One exit released, valid {$minutes} minutes (until {$expires})", 'reason' => $reason]);
    return ['id' => $id, 'expiresAt' => $expires, 'minutes' => $minutes];
}

/** Marks the release used (called when the exit is recorded). */
function consumeExitRelease($pdo, $release, $actorLabelText) {
    $stmt = $pdo->prepare("UPDATE `exit_releases` SET `used_at` = ?, `used_by_label` = ? WHERE `id` = ? AND `used_at` IS NULL");
    $stmt->execute([date('Y-m-d H:i:s'), $actorLabelText, $release['id']]);
    if ($stmt->rowCount() === 1) {
        auditLog($pdo, $actorLabelText, 'exit.release_used', ['entityType' => 'vehicle', 'entityId' => (int)$release['vehicle_id'], 'plate' => $release['plate_number'],
            'detail' => "Exit released by {$release['released_by_label']} was used", 'reason' => $release['reason']]);
        return true;
    }
    return false;
}
