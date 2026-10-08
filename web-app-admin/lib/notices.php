<?php
/**
 * SecurePark - Owner notices (portal + e-mail)
 *
 * When a registered vehicle is blocked at the gate or given a violation, the owner gets
 *   1. a notice in the student portal (always), and
 *   2. an e-mail through SMTP, if the owner has an address on file and SMTP is configured.
 *
 * queueOwnerNotice() only writes the row (safe inside a transaction). The e-mail itself is sent
 * AFTER the API response has been delivered (shutdown function), so a slow or blocked SMTP server
 * never delays the guard's screen. Each notice records how the e-mail went: Sent, Failed (with the
 * reason), Skipped (no address / SMTP not configured) or Pending.
 */

require_once __DIR__ . '/mailer.php';

function ownerEmailFor($pdo, $vehicle) {
    $email = trim((string)($vehicle['owner_email'] ?? ''));
    if ($email !== '' && filter_var($email, FILTER_VALIDATE_EMAIL)) return $email;
    $stmt = $pdo->prepare("SELECT `email` FROM `student_accounts` WHERE `owner_id_number` = ? LIMIT 1");
    $stmt->execute([trim((string)($vehicle['owner_id_number'] ?? ''))]);
    $email = trim((string)$stmt->fetchColumn());
    return ($email !== '' && filter_var($email, FILTER_VALIDATE_EMAIL)) ? $email : null;
}

/**
 * Records a notice for the owner of $vehicle. $kind is 'Violation' or 'Blocked'. Returns the notice id.
 * $rel may carry ['violationId' => .., 'incidentId' => ..].
 */
function queueOwnerNotice($pdo, $vehicle, $kind, $title, $message, array $rel = []) {
    if (!$vehicle || trim((string)($vehicle['owner_id_number'] ?? '')) === '') return null;
    // Reminders carry a key so each is sent only once (e.g. one 30-day expiry notice per pass)
    $refKey = $rel['refKey'] ?? null;
    if ($refKey !== null) {
        $dup = $pdo->prepare("SELECT COUNT(*) FROM `owner_notices` WHERE `ref_key` = ?");
        $dup->execute([$refKey]);
        if ((int)$dup->fetchColumn() > 0) return null;
    }
    $email = ownerEmailFor($pdo, $vehicle);
    $status = $email ? 'Pending' : 'Skipped';
    $error = $email ? null : 'No e-mail address on file for this owner.';
    $stmt = $pdo->prepare("INSERT INTO `owner_notices`
        (`owner_id_number`, `vehicle_id`, `plate_number`, `kind`, `title`, `message`, `email_to`, `email_status`, `email_error`, `violation_id`, `incident_id`, `created_at`, `ref_key`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([
        trim((string)$vehicle['owner_id_number']), $vehicle['id'] ?? null, $vehicle['plate_number'], $kind, $title, $message,
        $email, $status, $error, $rel['violationId'] ?? null, $rel['incidentId'] ?? null, date('Y-m-d H:i:s'), $refKey,
    ]);
    $id = (int)$pdo->lastInsertId();
    // Entry / exit mails are frequent and not urgent: send them right after the response only when the host can finish the
    // response first (fastcgi_finish_request); otherwise they stay Pending and go out with the next maintenance run, so a
    // slow mail server can never hold up a gate.
    $urgent = !in_array($kind, ['Entry', 'Exit'], true);
    if ($email && ($urgent || function_exists('fastcgi_finish_request'))) spScheduleNoticeDelivery();
    return $id;
}

/**
 * A guard blocked / flagged a vehicle (or a forged pass was presented for it): tell the registered owner.
 * Does nothing when the plate is not a registered vehicle.
 */
function noticeVehicleBlocked($pdo, $plate, $reason, $gatePoint, $caseNumber, $incidentId = null) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? LIMIT 1");
    $stmt->execute([strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)$plate))]);
    $vehicle = $stmt->fetch();
    if (!$vehicle) return null;
    $when = date('M j, Y g:i A');
    $person = '';
    if ($incidentId) {
        $i = $pdo->prepare("SELECT `driver_name`, `driver_relationship` FROM `security_incidents` WHERE `id` = ?");
        $i->execute([$incidentId]);
        if ($row = $i->fetch()) {
            $name = trim((string)$row['driver_name']);
            if ($name !== '' && !preg_match('/^(unknown|unverified|registered owner)$/i', $name)) {
                $person = $name . (trim((string)$row['driver_relationship']) !== '' ? ' (' . $row['driver_relationship'] . ')' : '');
            }
        }
    }
    $message = "Your vehicle {$vehicle['plate_number']} was stopped and blocked at the gate. It cannot enter or leave campus until the Security Office clears it.\n"
        . "Reason: {$reason}\n"
        . "Time: {$when}\n"
        . "Gate: {$gatePoint}\n"
        . ($person !== '' ? "Person at the gate: {$person}\n" : '')
        . "Vehicle: " . trim(($vehicle['make_model_color'] ?: $vehicle['vehicle_type'])) . "\n"
        . "Case number: {$caseNumber}";
    return queueOwnerNotice($pdo, $vehicle, 'Blocked', "Vehicle blocked at the gate: {$vehicle['plate_number']}", $message, ['incidentId' => $incidentId]);
}

