<?php
/**
 * SecurePark API - Guard duty (who is on which gate) and shift handover
 *
 * GET  /api/shifts.php                      Guards on duty now + my open shift + the latest handover note (staff)
 * GET  /api/shifts.php?scope=report         Per-guard activity for a period: from, to (YYYY-MM-DD, default last 7 days) (admin)
 * GET  /api/shifts.php?scope=timeline       Every shift touching a period (from, to; default today) with what was done during each, off-shift
 *                                           activity and gate coverage right now (admin)
 * GET  /api/shifts.php?scope=shift&id=N     One shift: handover note + everything that guard did during it, in order (admin)
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

/** How a shift ended: open, manual (the guard ended it), auto (closed by the maintenance job), moved (the guard started another gate). */
function shiftEndKind($r) {
    if (empty($r['ended_at'])) return 'open';
    $n = (string)($r['handover_notes'] ?? '');
    if (strpos($n, '(shift closed automatically') === 0) return 'auto';
    if ($n === '(moved to another gate)') return 'moved';
    return 'manual';
}

/**
 * What staff did, from every place it is recorded, between two timestamps (YYYY-MM-DD HH:MM:SS):
 * [userId, ts, type, label, plate]. type = entry | exit | denied | violation | incident | photo | visitor.
 */
function shiftEvents($pdo, $from, $to, $limit = 20000) {
    $ev = [];
    $push = function ($uid, $at, $type, $label, $plate) use (&$ev) {
        $ts = strtotime($at);
        if ($uid !== null && $ts) $ev[] = ['userId' => (int)$uid, 'ts' => $ts, 'at' => $at, 'type' => $type, 'label' => $label, 'plate' => $plate];
    };
    $stmt = $pdo->prepare("SELECT `logged_by_user_id` AS uid, `logged_at` AS at, `action`, `plate_number`, `gate_point`, `driver_name` FROM `gate_logs`
        WHERE `logged_at` BETWEEN ? AND ? AND `logged_by_user_id` IS NOT NULL ORDER BY `logged_at` ASC LIMIT {$limit}");
    $stmt->execute([$from, $to]);
    foreach ($stmt->fetchAll() as $r) {
        $type = $r['action'] === 'Entry Recorded' ? 'entry' : ($r['action'] === 'Exit Approved' ? 'exit' : 'denied');
        $label = ($type === 'entry' ? 'Entry recorded' : ($type === 'exit' ? 'Exit approved' : $r['action'])) . ' · ' . $r['plate_number']
            . ($r['gate_point'] ? ' at ' . $r['gate_point'] : '');
        $push($r['uid'], $r['at'], $type, $label, $r['plate_number']);
    }
    $stmt = $pdo->prepare("SELECT `logged_by_user_id` AS uid, `created_at` AS at, `violation_type`, `plate_number` FROM `vehicle_violations`
        WHERE `created_at` BETWEEN ? AND ? AND `logged_by_user_id` IS NOT NULL ORDER BY `created_at` ASC LIMIT {$limit}");
    $stmt->execute([$from, $to]);
    foreach ($stmt->fetchAll() as $r) $push($r['uid'], $r['at'], 'violation', 'Violation issued · ' . $r['plate_number'] . ' · ' . $r['violation_type'], $r['plate_number']);
    $stmt = $pdo->prepare("SELECT `logged_by_user_id` AS uid, `reported_at` AS at, `case_number`, `reason`, `plate_number` FROM `security_incidents`
        WHERE `reported_at` BETWEEN ? AND ? AND `logged_by_user_id` IS NOT NULL ORDER BY `reported_at` ASC LIMIT {$limit}");
    $stmt->execute([$from, $to]);
    foreach ($stmt->fetchAll() as $r) $push($r['uid'], $r['at'], 'incident', 'Vehicle held · ' . $r['plate_number'] . ' · ' . $r['reason'] . ' (' . $r['case_number'] . ')', $r['plate_number']);
    $stmt = $pdo->prepare("SELECT `taken_by_user_id` AS uid, `created_at` AS at, `kind`, `plate_number` FROM `evidence_photos`
        WHERE `created_at` BETWEEN ? AND ? AND `taken_by_user_id` IS NOT NULL ORDER BY `created_at` ASC LIMIT {$limit}");
    $stmt->execute([$from, $to]);
    foreach ($stmt->fetchAll() as $r) $push($r['uid'], $r['at'], 'photo', 'Evidence photo (' . $r['kind'] . ') · ' . $r['plate_number'], $r['plate_number']);
    $stmt = $pdo->prepare("SELECT `created_by_user_id` AS uid, `created_at` AS at, `pass_code`, `plate_number`, `visitor_name` FROM `visitor_passes`
        WHERE `created_at` BETWEEN ? AND ? AND `created_by_user_id` IS NOT NULL ORDER BY `created_at` ASC LIMIT {$limit}");
    $stmt->execute([$from, $to]);
    foreach ($stmt->fetchAll() as $r) $push($r['uid'], $r['at'], 'visitor', 'Visitor day pass issued · ' . $r['plate_number'] . ' · ' . $r['visitor_name'], $r['plate_number']);
    usort($ev, fn($a, $b) => $a['ts'] <=> $b['ts']);
    return $ev;
}

const SP_SHIFT_GATES = ['Gate 1 (Main Ingress)', 'Gate 2 (Main Egress)', 'Patrol / Other'];
const SP_LONG_SHIFT_HOURS = 12;

/** Timeline: every shift that touches the period, what was done during each, and who is where right now. (admin) */
if ($method === 'GET' && ($_GET['scope'] ?? '') === 'timeline') {
    requireStaff($pdo, ['admin']);
    $from = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['from'] ?? '') ? $_GET['from'] : date('Y-m-d');
    $to = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['to'] ?? '') ? $_GET['to'] : $from;
    if ($to < $from) [$from, $to] = [$to, $from];
    if (strtotime($to) - strtotime($from) > 62 * 86400) sendResponse(400, null, 'Choose a period of at most 62 days.');
    $startTs = strtotime("{$from} 00:00:00");
    $endTs = strtotime("{$to} 23:59:59");
    $nowTs = time();

    $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `started_at` <= ? AND (`ended_at` IS NULL OR `ended_at` >= ?) ORDER BY `started_at` ASC, `id` ASC LIMIT 1000");
    $stmt->execute([date('Y-m-d H:i:s', $endTs), date('Y-m-d H:i:s', $startTs)]);
    $rows = $stmt->fetchAll();

    $windowStart = $startTs;
    foreach ($rows as $r) $windowStart = min($windowStart, strtotime($r['started_at']));
    $events = shiftEvents($pdo, date('Y-m-d H:i:s', $windowStart), date('Y-m-d H:i:s', $endTs));

    $byUser = [];
    foreach ($rows as $i => $r) $byUser[(int)$r['user_id']][] = $i;
    $blank = fn() => ['entry' => 0, 'exit' => 0, 'denied' => 0, 'violation' => 0, 'incident' => 0, 'photo' => 0, 'visitor' => 0];
    $counts = array_fill(0, count($rows), $blank());
    $offShift = [];
    foreach ($events as $e) {
        $hit = null;
        foreach ($byUser[$e['userId']] ?? [] as $i) {
            $s = strtotime($rows[$i]['started_at']);
            $f = $rows[$i]['ended_at'] ? strtotime($rows[$i]['ended_at']) : $nowTs;
            if ($e['ts'] >= $s && $e['ts'] <= $f) { $hit = $i; break; }
        }
        if ($hit !== null) { $counts[$hit][$e['type']]++; continue; }
        if ($e['ts'] >= $startTs && $e['ts'] <= $endTs) $offShift[$e['userId']] = ($offShift[$e['userId']] ?? 0) + 1;
    }

    $users = [];
    $stmt = $pdo->prepare("SELECT `id`, `full_name`, `badge_number`, `role`, `gate_assigned` FROM `system_users` WHERE `role` = 'guard' ORDER BY `full_name`");
    $stmt->execute();
    foreach ($stmt->fetchAll() as $u) $users[(int)$u['id']] = ['userId' => (int)$u['id'], 'guard' => actorLabel($u), 'role' => $u['role'], 'assignedGate' => $u['gate_assigned'],
        'shifts' => 0, 'hours' => 0.0, 'offShiftActions' => 0];

    $shifts = [];
    $summary = ['onDuty' => 0, 'shifts' => 0, 'hours' => 0.0, 'autoClosed' => 0, 'longShifts' => 0, 'offShiftActions' => array_sum($offShift), 'actions' => 0];
    foreach ($rows as $i => $r) {
        $uid = (int)$r['user_id'];
        $s = strtotime($r['started_at']);
        $f = $r['ended_at'] ? strtotime($r['ended_at']) : $nowTs;
        $kind = shiftEndKind($r);
        $hours = max(0, ($f - $s) / 3600);
        $inRange = max(0, (min($f, $endTs, $nowTs) - max($s, $startTs)) / 3600);
        if (!isset($users[$uid])) $users[$uid] = ['userId' => $uid, 'guard' => $r['guard_label'], 'role' => 'staff', 'assignedGate' => null, 'shifts' => 0, 'hours' => 0.0, 'offShiftActions' => 0];
        $users[$uid]['shifts']++;
        $users[$uid]['hours'] += $inRange;
        $c = $counts[$i];
        $total = array_sum($c);
        $long = $hours > SP_LONG_SHIFT_HOURS;
        $summary['shifts']++;
        $summary['hours'] += $inRange;
        $summary['actions'] += $total;
        if ($kind === 'open') $summary['onDuty']++;
        if ($kind === 'auto') $summary['autoClosed']++;
        if ($long) $summary['longShifts']++;
        $shifts[] = ['id' => (int)$r['id'], 'userId' => $uid, 'guard' => $r['guard_label'], 'gate' => $r['gate'], 'startedAt' => $r['started_at'], 'endedAt' => $r['ended_at'],
            'durationMinutes' => (int)round($hours * 60), 'endKind' => $kind, 'long' => $long, 'handoverNotes' => $r['handover_notes'],
            'counts' => $c, 'actions' => $total];
    }
    foreach ($users as $uid => &$u) { $u['hours'] = round($u['hours'], 1); $u['offShiftActions'] = $offShift[$uid] ?? 0; }
    unset($u);
    $summary['hours'] = round($summary['hours'], 1);

    // Who is covering which gate right now (independent of the chosen period)
    $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `ended_at` IS NULL ORDER BY `started_at` ASC");
    $stmt->execute();
    $open = $stmt->fetchAll();
    $coverage = [];
    foreach (SP_SHIFT_GATES as $g) $coverage[$g] = [];
    foreach ($open as $r) {
        $g = $r['gate'] ?: 'Other';
        $coverage[$g][] = ['shiftId' => (int)$r['id'], 'userId' => (int)$r['user_id'], 'guard' => $r['guard_label'], 'startedAt' => $r['started_at'],
            'minutes' => (int)round(max(0, $nowTs - strtotime($r['started_at'])) / 60)];
    }
    $coverageList = [];
    foreach ($coverage as $g => $list) $coverageList[] = ['gate' => $g, 'guards' => $list];

    sendResponse(200, ['from' => $from, 'to' => $to, 'now' => date('Y-m-d H:i:s', $nowTs), 'summary' => $summary, 'guards' => array_values($users),
        'shifts' => $shifts, 'coverage' => $coverageList, 'longShiftHours' => SP_LONG_SHIFT_HOURS]);
}

/** One shift in detail: the handover note and everything that guard did while it ran, in time order. (admin) */
if ($method === 'GET' && ($_GET['scope'] ?? '') === 'shift') {
    requireStaff($pdo, ['admin']);
    $stmt = $pdo->prepare("SELECT * FROM `guard_shifts` WHERE `id` = ?");
    $stmt->execute([(int)($_GET['id'] ?? 0)]);
    $r = $stmt->fetch();
    if (!$r) sendResponse(404, null, 'Shift not found.');
    $uid = (int)$r['user_id'];
    $to = $r['ended_at'] ?: date('Y-m-d H:i:s');
    $activity = [];
    foreach (shiftEvents($pdo, $r['started_at'], $to, 2000) as $e) {
        if ($e['userId'] === $uid) $activity[] = ['at' => $e['at'], 'type' => $e['type'], 'label' => $e['label'], 'plate' => $e['plate']];
    }
    $shift = shiftView($r);
    $shift['endKind'] = shiftEndKind($r);
    $shift['durationMinutes'] = (int)round(max(0, (strtotime($to) - strtotime($r['started_at'])) / 60));
    sendResponse(200, ['shift' => $shift, 'activity' => array_slice($activity, 0, 500), 'truncated' => count($activity) > 500]);
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
