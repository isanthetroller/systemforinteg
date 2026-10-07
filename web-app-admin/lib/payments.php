<?php
/**
 * SecurePark - Registration fee payments (cashier + PayMongo)
 *
 * A newly registered vehicle is 'Unpaid' (or 'Waived' when its fee is 0). It has no usable QR
 * pass until a payment is settled: either an admin records cash at the cashier, or the owner pays
 * online through PayMongo Checkout from the student portal. Settling a payment is the ONE place
 * that flips a vehicle to 'Paid', and it issues a brand-new pass id, so no pass seen before
 * payment can ever be valid.
 *
 * Fees: bicycles / non-plated free; 2-wheel (motorcycle, scooter) and 3-wheel (tricycle) 250;
 * everything else 500.
 */

require_once __DIR__ . '/vehicles.php';

const SP_FEE_TWO_THREE_WHEEL = 250;
const SP_FEE_STANDARD = 500;

function registrationFee($vehicleType, $category = 'plated') {
    $t = strtolower(trim((string)$vehicleType . ' ' . (string)$category));
    if (preg_match('/motor|scooter|tricycle|\b[23]\s*-?\s*wheel/', $t)) return (float)SP_FEE_TWO_THREE_WHEEL;
    if (preg_match('/bicycle|non-?\s?plated|unplated|\bbike\b/', $t)) return 0.0;
    return (float)SP_FEE_STANDARD;
}

/** Payment states that allow the vehicle's QR pass to be shown and accepted at the gate. */
function vehiclePassIsActive($vehicleRow) {
    return ($vehicleRow['payment_status'] ?? 'Paid') !== 'Unpaid';
}

function paymentView($p) {
    if (!$p) return null;
    $amount = (float)$p['amount'];
    $tendered = $p['cash_tendered'] !== null ? (float)$p['cash_tendered'] : null;
    return [
        'id' => (int)$p['id'],
        'receiptNumber' => $p['receipt_number'],
        'vehicleId' => (int)$p['vehicle_id'],
        'plateNumber' => $p['plate_number'],
        'ownerIdNumber' => $p['owner_id_number'],
        'ownerName' => $p['owner_name'],
        'stickerYear' => $p['sticker_year'],
        'amount' => $amount,
        'method' => $p['method'],
        'providerMethod' => $p['provider_method'],
        'status' => $p['status'],
        'cashTendered' => $tendered,
        'change' => $tendered !== null ? round($tendered - $amount, 2) : null,
        'recordedBy' => $p['recorded_by'],
        'notes' => $p['notes'],
        'createdAt' => $p['created_at'],
        'paidAt' => $p['paid_at'],
    ];
}

/** Sum of everything actually paid (online or cash) for a vehicle. */
function paidTotalForVehicle($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT COALESCE(SUM(`amount`), 0) FROM `payments` WHERE `vehicle_id` = ? AND `status` = 'Paid'");
    $stmt->execute([(int)$vehicleId]);
    return (float)$stmt->fetchColumn();
}

function findPayment($pdo, $id) {
    $stmt = $pdo->prepare("SELECT * FROM `payments` WHERE `id` = ? LIMIT 1");
    $stmt->execute([(int)$id]);
    return $stmt->fetch() ?: null;
}

function findPaymentBySession($pdo, $sessionId) {
    $stmt = $pdo->prepare("SELECT * FROM `payments` WHERE `provider_session_id` = ? LIMIT 1");
    $stmt->execute([(string)$sessionId]);
    return $stmt->fetch() ?: null;
}

