<?php
/**
 * SecurePark - Cases
 *
 * One process for everything that holds a vehicle. A case is a violation (key V<id>) or a security incident that is
 * not tied to a violation (key I<id>). Nothing is copied: the case is built from those two tables, and the steps staff
 * log on top of it live in `case_events`.
 *
 *   Reported -> Owner contacted (any number of attempts) -> [Referred to police] -> Awaiting clearance -> Closed
 *
 * Closing (administrators only) needs an outcome and notes:
 *   Clearance signed | Referred to police / vehicle removed | Dismissed (needs a second administrator when there is one)
 * The vehicle's hold is lifted by the existing rules in lib/violations.php when its last open case closes.
 * There are no fines, no strikes and no automatic penalties.
 */

require_once __DIR__ . '/violations.php';
require_once __DIR__ . '/audit.php';

const SP_CASE_OUTCOMES = ['Clearance signed', 'Referred to police / vehicle removed', 'Dismissed'];
const SP_CONTACT_METHODS = ['Phone call', 'Text message', 'In person', 'E-mail', 'Other'];
const SP_CONTACT_RESULTS = ['Reached owner', 'No answer', 'Left message', 'Wrong or unreachable number'];

function caseParseKey($key) {
    if (!preg_match('/^([VI])(\d{1,9})$/', (string)$key, $m)) return null;
    return [$m[1] === 'V' ? 'violation' : 'incident', (int)$m[2]];
}

