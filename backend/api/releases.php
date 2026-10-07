<?php
/**
 * SecurePark API - Exit releases for vehicles on hold
 *
 * GET    /api/releases.php                         Releases that are still usable (staff)
 * POST   /api/releases.php { vehicleId, reason }   Release ONE exit of a vehicle that is inside campus and on hold (admin, reason required)
 * DELETE /api/releases.php?id=N                    Cancel an unused release (admin)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/releases.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    requireStaff($pdo);
    $stmt = $pdo->prepare("SELECT * FROM `exit_releases` WHERE `used_at` IS NULL AND `expires_at` > ? ORDER BY `id` DESC");
    $stmt->execute([date('Y-m-d H:i:s')]);
    sendResponse(200, array_map(fn($r) => [
        'id' => (int)$r['id'], 'vehicleId' => (int)$r['vehicle_id'], 'plateNumber' => $r['plate_number'], 'reason' => $r['reason'],
        'releasedBy' => $r['released_by_label'], 'expiresAt' => $r['expires_at'], 'createdAt' => $r['created_at'],
    ], $stmt->fetchAll()));
}

$admin = requireStaff($pdo, ['admin']);

if ($method === 'POST') {
    $data = getJsonInput();
    $vehicle = findVehicleById($pdo, (int)($data['vehicleId'] ?? 0));
    if (!$vehicle) sendResponse(404, null, 'Vehicle not found.');
    $reason = requireReason($data, 'releasing an exit');
    if (!vehicleIsOnHold($pdo, $vehicle)) {
        sendResponse(409, ['code' => 'NOT_ON_HOLD'], "{$vehicle['plate_number']} is not on hold, so there is nothing to release.");
    }
    if ($vehicle['status'] !== 'Inside Campus') {
        sendResponse(409, ['code' => 'NOT_INSIDE'], "{$vehicle['plate_number']} is not recorded inside campus. An exit release only lets a vehicle that is inside leave.");
    }
    if (activeExitRelease($pdo, $vehicle['id'])) {
        sendResponse(409, ['code' => 'ALREADY_RELEASED'], "An exit release for {$vehicle['plate_number']} is already active.");
    }
    $r = createExitRelease($pdo, $admin, $vehicle, $reason);
    sendResponse(201, $r, "One exit released for {$vehicle['plate_number']}. The guard has {$r['minutes']} minutes to let it out; the vehicle stays on hold and cannot come back in.");
}

if ($method === 'DELETE') {
    $id = (int)($_GET['id'] ?? 0);
    $stmt = $pdo->prepare("SELECT * FROM `exit_releases` WHERE `id` = ?");
    $stmt->execute([$id]);
    $r = $stmt->fetch();
    if (!$r) sendResponse(404, null, 'Release not found.');
    if ($r['used_at'] !== null) sendResponse(409, null, 'This release was already used.');
    $pdo->prepare("UPDATE `exit_releases` SET `expires_at` = ? WHERE `id` = ?")->execute([date('Y-m-d H:i:s', time() - 1), $id]);
    auditLog($pdo, $admin, 'exit.release_cancel', ['entityType' => 'vehicle', 'entityId' => (int)$r['vehicle_id'], 'plate' => $r['plate_number']]);
    sendResponse(200, ['id' => $id], 'Release cancelled.');
}

sendResponse(405, null, "Method {$method} not allowed");