function createPendingPayment($pdo, $vehicle, $method, $extra = []) {
    $stmt = $pdo->prepare("INSERT INTO `payments`
        (`vehicle_id`, `plate_number`, `owner_id_number`, `owner_name`, `sticker_year`, `amount`, `method`, `status`, `recorded_by`, `recorded_by_user_id`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?, ?, ?)");
    $stmt->execute([
        (int)$vehicle['id'], $vehicle['plate_number'], $vehicle['owner_id_number'], $vehicle['owner_name'],
        $vehicle['sticker_year'] ?? null, (float)$vehicle['fee_amount'], $method,
        $extra['recorded_by'] ?? null, $extra['recorded_by_user_id'] ?? null, date('Y-m-d H:i:s'),
    ]);
    return findPayment($pdo, $pdo->lastInsertId());
}

/**
 * Marks a payment Paid and activates the vehicle's pass. Idempotent (webhook retries, a double
 * click and the return-page check can all arrive for the same payment).
 *
 * If the vehicle was already settled some other way (cash while an online checkout was open), the
 * money was still received, so the payment is recorded Paid with a refund note instead of being lost.
 */
function settlePayment($pdo, $paymentId, array $extra = []) {
    $pdo->beginTransaction();
    try {
        $p = findPayment($pdo, $paymentId);
        if (!$p) throw new RuntimeException('Payment not found.');
        if ($p['status'] === 'Paid') {
            $pdo->commit();
            return $p;
        }

        $now = date('Y-m-d H:i:s');
        $vehicle = findVehicleById($pdo, $p['vehicle_id']);
        $duplicate = !$vehicle || $vehicle['payment_status'] !== 'Unpaid';

        $set = ['status' => 'Paid', 'paid_at' => $now, 'receipt_number' => sprintf('OR-%s-%06d', date('Y'), $p['id'])];
        foreach (['provider_payment_id', 'provider_method', 'cash_tendered', 'recorded_by', 'recorded_by_user_id'] as $col) {
            if (array_key_exists($col, $extra)) $set[$col] = $extra[$col];
        }
        if ($duplicate) {
            $set['notes'] = 'DUPLICATE: the vehicle was already settled when this payment arrived. Refund it.';
        }
        $cols = array_map(fn($c) => "`{$c}` = ?", array_keys($set));
        $pdo->prepare("UPDATE `payments` SET " . implode(', ', $cols) . " WHERE `id` = ?")
            ->execute(array_merge(array_values($set), [$p['id']]));

        if (!$duplicate) {
            // New pass id: any QR derived from the pre-payment id stops matching
            // fee_amount of a paid vehicle = everything paid so far (a later fee change only charges the difference)
            $pdo->prepare("UPDATE `vehicles` SET `payment_status` = 'Paid', `paid_at` = ?, `fee_amount` = ?, `pass_id` = ?, `qr_pass_code` = NULL WHERE `id` = ?")
                ->execute([$now, paidTotalForVehicle($pdo, $vehicle['id']), newPassId(), $vehicle['id']]);
        }
        $pdo->commit();
    } catch (Exception $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
    return findPayment($pdo, $paymentId);
}

/** Cancels open online checkouts for a vehicle (a newer checkout or a cash payment replaces them). */
function cancelPendingPayments($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT * FROM `payments` WHERE `vehicle_id` = ? AND `status` = 'Pending'");
    $stmt->execute([(int)$vehicleId]);
    foreach ($stmt->fetchAll() as $p) {
        if ($p['method'] === 'PayMongo' && paymongoConfigured() && !empty($p['provider_session_id'])
            && strpos($p['provider_session_id'], 'mock_') !== 0) {
            paymongoRequest('POST', '/checkout_sessions/' . rawurlencode($p['provider_session_id']) . '/expire');
        }
        $pdo->prepare("UPDATE `payments` SET `status` = 'Cancelled' WHERE `id` = ? AND `status` = 'Pending'")->execute([$p['id']]);
    }
}

/* --------------------------------------------------------------------------
   PayMongo (https://developers.paymongo.com) - Checkout Sessions
   -------------------------------------------------------------------------- */

function paymongoConfigured() {
    return defined('SP_PAYMONGO_SECRET_KEY') && SP_PAYMONGO_SECRET_KEY !== ''
        && strpos(SP_PAYMONGO_SECRET_KEY, 'CHANGE_ME') === false;
}

/** With no PayMongo key and SP_DEBUG on (local development), a built-in fake checkout page stands in. */
function paymongoMockEnabled() {
    return !paymongoConfigured() && defined('SP_DEBUG') && SP_DEBUG === true;
}

function paymongoRequest($method, $path, $body = null) {
    if (!paymongoConfigured()) return ['ok' => false, 'status' => 0, 'data' => null, 'error' => 'PayMongo is not configured.'];
    $url = 'https://api.paymongo.com/v1' . $path;
    $headers = ['Content-Type: application/json', 'Accept: application/json',
        'Authorization: Basic ' . base64_encode(SP_PAYMONGO_SECRET_KEY . ':')];
    $payload = $body !== null ? json_encode($body) : null;
    $status = 0; $raw = false; $error = '';

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HTTPHEADER => $headers,
            CURLOPT_TIMEOUT => 20, CURLOPT_CONNECTTIMEOUT => 8]);
        if ($payload !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
        $raw = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);
    } else {
        $ctx = stream_context_create(['http' => ['method' => $method, 'header' => implode("\r\n", $headers),
            'content' => $payload ?? '', 'timeout' => 20, 'ignore_errors' => true]]);
        $raw = @file_get_contents($url, false, $ctx);
        if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) $status = (int)$m[1];
        if ($raw === false) $error = 'Could not reach PayMongo.';
    }
    if ($raw === false || $status === 0) {
        return ['ok' => false, 'status' => $status, 'data' => null, 'error' => $error ?: 'Could not reach PayMongo.'];
    }
    $data = json_decode($raw, true);
    $ok = $status >= 200 && $status < 300 && is_array($data);
    $message = '';
    if (!$ok && is_array($data) && !empty($data['errors'][0]['detail'])) $message = $data['errors'][0]['detail'];
    return ['ok' => $ok, 'status' => $status, 'data' => $data, 'error' => $ok ? '' : ($message ?: "PayMongo returned HTTP {$status}.")];
}

