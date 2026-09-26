<?php
/**
 * SecurePark API - Student / Vehicle-Owner Portal
 *
 * All data is scoped to the signed-in student's owner ID taken from the session
 * token. No endpoint accepts an owner ID, vehicle ID or plate from the client.
 *
 * GET /api/student.php?action=me           Profile + standing summary
 * GET /api/student.php?action=vehicles     Own vehicles with drivers, status, strikes and signed QR pass
 * GET /api/student.php?action=violations   Warnings / violations on own vehicles
 * GET /api/student.php?action=activity     Last 15 gate entries / exits of own vehicles
 *
 * Sign in:          POST /api/auth.php?action=login&realm=student  { username: <student ID>, password }
 * Change password:  POST /api/auth.php?action=change_password
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(405, null, 'Method not allowed');
}

$student = requireStudent($pdo);
$ownerId = $student['owner_id_number'];
$action = $_GET['action'] ?? 'me';

function ownVehicles($pdo, $ownerId) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `owner_id_number` = ? ORDER BY `id` ASC");
    $stmt->execute([$ownerId]);
    return $stmt->fetchAll();
}

function studentVehicleView($pdo, $row) {
    $v = vehicleForOutput($pdo, $row, true);
    // Only what the owner needs; internal / duplicate snake_case keys are dropped
    return [
        'id' => $v['id'],
        'plateNumber' => $v['plateNumber'],
        'vehicleType' => $v['vehicleType'],
        'makeModelColor' => $v['makeModelColor'],
        'ownerName' => $v['ownerName'],
        'ownerRole' => $v['ownerRole'],
        'department' => $v['department'],
        'stickerYear' => $v['stickerYear'],
        'status' => $v['status'],
        'registrationStatus' => $v['registrationStatus'],
        'vehiclePhoto' => $v['vehiclePhoto'],
        'passId' => $v['passId'],
        'passValidUntil' => $v['passValidUntil'],
        'passExpired' => $v['passValidUntil'] !== null && $v['passValidUntil'] < date('Y-m-d'),
        'warningCount' => $v['warningCount'],
        'isBanned' => $v['isBanned'],
        'qrPayload' => $v['qrPayload'],
        'authorizedDrivers' => array_map(function ($d) {
            return [
                'fullName' => $d['fullName'],
                'relationship' => $d['relationship'],
                'licenseNo' => $d['licenseNo'],
            ];
        }, $v['authorizedDrivers']),
    ];
}

switch ($action) {
    case 'me':
        $vehicles = ownVehicles($pdo, $ownerId);
        sendResponse(200, [
            'student' => publicStudent($student),
            'summary' => [
                'vehicles' => count($vehicles),
                'banned' => count(array_filter($vehicles, fn($v) => (int)$v['is_banned'] === 1)),
                'strikes' => array_sum(array_map(fn($v) => (int)$v['warning_count'], $vehicles)),
                'strikeLimit' => 3,
            ],
        ]);

    case 'vehicles':
        sendResponse(200, array_map(fn($row) => studentVehicleView($pdo, $row), ownVehicles($pdo, $ownerId)));

    case 'violations':
        $stmt = $pdo->prepare("SELECT vv.* FROM `vehicle_violations` vv
            JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
            WHERE v.`owner_id_number` = ?
            ORDER BY vv.`id` DESC LIMIT 200");
        $stmt->execute([$ownerId]);
        $rows = array_map(function ($r) {
            return [
                'id' => (int)$r['id'],
                'plateNumber' => $r['plate_number'],
                'violationType' => $r['violation_type'],
                'description' => $r['description'],
                'severity' => $r['severity'],
                'status' => $r['status'],
                'countsAsStrike' => (int)$r['counts_as_strike'] === 1,
                'createdAt' => $r['created_at'],
                'resolvedAt' => $r['resolved_at'],
                'resolutionNotes' => $r['status'] === 'Pending' ? null : $r['resolution_notes'],
            ];
        }, $stmt->fetchAll());
        sendResponse(200, $rows);

    case 'activity':
        $plates = array_map(fn($v) => normalizePlate($v['plate_number']), ownVehicles($pdo, $ownerId));
        if (!$plates) sendResponse(200, []);
        $placeholders = implode(',', array_fill(0, count($plates), '?'));
        $stmt = $pdo->prepare("SELECT `plate_number`, `action`, `gate_type`, `gate_point`, `driver_name`, `logged_at`
            FROM `gate_logs`
            WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') IN ({$placeholders})
            ORDER BY `id` DESC LIMIT 15");
        $stmt->execute($plates);
        sendResponse(200, array_map(function ($r) {
            return [
                'plateNumber' => $r['plate_number'],
                'action' => $r['action'],
                'gateType' => $r['gate_type'],
                'gatePoint' => $r['gate_point'],
                'driverName' => $r['driver_name'],
                'loggedAt' => $r['logged_at'],
            ];
        }, $stmt->fetchAll()));

    default:
        sendResponse(400, null, 'Unknown action. Use me, vehicles, violations or activity.');
}
