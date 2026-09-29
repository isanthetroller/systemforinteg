<?php
/**
 * SecurePark API - Overtime & Overnight Parking Detection
 *
 * GET  /api/overnight_check.php                   Vehicles inside campus that are overnight or overtime (staff)
 * POST /api/overnight_check.php                   Run detection: one overnight strike per vehicle per night (staff)
 * POST /api/overnight_check.php { vehicle_id }    Manually flag an overnight / overtime strike (staff)
 *
 * Definitions (Asia/Manila):
 *   - The curfew is SP_CURFEW_TIME (default 22:00). A "night" starts at that day's curfew
 *     and lasts until the next curfew, so each night yields at most one strike.
 *   - OVERNIGHT: vehicle is Inside Campus and entered before the curfew of the current night.
 *   - OVERTIME:  vehicle is Inside Campus for SP_OVERTIME_HOURS or more, but not overnight yet.
 *
 * InfinityFree has no cron, so the admin / guard dashboard triggers the POST when it loads
 * and every 10 minutes. Running it any number of times is safe (idempotent per night).
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/strikes.php';
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
handleDetection($pdo, $now);

/* -------------------------------------------------------------------------- */

function lastEntryTime($pdo, $vehicle) {
    $entry = lastEntryLog($pdo, $vehicle);
    return $entry ? $entry['time'] : null;
}

function overnightStrikeSince($pdo, $vehicleId, $sinceTs) {
    $stmt = $pdo->prepare("SELECT `id`, `created_at` FROM `vehicle_violations`
        WHERE `vehicle_id` = ? AND `violation_type` = ? AND `status` <> 'Dismissed' AND `created_at` >= ?
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

        // A strike already recorded for this night, or (for overtime) since this entry
        $flag = overnightStrikeSince($pdo, $v['id'], $overnight ? $nightStart : $entry);
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
            'warningCount' => (int)$v['warning_count'],
            'isBanned' => (int)$v['is_banned'] === 1,
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

function strikeNotes($item, $curfew) {
    $entry = date('M d, h:i A', strtotime($item['entryTime']));
    return $item['category'] === 'overnight'
        ? "Still inside campus past the {$curfew} curfew. Entered {$entry} ({$item['elapsedHours']} h inside)."
        : "Inside campus for {$item['elapsedHours']} h (limit " . SP_OVERTIME_HOURS . " h). Entered {$entry}.";
}

/**
 * Automatic run: one strike per overnight vehicle per night. Overtime vehicles are only listed.
 */
function handleDetection($pdo, $now) {
    $report = buildReport($pdo, $now);
    $system = ['id' => null, 'full_name' => 'System (Overnight Check)', 'badge_number' => null];
    $flagged = [];

    foreach ($report['items'] as &$item) {
        if ($item['category'] !== 'overnight' || $item['flaggedThisNight']) continue;
        $vehicle = findVehicleById($pdo, $item['vehicleId']);
        $pdo->beginTransaction();
        try {
            $outcome = addWarning($pdo, $system, $vehicle, SP_OVERNIGHT_TYPE, strikeNotes($item, SP_CURFEW_TIME));
            $pdo->commit();
        } catch (Exception $e) {
            $pdo->rollBack();
            continue;
        }
        $item['flaggedThisNight'] = true;
        $item['flaggedAt'] = date('Y-m-d H:i:s');
        $item['warningCount'] = $outcome['strikes'];
        $item['isBanned'] = $outcome['banned'];
        $flagged[] = ['plateNumber' => $item['plateNumber'], 'strikes' => $outcome['strikes'], 'banned' => $outcome['banned']];
    }
    unset($item);

    $report['flagged'] = $flagged;
    $message = $flagged ? count($flagged) . ' overnight strike(s) recorded.' : 'No new overnight strikes.';
    sendResponse(200, $report, $message);
}

/**
 * "Flag Overnight Strike" button: staff records the strike for a listed vehicle.
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
        sendResponse(409, ['code' => 'ALREADY_FLAGGED'], "An overnight / overtime strike was already recorded for {$item['plateNumber']} ({$item['flaggedAt']}).");
    }
    $vehicle = findVehicleById($pdo, $vehicleId);
    $pdo->beginTransaction();
    try {
        $outcome = addWarning($pdo, $actor, $vehicle, SP_OVERNIGHT_TYPE, strikeNotes($item, SP_CURFEW_TIME));
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, 'Failed to record the strike.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }
    $msg = $outcome['autoViolationId']
        ? "Strike {$outcome['strikes']} of " . SP_STRIKE_LIMIT . " for {$item['plateNumber']}: 3-strike policy enforced, vehicle banned."
        : "Overnight / overtime strike recorded for {$item['plateNumber']} (strike {$outcome['strikes']} of " . SP_STRIKE_LIMIT . ").";
    sendResponse(201, ['strikes' => $outcome['strikes'], 'banned' => $outcome['banned'], 'report' => buildReport($pdo, $now)], $msg);
}
