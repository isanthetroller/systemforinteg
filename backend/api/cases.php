<?php
/**
 * SecurePark API - Cases (violations and security incidents as one process)
 *
 * GET  /api/cases.php?status=active|open|awaiting|closed|all&type=Violation|Security|Overnight&q=&plate=&from=&to=&outcome=&page=&limit=
 *        Search + counts (staff). Add &format=csv to download the matches as a spreadsheet (admin).
 * GET  /api/cases.php?key=V12                                                                       One case with its timeline (staff)
 * POST /api/cases.php { key, action, ... }
 *        contact   { method, result, note? }          Record an attempt to reach the owner (guard or admin)
 *        awaiting  { note? }                          The owner will come in for clearance (guard or admin)
 *        note      { note }                           Add a note to the timeline (guard or admin)
 *        police    { reason, reference? }             Refer the case to the police (admin; after at least one contact attempt)
 *        close     { outcome, notes }                 Close it (admin): Clearance signed | Referred to police / vehicle removed | Dismissed
 * See lib/cases.php for the rules.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/cases.php';
require_once __DIR__ . '/../lib/approvals.php';
require_once __DIR__ . '/../lib/notices.php';

$method = $_SERVER['REQUEST_METHOD'];
$staff = requireStaff($pdo);

function caseDetail($pdo, $key, $isAdmin) {
    $loaded = caseLoad($pdo, $key);
    if (!$loaded) return null;
    $events = caseEventsFor($pdo, [$key])[$key] ?? [];
    $summary = caseSummary($loaded['kind'], $loaded['row'], $events);
    caseFillOwner($pdo, $summary);
    $summary['timeline'] = caseTimeline($loaded['kind'], $loaded['row'], $events, $summary);
    $plate = $summary['plateNumber'];
    $stmt = $pdo->prepare("SELECT `id`, `status`, `is_banned`, `owner_phone`, `owner_name` FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? ORDER BY `is_retired` ASC, `id` DESC LIMIT 1");
    $stmt->execute([normalizePlate($plate)]);
    $veh = $stmt->fetch();
    $summary['vehicle'] = $veh ? ['id' => (int)$veh['id'], 'status' => $veh['status'], 'isBanned' => (int)$veh['is_banned'] === 1] : null;
    if ($veh && !$summary['ownerPhone']) $summary['ownerPhone'] = $veh['owner_phone'];
    $summary['ownerKnown'] = (bool)$veh;
    $summary['approvalPending'] = $loaded['kind'] === 'violation' && (bool)pendingApproval($pdo, 'violation_dismiss', null, $summary['violationId']);
    $summary['evidence'] = [];
    if ($isAdmin && $summary['violationId']) {
        $stmt = $pdo->prepare("SELECT `id`, `kind`, `plate_read`, `plate_matches`, `created_at`, `taken_by_label`, `purged_at` FROM `evidence_photos` WHERE `violation_id` = ? ORDER BY `id`");
        $stmt->execute([$summary['violationId']]);
        $summary['evidence'] = array_map(fn($r) => ['id' => (int)$r['id'], 'kind' => $r['kind'], 'plateRead' => $r['plate_read'],
            'plateMatches' => $r['plate_matches'] === null ? null : (bool)(int)$r['plate_matches'], 'takenBy' => $r['taken_by_label'], 'createdAt' => $r['created_at'], 'purged' => $r['purged_at'] !== null], $stmt->fetchAll());
    }
    return $summary;
}

if ($method === 'GET') {
    $isAdmin = ($staff['role'] ?? '') === 'admin';
    if (!empty($_GET['key'])) {
        $c = caseDetail($pdo, $_GET['key'], $isAdmin);
        if (!$c) sendResponse(404, null, 'Case not found.');
        sendResponse(200, $c);
    }
    $filters = [
        'status' => $_GET['status'] ?? 'active', 'type' => $_GET['type'] ?? '', 'q' => $_GET['q'] ?? '', 'plate' => $_GET['plate'] ?? '',
        'from' => $_GET['from'] ?? '', 'to' => $_GET['to'] ?? '', 'outcome' => $_GET['outcome'] ?? '',
        'page' => $_GET['page'] ?? 1, 'limit' => $_GET['limit'] ?? 25,
    ];
    if (($_GET['format'] ?? '') === 'csv') {
        if (!$isAdmin) sendResponse(403, null, 'Only an administrator can export cases.');
        $res = caseSearch($pdo, $filters, false);
        $out = fopen('php://temp', 'w+');
        fputcsv($out, ['Case', 'Type', 'Plate', 'Owner', 'Owner ID', 'What happened', 'Opened', 'Opened by', 'Status', 'Outcome', 'Closed', 'Closed by', 'Contact attempts', 'Police referral', 'Closing notes']);
        foreach ($res['rows'] as $c) {
            fputcsv($out, [$c['caseNumber'] ?: $c['key'], $c['type'], $c['plateNumber'], $c['ownerName'], $c['ownerIdNumber'], $c['title'], $c['openedAt'], $c['openedBy'],
                $c['status'], $c['outcome'], $c['closedAt'], $c['closedBy'], $c['contactAttempts'], $c['policeReferred'] ? 'Yes' : 'No', $c['closeNotes']]);
        }
        rewind($out);
        $csv = "\xEF\xBB\xBF" . stream_get_contents($out); // BOM so Excel reads UTF-8
        while (ob_get_level() > 0) @ob_end_clean();
        header('Content-Type: text/csv; charset=UTF-8');
        header('Content-Disposition: attachment; filename="securepark-cases-' . date('Ymd') . '.csv"');
        echo $csv;
        exit;
    }
    $res = caseSearch($pdo, $filters);
    sendResponse(200, ['summary' => caseCounts($pdo), 'cases' => $res['rows'], 'total' => $res['total'],
        'page' => max(1, (int)$filters['page']), 'limit' => max(1, min(100, (int)$filters['limit']))]);
}

if ($method !== 'POST') sendResponse(405, null, "Method {$method} not allowed");

$data = getJsonInput();
$key = (string)($data['key'] ?? '');
$action = (string)($data['action'] ?? '');
$loaded = caseLoad($pdo, $key);
if (!$loaded) sendResponse(404, null, 'Case not found.');
$events = caseEventsFor($pdo, [$key])[$key] ?? [];
$case = caseSummary($loaded['kind'], $loaded['row'], $events);
$row = $loaded['row'];
$isAdmin = ($staff['role'] ?? '') === 'admin';
$plate = $case['plateNumber'];

if ($case['status'] === 'Closed') sendResponse(409, ['code' => 'CASE_CLOSED'], 'This case is already closed.');
if (!in_array($action, ['contact', 'awaiting', 'note'], true) && !$isAdmin) {
    sendResponse(403, null, 'Only an administrator can do this.');
}
$note = trim((string)($data['note'] ?? ''));
if (mb_strlen($note) > 1000) sendResponse(400, null, 'The note is too long (1000 characters max).');

switch ($action) {
    case 'contact':
        $m = (string)($data['method'] ?? '');
        $r = (string)($data['result'] ?? '');
        if (!in_array($m, SP_CONTACT_METHODS, true)) sendResponse(400, null, 'Choose how you tried to reach the owner: ' . implode(', ', SP_CONTACT_METHODS) . '.');
        if (!in_array($r, SP_CONTACT_RESULTS, true)) sendResponse(400, null, 'Choose the result: ' . implode(', ', SP_CONTACT_RESULTS) . '.');
        caseAddEvent($pdo, $staff, $key, 'contact', ['method' => $m, 'result' => $r, 'note' => $note]);
        auditLog($pdo, $staff, 'case.contact', ['entityType' => 'case', 'plate' => $plate, 'detail' => "{$key}: {$m}, {$r}" . ($note !== '' ? ". {$note}" : '')]);
        $message = 'Contact attempt recorded.';
        break;

    case 'awaiting':
        if ($case['status'] === 'Awaiting clearance') sendResponse(409, null, 'This case is already waiting for the owner to come in.');
        caseAddEvent($pdo, $staff, $key, 'awaiting', ['note' => $note]);
        $message = 'Marked as waiting for the owner to come in for clearance.';
        break;

    case 'note':
        if ($note === '') sendResponse(400, null, 'Write the note.');
        caseAddEvent($pdo, $staff, $key, 'note', ['note' => $note]);
        $message = 'Note added.';
        break;

    case 'police':
        if ($case['policeReferred']) sendResponse(409, null, 'This case was already referred to the police.');
        $reason = requireReason($data, 'referring a case to the police');
        $detail = caseDetail($pdo, $key, true);
        if ($detail['ownerKnown'] && $case['contactAttempts'] < 1) {
            sendResponse(409, ['code' => 'CONTACT_REQUIRED'], 'Record at least one attempt to reach the owner before referring the case to the police.');
        }
        $ref = trim((string)($data['reference'] ?? ''));
        caseAddEvent($pdo, $staff, $key, 'police', ['reference' => mb_substr($ref, 0, 100), 'note' => $reason]);
        auditLog($pdo, $staff, 'case.police', ['entityType' => 'case', 'plate' => $plate, 'detail' => "{$key} referred to the police" . ($ref !== '' ? " (ref {$ref})" : ''), 'reason' => $reason]);
        try {
            $vehRow = $detail['vehicle'] ? findVehicleById($pdo, $detail['vehicle']['id']) : null;
            if ($vehRow) {
                queueOwnerNotice($pdo, $vehRow, 'Reminder', "Case referred to the police: {$plate}",
                    "The Security Office could not settle the case on your vehicle {$plate} ({$case['title']}) and referred it to the police. Please visit the Security Office as soon as possible.",
                    ['refKey' => "police:{$key}"]);
            }
        } catch (Exception $e) {
            error_log('[Cases] police notice: ' . $e->getMessage());
        }
        $message = 'Referred to the police. The vehicle stays on hold until the case is closed.';
        break;

    case 'close':
        $outcome = (string)($data['outcome'] ?? '');
        if (!in_array($outcome, SP_CASE_OUTCOMES, true)) sendResponse(400, null, 'Choose an outcome: ' . implode(', ', SP_CASE_OUTCOMES) . '.');
        $notes = requireReason($data, 'closing a case', 'notes');
        $stored = "[{$outcome}] {$notes}";

        if ($loaded['kind'] === 'violation' && $outcome === 'Dismissed' && needsSecondAdmin($pdo)) {
            if (pendingApproval($pdo, 'violation_dismiss', null, (int)$row['id'])) {
                sendResponse(409, ['code' => 'APPROVAL_PENDING'], 'A dismissal for this case is already waiting for a second administrator.');
            }
            $approvalId = createApprovalRequest($pdo, $staff, 'violation_dismiss', null, $row, $notes);
            sendResponse(202, ['approvalPending' => true, 'approvalId' => $approvalId, 'case' => caseDetail($pdo, $key, true)],
                "Dismissal sent for a second administrator's approval. {$plate} stays on hold until then.");
        }

        $pdo->beginTransaction();
        try {
            if ($loaded['kind'] === 'violation') {
                $lifted = ($outcome === 'Dismissed' ? dismissViolation($pdo, $staff, $row, $stored) : resolveViolation($pdo, $staff, $row, $stored))['holdLifted'];
            } else {
                caseResolveIncident($pdo, $staff, $row, $stored);
                $lifted = true;
            }
            caseAddEvent($pdo, $staff, $key, 'closed', ['result' => $outcome, 'note' => $notes]);
            $pdo->commit();
        } catch (Exception $e) {
            $pdo->rollBack();
            sendResponse(500, null, 'Could not close the case.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
        }
        auditLog($pdo, $staff, 'case.close', ['entityType' => 'case', 'plate' => $plate, 'detail' => "{$key} ({$case['title']}) closed: {$outcome}", 'reason' => $notes]);
        $message = $lifted ? "Case closed. {$plate} can enter and leave campus again." : "Case closed. {$plate} still has another open case.";
        break;

    default:
        sendResponse(400, null, 'Unknown action. Use contact, awaiting, note, police or close.');
}

sendResponse(200, ['case' => caseDetail($pdo, $key, $isAdmin)], $message);
