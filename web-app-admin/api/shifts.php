<?php
/**
 * SecurePark API - Guard duty (who is on which gate) and shift handover
 *
 * GET  /api/shifts.php                      Guards on duty now + my open shift + the latest handover note (staff)
 * GET  /api/shifts.php?scope=report         Per-guard activity for a period: from, to (YYYY-MM-DD, default last 7 days) (admin)
 * POST /api/shifts.php {action:'start', gate}
 *                                           Go on duty at a gate. Ends any shift of yours still open. Returns the previous
 *                                           guard's handover note for that gate.
 * POST /api/shifts.php {action:'end', notes}
 *                                           End your shift and leave a handover note for the next guard.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/records.php';

$method = $_SERVER['REQUEST_METHOD'];
$staff = requireStaff($pdo);

function shiftView($r) {
    return [
        'id' => (int)$r['id'], 'userId' => (int)$r['user_id'], 'guard' => $r['guard_label'], 'gate' => $r['gate'],
        'startedAt' => $r['started_at'], 'endedAt' => $r['ended_at'], 'handoverNotes' => $r['handover_notes'],
    ];
}

function openShiftOf($pdo, $userId) {
    $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `user_id` = ? AND `ended_at` IS NULL ORDER BY `id` DESC LIMIT 1");
    $stmt->execute([$userId]);
    return $stmt->fetch() ?: null;
}

/** Latest handover note left by someone else in the last 24 hours (same gate first, then any gate). */
function latestHandover($pdo, $userId, $gate) {
    $since = date('Y-m-d H:i:s', strtotime('-24 hours'));
    $base = "SELECT * FROM `guard_shifts` WHERE `ended_at` IS NOT NULL AND `ended_at` >= ? AND `user_id` <> ? AND `handover_notes` IS NOT NULL AND `handover_notes` <> ''";
    if ($gate) {
        $stmt = $pdo->prepare($base . " AND `gate` = ? ORDER BY `ended_at` DESC, `id` DESC LIMIT 1");
        $stmt->execute([$since, $userId, $gate]);
        if ($row = $stmt->fetch()) return $row;
    }
    $stmt = $pdo->prepare($base . " ORDER BY `ended_at` DESC, `id` DESC LIMIT 1");
    $stmt->execute([$since, $userId]);
    return $stmt->fetch() ?: null;
}

