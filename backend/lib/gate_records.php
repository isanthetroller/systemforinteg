<?php
/** Read-only, paginated gate history. logged_at stores Asia/Manila wall time. */
function gateRecordParam($key, $default = '', $max = 150) {
    $value = $_GET[$key] ?? $default;
    if (!is_string($value) || strlen($value) > $max) sendResponse(400, null, "Invalid {$key} filter.");
    return trim($value);
}

function gateRecordChoice($key, $choices, $default) {
    $value = gateRecordParam($key, $default);
    if (!in_array($value, $choices, true)) sendResponse(400, null, "Invalid {$key} filter.");
    return $value;
}

function gateRecordInteger($key, $default, $max) {
    $value = gateRecordParam($key, (string)$default, 12);
    if (!preg_match('/^[1-9][0-9]*$/', $value) || (float)$value > $max) sendResponse(400, null, "Invalid {$key} filter.");
    return (int)$value;
}

function gateRecordDate($key) {
    $value = gateRecordParam($key);
    if ($value === '') return '';
    $date = DateTimeImmutable::createFromFormat('!Y-m-d', $value, new DateTimeZone('Asia/Manila'));
    if (!$date || $date->format('Y-m-d') !== $value || $value < '1000-01-01' || $value > '9999-12-30') {
        sendResponse(400, null, "Invalid {$key} date. Use YYYY-MM-DD.");
    }
    return $value;
}

