<?php
/**
 * SecurePark API - PayMongo webhook receiver
 *
 * Register this URL in the PayMongo dashboard (Developers > Webhooks) for the event
 * `checkout_session.payment.paid`:   https://<site>/api/paymongo_webhook.php
 * and put the webhook's signing secret in config/secret.php as SP_PAYMONGO_WEBHOOK_SECRET.
 *
 * The request is trusted only if its Paymongo-Signature HMAC matches the raw body.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/payments.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(405, null, 'Method not allowed');
}

$raw = file_get_contents('php://input');
$event = json_decode($raw, true);
$secret = defined('SP_PAYMONGO_WEBHOOK_SECRET') ? SP_PAYMONGO_WEBHOOK_SECRET : '';
$livemode = !empty($event['data']['attributes']['livemode']);

if (!is_array($event) || !paymongoWebhookSignatureValid($raw, $_SERVER['HTTP_PAYMONGO_SIGNATURE'] ?? '', $secret, $livemode)) {
    sendResponse(401, null, 'Invalid signature.');
}

$type = $event['data']['attributes']['type'] ?? '';
if ($type !== 'checkout_session.payment.paid') {
    sendResponse(200, ['ignored' => $type]); // other events are acknowledged and ignored
}

$session = $event['data']['attributes']['data'] ?? [];
$payment = findPaymentBySession($pdo, $session['id'] ?? '');
if (!$payment) {
    sendResponse(200, ['ignored' => 'unknown session']);
}
$paid = paymongoPaidFromSession($session, (float)$payment['amount']);
if (!$paid) {
    error_log("[PayMongo] webhook for payment {$payment['id']} did not carry a paid amount of at least {$payment['amount']}");
    sendResponse(200, ['ignored' => 'amount mismatch']);
}
try {
    settlePayment($pdo, $payment['id'], $paid);
} catch (Exception $e) {
    sendResponse(500, null, 'Could not settle payment.'); // PayMongo will retry
}
sendResponse(200, ['settled' => (int)$payment['id']]);