if ($method === 'GET' && ($_GET['scope'] ?? '') === 'report') {
    requireStaff($pdo, ['admin']);
    $from = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['from'] ?? '') ? $_GET['from'] : date('Y-m-d', strtotime('-6 days'));
    $to = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['to'] ?? '') ? $_GET['to'] : date('Y-m-d');
    $start = "{$from} 00:00:00";
    $end = "{$to} 23:59:59";

    $guards = [];
    $stmt = $pdo->prepare("SELECT `id`, `full_name`, `badge_number` FROM `system_users` WHERE `role` = 'guard' ORDER BY `full_name`");
    $stmt->execute();
    foreach ($stmt->fetchAll() as $u) {
        $guards[(int)$u['id']] = ['userId' => (int)$u['id'], 'guard' => actorLabel($u), 'entries' => 0, 'exits' => 0, 'denials' => 0,
            'manualLookups' => 0, 'violationsIssued' => 0, 'photos' => 0, 'shifts' => 0, 'hoursOnDuty' => 0.0];
    }

    $stmt = $pdo->prepare("SELECT `logged_by_user_id` AS uid, `action`, `lookup_method`, COUNT(*) AS n FROM `gate_logs`
        WHERE `logged_at` BETWEEN ? AND ? AND `logged_by_user_id` IS NOT NULL GROUP BY `logged_by_user_id`, `action`, `lookup_method`");
    $stmt->execute([$start, $end]);
    foreach ($stmt->fetchAll() as $r) {
        $uid = (int)$r['uid'];
        if (!isset($guards[$uid])) continue;
        $n = (int)$r['n'];
        if ($r['action'] === 'Entry Recorded') $guards[$uid]['entries'] += $n;
        elseif ($r['action'] === 'Exit Approved') $guards[$uid]['exits'] += $n;
        else $guards[$uid]['denials'] += $n;
        if ($r['lookup_method'] === 'manual') $guards[$uid]['manualLookups'] += $n;
    }

    $stmt = $pdo->prepare("SELECT `logged_by_user_id` AS uid, COUNT(*) AS n FROM `vehicle_violations`
        WHERE `created_at` BETWEEN ? AND ? AND `logged_by_user_id` IS NOT NULL GROUP BY `logged_by_user_id`");
    $stmt->execute([$start, $end]);
    foreach ($stmt->fetchAll() as $r) {
        if (isset($guards[(int)$r['uid']])) $guards[(int)$r['uid']]['violationsIssued'] = (int)$r['n'];
    }

    $stmt = $pdo->prepare("SELECT `taken_by_user_id` AS uid, COUNT(*) AS n FROM `evidence_photos`
        WHERE `created_at` BETWEEN ? AND ? AND `taken_by_user_id` IS NOT NULL GROUP BY `taken_by_user_id`");
    $stmt->execute([$start, $end]);
    foreach ($stmt->fetchAll() as $r) {
        if (isset($guards[(int)$r['uid']])) $guards[(int)$r['uid']]['photos'] = (int)$r['n'];
    }

    $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `started_at` BETWEEN ? AND ?");
    $stmt->execute([$start, $end]);
    foreach ($stmt->fetchAll() as $r) {
        $uid = (int)$r['user_id'];
        if (!isset($guards[$uid])) continue;
        $guards[$uid]['shifts']++;
        $endTs = $r['ended_at'] ? strtotime($r['ended_at']) : time();
        $guards[$uid]['hoursOnDuty'] = round($guards[$uid]['hoursOnDuty'] + max(0, ($endTs - strtotime($r['started_at'])) / 3600), 1);
    }

    $rows = array_values($guards);
    foreach ($rows as &$g) {
        $handled = $g['entries'] + $g['exits'] + $g['denials'];
        $g['denialRate'] = $handled > 0 ? round($g['denials'] * 100 / $handled, 1) : 0;
        $g['manualRate'] = $handled > 0 ? round($g['manualLookups'] * 100 / $handled, 1) : 0;
    }
    unset($g);
    sendResponse(200, ['from' => $from, 'to' => $to, 'guards' => $rows]);
}

if ($method === 'GET') {
    $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `ended_at` IS NULL ORDER BY `started_at` DESC");
    $stmt->execute();
    $onDuty = array_map('shiftView', $stmt->fetchAll());
    $mine = !empty($staff['id']) ? openShiftOf($pdo, (int)$staff['id']) : null;
    $handover = latestHandover($pdo, (int)($staff['id'] ?? 0), $mine['gate'] ?? null);
    sendResponse(200, ['onDuty' => $onDuty, 'mine' => $mine ? shiftView($mine) : null, 'handover' => $handover ? shiftView($handover) : null]);
}

if ($method === 'POST') {
    if (empty($staff['id'])) sendResponse(403, null, 'Shifts need a personal sign-in, not a scanner key.');
    $data = getJsonInput();
    $action = $data['action'] ?? '';
    $uid = (int)$staff['id'];
    $now = date('Y-m-d H:i:s');

    if ($action === 'start') {
        $gate = trim((string)($data['gate'] ?? ''));
        if ($gate === '') sendResponse(400, null, 'Choose the gate you are on duty at.');
        if (mb_strlen($gate) > 100) sendResponse(400, null, 'Gate name is too long.');
        $open = openShiftOf($pdo, $uid);
        if ($open && $open['gate'] === $gate) {
            // Resuming the same shift after the app restarted
            sendResponse(200, ['shift' => shiftView($open), 'handover' => ($h = latestHandover($pdo, $uid, $gate)) ? shiftView($h) : null], 'You are already on duty at this gate.');
        }
        if ($open) {
            $pdo->prepare("UPDATE `guard_shifts` SET `ended_at` = ?, `handover_notes` = COALESCE(`handover_notes`, '(moved to another gate)') WHERE `id` = ?")->execute([$now, $open['id']]);
        }
        $pdo->prepare("INSERT INTO `guard_shifts` (`user_id`, `guard_label`, `gate`, `started_at`) VALUES (?, ?, ?, ?)")
            ->execute([$uid, actorLabel($staff), $gate, $now]);
        $id = (int)$pdo->lastInsertId();
        $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `id` = ?");
        $stmt->execute([$id]);
        $handover = latestHandover($pdo, $uid, $gate);
        sendResponse(201, ['shift' => shiftView($stmt->fetch()), 'handover' => $handover ? shiftView($handover) : null], "On duty at {$gate}.");
    }

    if ($action === 'end') {
        $open = openShiftOf($pdo, $uid);
        if (!$open) sendResponse(409, ['code' => 'NO_OPEN_SHIFT'], 'You are not on duty.');
        $notes = trim((string)($data['notes'] ?? ''));
        if (mb_strlen($notes) > 2000) sendResponse(400, null, 'Handover notes are too long (2000 characters max).');
        $pdo->prepare("UPDATE `guard_shifts` SET `ended_at` = ?, `handover_notes` = ? WHERE `id` = ?")->execute([$now, $notes !== '' ? $notes : null, $open['id']]);
        sendResponse(200, ['endedAt' => $now], 'Shift ended. Thank you.');
    }

    sendResponse(400, null, "Unknown action. Use 'start' or 'end'.");
}

sendResponse(405, null, "Method {$method} not allowed");
