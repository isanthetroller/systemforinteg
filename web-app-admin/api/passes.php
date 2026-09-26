<?php
/**
 * SecurePark API - Permanent Pass Management (admin only)
 *
 * POST /api/passes.php  { vehicle_id, action: "reissue", valid_until?: "YYYY-MM-DD" }
 *
 * Reissuing gives the vehicle a new pass id: every previously printed QR for this
 * vehicle (signed or legacy) stops working immediately and is reported as REVOKED.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(405, null, 'Method not allowed');
}

requireStaff($pdo, ['admin']);
$data = getJsonInput();
$action = $data['action'] ?? '';
$vehicle = findVehicleById($pdo, $data['vehicle_id'] ?? 0);

if (!$vehicle) {
    sendResponse(404, null, 'Vehicle not found.');
}
if ($action !== 'reissue') {
    sendResponse(400, null, 'Unknown action. Use reissue.');
}

$validUntil = $data['valid_until'] ?? '';
if ($validUntil !== '') {
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $validUntil) || !checkdate((int)substr($validUntil, 5, 2), (int)substr($validUntil, 8, 2), (int)substr($validUntil, 0, 4))) {
        sendResponse(400, null, 'valid_until must be a date in YYYY-MM-DD format.');
    }
} else {
    $validUntil = $vehicle['pass_valid_until'] ?: defaultPassValidUntil($vehicle['sticker_year']);
}

$stmt = $pdo->prepare("UPDATE `vehicles` SET `pass_id` = ?, `pass_valid_until` = ?, `qr_pass_code` = NULL WHERE `id` = ?");
$stmt->execute([newPassId(), $validUntil, $vehicle['id']]);

sendResponse(200, vehicleForOutput($pdo, findVehicleById($pdo, $vehicle['id']), true),
    "New pass issued for {$vehicle['plate_number']}. All previous QR codes for this vehicle are now revoked.");
