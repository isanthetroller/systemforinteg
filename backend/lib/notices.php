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
    if ($email) spScheduleNoticeDelivery();
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
    $message = "Your vehicle {$vehicle['plate_number']} was blocked at the gate ({$gatePoint}) on {$when}.\nReason: {$reason}.\nIt is being held under case {$caseNumber}.";
    return queueOwnerNotice($pdo, $vehicle, 'Blocked', 'Vehicle blocked at the gate', $message, ['incidentId' => $incidentId]);
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

function noticeEmailBodies($notice, $vehicle) {
    $owner = $vehicle['owner_name'] ?? 'Vehicle owner';
    $plate = $notice['plate_number'];
    $portal = defined('SP_PUBLIC_URL') && SP_PUBLIC_URL !== '' ? rtrim((string)SP_PUBLIC_URL, '/') . '/student/' : '';
    $steps = [
        'Violation' => "Your vehicle cannot enter or leave campus until the Campus Security Office resolves this violation. Please visit the Security Office.",
        'Reminder' => "Your vehicle still cannot enter or leave campus. Please visit the Campus Security Office to settle the violation.",
        'Expiry' => "Renew in the student portal (pay online) or at the Campus Security Office cashier before it expires, so your QR keeps working at the gate.",
    ][$notice['kind']] ?? "Your vehicle was stopped at the gate and is being held. Please contact or visit the Campus Security Office.";
    $text = "Dear {$owner},\n\n{$notice['message']}\n\nVehicle: {$plate}\n\n{$steps}\n"
        . ($portal !== '' ? "\nYou can also see this notice in the SecurePark student portal: {$portal}\n" : '')
        . "\nNCST Campus Security Office\n(This is an automated message from SecurePark.)\n";
    $e = fn($s) => htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
    $html = '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#0f172a">'
        . '<div style="background:#1b3676;color:#fff;padding:16px 20px;border-radius:10px 10px 0 0"><strong>NCST SecurePark</strong><br><span style="font-size:12px;opacity:.85">Campus Security Notice</span></div>'
        . '<div style="border:1px solid #e2e8f0;border-top:0;padding:20px;border-radius:0 0 10px 10px">'
        . '<p>Dear ' . $e($owner) . ',</p>'
        . '<p style="background:#fef2f2;border-left:4px solid #dc2626;padding:12px 14px;margin:16px 0"><strong>' . $e($notice['title']) . '</strong><br>' . nl2br($e($notice['message'])) . '</p>'
        . '<p><strong>Vehicle:</strong> <span style="font-family:monospace;font-size:16px">' . $e($plate) . '</span></p>'
        . '<p>' . $e($steps) . '</p>'
        . ($portal !== '' ? '<p><a href="' . $e($portal) . '">Open the student portal</a></p>' : '')
        . '<p style="color:#64748b;font-size:12px">NCST Campus Security Office. This is an automated message from SecurePark.</p>'
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
        $subject = ([
            'Violation' => 'Violation recorded for ',
            'Reminder' => 'Reminder: unresolved violation on ',
            'Expiry' => 'Campus pass expiring: ',
        ][$n['kind']] ?? 'Vehicle blocked at the gate: ') . $n['plate_number'] . ' - NCST SecurePark';
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
