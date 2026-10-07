<?php
/**
 * SecurePark API - Cashier (admin only)
 *
 * GET  /api/payments.php?view=unpaid            Vehicles waiting for their registration fee
 * GET  /api/payments.php[?q=&status=&method=]   Payment history (newest first) + today's totals
 * POST /api/payments.php { action: "cash", vehicleId, tendered? }
 *                                                Record an in-person cash payment: activates the vehicle's QR pass
 *                                                and returns the receipt. Fails if the vehicle is not Unpaid.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/payments.php';

$admin = requireStaff($pdo, ['admin']);
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    if (($_GET['view'] ?? '') === 'unpaid') {
        $rows = $pdo->query("SELECT * FROM `vehicles` WHERE `payment_status` = 'Unpaid' ORDER BY `id` DESC")->fetchAll();
        $open = $pdo->prepare("SELECT COUNT(*) FROM `payments` WHERE `vehicle_id` = ? AND `status` = 'Pending'");
        sendResponse(200, array_map(function ($v) use ($open) {
            $open->execute([$v['id']]);
            return [
                'vehicleId' => (int)$v['id'],
                'plateNumber' => $v['plate_number'],
                'ownerName' => $v['owner_name'],
                'ownerIdNumber' => $v['owner_id_number'],
                'ownerRole' => $v['owner_role'],
                'department' => $v['department'],
                'vehicleType' => $v['vehicle_type'],
                'makeModelColor' => $v['make_model_color'],
                'stickerYear' => $v['sticker_year'],
                'feeAmount' => (float)$v['fee_amount'],
                'registeredAt' => $v['created_at'],
                'onlineCheckoutOpen' => (int)$open->fetchColumn() > 0,
            ];
        }, $rows));
    }

    $where = ["`status` <> 'Cancelled'"];
    $params = [];
    $status = $_GET['status'] ?? '';
    if (in_array($status, ['Pending', 'Paid', 'Cancelled'], true)) {
        $where = ["`status` = ?"];
        $params[] = $status;
    }
    if (in_array($_GET['method'] ?? '', ['Cash', 'PayMongo'], true)) {
        $where[] = "`method` = ?";
        $params[] = $_GET['method'];
    }
    $q = trim($_GET['q'] ?? '');
    if ($q !== '') {
        // Plates match however they are typed (spaces / hyphens / case are ignored)
        $where[] = "(`plate_number` LIKE ? OR REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') LIKE ?
            OR `owner_name` LIKE ? OR `owner_id_number` LIKE ? OR `receipt_number` LIKE ?)";
        array_push($params, "%{$q}%", '%' . normalizePlate($q) . '%', "%{$q}%", "%{$q}%", "%{$q}%");
    }
    $stmt = $pdo->prepare("SELECT * FROM `payments` WHERE " . implode(' AND ', $where) . " ORDER BY `id` DESC LIMIT 300");
    $stmt->execute($params);

    $dayStart = date('Y-m-d') . ' 00:00:00';
    $dayEnd = date('Y-m-d', strtotime('+1 day')) . ' 00:00:00';
    $today = $pdo->prepare("SELECT `method`, COUNT(*) AS n, SUM(`amount`) AS total FROM `payments`
        WHERE `status` = 'Paid' AND `paid_at` >= ? AND `paid_at` < ? GROUP BY `method`");
    $today->execute([$dayStart, $dayEnd]);
    $byMethod = ['Cash' => ['count' => 0, 'total' => 0.0], 'PayMongo' => ['count' => 0, 'total' => 0.0]];
    foreach ($today->fetchAll() as $r) {
        $byMethod[$r['method']] = ['count' => (int)$r['n'], 'total' => (float)$r['total']];
    }
    $unpaid = $pdo->query("SELECT COUNT(*) AS n, COALESCE(SUM(`fee_amount`), 0) AS total FROM `vehicles` WHERE `payment_status` = 'Unpaid'")->fetch();
    $duplicates = (int)$pdo->query("SELECT COUNT(*) FROM `payments` WHERE `notes` LIKE 'DUPLICATE%'")->fetchColumn();

    sendResponse(200, [
        'summary' => [
            'unpaidCount' => (int)$unpaid['n'],
            'unpaidTotal' => (float)$unpaid['total'],
            'collectedToday' => $byMethod['Cash']['total'] + $byMethod['PayMongo']['total'],
            'cashToday' => $byMethod['Cash'],
            'onlineToday' => $byMethod['PayMongo'],
            'duplicates' => $duplicates,
            'onlineAvailable' => paymongoConfigured() || paymongoMockEnabled(),
            'onlineMock' => paymongoMockEnabled(),
        ],
        'payments' => array_map('paymentView', $stmt->fetchAll()),
    ]);
}

if ($method === 'POST') {
    $data = getJsonInput();
    if (($data['action'] ?? '') !== 'cash') {
        sendResponse(400, null, 'Unknown action. Use cash.');
    }
    $vehicle = findVehicleById($pdo, (int)($data['vehicleId'] ?? 0));
    if (!$vehicle) sendResponse(404, null, 'Vehicle not found.');
    if ($vehicle['payment_status'] !== 'Unpaid') {
        sendResponse(409, ['code' => 'NOT_UNPAID'], 'This vehicle has no outstanding registration fee.');
    }
    $fee = (float)$vehicle['fee_amount'];
    $tendered = isset($data['tendered']) && $data['tendered'] !== '' ? round((float)$data['tendered'], 2) : $fee;
    if ($tendered + 0.001 < $fee) {
        sendResponse(400, null, 'Cash received is less than the fee of PHP ' . number_format($fee, 2) . '.');
    }

    try {
        // A cash payment replaces any online checkout the owner left open
        cancelPendingPayments($pdo, $vehicle['id']);
        $by = ['recorded_by' => actorLabel($admin), 'recorded_by_user_id' => actorUserId($admin)];
        $payment = createPendingPayment($pdo, $vehicle, 'Cash', $by);
        $payment = settlePayment($pdo, $payment['id'], $by + ['cash_tendered' => $tendered]);
    } catch (Exception $e) {
        sendResponse(500, null, 'Could not record the payment: ' . $e->getMessage());
    }
    sendResponse(201, [
        'payment' => paymentView($payment),
        'vehicle' => vehicleForOutput($pdo, findVehicleById($pdo, $vehicle['id']), true),
    ], "Payment received for {$vehicle['plate_number']}. The QR pass is now active.");
}

sendResponse(405, null, "Method {$method} not allowed");
