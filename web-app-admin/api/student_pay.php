<?php
/**
 * SecurePark API - Student portal: pay the registration fee online (PayMongo Checkout)
 *
 * POST /api/student_pay.php  { vehicleId, returnUrl }   Start an online payment for one of the student's own Unpaid
 *                                                       vehicles. Returns { checkoutUrl }. returnUrl is the portal's own
 *                                                       address (same host only) where PayMongo sends the student back.
 * GET  /api/student_pay.php?paymentId=ID                Status of one of the student's payments. A Pending online
 *                                                       payment is checked with PayMongo first, so the student sees the
 *                                                       result immediately even before the webhook arrives.
 *
 * Only the server marks a payment paid (webhook or this status check against PayMongo); the browser never can.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/payments.php';
require_once __DIR__ . '/../lib/renewals.php';

$student = requireStudent($pdo);
$ownerId = $student['owner_id_number'];
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'POST') {
    $data = getJsonInput();
    $vehicle = findVehicleById($pdo, (int)($data['vehicleId'] ?? 0));
    if (!$vehicle || $vehicle['owner_id_number'] !== $ownerId) {
        sendResponse(404, null, 'Vehicle not found.');
    }
    $base = safeReturnBase($data['returnUrl'] ?? '');
    if (!$base) sendResponse(400, null, 'Invalid return address.');
    if ((int)$vehicle['is_retired'] === 1) sendResponse(409, ['code' => 'VEHICLE_RETIRED'], 'This vehicle was retired.');

    $opts = [];
    if (($data['purpose'] ?? '') === 'renewal') {
        $info = renewalInfo($pdo, $vehicle);
        if (!$info['eligible']) sendResponse(409, ['code' => 'NOT_RENEWABLE'], $info['blocker'] ?: 'This pass cannot be renewed now.');
        if ($info['fee'] <= 0) sendResponse(409, ['code' => 'FREE_RENEWAL'], 'This renewal has no fee. Ask the Security Office to renew it.');
        $opts = ['purpose' => 'Renewal', 'sticker_year' => (string)$info['targetYear'], 'amount' => $info['fee']];
    } elseif ($vehicle['payment_status'] !== 'Unpaid') {
        sendResponse(409, ['code' => 'NOT_UNPAID'], 'This vehicle has no outstanding registration fee.');
    }

    try {
        $started = startOnlinePayment($pdo, $vehicle, $base, $opts);
    } catch (RuntimeException $e) {
        sendResponse(503, ['code' => 'ONLINE_UNAVAILABLE'], $e->getMessage());
    }
    sendResponse(201, [
        'paymentId' => (int)$started['payment']['id'],
        'checkoutUrl' => $started['checkoutUrl'],
        'amount' => (float)$started['payment']['amount'],
    ]);
}

if ($method === 'GET') {
    $payment = findPayment($pdo, (int)($_GET['paymentId'] ?? 0));
    if (!$payment || $payment['owner_id_number'] !== $ownerId) {
        sendResponse(404, null, 'Payment not found.');
    }
    $payment = refreshOnlinePayment($pdo, $payment);
    sendResponse(200, paymentView($payment));
}

sendResponse(405, null, "Method {$method} not allowed");
