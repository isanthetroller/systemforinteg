<?php
/**
 * SecurePark - "This wasn't me" link from an e-mail (entry / exit / blocked notices)
 *
 * GET  /api/notice_report.php?n=<notice id>&s=<signature>   A page that shows the notice and asks for confirmation
 * POST /api/notice_report.php  (the same n and s)           Puts the vehicle on hold and opens a security case
 *
 * The signature is an HMAC of the notice id (see noticeToken()): only the owner who received the e-mail has the link.
 * Nothing happens on GET, so mail scanners that open links cannot trigger a report. Reporting twice is harmless.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/records.php';
require_once __DIR__ . '/../lib/notices.php';
require_once __DIR__ . '/../lib/audit.php';

header('Content-Type: text/html; charset=UTF-8');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');

function reportPage($title, $bodyHtml, $code = 200) {
    http_response_code($code);
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>' . htmlspecialchars($title) . ' - SecurePark</title>'
        . '<style>body{font-family:Arial,Helvetica,sans-serif;background:#f4f6fa;margin:0;padding:24px;color:#0f172a;line-height:1.5}'
        . '.card{max-width:520px;margin:24px auto;background:#fff;border:1px solid #e2e8f0;border-radius:14px;overflow:hidden}'
        . '.top{background:#1b3676;color:#fff;padding:16px 20px}.top b{font-size:16px}.pad{padding:20px}h1{font-size:20px;margin:0 0 12px}'
        . 'table{width:100%;border-collapse:collapse;margin:12px 0;font-size:14px}td{padding:7px 8px;border-bottom:1px solid #e2e8f0}td:first-child{color:#64748b;width:36%}'
        . 'button{background:#b91c1c;color:#fff;border:0;border-radius:8px;padding:12px 18px;font-weight:bold;font-size:15px;cursor:pointer;width:100%}'
        . '.ok{background:#f0fdf4;border:1px solid #bbf7d0;color:#166534;padding:12px 14px;border-radius:8px}.small{color:#64748b;font-size:12px;margin-top:14px}</style></head><body>'
        . '<div class="card"><div class="top"><b>NCST SecurePark</b><br><span style="font-size:12px;opacity:.85">Campus Security Office</span></div><div class="pad">'
        . $bodyHtml . '</div></div></body></html>';
    exit;
}

$noticeId = (int)($_REQUEST['n'] ?? 0);
$token = (string)($_REQUEST['s'] ?? '');
if ($noticeId <= 0 || !noticeTokenValid($noticeId, $token)) {
    reportPage('Link not valid', '<h1>This link is not valid</h1><p>It may be incomplete or out of date. Please go to the Campus Security Office and tell them about your vehicle.</p>', 400);
}
$stmt = $pdo->prepare("SELECT * FROM `owner_notices` WHERE `id` = ?");
$stmt->execute([$noticeId]);
$notice = $stmt->fetch();
if (!$notice) reportPage('Notice not found', '<h1>We could not find this notice</h1><p>Please go to the Campus Security Office.</p>', 404);

$h = fn($v) => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
$what = ['Entry' => 'entered campus', 'Exit' => 'left campus', 'Blocked' => 'was blocked at the gate'][$notice['kind']] ?? 'was recorded';
[$paras, $rows] = noticeSplitMessage($notice['message']);
$table = '<table><tr><td>Vehicle</td><td><b>' . $h($notice['plate_number']) . '</b></td></tr>'
    . '<tr><td>What happened</td><td>' . $h($what) . '</td></tr>';
foreach ($rows as $r) $table .= '<tr><td>' . $h($r[0]) . '</td><td>' . $h($r[1]) . '</td></tr>';
$table .= '</table>';

// Already reported?
$marker = "[notice #{$noticeId}]";
$existing = $pdo->prepare("SELECT `case_number`, `status` FROM `security_incidents` WHERE `notes` LIKE ? ORDER BY `id` DESC LIMIT 1");
$existing->execute(['%' . $marker . '%']);
$already = $existing->fetch();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!$already) {
        $vStmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ?");
        $vStmt->execute([(int)$notice['vehicle_id']]);
        $vehicle = $vStmt->fetch() ?: null;
        $plate = $notice['plate_number'];
        $actor = ['id' => null, 'full_name' => 'Owner report (e-mail link)', 'badge_number' => null, 'role' => 'owner'];
        $incident = openSecurityIncident($pdo, $actor, [
            'plate' => $plate,
            'vehicleType' => $vehicle['vehicle_type'] ?? null,
            'ownerName' => $vehicle['owner_name'] ?? null,
            'ownerRole' => $vehicle['owner_role'] ?? null,
            'driverName' => 'Unknown',
            'driverRelationship' => 'Owner says this was not them',
            'reason' => 'Owner reports: this was not me',
            'gatePoint' => $vehicle['last_gate_point'] ?? 'Campus',
            'notes' => "The owner used the link in the e-mail \"{$notice['title']}\" to say they did not authorize this. {$marker}",
        ]);
        if ($vehicle) {
            $pdo->prepare("UPDATE `vehicles` SET `status` = 'Blocked / Alert' WHERE `id` = ?")->execute([$vehicle['id']]);
        }
        auditLog($pdo, 'Owner (e-mail link)', 'owner.report', ['entityType' => 'vehicle', 'entityId' => $vehicle ? (int)$vehicle['id'] : null, 'plate' => $plate,
            'detail' => "Owner reported notice #{$noticeId} ({$notice['title']}) as not them; case {$incident['caseNumber']}"]);
        $caseNumber = $incident['caseNumber'];
    } else {
        $caseNumber = $already['case_number'];
    }
    reportPage('Report received', '<h1>Thank you, we have your report</h1>'
        . '<div class="ok">Your vehicle <b>' . $h($notice['plate_number']) . '</b> is now on hold at the gate. Case number: <b>' . $h($caseNumber) . '</b></div>'
        . '<p>Please go to the Campus Security Office as soon as you can and give them this case number. They will check what happened and clear the vehicle with you.</p>'
        . '<p class="small">If you reported this by mistake, tell the Security Office and they will close the case.</p>');
}

if ($already) {
    reportPage('Already reported', '<h1>You already reported this</h1><div class="ok">Case number: <b>' . $h($already['case_number']) . '</b></div>'
        . '<p>Please go to the Campus Security Office and give them this case number.</p>');
}

reportPage('Is this you?', '<h1>Is this you?</h1><p>This is what we recorded:</p>' . $table
    . '<p>If this was you, or someone you allowed to drive your vehicle, you can close this page. Nothing else is needed.</p>'
    . '<p>If it was <b>not</b> you, press the button. We will put your vehicle on hold at the gate and the Security Office will follow up.</p>'
    . '<form method="post" action=""><input type="hidden" name="n" value="' . $h($noticeId) . '"><input type="hidden" name="s" value="' . $h($token) . '">'
    . '<button type="submit">This wasn\'t me - put my vehicle on hold</button></form>'
    . '<p class="small">A guard may still stop the vehicle at the gate until the Security Office clears it.</p>');