/**
 * "Is this you?" - tells the owner each time their vehicle enters or leaves campus, with a one-tap way to say it was not
 * them. $gateType is 'Ingress' or 'Egress'. Controlled by the notify_entry_exit setting. Returns the notice id or null.
 */
function noticeVehiclePassage($pdo, $vehicle, $gateType, $gatePoint, $driverName, $driverRelationship, $occurredAt, $guardLabel, $logId = null) {
    if (!$vehicle || (int)spSetting($pdo, 'notify_entry_exit', 1) !== 1) return null;
    $entered = $gateType !== 'Egress';
    $when = date('M j, Y g:i A', strtotime($occurredAt ?: 'now'));
    $person = trim((string)$driverName);
    if ($person !== '' && trim((string)$driverRelationship) !== '' && !preg_match('/^unverified$/i', $driverRelationship)) {
        $person .= " ({$driverRelationship})";
    }
    $message = "Your vehicle {$vehicle['plate_number']} " . ($entered ? 'entered' : 'left') . " campus.\n"
        . "Time: {$when}\n"
        . "Gate: {$gatePoint}\n"
        . ($person !== '' ? "Driver: {$person}\n" : '')
        . "Checked by: {$guardLabel}\n"
        . "Vehicle: " . trim(($vehicle['make_model_color'] ?: $vehicle['vehicle_type']));
    return queueOwnerNotice($pdo, $vehicle, $entered ? 'Entry' : 'Exit',
        ($entered ? 'Entered campus: ' : 'Left campus: ') . $vehicle['plate_number'], $message,
        ['refKey' => $logId ? 'passage:' . (int)$logId : null]);
}

/* ---- the "this wasn't me" link in the e-mails ---- */

/** Base address of the API for links in e-mails: SP_PUBLIC_URL/api on the live site, otherwise this request's own folder. */
function spApiBase() {
    if (defined('SP_PUBLIC_URL') && trim((string)SP_PUBLIC_URL) !== '') return rtrim((string)SP_PUBLIC_URL, '/') . '/api';
    $scheme = function_exists('isSecureRequest') && isSecureRequest() ? 'https' : 'http';
    return $scheme . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/api/x.php')), '/');
}

function noticeToken($noticeId) {
    $secret = defined('SP_QR_SECRET') ? (string)SP_QR_SECRET : 'securepark';
    return rtrim(strtr(base64_encode(substr(hash_hmac('sha256', 'notice-report:' . (int)$noticeId, $secret, true), 0, 16)), '+/', '-_'), '=');
}

