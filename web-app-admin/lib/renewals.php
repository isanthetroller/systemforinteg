<?php
/**
 * SecurePark - Yearly pass renewal
 *
 * A pass runs to Dec 31 of its sticker year. Renewal opens `renewal_window_days` (default 60) before that date and
 * stays open after it. It costs the same fee schedule as registration (bicycles free). Paying (cash at the cashier,
 * or online through PayMongo) extends the pass to Dec 31 of the target year, updates the sticker year and issues a
 * fresh pass id. A vehicle that never paid its registration must do that first. Retired vehicles cannot renew.
 */

require_once __DIR__ . '/payments.php';
require_once __DIR__ . '/settings.php';
require_once __DIR__ . '/audit.php';

/**
 * Renewal state of a vehicle:
 * ['eligible' => bool, 'due' => bool, 'expired' => bool, 'daysLeft' => int|null, 'fee' => float, 'targetYear' => int,
 *  'newValidUntil' => 'YYYY-12-31', 'blocker' => string|null]
 */
function renewalInfo($pdo, $vehicle, $today = null) {
    $today = $today ?: date('Y-m-d');
    $until = $vehicle['pass_valid_until'] ?? null;
    $info = ['eligible' => false, 'due' => false, 'expired' => false, 'daysLeft' => null, 'fee' => 0.0, 'targetYear' => (int)date('Y', strtotime($today)),
        'newValidUntil' => null, 'blocker' => null];
    if (!$until) { $info['blocker'] = 'This vehicle has no pass date yet.'; return $info; }

    $daysLeft = (int)floor((strtotime($until) - strtotime($today)) / 86400);
    $target = max((int)date('Y', strtotime($until)) + 1, (int)date('Y', strtotime($today)));
    $fee = isVipVehicle($vehicle) ? 0.0 : registrationFee($vehicle['vehicle_type'], $vehicle['category']);
    $window = (int)spSetting($pdo, 'renewal_window_days');

    $info['daysLeft'] = $daysLeft;
    $info['expired'] = $daysLeft < 0;
    $info['due'] = $daysLeft <= $window;
    $info['fee'] = $fee;
    $info['targetYear'] = $target;
    $info['newValidUntil'] = "{$target}-12-31";

    if ((int)($vehicle['is_retired'] ?? 0) === 1) {
        $info['blocker'] = 'This vehicle was retired.';
    } elseif (($vehicle['payment_status'] ?? 'Paid') === 'Unpaid') {
        $info['blocker'] = 'Pay the registration fee first.';
    } elseif (!$info['due']) {
        $info['blocker'] = "Renewal opens {$window} days before the pass expires.";
    } else {
        $info['eligible'] = true;
    }
    return $info;
}

/**
 * Renews a vehicle at the cashier. $method is 'Cash' (fee collected) or 'Free' (fee 0).
 * Returns ['payment' => row, 'vehicle' => row] or throws RuntimeException with a user-safe message.
 */
function renewAtCashier($pdo, $admin, $vehicle, $method, $tendered = null) {
    $info = renewalInfo($pdo, $vehicle);
    if (!$info['eligible']) throw new RuntimeException($info['blocker'] ?: 'This vehicle cannot be renewed now.');
    if ($method === 'Free' && $info['fee'] > 0) throw new RuntimeException('This renewal has a fee. Receive the cash instead.');
    if ($method === 'Cash') {
        if ($info['fee'] <= 0) throw new RuntimeException('This renewal is free. Use the free renewal.');
        if ($tendered !== null && $tendered + 0.001 < $info['fee']) throw new RuntimeException('Cash received is less than the fee of PHP ' . number_format($info['fee'], 2) . '.');
    }
    cancelPendingPayments($pdo, $vehicle['id']);
    $by = ['recorded_by' => actorLabel($admin), 'recorded_by_user_id' => actorUserId($admin)];
    $payment = createPendingPayment($pdo, $vehicle, $method, $by + ['purpose' => 'Renewal', 'sticker_year' => (string)$info['targetYear'], 'amount' => $info['fee']]);
    $payment = settlePayment($pdo, $payment['id'], $by + ['cash_tendered' => $method === 'Cash' ? ($tendered ?? $info['fee']) : null]);
    auditLog($pdo, $admin, $method === 'Free' ? 'renewal.free' : 'renewal.cash', ['entityType' => 'vehicle', 'entityId' => (int)$vehicle['id'], 'plate' => $vehicle['plate_number'],
        'detail' => "{$payment['receipt_number']}: pass renewed to {$info['newValidUntil']}" . ($method === 'Cash' ? ', PHP ' . number_format($info['fee'], 2) : ' (no fee)')]);
    return ['payment' => $payment, 'vehicle' => findVehicleById($pdo, $vehicle['id'])];
}
