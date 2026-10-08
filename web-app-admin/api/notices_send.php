<?php
/**
 * SecurePark API - Send the owner e-mails that are waiting
 *
 * POST /api/notices_send.php   (signed-in guard / admin, or the scanner device key)
 *
 * Entry / exit e-mails are written when the passage is recorded, but on a host that cannot send mail after the response
 * has gone out they must not be sent inside the gate request (a slow mail server would hold up the gate). The apps call
 * this right AFTER a passage has been recorded, in a separate request nobody waits for. Safe to call as often as you like:
 * each waiting e-mail is claimed before it is sent, so it can never go out twice.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/notices.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') sendResponse(405, null, 'Method not allowed');
requireStaffOrScanner($pdo);

$sent = 0;
if (spMailConfigured()) {
    $sent = deliverPendingNotices($pdo);
}
$waiting = (int)$pdo->query("SELECT COUNT(*) FROM `owner_notices` WHERE `email_status` = 'Pending'")->fetchColumn();
sendResponse(200, ['sent' => $sent, 'waiting' => $waiting]);