/**
 * The student portal's own address, taken from the browser, may only point back at this same host.
 * Returns the validated base URL (no query/fragment) or null.
 */
function safeReturnBase($url) {
    $parts = parse_url((string)$url);
    if (!$parts || empty($parts['host']) || empty($parts['scheme']) || !in_array($parts['scheme'], ['http', 'https'], true)) return null;
    $requestHost = strtolower(preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST'] ?? ''));
    if (strtolower($parts['host']) !== $requestHost) return null;
    return $parts['scheme'] . '://' . $parts['host'] . (isset($parts['port']) ? ':' . $parts['port'] : '') . ($parts['path'] ?? '/');
}

function paymentReturnUrl($base, $paymentId, $outcome) {
    return $base . '?payment=' . $outcome . '&p=' . (int)$paymentId;
}

/**
 * Starts an online payment for an Unpaid vehicle. Returns the Pending payment row with its checkout URL.
 * Throws RuntimeException with a user-safe message on failure.
 */
function startOnlinePayment($pdo, $vehicle, $returnBase) {
    cancelPendingPayments($pdo, $vehicle['id']);
    $payment = createPendingPayment($pdo, $vehicle, 'PayMongo');

    if (paymongoMockEnabled()) {
        $session = 'mock_' . bin2hex(random_bytes(8));
        $pdo->prepare("UPDATE `payments` SET `provider_session_id` = ? WHERE `id` = ?")->execute([$session, $payment['id']]);
        $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $dir = rtrim(dirname($_SERVER['SCRIPT_NAME']), '/');
        $url = $scheme . '://' . $_SERVER['HTTP_HOST'] . $dir . '/paymongo_mock.php?session=' . $session . '&return=' . rawurlencode($returnBase);
        return ['payment' => findPayment($pdo, $payment['id']), 'checkoutUrl' => $url, 'mock' => true];
    }
    if (!paymongoConfigured()) {
        $pdo->prepare("UPDATE `payments` SET `status` = 'Cancelled' WHERE `id` = ?")->execute([$payment['id']]);
        throw new RuntimeException('Online payment is not available yet. Please pay at the cashier.');
    }

    $methods = defined('SP_PAYMONGO_METHODS') ? SP_PAYMONGO_METHODS : ['gcash', 'paymaya', 'card'];
    $res = paymongoRequest('POST', '/checkout_sessions', ['data' => ['attributes' => [
        'line_items' => [[
            'currency' => 'PHP',
            'amount' => (int)round(((float)$payment['amount']) * 100),
            'name' => 'SecurePark vehicle registration ' . $vehicle['plate_number'] . ' (' . ($vehicle['sticker_year'] ?? date('Y')) . ')',
            'quantity' => 1,
        ]],
        'payment_method_types' => $methods,
        'description' => 'NCST campus vehicle registration fee',
        'reference_number' => 'SP-PAY-' . $payment['id'],
        'send_email_receipt' => false,
        'show_description' => true,
        'success_url' => paymentReturnUrl($returnBase, $payment['id'], 'success'),
        'cancel_url' => paymentReturnUrl($returnBase, $payment['id'], 'cancelled'),
        'metadata' => ['payment_id' => (string)$payment['id'], 'plate' => $vehicle['plate_number']],
    ]]]);
    $sessionId = $res['data']['data']['id'] ?? null;
    $checkoutUrl = $res['data']['data']['attributes']['checkout_url'] ?? null;
    if (!$res['ok'] || !$sessionId || !$checkoutUrl) {
        error_log('[PayMongo] checkout failed: ' . $res['error']);
        $pdo->prepare("UPDATE `payments` SET `status` = 'Cancelled', `notes` = ? WHERE `id` = ?")
            ->execute([substr('Checkout failed: ' . $res['error'], 0, 250), $payment['id']]);
        throw new RuntimeException('Could not start the online payment. Please try again or pay at the cashier.');
    }
    $pdo->prepare("UPDATE `payments` SET `provider_session_id` = ? WHERE `id` = ?")->execute([$sessionId, $payment['id']]);
    return ['payment' => findPayment($pdo, $payment['id']), 'checkoutUrl' => $checkoutUrl, 'mock' => false];
}

/**
 * Asks PayMongo whether a Pending online payment has been paid and settles it if so.
 * Used when the owner returns from checkout (the webhook may be slower, or unreachable in development).
 */
function refreshOnlinePayment($pdo, $payment) {
    if ($payment['status'] !== 'Pending' || $payment['method'] !== 'PayMongo' || empty($payment['provider_session_id'])) return $payment;
    if (strpos($payment['provider_session_id'], 'mock_') === 0) return $payment; // the mock page settles by itself
    $res = paymongoRequest('GET', '/checkout_sessions/' . rawurlencode($payment['provider_session_id']));
    if (!$res['ok']) return $payment;
    $paid = paymongoPaidFromSession($res['data']['data'] ?? [], (float)$payment['amount']);
    if ($paid) return settlePayment($pdo, $payment['id'], $paid);
    return $payment;
}

/**
 * Reads a PayMongo checkout session resource. Returns settle-extras when a payment of at least
 * $expectedAmount succeeded, otherwise null.
 */
function paymongoPaidFromSession($session, $expectedAmount) {
    $attrs = $session['attributes'] ?? [];
    foreach (($attrs['payments'] ?? []) as $pay) {
        $pa = $pay['attributes'] ?? [];
        if (($pa['status'] ?? '') !== 'paid') continue;
        if (((int)($pa['amount'] ?? 0)) < (int)round($expectedAmount * 100)) continue;
        return [
            'provider_payment_id' => $pay['id'] ?? null,
            'provider_method' => $pa['source']['type'] ?? null,
        ];
    }
    return null;
}

/** Verifies the Paymongo-Signature header of a webhook call against the raw request body. */
function paymongoWebhookSignatureValid($rawBody, $header, $secret, $livemode) {
    if ($secret === '' || $header === '') return false;
    $parts = [];
    foreach (explode(',', $header) as $piece) {
        $kv = explode('=', trim($piece), 2);
        if (count($kv) === 2) $parts[$kv[0]] = $kv[1];
    }
    if (empty($parts['t'])) return false;
    $expected = hash_hmac('sha256', $parts['t'] . '.' . $rawBody, $secret);
    $given = $livemode ? ($parts['li'] ?? '') : ($parts['te'] ?? '');
    return $given !== '' && hash_equals($expected, $given);
}
