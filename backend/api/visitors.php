<?php
/**
 * SecurePark API - Single-Day Visitor Passes
 *
 * GET  /api/visitors.php?date=YYYY-MM-DD&status=Active   List passes for a day (staff; default today)
 * GET  /api/visitors.php?id=123                           One pass with its signed QR payload (staff)
 * POST /api/visitors.php  { visitor_name, contact_number, plate, vehicle_model?, purpose, person_to_visit,
 *                           items?: [{ name, quantity, description? }] }   (up to 20 items brought in)
 *        Admins and guards. valid_date is ALWAYS today (server clock) and cannot be chosen.
 * PUT  /api/visitors.php  { id, action: "revoke", notes? }   (admin)
 *
 * The QR is signed as type "visitor_temp" (lib/qr.php). verify.php rejects it on any
 * other date as "EXPIRED TEMPORARY PASS".
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        $isSingle = !empty($_GET['id']) || !empty($_GET['q']);
        $actor = $isSingle ? requireStaffOrScanner($pdo) : requireStaff($pdo);
        handleListVisitors($pdo);
        break;
    case 'POST':
        $actor = requireStaffOrScanner($pdo);
        if (isset($_GET['action']) && $_GET['action'] === 'exit') {
            handleVisitorExit($pdo, $actor);
        } else {
            handleCreateVisitor($pdo, $actor);
        }
        break;
    case 'PUT':
        $admin = requireStaff($pdo, ['admin']);
        handleRevokeVisitor($pdo, $admin);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function formatVisitorPass($row) {
    global $pdo;
    $inside = !empty($row['entry_time']) && empty($row['exit_time']);
    return [
        'id' => (int)$row['id'],
        'passCode' => $row['pass_code'],
        'visitorName' => $row['visitor_name'],
        'contactNumber' => $row['contact_number'],
        'plateNumber' => $row['plate_number'],
        'vehicleModel' => $row['vehicle_model'],
        'purposeOfVisit' => $row['purpose_of_visit'],
        'personToVisit' => $row['person_to_visit'],
        'validDate' => $row['valid_date'],
        'entryTime' => $row['entry_time'],
        'exitTime' => $row['exit_time'],
        'status' => $row['status'],
        'isInside' => $inside,
        'createdBy' => $row['created_by'],
        'createdAt' => $row['created_at'],
        'items' => visitorPassItems($pdo, $row['id']),
        // Staff can re-display the card; the server re-signs the same content every time
        'qrPayload' => signPassPayload($row['pass_code'], $row['plate_number'], 'visitor_temp', $row['valid_date']),
    ];
}

/**
 * Passes from earlier days that were never used become Expired. A visitor who entered
 * and has not exited stays Active so the exit can still be recorded.
 */
function expireOldPasses($pdo) {
    $stmt = $pdo->prepare("UPDATE `visitor_passes` SET `status` = 'Expired'
        WHERE `status` = 'Active' AND `valid_date` < ? AND `entry_time` IS NULL");
    $stmt->execute([date('Y-m-d', spNow())]);
}

function handleListVisitors($pdo) {
    expireOldPasses($pdo);

    if (!empty($_GET['id'])) {
        $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `id` = ? LIMIT 1");
        $stmt->execute([(int)$_GET['id']]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, 'Visitor pass not found.');
        sendResponse(200, formatVisitorPass($row));
    }

    if (!empty($_GET['q'])) {
        $q = trim((string)$_GET['q']);
        $norm = normalizePlate($q);
        $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `pass_code` = ? OR `plate_number` = ? OR REPLACE(REPLACE(`plate_number`, '-', ''), ' ', '') = ? ORDER BY `id` DESC LIMIT 1");
        $stmt->execute([$q, $q, $norm]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, 'Visitor pass not found.');
        sendResponse(200, formatVisitorPass($row));
    }

    $date = $_GET['date'] ?? date('Y-m-d', spNow());
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
        sendResponse(400, null, 'date must be YYYY-MM-DD.');
    }
    $sql = "SELECT * FROM `visitor_passes` WHERE (`valid_date` = ? OR (`entry_time` IS NOT NULL AND `exit_time` IS NULL AND `valid_date` < ?))";
    $params = [$date, $date];
    if (!empty($_GET['status']) && in_array($_GET['status'], ['Active', 'Used', 'Expired', 'Revoked'], true)) {
        $sql .= " AND `status` = ?";
        $params[] = $_GET['status'];
    }
    $sql .= " ORDER BY `id` DESC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    sendResponse(200, array_map('formatVisitorPass', $stmt->fetchAll()));
}

