<?php
/**
 * SecurePark API - Pass renewals (admin only)
 *
 * GET  /api/renewals.php                          Vehicles whose renewal is open (expiring within the window or expired)
 * POST /api/renewals.php { action: "cash", vehicleId, tendered? }   Renew at the cashier with cash
 * POST /api/renewals.php { action: "free", vehicleId }              Renew a free (bicycle / VIP) vehicle
 * POST /api/renewals.php { action: "bulk", vehicleIds: [..], cashCollected: true }
 *        Renew many at once: free ones directly, paid ones as exact cash (the cashier confirms the total was collected)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/renewals.php';

$admin = requireStaff($pdo, ['admin']);
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $window = (int)spSetting($pdo, 'renewal_window_days');
    $cutoff = date('Y-m-d', strtotime("+{$window} days"));
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `is_retired` = 0 AND `pass_valid_until` IS NOT NULL AND `pass_valid_until` <= ? ORDER BY `pass_valid_until` ASC, `id` ASC");
    $stmt->execute([$cutoff]);
    $open = $pdo->prepare("SELECT COUNT(*) FROM `payments` WHERE `vehicle_id` = ? AND `status` = 'Pending' AND `purpose` = 'Renewal'");
    $rows = [];
    $totalFee = 0.0;
    $expired = 0;
    foreach ($stmt->fetchAll() as $v) {
        $info = renewalInfo($pdo, $v);
        $open->execute([$v['id']]);
        if ($info['expired']) $expired++;
        if ($info['eligible']) $totalFee += $info['fee'];
        $rows[] = [
            'vehicleId' => (int)$v['id'], 'plateNumber' => $v['plate_number'], 'ownerName' => $v['owner_name'], 'ownerIdNumber' => $v['owner_id_number'],
            'ownerRole' => $v['owner_role'], 'vehicleType' => $v['vehicle_type'], 'isVip' => isVipVehicle($v),
            'passValidUntil' => $v['pass_valid_until'], 'daysLeft' => $info['daysLeft'], 'expired' => $info['expired'],
            'fee' => $info['fee'], 'targetYear' => $info['targetYear'], 'newValidUntil' => $info['newValidUntil'],
            'eligible' => $info['eligible'], 'blocker' => $info['blocker'], 'onlineCheckoutOpen' => (int)$open->fetchColumn() > 0,
        ];
    }
    sendResponse(200, ['windowDays' => $window, 'summary' => ['due' => count($rows), 'expired' => $expired, 'feesToCollect' => $totalFee], 'vehicles' => $rows]);
}

if ($method !== 'POST') sendResponse(405, null, "Method {$method} not allowed");

$data = getJsonInput();
$action = $data['action'] ?? '';

if (in_array($action, ['cash', 'free'], true)) {
    $vehicle = findVehicleById($pdo, (int)($data['vehicleId'] ?? 0));
    if (!$vehicle) sendResponse(404, null, 'Vehicle not found.');
    try {
        $tendered = isset($data['tendered']) && $data['tendered'] !== '' ? round((float)$data['tendered'], 2) : null;
        $res = renewAtCashier($pdo, $admin, $vehicle, $action === 'free' ? 'Free' : 'Cash', $tendered);
    } catch (RuntimeException $e) {
        sendResponse(409, ['code' => 'NOT_RENEWABLE'], $e->getMessage());
    } catch (Exception $e) {
        sendResponse(500, null, 'Could not renew the pass: ' . $e->getMessage());
    }
    sendResponse(201, ['payment' => paymentView($res['payment']), 'vehicle' => vehicleForOutput($pdo, $res['vehicle'], true)],
        "Pass of {$vehicle['plate_number']} renewed until {$res['vehicle']['pass_valid_until']}.");
}

if ($action === 'bulk') {
    $ids = array_values(array_unique(array_map('intval', is_array($data['vehicleIds'] ?? null) ? $data['vehicleIds'] : [])));
    if (!$ids) sendResponse(400, null, 'Select at least one vehicle.');
    if (count($ids) > 200) sendResponse(400, null, 'Renew at most 200 vehicles at once.');
    $results = [];
    $collected = 0.0;
    $renewed = 0;
    // First work out what the cashier must have collected, so a missing confirmation is refused before anything changes
    $plan = [];
    $due = 0.0;
    foreach ($ids as $id) {
        $v = findVehicleById($pdo, $id);
        $info = $v ? renewalInfo($pdo, $v) : null;
        $plan[$id] = [$v, $info];
        if ($v && $info['eligible']) $due += $info['fee'];
    }
    if ($due > 0 && empty($data['cashCollected'])) {
        sendResponse(400, ['code' => 'CASH_CONFIRMATION_REQUIRED', 'totalDue' => $due], 'Collect PHP ' . number_format($due, 2) . ' in cash and confirm it before renewing these vehicles.');
    }
    foreach ($plan as $id => [$v, $info]) {
        if (!$v) { $results[] = ['vehicleId' => $id, 'ok' => false, 'message' => 'Vehicle not found.']; continue; }
        try {
            $res = renewAtCashier($pdo, $admin, $v, $info['fee'] > 0 ? 'Cash' : 'Free');
            $renewed++;
            $collected += (float)$res['payment']['amount'];
            $results[] = ['vehicleId' => $id, 'plateNumber' => $v['plate_number'], 'ok' => true, 'receiptNumber' => $res['payment']['receipt_number'],
                'amount' => (float)$res['payment']['amount'], 'validUntil' => $res['vehicle']['pass_valid_until']];
        } catch (Exception $e) {
            $results[] = ['vehicleId' => $id, 'plateNumber' => $v['plate_number'], 'ok' => false, 'message' => $e->getMessage()];
        }
    }
    auditLog($pdo, $admin, 'renewal.bulk', ['detail' => "{$renewed} of " . count($ids) . ' passes renewed, PHP ' . number_format($collected, 2) . ' collected']);
    sendResponse(200, ['renewed' => $renewed, 'requested' => count($ids), 'collected' => $collected, 'results' => $results], "{$renewed} pass(es) renewed.");
}

sendResponse(400, null, 'Unknown action. Use cash, free or bulk.');