function noticeReportUrl($noticeId) {
    return spApiBase() . '/notice_report.php?n=' . (int)$noticeId . '&s=' . noticeToken($noticeId);
}

function noticeTokenValid($noticeId, $token) {
    return is_string($token) && $token !== '' && hash_equals(noticeToken($noticeId), $token);
}

/** Arranges for pending e-mails to be sent once the response has gone out. */
function spScheduleNoticeDelivery() {
    if (!empty($GLOBALS['sp_pending_notices'])) return;
    $GLOBALS['sp_pending_notices'] = true;
    ignore_user_abort(true);
    register_shutdown_function(function () {
        if (!isset($GLOBALS['pdo'])) return;
        try {
            deliverPendingNotices($GLOBALS['pdo']);
        } catch (Throwable $e) {
            error_log('[Notices] delivery failed: ' . $e->getMessage());
        }
    });
}

/** "Label: value" lines of a notice message become a details table; every other line is a paragraph. */
function noticeSplitMessage($message) {
    $rows = [];
    $paras = [];
    foreach (preg_split('/\r?\n/', (string)$message) as $line) {
        $line = trim($line);
        if ($line === '') continue;
        if (preg_match('/^([A-Za-z][A-Za-z \/]{1,26}):\s+(.+)$/', $line, $m)) $rows[] = [$m[1], $m[2]];
        else $paras[] = $line;
    }
    return [$paras, $rows];
}

function noticeSubject($n) {
    $plate = $n['plate_number'];
    switch ($n['kind']) {
        case 'Entry': return "{$plate} entered campus - is this you? - NCST SecurePark";
        case 'Exit': return "{$plate} left campus - is this you? - NCST SecurePark";
        case 'Violation': return "Violation recorded for {$plate}: action needed - NCST SecurePark";
        case 'Reminder': return "Reminder: unresolved violation on {$plate} - NCST SecurePark";
        case 'Expiry': return "Campus pass notice: {$plate} - NCST SecurePark";
        default: return "ACTION NEEDED: {$plate} was blocked at the gate - NCST SecurePark";
    }
}

/**
 * Text and HTML for a notice. Blocked / violation mails carry the details and the numbered steps to get the vehicle
 * cleared; entry / exit mails ask "is this you?" with a one-tap report link.
 */