function readGateRecords($pdo) {
    $page = gateRecordInteger('page', 1, 100000000);
    $limit = gateRecordInteger('limit', 25, 200);
    $sort = gateRecordChoice('sort', ['newest', 'oldest'], 'newest');
    $status = gateRecordChoice('status', ['All', 'Inside', 'Exited', 'Blocked'], 'All');
    $event = gateRecordChoice('event', ['All', 'Entry', 'ExitApproved', 'EntryDenied', 'ExitDenied', 'SecurityHold'], 'All');
    $gate = gateRecordChoice('gate', ['All', 'Gate 1', 'Gate 2'], 'All');
    $source = gateRecordChoice('source', ['All', 'online', 'offline'], 'All');
    $from = gateRecordDate('from'); $to = gateRecordDate('to');
    if ($from !== '' && $to !== '' && $from > $to) sendResponse(400, null, 'Start date must be on or before end date.');
    $timeFrom = gateRecordParam('time_from'); $timeTo = gateRecordParam('time_to');
    foreach ([$timeFrom, $timeTo] as $time) {
        if ($time !== '' && !preg_match('/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/', $time)) sendResponse(400, null, 'Time filters must use HH:MM.');
    }
    $snapshot = isset($_GET['snapshot']) ? gateRecordInteger('snapshot', 1, PHP_INT_MAX) : (int)$pdo->query('SELECT COALESCE(MAX(id),0) FROM gate_logs')->fetchColumn();
    $where = ['id <= ?']; $params = [$snapshot];
    $add = function($sql, ...$values) use (&$where, &$params) { $where[] = $sql; array_push($params, ...$values); };
    if ($from !== '') $add('logged_at >= ?', $from . ' 00:00:00');
    if ($to !== '') {
        $next = (new DateTimeImmutable($to, new DateTimeZone('Asia/Manila')))->modify('+1 day')->format('Y-m-d');
        $add('logged_at < ?', $next . ' 00:00:00');
    }
    // Clock windows repeat on each selected date. 22:00–06:00 crosses midnight.
    $clock = "SUBSTR(logged_at,12,8)";
    if ($timeFrom !== '' && $timeTo !== '' && $timeFrom > $timeTo) {
        $add("({$clock} >= ? OR {$clock} <= ?)", $timeFrom . ':00', $timeTo . ':59');
    } else {
        if ($timeFrom !== '') $add("{$clock} >= ?", $timeFrom . ':00');
        if ($timeTo !== '') $add("{$clock} <= ?", $timeTo . ':59');
    }
    $security = "(status = 'Blocked / Alert' OR LOWER(action) LIKE '%denied%' OR LOWER(action) LIKE '%hold%' OR LOWER(action) LIKE '%flag%' OR LOWER(action) LIKE '%alert%')";
    if ($status === 'Inside') $add("status = 'Inside Campus'");
    if ($status === 'Exited') $add("status = 'Exited'");
    if ($status === 'Blocked' || $event === 'SecurityHold') $add($security);
    $actions = ['Entry'=>'Entry Recorded', 'ExitApproved'=>'Exit Approved', 'EntryDenied'=>'Entry Denied', 'ExitDenied'=>'Exit Denied'];
    if (isset($actions[$event])) $add('action = ?', $actions[$event]);
    if ($gate !== 'All') {
        $number = substr($gate, -1);
        $add("(LOWER(gate_point) = ? OR LOWER(gate_point) LIKE ? OR LOWER(gate_point) = ? OR LOWER(gate_point) LIKE ?)",
            'gate '.$number, 'gate '.$number.' %', 'checkpoint '.$number, 'checkpoint '.$number.' %');
    }
    $hasSynced = columnExists($pdo, 'gate_logs', 'synced_at');
    if ($source === 'offline') $add($hasSynced ? "(synced_at IS NOT NULL AND synced_at <> '')" : '1 = 0');
    if ($source === 'online' && $hasSynced) $add("(synced_at IS NULL OR synced_at = '')");
    $officer = gateRecordParam('officer', '', 400);
    if ($officer !== '') $add('guard_name = ?', $officer);
    $search = gateRecordParam('q');
    if ($search !== '') {
        // LOCATE/INSTR treat user '%' and '_' literally and bind all values.
        $fn = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql' ? 'LOCATE' : 'INSTR';
        $fields = ['plate_number','owner_name','driver_name','gate_point','guard_name','action','status','vehicle_type','notes'];
        $clauses = [];
        foreach ($fields as $field) {
            $clauses[] = $fn === 'LOCATE' ? "LOCATE(LOWER(?),LOWER(COALESCE({$field},''))) > 0" : "INSTR(LOWER(COALESCE({$field},'')),LOWER(?)) > 0";
        }
        $clauses[] = 'id = ?';
        $add('('.implode(' OR ', $clauses).')', ...array_merge(array_fill(0,count($fields),$search), [ctype_digit($search) ? $search : -1]));
    }
    $whereSql = 'WHERE '.implode(' AND ', $where);
    $stmt = $pdo->prepare("SELECT COUNT(*) AS total, COALESCE(SUM(CASE WHEN action='Entry Recorded' THEN 1 ELSE 0 END),0) AS entries,
        COALESCE(SUM(CASE WHEN action='Exit Approved' THEN 1 ELSE 0 END),0) AS exits,
        COALESCE(SUM(CASE WHEN {$security} THEN 1 ELSE 0 END),0) AS security,
        COALESCE(SUM(CASE WHEN status='Inside Campus' THEN 1 ELSE 0 END),0) AS inside,
        COALESCE(SUM(CASE WHEN status='Exited' THEN 1 ELSE 0 END),0) AS exited FROM gate_logs {$whereSql}");
    $stmt->execute($params); $summary = array_map('intval', $stmt->fetch());
    $page = min($page, max(1,(int)ceil($summary['total']/$limit))); $offset = ($page-1)*$limit;
    $extra = $hasSynced ? ', synced_at AS syncedAt' : ', NULL AS syncedAt';
    if (columnExists($pdo, 'gate_logs', 'lookup_method')) $extra .= ', lookup_method AS lookupMethod';
    $direction = $sort === 'oldest' ? 'ASC' : 'DESC';
    $stmt=$pdo->prepare("SELECT id, DATE_FORMAT(logged_at, '%b %d, %Y • %h:%i %p') AS timestamp,
        plate_number AS plateNumber, vehicle_type AS vehicleType, owner_name AS ownerName,
        driver_name AS driverName, driver_relationship AS driverRelationship, gate_point AS gatePoint,
        action, gate_type AS gateType, verified_driver_name AS verifiedDriverName, status,
        guard_name AS guardName, notes, logged_at AS loggedAt {$extra}
        FROM gate_logs {$whereSql} ORDER BY logged_at {$direction}, id {$direction} LIMIT {$limit} OFFSET {$offset}");
    $stmt->execute($params); $rows=$stmt->fetchAll();
    $officers=$pdo->query("SELECT DISTINCT guard_name FROM gate_logs WHERE guard_name IS NOT NULL AND guard_name <> '' ORDER BY guard_name")->fetchAll(PDO::FETCH_COLUMN);
    sendResponse(200, ['rows'=>$rows, 'total'=>$summary['total'], 'page'=>$page, 'limit'=>$limit,
        'snapshot'=>$snapshot, 'summary'=>$summary, 'officers'=>$officers, 'timezone'=>'Asia/Manila']);
}
