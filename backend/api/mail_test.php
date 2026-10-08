<?php
/**
 * SecurePark API - Send a test e-mail (admin only)
 *
 * POST /api/mail_test.php { to }   Sends one message through the configured SMTP account and reports exactly what happened,
 *                                  including why it failed (blocked port, wrong login...). Used from Admin Center > Settings.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/mailer.php';
require_once __DIR__ . '/../lib/audit.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') sendResponse(405, null, 'Method not allowed');
$admin = requireStaff($pdo, ['admin']);
$data = getJsonInput();
$to = trim((string)($data['to'] ?? ''));
if (!filter_var($to, FILTER_VALIDATE_EMAIL)) sendResponse(400, null, 'Enter a valid e-mail address to send the test to.');
if (!spMailConfigured()) {
    sendResponse(409, ['code' => 'MAIL_NOT_CONFIGURED'], 'E-mail is not set up on this server yet (SP_SMTP_HOST and SP_MAIL_FROM are missing in config/secret.php).');
}

$started = microtime(true);
[$ok, $err] = spSendMail($to, 'SecurePark test e-mail', "This is a test message from NCST SecurePark.\n\nIf you can read it, e-mail notices to vehicle owners will work.\n",
    '<div style="font-family:Arial,sans-serif"><h3>SecurePark test e-mail</h3><p>If you can read this, e-mail notices to vehicle owners will work.</p></div>');
$seconds = round(microtime(true) - $started, 1);
auditLog($pdo, $admin, 'mail.test', ['detail' => "Test e-mail to {$to}: " . ($ok ? 'sent' : 'failed - ' . $err)]);
if ($ok) sendResponse(200, ['seconds' => $seconds, 'host' => SP_SMTP_HOST, 'port' => defined('SP_SMTP_PORT') ? SP_SMTP_PORT : 587], "Test e-mail sent to {$to}. Check the inbox (and the spam folder).");
sendResponse(502, ['code' => 'MAIL_FAILED', 'seconds' => $seconds], 'The test e-mail could not be sent: ' . $err);