/** ['kind' => 'violation'|'incident', 'row' => row] or null. An incident tied to a violation is that violation's case. */
function caseLoad($pdo, $key) {
    $parsed = caseParseKey($key);
    if (!$parsed) return null;
    [$kind, $id] = $parsed;
    if ($kind === 'violation') {
        $stmt = $pdo->prepare("SELECT vv.*, v.`owner_name`, v.`owner_phone`, v.`owner_id_number`, v.`owner_role`
            FROM `vehicle_violations` vv JOIN `vehicles` v ON v.`id` = vv.`vehicle_id` WHERE vv.`id` = ? AND vv.`severity` = 'Violation'");
    } else {
        $stmt = $pdo->prepare("SELECT * FROM `security_incidents` WHERE `id` = ? AND `id` NOT IN (SELECT `incident_id` FROM `vehicle_violations` WHERE `incident_id` IS NOT NULL)");
    }
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    return $row ? ['kind' => $kind, 'row' => $row] : null;
}

function caseEventsFor($pdo, array $keys) {
    $out = [];
    if (!$keys) return $out;
    $stmt = $pdo->prepare("SELECT * FROM `case_events` WHERE `case_key` IN (" . implode(',', array_fill(0, count($keys), '?')) . ") ORDER BY `id` ASC");
    $stmt->execute(array_values($keys));
    foreach ($stmt->fetchAll() as $e) $out[$e['case_key']][] = $e;
    return $out;
}

function caseAddEvent($pdo, $actor, $key, $type, array $o = []) {
    $pdo->prepare("INSERT INTO `case_events` (`case_key`, `event_type`, `method`, `result`, `reference`, `note`, `actor_user_id`, `actor_label`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
        ->execute([$key, $type, $o['method'] ?? null, $o['result'] ?? null, $o['reference'] ?? null, $o['note'] ?? null,
            actorUserId($actor), gateActorLabel($actor), date('Y-m-d H:i:s', spNow())]);
}

function caseKeyOf($kind, $row) {
    return ($kind === 'violation' ? 'V' : 'I') . (int)$row['id'];
}

/**
 * The case as the staff list shows it. $events = that case's rows from case_events.
 * Keys: key, kind, type (Violation|Security|Overnight), title, plateNumber, owner..., status (Open|Awaiting clearance|Closed),
 *       step, policeReferred, contactAttempts, lastContactResult, openedAt, openedBy, closedAt, closedBy, outcome, notes.
 */
function caseSummary($kind, $row, array $events) {
    $key = caseKeyOf($kind, $row);
    if ($kind === 'violation') {
        $type = $row['violation_type'] === 'Overnight / Unauthorized Overtime Parking' ? 'Overnight' : 'Violation';
        $closed = $row['status'] !== 'Pending';
        $c = [
            'key' => $key, 'kind' => $kind, 'type' => $type, 'title' => $row['violation_type'], 'description' => $row['description'],
            'plateNumber' => $row['plate_number'], 'vehicleId' => (int)$row['vehicle_id'], 'ownerName' => $row['owner_name'],
            'ownerPhone' => $row['owner_phone'], 'ownerIdNumber' => $row['owner_id_number'],
            'openedAt' => $row['created_at'], 'openedBy' => $row['logged_by'],
            'closedAt' => $closed ? $row['resolved_at'] : null, 'closedBy' => $closed ? $row['resolved_by'] : null,
            'closeNotes' => $closed ? $row['resolution_notes'] : null,
            'violationId' => (int)$row['id'], 'incidentId' => $row['incident_id'] !== null ? (int)$row['incident_id'] : null,
            'caseNumber' => null,
        ];
        $defaultOutcome = $row['status'] === 'Dismissed' ? 'Dismissed' : 'Resolved';
    } else {
        $closed = $row['status'] !== 'Held';
        $c = [
            'key' => $key, 'kind' => $kind, 'type' => 'Security', 'title' => $row['reason'], 'description' => $row['notes'],
            'plateNumber' => $row['plate_number'], 'vehicleId' => null, 'ownerName' => $row['owner_name'], 'ownerPhone' => null, 'ownerIdNumber' => null,
            'openedAt' => $row['reported_at'], 'openedBy' => $row['officer'],
            'closedAt' => $closed ? $row['resolved_at'] : null, 'closedBy' => null, 'closeNotes' => null,
            'violationId' => null, 'incidentId' => (int)$row['id'], 'caseNumber' => $row['case_number'],
        ];
        $defaultOutcome = 'Resolved';
    }
    $contacts = array_values(array_filter($events, fn($e) => $e['event_type'] === 'contact'));
    $awaiting = (bool)array_filter($events, fn($e) => $e['event_type'] === 'awaiting');
    $police = (bool)array_filter($events, fn($e) => $e['event_type'] === 'police');
    $closedEvent = null;
    foreach ($events as $e) if ($e['event_type'] === 'closed') $closedEvent = $e;
    $lastContact = $contacts ? end($contacts) : null;

    $c['status'] = $closed ? 'Closed' : ($awaiting ? 'Awaiting clearance' : 'Open');
    $c['policeReferred'] = $police;
    $c['contactAttempts'] = count($contacts);
    $c['lastContactResult'] = $lastContact ? $lastContact['result'] : null;
    $c['outcome'] = $closed ? ($closedEvent['result'] ?? $defaultOutcome) : null;
    if ($closed) {
        $c['closedAt'] = $c['closedAt'] ?: ($closedEvent['created_at'] ?? null);
        $c['closedBy'] = $c['closedBy'] ?: ($closedEvent['actor_label'] ?? null);
        $c['step'] = 'Closed: ' . $c['outcome'];
    } elseif ($awaiting) {
        $c['step'] = 'Awaiting clearance';
    } elseif ($police) {
        $c['step'] = 'Referred to police';
    } elseif ($lastContact) {
        $c['step'] = $lastContact['result'] === 'Reached owner' ? 'Owner reached' : 'Contact attempted';
    } else {
        $c['step'] = 'Reported';
    }
    return $c;
}

/** Full timeline for the staff drawer: [{at, type, label, detail, by}] oldest first. */
function caseTimeline($kind, $row, array $events, array $summary) {
    $tl = [['at' => $summary['openedAt'], 'type' => 'reported', 'label' => 'Reported', 'detail' => $summary['title'] . ($summary['description'] ? ': ' . $summary['description'] : ''), 'by' => $summary['openedBy']]];
    foreach ($events as $e) {
        switch ($e['event_type']) {
            case 'contact':
                $tl[] = ['at' => $e['created_at'], 'type' => 'contact', 'label' => 'Tried to reach the owner', 'detail' => trim("{$e['method']}: {$e['result']}" . ($e['note'] ? ". {$e['note']}" : '')), 'by' => $e['actor_label']];
                break;
            case 'awaiting':
                $tl[] = ['at' => $e['created_at'], 'type' => 'awaiting', 'label' => 'Waiting for the owner to come in', 'detail' => (string)$e['note'], 'by' => $e['actor_label']];
                break;
            case 'police':
                $tl[] = ['at' => $e['created_at'], 'type' => 'police', 'label' => 'Referred to the police', 'detail' => trim(($e['reference'] ? "Reference {$e['reference']}. " : '') . $e['note']), 'by' => $e['actor_label']];
                break;
            case 'note':
                $tl[] = ['at' => $e['created_at'], 'type' => 'note', 'label' => 'Note', 'detail' => (string)$e['note'], 'by' => $e['actor_label']];
                break;
            case 'closed':
                $tl[] = ['at' => $e['created_at'], 'type' => 'closed', 'label' => 'Closed: ' . $e['result'], 'detail' => (string)$e['note'], 'by' => $e['actor_label']];
                break;
        }
    }
    if ($summary['status'] === 'Closed' && !array_filter($events, fn($e) => $e['event_type'] === 'closed')) {
        $tl[] = ['at' => $summary['closedAt'], 'type' => 'closed', 'label' => 'Closed: ' . $summary['outcome'], 'detail' => (string)$summary['closeNotes'], 'by' => $summary['closedBy']];
    }
    usort($tl, fn($a, $b) => strcmp((string)$a['at'], (string)$b['at']));
    return $tl;
}

/** What the vehicle's owner sees: no staff names, no internal notes. */
function casePublicView($summary, array $events) {
    $tl = [['at' => $summary['openedAt'], 'label' => 'Case opened: ' . $summary['title']]];
    foreach ($events as $e) {
        if ($e['event_type'] === 'contact') {
            $tl[] = ['at' => $e['created_at'], 'label' => $e['result'] === 'Reached owner'
                ? "The Security Office spoke with you ({$e['method']})" : "The Security Office tried to reach you ({$e['method']}) without success"];
        } elseif ($e['event_type'] === 'awaiting') {
            $tl[] = ['at' => $e['created_at'], 'label' => 'Waiting for you to come to the Security Office'];
        } elseif ($e['event_type'] === 'police') {
            $tl[] = ['at' => $e['created_at'], 'label' => 'The case was referred to the police'];
        }
    }
    if ($summary['status'] === 'Closed') $tl[] = ['at' => $summary['closedAt'], 'label' => 'Closed: ' . $summary['outcome']];
    usort($tl, fn($a, $b) => strcmp((string)$a['at'], (string)$b['at']));

    if ($summary['status'] === 'Closed') $next = 'This case is closed. Your vehicle can enter and leave campus again unless another case is open.';
    elseif ($summary['status'] === 'Awaiting clearance') $next = 'Come to the Security Office to sign your clearance. Bring a valid ID.';
    elseif ($summary['policeReferred']) $next = 'Your vehicle was referred to the police. Visit the Security Office to settle this.';
    else $next = 'Please contact or visit the Security Office to settle this case. Your vehicle cannot enter or leave campus until it is closed.';
    return [
        'key' => $summary['key'], 'type' => $summary['type'], 'title' => $summary['title'], 'plateNumber' => $summary['plateNumber'],
        'status' => $summary['status'], 'step' => $summary['step'], 'outcome' => $summary['outcome'],
        'openedAt' => $summary['openedAt'], 'closedAt' => $summary['closedAt'], 'nextStep' => $next, 'timeline' => $tl,
    ];
}

/** All cases (newest first, capped), each with its summary. */
function caseList($pdo, $limit = 300) {
    $limit = max(1, min(400, (int)$limit));
    $v = $pdo->query("SELECT vv.*, v.`owner_name`, v.`owner_phone`, v.`owner_id_number`, v.`owner_role`
        FROM `vehicle_violations` vv JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
        WHERE vv.`severity` = 'Violation' ORDER BY vv.`id` DESC LIMIT {$limit}")->fetchAll();
    $i = $pdo->query("SELECT * FROM `security_incidents`
        WHERE `id` NOT IN (SELECT `incident_id` FROM `vehicle_violations` WHERE `incident_id` IS NOT NULL)
        ORDER BY `id` DESC LIMIT {$limit}")->fetchAll();
    $keys = [];
    foreach ($v as $r) $keys[] = 'V' . $r['id'];
    foreach ($i as $r) $keys[] = 'I' . $r['id'];
    $events = caseEventsFor($pdo, $keys);
    $out = [];
    foreach ($v as $r) $out[] = caseSummary('violation', $r, $events['V' . $r['id']] ?? []);
    foreach ($i as $r) $out[] = caseSummary('incident', $r, $events['I' . $r['id']] ?? []);
    return $out;
}

/** Open case for a plate, for the gate scan: ['key', 'type', 'title', 'step', 'policeReferred'] or null. */
function caseOpenForPlate($pdo, $plate) {
    $norm = normalizePlate($plate);
    $stmt = $pdo->prepare("SELECT vv.*, v.`owner_name`, v.`owner_phone`, v.`owner_id_number`, v.`owner_role`
        FROM `vehicle_violations` vv JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
        WHERE vv.`severity` = 'Violation' AND vv.`status` = 'Pending'
          AND REPLACE(REPLACE(UPPER(vv.`plate_number`), '-', ''), ' ', '') = ? ORDER BY vv.`id` DESC LIMIT 1");
    $stmt->execute([$norm]);
    if ($row = $stmt->fetch()) {
        $c = caseSummary('violation', $row, caseEventsFor($pdo, ['V' . $row['id']])['V' . $row['id']] ?? []);
        return ['key' => $c['key'], 'type' => $c['type'], 'title' => $c['title'], 'step' => $c['step'], 'policeReferred' => $c['policeReferred']];
    }
    return null;
}

/**
 * Closes a case that is not a violation (a security incident): marks it resolved and restores the vehicle's gate status
 * when no other incident holds it. Same rules as PUT /api/incidents.php.
 */
function caseResolveIncident($pdo, $admin, $row, $notes) {
    closeIncident($pdo, $row['id'], $admin, $notes);
    $check = $pdo->prepare("SELECT `id` FROM `security_incidents` WHERE `plate_number` = ? AND `status` = 'Held'");
    $check->execute([$row['plate_number']]);
    if (!$check->fetch()) {
        $logStmt = $pdo->prepare("SELECT `action` FROM `gate_logs`
            WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `action` IN ('Entry Recorded', 'Exit Approved')
            ORDER BY `id` DESC LIMIT 1");
        $logStmt->execute([normalizePlate($row['plate_number'])]);
        $restored = ($logStmt->fetchColumn() === 'Entry Recorded') ? 'Inside Campus' : 'Outside';
        $pdo->prepare("UPDATE `vehicles` SET `status` = ? WHERE `plate_number` = ? AND `status` = 'Blocked / Alert'")->execute([$restored, $row['plate_number']]);
    }
}
