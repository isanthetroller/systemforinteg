<?php
/**
 * SecurePark API - Operational Statistics & KPI Metrics Endpoint
 * GET /api/stats.php - Aggregated dashboard metrics & gate charts
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/capacity.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(405, null, "Method not allowed");
}

requireStaff($pdo);

try {
    // 1. Vehicles & Visitors Currently Inside Campus (with parking capacity)
    $occupancy = campusOccupancy($pdo);
    $insideVehicles = $occupancy['insideVehicles'];
    $insideVisitors = $occupancy['insideVisitors'];
    $insideCount = $occupancy['inside'];

    // 2. Active Incidents / Blocked Vehicles
    $stmtBlocked = $pdo->query("SELECT COUNT(*) AS cnt FROM `security_incidents` WHERE `status` = 'Held'");
    $blockedCount = (int)$stmtBlocked->fetch()['cnt'];

    // 3. Today's Gate Entries
    $stmtEntries = $pdo->query("
        SELECT COUNT(*) AS cnt FROM `gate_logs` 
        WHERE `action` = 'Entry Recorded' AND DATE(`logged_at`) = CURDATE()
    ");
    $todayEntries = (int)$stmtEntries->fetch()['cnt'];

    // 4. Total Registered Fleet
    $stmtFleet = $pdo->query("SELECT COUNT(*) AS cnt FROM `vehicles`");
    $fleetCount = (int)$stmtFleet->fetch()['cnt'];

    // 5. Hourly Activity Distribution (Today)
    $stmtHourly = $pdo->query("
        SELECT 
            HOUR(`logged_at`) AS hr,
            SUM(CASE WHEN `action` = 'Entry Recorded' THEN 1 ELSE 0 END) AS entries,
            SUM(CASE WHEN `action` = 'Exit Approved' THEN 1 ELSE 0 END) AS exits
        FROM `gate_logs`
        WHERE DATE(`logged_at`) = CURDATE()
        GROUP BY HOUR(`logged_at`)
        ORDER BY hr ASC
    ");
    $hourlyData = $stmtHourly->fetchAll();

    // 6. Activity by Gate
    $stmtGate = $pdo->query("
        SELECT 
            `gate_point` AS gate,
            COUNT(*) AS totalPassages
        FROM `gate_logs`
        WHERE DATE(`logged_at`) = CURDATE()
        GROUP BY `gate_point`
    ");
    $gateData = $stmtGate->fetchAll();

    $stats = [
        'inside' => $insideCount,
        'insideVehicles' => $insideVehicles,
        'insideVisitors' => $insideVisitors,
        'occupancy' => $occupancy,
        'blocked' => $blockedCount,
        'todayEntries' => $todayEntries,
        'registeredFleet' => $fleetCount,
        'hourly' => $hourlyData,
        'byGate' => $gateData
    ];

    sendResponse(200, $stats);
} catch (Exception $e) {
    sendResponse(500, null, "Failed to compute stats: " . $e->getMessage());
}