function noticeEmailBodies($notice, $vehicle) {
    $owner = $vehicle['owner_name'] ?? 'Vehicle owner';
    $plate = $notice['plate_number'];
    $kind = $notice['kind'];
    $portal = defined('SP_PUBLIC_URL') && SP_PUBLIC_URL !== '' ? rtrim((string)SP_PUBLIC_URL, '/') . '/student/' : '';
    [$paras, $rows] = noticeSplitMessage($notice['message']);
    $reportUrl = in_array($kind, ['Entry', 'Exit', 'Blocked'], true) ? noticeReportUrl($notice['id']) : '';
    $case = '';
    foreach ($rows as $r) if (strcasecmp($r[0], 'Case number') === 0) $case = $r[1];

    $heading = [
        'Entry' => 'Is this you? Your vehicle entered campus',
        'Exit' => 'Is this you? Your vehicle left campus',
        'Violation' => 'A violation was recorded: action needed',
        'Reminder' => 'Your vehicle is still on hold',
        'Expiry' => 'About your campus pass',
        'Blocked' => 'Your vehicle was blocked at the gate: action needed',
    ][$kind] ?? $notice['title'];
    $tone = in_array($kind, ['Entry', 'Exit'], true) ? '#1b3676' : ($kind === 'Expiry' ? '#b45309' : '#b91c1c');

    $steps = [];
    if (in_array($kind, ['Blocked', 'Violation', 'Reminder'], true)) {
        $steps = [
            'Do not try to take the vehicle through the gate again until it is cleared. The guard will stop it and it will only delay you.',
            'Go to the Campus Security Office as soon as you can. Bring a valid school ID' . ($case !== '' ? " and tell the officer your case number ({$case})" : ' and tell the officer your plate number') . '.',
            'The officer will explain what happened and may ask you questions. If you cannot come in person, answer the call or message from the Security Office.',
            'If a clearance form is needed, sign it at the office. Once an administrator closes the case, your vehicle can enter and leave campus again.',
            'If the vehicle is inside campus, ask the officer how it will be released (an administrator can allow one exit in an emergency).',
        ];
        if ($portal !== '') $steps[] = "You can follow the progress of your case at any time in the student portal (Cases tab): {$portal}";
    } elseif ($kind === 'Expiry') {
        $steps = ['Renew in the student portal (pay online) or at the Campus Security Office cashier before it expires, so your QR keeps working at the gate.'];
    }

    $ask = '';
    if (in_array($kind, ['Entry', 'Exit'], true)) {
        $ask = "If this was you, or someone you allowed to drive your vehicle, you do not need to do anything.\n"
            . "If this was NOT you, report it right away" . ($reportUrl !== '' ? ": {$reportUrl}" : ' to the Campus Security Office') . ". We will put your vehicle on hold at the gate and the Security Office will follow up.";
    } elseif ($kind === 'Blocked' && $reportUrl !== '') {
        $ask = "If you did not give anyone permission to drive this vehicle, tell us right away: {$reportUrl}";
    }

    // ---------- plain text
    $text = "Dear {$owner},\n\n{$heading}\n\n";
    foreach ($paras as $p) $text .= $p . "\n";
    if ($rows) {
        $text .= "\nDetails\n";
        foreach ($rows as $r) $text .= "  {$r[0]}: {$r[1]}\n";
    }
    if ($steps) {
        $text .= "\nWhat to do\n";
        foreach ($steps as $i => $st) $text .= '  ' . ($i + 1) . ". {$st}\n";
    }
    if ($ask !== '') $text .= "\n{$ask}\n";
    if ($portal !== '' && !$steps) $text .= "\nYou can also see this in the SecurePark student portal: {$portal}\n";
    $text .= "\nNCST Campus Security Office\n(This is an automated message from SecurePark. Please do not reply to it.)\n";

    // ---------- HTML
    $e = fn($s) => htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
    $html = '<div style="font-family:Arial,Helvetica,sans-serif;max-width:580px;margin:auto;color:#0f172a;line-height:1.5">'
        . '<div style="background:#1b3676;color:#fff;padding:16px 20px;border-radius:10px 10px 0 0"><strong style="font-size:16px">NCST SecurePark</strong><br><span style="font-size:12px;opacity:.85">Campus Security Office</span></div>'
        . '<div style="border:1px solid #e2e8f0;border-top:0;padding:20px;border-radius:0 0 10px 10px">'
        . '<p style="margin:0 0 12px">Dear ' . $e($owner) . ',</p>'
        . '<p style="margin:0 0 14px;padding:12px 14px;border-radius:8px;border:1px solid ' . $tone . ';font-size:16px;font-weight:bold;color:' . $tone . '">' . $e($heading) . '</p>';
    foreach ($paras as $p) $html .= '<p style="margin:0 0 10px">' . $e($p) . '</p>';
    if ($rows) {
        $html .= '<table style="width:100%;border-collapse:collapse;margin:8px 0 14px;font-size:14px">';
        foreach ($rows as $r) {
            $html .= '<tr><td style="padding:7px 10px;border-bottom:1px solid #e2e8f0;color:#64748b;width:38%">' . $e($r[0]) . '</td>'
                . '<td style="padding:7px 10px;border-bottom:1px solid #e2e8f0;font-weight:bold">' . $e($r[1]) . '</td></tr>';
        }
        $html .= '</table>';
    }
    if ($steps) {
        $html .= '<p style="margin:14px 0 6px;font-weight:bold">What to do</p><ol style="margin:0 0 14px;padding-left:20px">';
        foreach ($steps as $st) $html .= '<li style="margin-bottom:6px">' . $e($st) . '</li>';
        $html .= '</ol>';
    }
    if (in_array($kind, ['Entry', 'Exit'], true)) {
        $html .= '<p style="margin:14px 0 8px;padding:12px 14px;background:#f1f5f9;border-radius:8px">If this was you, or someone you allowed to drive your vehicle, you do not need to do anything.</p>'
            . '<p style="margin:0 0 8px">If this was <strong>not</strong> you, report it right away. We will put your vehicle on hold at the gate and the Security Office will follow up.</p>'
            . ($reportUrl !== '' ? '<p style="margin:0 0 14px"><a href="' . $e($reportUrl) . '" style="display:inline-block;background:#b91c1c;color:#fff;text-decoration:none;font-weight:bold;padding:11px 18px;border-radius:8px">This wasn\'t me</a></p>' : '');
    } elseif ($kind === 'Blocked' && $reportUrl !== '') {
        $html .= '<p style="margin:0 0 8px">If you did <strong>not</strong> give anyone permission to drive this vehicle, tell us right away:</p>'
            . '<p style="margin:0 0 14px"><a href="' . $e($reportUrl) . '" style="display:inline-block;background:#b91c1c;color:#fff;text-decoration:none;font-weight:bold;padding:11px 18px;border-radius:8px">I did not authorize this</a></p>';
    }
    if ($portal !== '') $html .= '<p style="margin:0 0 14px"><a href="' . $e($portal) . '" style="color:#1b3676">Open the student portal</a></p>';
    $html .= '<p style="margin:16px 0 0;color:#64748b;font-size:12px">NCST Campus Security Office. This is an automated message from SecurePark; please do not reply to it.</p>'
        . '</div></div>';
    return [$text, $html];
}

