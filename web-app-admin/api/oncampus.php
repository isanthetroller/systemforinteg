<?php
/**
 * SecurePark API - Vehicles currently on campus
 *
 * GET /api/oncampus.php   (staff)
 *
 * Registered vehicles with status "Inside Campus" and visitors who entered on a day pass
 * but have not exited, with how long they have been inside, who drove in, owner contact,
 * strike standing and any items the visitor brought in.
 *
 * Both lists come back in arrival order: the vehicle that entered first is first, so the
 * guard can monitor them in the order they came in. `entryLogId` is the gate log of that entry
 * (its CCTV clip).
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/campus.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(405, null, 'Method not allowed');
}
requireStaff($pdo);

$now = spNow();
$nightStart = currentNightStart($now);
$today = date('Y-m-d', $now);

/* ---------- Registered vehicles ---------- */
$vehicles = [];
$candidateVehicles = $pdo->query("
    SELECT * FROM `vehicles` 
    WHERE `status` IN ('Inside Campus', 'Blocked / Alert') 
    ORDER BY `plate_number`
")->fetchAll();

foreach ($candidateVehicles as $v) {
    $entry = lastEntryLog($pdo, $v);
    if (!$entry) {
        if ($v['status'] !== 'Inside Campus') {
            continue;
        }
    } else {
        // If there was an approved exit after the last entry, vehicle is no longer on campus
        $exitStmt = $pdo->prepare("
            SELECT `logged_at` FROM `gate_logs` 
            WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? 
              AND `action` = 'Exit Approved'
              AND `logged_at` >= ?
            LIMIT 1
        ");
        $exitStmt->execute([normalizePlate($v['plate_number']), date('Y-m-d H:i:s', $entry['time'])]);
        if ($exitStmt->fetch()) {
            continue;
        }
    }

    // Check active security hold
    $holdStmt = $pdo->prepare("
        SELECT id, case_number, reason, notes, status 
        FROM `security_incidents` 
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? 
          AND `status` = 'Held' 
        ORDER BY id DESC LIMIT 1
    ");
    $holdStmt->execute([normalizePlate($v['plate_number'])]);
    $activeHold = $holdStmt->fetch() ?: null;

    // Check if exit was denied during egress attempt
    $deniedStmt = $pdo->prepare("
        SELECT id, action, notes, logged_at 
        FROM `gate_logs` 
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? 
          AND `action` = 'Exit Denied' 
        ORDER BY id DESC LIMIT 1
    ");
    $deniedStmt->execute([normalizePlate($v['plate_number'])]);
    $lastExitDenied = $deniedStmt->fetch() ?: null;
    $hasExitDenied = false;
    if ($lastExitDenied && $entry) {
        $hasExitDenied = strtotime($lastExitDenied['logged_at']) >= $entry['time'];
    }

    $hours = $entry ? round(max(0, $now - $entry['time']) / 3600, 1) : null;
    $overnight = $entry && $entry['time'] < $nightStart && $now >= $nightStart;
    $vehicles[] = [
        'vehicleId' => (int)$v['id'],
        'plateNumber' => $v['plate_number'],
        'vehicleType' => $v['vehicle_type'],
        'makeModelColor' => $v['make_model_color'],
        'ownerName' => $v['owner_name'],
        'ownerRole' => $v['owner_role'],
        'department' => $v['department'],
        'ownerPhone' => $v['owner_phone'],
        'entryTime' => $entry ? date('Y-m-d H:i:s', $entry['time']) : null,
        'entryLogId' => $entry['logId'] ?? null,
        'enteredBy' => $entry['driver'] ?? null,
        'entryGate' => $entry['gatePoint'] ?? null,
        'admittedBy' => $entry['guard'] ?? null,
        'hoursInside' => $hours,
        'isVip' => isVipVehicle($v),
        'timeFlag' => isVipVehicle($v) ? null : ($overnight ? 'overnight' : ($hours !== null && $hours >= SP_OVERTIME_HOURS ? 'overtime' : null)),
        'warningCount' => (int)$v['warning_count'],
        'isBanned' => (int)$v['is_banned'] === 1,
        'registrationStatus' => $v['registration_status'],
        'status' => $v['status'],
        'activeHold' => $activeHold ? [
            'id' => (int)$activeHold['id'],
            'caseNumber' => $activeHold['case_number'],
            'reason' => $activeHold['reason'],
            'notes' => $activeHold['notes'],
        ] : null,
        'exitDenied' => $hasExitDenied,
    ];
}
// Arrival order: earliest entry first; a vehicle with no recorded entry time goes last
usort($vehicles, fn($a, $b) => [$a['entryTime'] === null, $a['entryTime']] <=> [$b['entryTime'] === null, $b['entryTime']]);

/* ---------- Visitors on day passes ---------- */
$visitors = [];
$stmt = $pdo->query("SELECT * FROM `visitor_passes` WHERE `entry_time` IS NOT NULL AND `exit_time` IS NULL AND `status` IN ('Active', 'Revoked') ORDER BY `entry_time` ASC, `id` ASC");
foreach ($stmt->fetchAll() as $p) {
    $entryLog = $pdo->prepare("SELECT `id` FROM `gate_logs` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `action` = 'Entry Recorded' AND `logged_at` = ? ORDER BY `id` DESC LIMIT 1");
    $entryLog->execute([normalizePlate($p['plate_number']), $p['entry_time']]);
    $entryLogId = $entryLog->fetchColumn();
    // Check active security hold
    $holdStmt = $pdo->prepare("
        SELECT id, case_number, reason, notes, status 
        FROM `security_incidents` 
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? 
          AND `status` = 'Held' 
        ORDER BY id DESC LIMIT 1
    ");
    $holdStmt->execute([normalizePlate($p['plate_number'])]);
    $activeHold = $holdStmt->fetch() ?: null;

    // Check if exit was denied during egress attempt
    $deniedStmt = $pdo->prepare("
        SELECT id, action, notes, logged_at 
        FROM `gate_logs` 
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? 
          AND `action` = 'Exit Denied' 
        ORDER BY id DESC LIMIT 1
    ");
    $deniedStmt->execute([normalizePlate($p['plate_number'])]);
    $lastExitDenied = $deniedStmt->fetch() ?: null;
    $hasExitDenied = false;
    if ($lastExitDenied && $p['entry_time']) {
        $hasExitDenied = strtotime($lastExitDenied['logged_at']) >= strtotime($p['entry_time']);
    }

    $entryTs = strtotime($p['entry_time']);
    $visitors[] = [
        'passId' => (int)$p['id'],
        'passCode' => $p['pass_code'],
        'plateNumber' => $p['plate_number'],
        'vehicleModel' => $p['vehicle_model'],
        'visitorName' => $p['visitor_name'],
        'contactNumber' => $p['contact_number'],
        'personToVisit' => $p['person_to_visit'],
        'purposeOfVisit' => $p['purpose_of_visit'],
        'validDate' => $p['valid_date'],
        'overstayed' => $p['valid_date'] < $today,
        'revoked' => $p['status'] === 'Revoked',
        'entryTime' => $p['entry_time'],
        'entryLogId' => $entryLogId !== false ? (int)$entryLogId : null,
        'hoursInside' => round(max(0, $now - $entryTs) / 3600, 1),
        'items' => visitorPassItems($pdo, $p['id']),
        'activeHold' => $activeHold ? [
            'id' => (int)$activeHold['id'],
            'caseNumber' => $activeHold['case_number'],
            'reason' => $activeHold['reason'],
            'notes' => $activeHold['notes'],
        ] : null,
        'exitDenied' => $hasExitDenied,
    ];
}

sendResponse(200, [
    'now' => date('Y-m-d H:i:s', $now),
    'counts' => [
        'total' => count($vehicles) + count($visitors),
        'registered' => count($vehicles),
        'visitors' => count($visitors),
        'flagged' => count(array_filter($vehicles, fn($v) => $v['timeFlag'] !== null || !empty($v['activeHold']) || $v['exitDenied'])) + count(array_filter($visitors, fn($v) => $v['overstayed'] || $v['revoked'] || !empty($v['activeHold']) || $v['exitDenied'])),
        'withStrikes' => count(array_filter($vehicles, fn($v) => $v['warningCount'] > 0 || $v['isBanned'])),
        'blocked' => count(array_filter($vehicles, fn($v) => !empty($v['activeHold']) || $v['exitDenied'])) + count(array_filter($visitors, fn($v) => !empty($v['activeHold']) || $v['exitDenied'])),
    ],
    'vehicles' => $vehicles,
    'visitors' => $visitors,
]);