function newVisitorPassCode($pdo, $date) {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for ($attempt = 0; $attempt < 10; $attempt++) {
        $suffix = '';
        for ($i = 0; $i < 4; $i++) $suffix .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        $code = 'VP-' . str_replace('-', '', $date) . '-' . $suffix;
        $stmt = $pdo->prepare("SELECT 1 FROM `visitor_passes` WHERE `pass_code` = ?");
        $stmt->execute([$code]);
        if (!$stmt->fetch()) return $code;
    }
    throw new RuntimeException('Could not allocate a unique pass code.');
}

function handleCreateVisitor($pdo, $actor) {
    $data = getJsonInput();
    $field = function ($keys, $max) use ($data) {
        foreach ((array)$keys as $k) {
            if (isset($data[$k]) && trim((string)$data[$k]) !== '') return mb_substr(trim((string)$data[$k]), 0, $max);
        }
        return '';
    };
    $visitorName = $field(['visitor_name', 'visitorName'], 150);
    $contact = $field(['contact_number', 'contact', 'contactNumber'], 20);
    $plateRaw = $field(['plate', 'plate_number', 'plateNumber'], 20);
    $vehicleModel = $field(['vehicle_model', 'vehicleModel'], 100);
    $purpose = $field(['purpose', 'purpose_of_visit', 'purposeOfVisit'], 255);
    $host = $field(['person_to_visit', 'insider', 'personToVisit'], 150);

    $missing = [];
    if ($visitorName === '') $missing[] = 'visitor name';
    if ($contact === '') $missing[] = 'contact number';
    if ($plateRaw === '') $missing[] = 'plate number';
    if ($purpose === '') $missing[] = 'purpose of visit';
    if ($host === '') $missing[] = 'person / department to visit';
    if ($missing) {
        sendResponse(400, null, 'Missing required fields: ' . implode(', ', $missing) . '.');
    }
    if (!preg_match('/^[0-9+()\-\s]{7,20}$/', $contact)) {
        sendResponse(400, null, 'Enter a valid contact number.');
    }
    $plate = normalizePlate($plateRaw);
    if (strlen($plate) < 2) {
        sendResponse(400, null, 'Enter a valid plate number.');
    }
    $items = parseVisitorItems($data['items'] ?? []);

    // Registered vehicles must use their own pass (this also stops banned vehicles
    // from getting around a ban with a visitor pass)
    if ($registered = findVehicleByPlate($pdo, $plate)) {
        $why = (int)$registered['is_banned'] === 1 ? ' It is currently BANNED.' : '';
        sendResponse(409, ['code' => 'PLATE_REGISTERED'], "{$registered['plate_number']} is a registered campus vehicle and must use its permanent pass.{$why}");
    }

    $today = date('Y-m-d', spNow());
    $dup = $pdo->prepare("SELECT `pass_code` FROM `visitor_passes` WHERE `plate_number` = ? AND `valid_date` = ? AND `status` = 'Active' LIMIT 1");
    $dup->execute([$plate, $today]);
    if ($existing = $dup->fetchColumn()) {
        sendResponse(409, ['code' => 'PASS_EXISTS', 'passCode' => $existing], "An active day pass ({$existing}) already exists for {$plate} today.");
    }

    $clientCode = trim((string)($data['passCode'] ?? $data['passId'] ?? $data['pass_code'] ?? ''));
    $code = $clientCode !== '' ? $clientCode : newVisitorPassCode($pdo, $today);
    $stmt = $pdo->prepare("INSERT INTO `visitor_passes`
        (`pass_code`, `visitor_name`, `contact_number`, `plate_number`, `vehicle_model`, `purpose_of_visit`,
         `person_to_visit`, `valid_date`, `status`, `created_by`, `created_by_user_id`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'Active', ?, ?, ?)");
    $stmt->execute([$code, $visitorName, $contact, $plate, $vehicleModel ?: null, $purpose, $host, $today,
        actorLabel($actor), actorUserId($actor), date('Y-m-d H:i:s', spNow())]);

    $passId = (int)$pdo->lastInsertId();
    $itemStmt = $pdo->prepare("INSERT INTO `visitor_pass_items` (`visitor_pass_id`, `item_name`, `quantity`, `description`) VALUES (?, ?, ?, ?)");
    foreach ($items as $item) {
        $itemStmt->execute([$passId, $item['name'], $item['quantity'], $item['description']]);
    }

    $row = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `id` = ?");
    $row->execute([$passId]);
    $itemNote = $items ? ' Items declared: ' . count($items) . '.' : '';
    sendResponse(201, formatVisitorPass($row->fetch()), "Day pass {$code} issued. Valid only on {$today}.{$itemNote}");
}

/**
 * Validates the items a visitor brings in. Returns a clean list or ends the request with 400.
 */
function parseVisitorItems($raw) {
    if ($raw === null || $raw === '' || $raw === []) return [];
    if (!is_array($raw)) sendResponse(400, null, 'items must be a list.');
    $items = [];
    foreach (array_values($raw) as $i => $item) {
        if (!is_array($item)) sendResponse(400, null, 'Each item needs a name and quantity.');
        $name = mb_substr(trim((string)($item['name'] ?? '')), 0, 100);
        $desc = mb_substr(trim((string)($item['description'] ?? '')), 0, 255);
        $qty = $item['quantity'] ?? 1;
        if ($name === '' && $desc === '') continue; // blank row from the form
        if ($name === '') sendResponse(400, null, 'Item ' . ($i + 1) . ' needs a name.');
        if (!is_numeric($qty) || (int)$qty != $qty || (int)$qty < 1 || (int)$qty > 9999) {
            sendResponse(400, null, "Quantity for \"{$name}\" must be a whole number from 1 to 9999.");
        }
        $items[] = ['name' => $name, 'quantity' => (int)$qty, 'description' => $desc !== '' ? $desc : null];
    }
    if (count($items) > 20) sendResponse(400, null, 'A day pass can list at most 20 items.');
    return $items;
}

function handleRevokeVisitor($pdo, $admin) {
    $data = getJsonInput();
    if (($data['action'] ?? '') !== 'revoke') {
        sendResponse(400, null, 'Unknown action. Use revoke.');
    }
    $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `id` = ? LIMIT 1");
    $stmt->execute([(int)($data['id'] ?? 0)]);
    $row = $stmt->fetch();
    if (!$row) sendResponse(404, null, 'Visitor pass not found.');
    if ($row['status'] !== 'Active') sendResponse(409, null, "This pass is already {$row['status']}.");

    $pdo->prepare("UPDATE `visitor_passes` SET `status` = 'Revoked' WHERE `id` = ?")->execute([$row['id']]);
    $row['status'] = 'Revoked';
    sendResponse(200, formatVisitorPass($row), "Day pass {$row['pass_code']} revoked by " . actorLabel($admin) . '.');
}

function handleVisitorExit($pdo, $actor) {
    $data = getJsonInput();
    $passId = trim((string)($data['passId'] ?? $data['pass_code'] ?? ''));
    $plate = trim((string)($data['plateNumber'] ?? $data['plate'] ?? ''));

    if ($passId === '' && $plate === '') {
        sendResponse(400, null, 'Provide passId or plateNumber for visitor checkout.');
    }

    $norm = normalizePlate($plate);
    $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `pass_code` = ? OR `plate_number` = ? OR REPLACE(REPLACE(`plate_number`, '-', ''), ' ', '') = ? ORDER BY `id` DESC LIMIT 1");
    $stmt->execute([$passId, $plate, $norm]);
    $pass = $stmt->fetch();

    if (!$pass) {
        sendResponse(404, null, 'Visitor pass not found.');
    }

    $now = date('Y-m-d H:i:s', spNow());
    $upd = $pdo->prepare("UPDATE `visitor_passes` SET `exit_time` = COALESCE(`exit_time`, ?), `status` = 'Used' WHERE `id` = ?");
    $upd->execute([$now, $pass['id']]);

    sendResponse(200, [
        'passId' => $pass['pass_code'],
        'plateNumber' => $pass['plate_number'],
        'exitTime' => $now,
        'status' => 'Used',
    ], 'Visitor checkout confirmed.');
}