/** Sends every Pending notice. Returns the number sent. */
function deliverPendingNotices($pdo) {
    $rows = $pdo->query("SELECT * FROM `owner_notices` WHERE `email_status` = 'Pending' ORDER BY `id` ASC LIMIT 20")->fetchAll();
    $sent = 0;
    foreach ($rows as $n) {
        // Claim the row so two overlapping requests never send the same e-mail twice
        $claim = $pdo->prepare("UPDATE `owner_notices` SET `email_status` = 'Sending' WHERE `id` = ? AND `email_status` = 'Pending'");
        $claim->execute([$n['id']]);
        if ($claim->rowCount() !== 1) continue;

        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ? LIMIT 1");
        $stmt->execute([$n['vehicle_id']]);
        $vehicle = $stmt->fetch() ?: ['owner_name' => 'Vehicle owner'];
        [$text, $html] = noticeEmailBodies($n, $vehicle);
        $subject = noticeSubject($n);
        [$ok, $err] = spSendMail($n['email_to'], $subject, $text, $html);
        if (!$ok && !spMailConfigured()) {
            $pdo->prepare("UPDATE `owner_notices` SET `email_status` = 'Skipped', `email_error` = ? WHERE `id` = ?")->execute([$err, $n['id']]);
            continue;
        }
        $pdo->prepare("UPDATE `owner_notices` SET `email_status` = ?, `email_error` = ?, `emailed_at` = ? WHERE `id` = ?")
            ->execute([$ok ? 'Sent' : 'Failed', $ok ? null : substr($err, 0, 250), $ok ? date('Y-m-d H:i:s') : null, $n['id']]);
        if ($ok) $sent++;
    }
    return $sent;
}

function noticeView($n) {
    return [
        'id' => (int)$n['id'],
        'kind' => $n['kind'],
        'title' => $n['title'],
        'message' => $n['message'],
        'plateNumber' => $n['plate_number'],
        'emailStatus' => $n['email_status'],
        'emailed' => $n['email_status'] === 'Sent',
        'createdAt' => $n['created_at'],
    ];
}
