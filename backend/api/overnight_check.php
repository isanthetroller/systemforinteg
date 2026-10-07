<?php
/**
 * SecurePark API - Overtime & Overnight Parking Detection
 *
 * GET  /api/overnight_check.php                   Vehicles inside campus that are overnight or overtime (staff)
 * POST /api/overnight_check.php                   Same list (kept for older clients; nothing is recorded automatically)
 * POST /api/overnight_check.php { vehicle_id }    Issue a violation for a listed vehicle (guard or admin)
 *
 * Nothing is issued automatically: the guard first tries to contact the owner (phone shown in the list).
 * If the owner cannot be reached, the vehicle is reported to the police for removal (outside this system).
 * A violation is only issued when staff press "Issue Violation".
 *
 * Definitions (Asia/Manila):
 *   - The curfew is SP_CURFEW_TIME (default 22:00). A "night" starts at that day's curfew
 *     and lasts until the next curfew.
 *   - OVERNIGHT: vehicle is Inside Campus and entered before the curfew of the current night.
 *   - OVERTIME:  vehicle is Inside Campus for SP_OVERTIME_HOURS or more, but not overnight yet.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/violations.php';
require_once __DIR__ . '/../lib/campus.php';

const SP_OVERNIGHT_TYPE = 'Overnight / Unauthorized Overtime Parking';

$method = $_SERVER['REQUEST_METHOD'];
$actor = requireStaff($pdo);
$now = spNow();

if ($method === 'GET') {
    sendResponse(200, buildReport($pdo, $now));
}
if ($method !== 'POST') {
    sendResponse(405, null, "Method {$method} not allowed");
}

$data = getJsonInput();
if (!empty($data['vehicle_id'])) {
    handleManualFlag($pdo, $actor, (int)$data['vehicle_id'], $now);
}
$report = buildReport($pdo, $now);
sendResponse(200, $report, $report['items'] ? count($report['items']) . ' vehicle(s) overnight or overtime.' : 'No overnight or overtime vehicles.');

/* -------------------------------------------------------------------------- */

function lastEntryTime($pdo, $vehicle) {
    $entry = lastEntryLog($pdo, $vehicle);
    return $entry ? $entry['time'] : null;
}

function overnightViolationSince($pdo, $vehicleId, $sinceTs) {
    $stmt = $pdo->prepare("SELECT `id`, `created_at` FROM `vehicle_violations`
        WHERE `vehicle_id` = ? AND `violation_type` = ? AND `severity` = 'Violation' AND `status` <> 'Dismissed' AND `created_at` >= ?
        ORDER BY `id` DESC LIMIT 1");
    $stmt->execute([$vehicleId, SP_OVERNIGHT_TYPE, date('Y-m-d H:i:s', $sinceTs)]);
    return $stmt->fetch() ?: null;
}

/**
 * Classifies every vehicle currently inside campus.
 */
function buildReport($pdo, $now) {
    $nightStart = currentNightStart($now);
    $rows = $pdo->query("SELECT * FROM `vehicles` WHERE `status` = 'Inside Campus' ORDER BY `plate_number`")->fetchAll();
    $items = [];
    foreach ($rows as $v) {
        if (isVipVehicle($v)) continue; // VIP vehicles are exempt from overnight / overtime checks
        $entry = lastEntryTime($pdo, $v);
        if (!$entry) continue;
        $elapsedHours = max(0, ($now - $entry) / 3600);
        $overnight = $entry < $nightStart && $now >= $nightStart;
        $overtime = !$overnight && $elapsedHours >= SP_OVERTIME_HOURS;
        if (!$overnight && !$overtime) continue;

        // A violation already issued for this night, or (for overtime) since this entry
        $flag = overnightViolationSince($pdo, $v['id'], $overnight ? $nightStart : $entry);
        $items[] = [
            'vehicleId' => (int)$v['id'],
            'plateNumber' => $v['plate_number'],
            'ownerName' => $v['owner_name'],
            'ownerRole' => $v['owner_role'],
            'ownerPhone' => $v['owner_phone'],
            'vehicleType' => $v['vehicle_type'],
            'entryTime' => date('Y-m-d H:i:s', $entry),
            'elapsedHours' => round($elapsedHours, 1),
            'category' => $overnight ? 'overnight' : 'overtime',
            'onHold' => (int)$v['is_banned'] === 1,
            'flaggedThisNight' => $flag !== null,
            'flaggedAt' => $flag['created_at'] ?? null,
        ];
    }
    usort($items, function ($a, $b) {
        return [$a['category'] !== 'overnight', -$a['elapsedHours']] <=> [$b['category'] !== 'overnight', -$b['elapsedHours']];
    });
    return [
        'now' => date('Y-m-d H:i:s', $now),
        'curfew' => SP_CURFEW_TIME,
        'overtimeHours' => SP_OVERTIME_HOURS,
        'nightStartedAt' => date('Y-m-d H:i:s', $nightStart),
        'items' => $items,
    ];
}

function violationNotes($item, $curfew) {
    $entry = date('M d, h:i A', strtotime($item['entryTime']));
    return $item['category'] === 'overnight'
        ? "Still inside campus past the {$curfew} curfew. Entered {$entry} ({$item['elapsedHours']} h inside)."
        : "Inside campus for {$item['elapsedHours']} h (limit " . SP_OVERTIME_HOURS . " h). Entered {$entry}.";
}

/**
 * "Issue Violation" button: staff issue the violation for a listed vehicle (the vehicle is then on hold).
 */
function handleManualFlag($pdo, $actor, $vehicleId, $now) {
    $report = buildReport($pdo, $now);
    $item = null;
    foreach ($report['items'] as $candidate) {
        if ($candidate['vehicleId'] === $vehicleId) $item = $candidate;
    }
    if (!$item) {
        sendResponse(404, null, 'This vehicle is not currently overnight or overtime inside campus.');
    }
    if ($item['flaggedThisNight']) {
        sendResponse(409, ['code' => 'ALREADY_FLAGGED'], "A violation was already issued for {$item['plateNumber']} ({$item['flaggedAt']}).");
    }
    $vehicle = findVehicleById($pdo, $vehicleId);
    $pdo->beginTransaction();
    try {
        $outcome = issueViolation($pdo, $actor, $vehicle, SP_OVERNIGHT_TYPE, violationNotes($item, SP_CURFEW_TIME));
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, 'Failed to issue the violation.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }
    sendResponse(201, ['violationId' => $outcome['violationId'], 'onHold' => true, 'report' => buildReport($pdo, $now)],
        "Violation issued for {$item['plateNumber']}. It cannot leave campus until an administrator resolves it.");
}
