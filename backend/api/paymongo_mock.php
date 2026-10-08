<?php
/**
 * SecurePark - LOCAL TEST checkout (stands in for PayMongo while no PayMongo key is configured)
 *
 * Only works when SP_PAYMONGO_SECRET_KEY is not set AND SP_DEBUG is true, i.e. on a developer's
 * machine. On the live site (key set, SP_DEBUG false) this endpoint answers 404 and cannot mark
 * anything paid.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/payments.php';

if (!paymongoMockEnabled()) {
    sendResponse(404, null, 'Not found.');
}

$session = (string)($_GET['session'] ?? $_POST['session'] ?? '');
$returnBase = safeReturnBase($_GET['return'] ?? $_POST['return'] ?? '');
$payment = strpos($session, 'mock_') === 0 ? findPaymentBySession($pdo, $session) : null;
if (!$payment || !$returnBase) {
    sendResponse(404, null, 'Test checkout session not found.');
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (($_POST['do'] ?? '') === 'pay' && $payment['status'] === 'Pending') {
        settlePayment($pdo, $payment['id'], ['provider_payment_id' => 'mock_pay_' . $payment['id'], 'provider_method' => 'test']);
        header('Location: ' . paymentReturnUrl($returnBase, $payment['id'], 'success'));
    } else {
        header('Location: ' . paymentReturnUrl($returnBase, $payment['id'], 'cancelled'));
    }
    exit;
}

header('Content-Type: text/html; charset=UTF-8');
$h = fn($v) => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Test checkout - SecurePark</title>
<style>
  body { font-family: system-ui, sans-serif; background: #f1f5f9; margin: 0; display: grid; place-items: center; min-height: 100vh; }
  .card { background: #fff; border-radius: 14px; padding: 28px; width: min(420px, 92vw); box-shadow: 0 6px 30px rgba(15,23,42,.12); }
  .badge { display: inline-block; background: #fef3c7; color: #92400e; font-size: 12px; font-weight: 700; padding: 3px 9px; border-radius: 99px; }
  h1 { font-size: 20px; margin: 14px 0 4px; color: #0f172a; }
  .amount { font-size: 34px; font-weight: 800; color: #0f172a; margin: 10px 0 2px; }
  p { color: #475569; font-size: 14px; line-height: 1.5; }
  button { width: 100%; padding: 12px; border-radius: 10px; border: 0; font-size: 15px; font-weight: 700; cursor: pointer; margin-top: 10px; }
  .pay { background: #0b2a5b; color: #fff; }
  .cancel { background: #e2e8f0; color: #334155; }
</style>
</head>
<body>
<div class="card">
  <span class="badge">TEST MODE - no real money</span>
  <h1>PayMongo test checkout</h1>
  <p><?= ($payment["purpose"] ?? "") === "Renewal" ? "Pass renewal for" : "Registration fee for" ?> <strong><?= $h($payment['plate_number']) ?></strong> (<?= $h($payment['owner_name']) ?>). This page only appears on a local development server with no PayMongo key.</p>
  <div class="amount">PHP <?= number_format((float)$payment['amount'], 2) ?></div>
  <form method="post">
    <input type="hidden" name="session" value="<?= $h($session) ?>">
    <input type="hidden" name="return" value="<?= $h($returnBase) ?>">
    <button class="pay" name="do" value="pay">Simulate successful payment</button>
    <button class="cancel" name="do" value="cancel">Cancel</button>
  </form>
</div>
</body>
</html>
