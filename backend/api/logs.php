<?php
/**
 * SecurePark API - Gate Logs & Audit Stream Endpoint
 * GET  /api/logs.php             - List gate passage audit logs
 * POST /api/logs.php             - Record a gate decision (Web Gate Monitor & Mobile App)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/records.php';
require_once __DIR__ . '/../lib/movements.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        requireStaff($pdo);
        handleGetLogs($pdo);
        break;
    case 'POST':
        $actor = requireStaffOrScanner($pdo);
        handleCreateLog($pdo, $actor);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function handleGetLogs($pdo) {
    $plate = isset($_GET['plate']) ? trim($_GET['plate']) : '';
    $action = isset($_GET['action']) ? trim($_GET['action']) : '';
    $limit = isset($_GET['limit']) ? min((int)$_GET['limit'], 200) : 100;

    $where = [];
    $params = [];

    if ($plate !== '') {
        $where[] = "`plate_number` = ?";
        $params[] = $plate;
    }
    if ($action !== '') {
        $where[] = "`action` LIKE ?";
        $params[] = "%{$action}%";
    }

    $whereSql = !empty($where) ? "WHERE " . implode(' AND ', $where) : "";
    // Rows recorded offline carry the time they reached the server (migration 006)
    $syncedSelect = columnExists($pdo, 'gate_logs', 'synced_at') ? ",\n            synced_at AS syncedAt" : '';
    $sql = "
        SELECT 
            id,
            DATE_FORMAT(logged_at, '%b %d, %Y • %h:%i %p') AS timestamp,
            plate_number AS plateNumber,
            vehicle_type AS vehicleType,
            owner_name AS ownerName,
            driver_name AS driverName,
            driver_relationship AS driverRelationship,
            gate_point AS gatePoint,
            action,
            gate_type AS gateType,
            verified_driver_name AS verifiedDriverName,
            status,
            guard_name AS guardName,
            notes,
            logged_at AS loggedAt{$syncedSelect}
        FROM `gate_logs`
        {$whereSql}
        ORDER BY `id` DESC
        LIMIT {$limit}
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $logs = $stmt->fetchAll();

    sendResponse(200, $logs);
}

/**
 * Records a gate decision.
 *
 * Web gate monitor: { plate, action, gate_type, driver_id | visitor_pass_id, qr_code?, notes? }
 * Mobile app (legacy): { plateNumber, driverName, driverRelationship, action, status, ... }
 *
 * Approvals are re-checked here (bans, suspensions, visitor day validity) so a
 * manipulated client can never record an entry that verify.php would refuse.
 */
function handleCreateLog($pdo, $actor) {
    $data = getJsonInput();
    $isScanner = !empty($actor['is_scanner']);

    // A retry of a write that already reached the server (reply lost) must not log twice
    $clientRef = trim((string)($data['client_ref'] ?? ''));
    if (!preg_match('/^[A-Za-z0-9._:-]{8,64}$/', $clientRef) || !columnExists($pdo, 'gate_logs', 'client_ref')) {
        $clientRef = '';
    }
    if ($clientRef !== '') {
        $dup = $pdo->prepare("SELECT `id` FROM `gate_logs` WHERE `client_ref` = ? LIMIT 1");
        $dup->execute([$clientRef]);
        if ($existingId = $dup->fetchColumn()) {
            sendResponse(200, ['id' => (int)$existingId, 'duplicate' => true], 'Already recorded.');
        }
    }

    $plateNumber = strtoupper(trim((string)($data['plate'] ?? $data['plateNumber'] ?? $data['plate_number'] ?? '')));
    $action = normalizeGateAction(trim((string)($data['action'] ?? 'Entry Recorded')));

    if ($plateNumber === '') {
        sendResponse(400, null, "Missing required field: plate.");
    }
    if ($action === null) {
        sendResponse(400, null, "Invalid action. Allowed: " . implode(', ', gateActions()) . ".");
    }
    $gateType = in_array($action, ['Exit Approved', 'Exit Denied'], true) ? 'Egress' : 'Ingress';
    if (isset($data['gate_type']) && $data['gate_type'] !== $gateType) {
        sendResponse(400, null, "Action {$action} does not match gate type {$data['gate_type']}.");
    }
    $isApproval = in_array($action, ['Entry Recorded', 'Exit Approved'], true);

    $vehicle = findVehicleByPlate($pdo, $plateNumber);
    $observedRevision = $vehicle ? movementRevision($pdo, $vehicle['plate_number']) : null;
    $isVip = isVipVehicle($vehicle);
    $visitor = null;
    if (!empty($data['visitor_pass_id'])) {
        $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `id` = ? LIMIT 1");
        $stmt->execute([(int)$data['visitor_pass_id']]);
        $visitor = $stmt->fetch() ?: null;
        if (!$visitor) sendResponse(404, null, 'Visitor pass not found.');
    } elseif (!$vehicle) {
        $visitor = findVisitorPassByPlate($pdo, $plateNumber, date('Y-m-d'), true);
    }

    /* ---- Driver confirmation ------------------------------------------- */
    $driverName = trim((string)($data['driverName'] ?? $data['driver_name'] ?? ''));
    $driverRelationship = trim((string)($data['driverRelationship'] ?? $data['driver_relationship'] ?? ''));
    $verifiedDriverName = null;
    $driverId = (int)($data['driver_id'] ?? 0);

    if ($driverId > 0) {
        if (!$vehicle) sendResponse(400, null, 'driver_id given but the plate is not a registered vehicle.');
        $stmt = $pdo->prepare("SELECT * FROM `authorized_drivers` WHERE `id` = ? AND `vehicle_id` = ? LIMIT 1");
        $stmt->execute([$driverId, $vehicle['id']]);
        $drv = $stmt->fetch();
        if (!$drv) sendResponse(400, ['code' => 'DRIVER_NOT_AUTHORIZED'], 'The selected driver is not authorized for this vehicle.');
        $driverName = $drv['full_name'];
        $driverRelationship = $drv['relationship'];
        $verifiedDriverName = $drv['full_name'];
    } elseif ($visitor && $isApproval) {
        $driverName = $visitor['visitor_name'];
        $driverRelationship = 'Visitor (Day Pass)';
        $verifiedDriverName = $visitor['visitor_name'];
    } elseif (!$isScanner && $isApproval && $vehicle && !$isVip) {
        // The web gate monitor must confirm who is behind the wheel before approving (VIPs are waved through)
        sendResponse(400, ['code' => 'DRIVER_CONFIRMATION_REQUIRED'], 'Select the authorized driver currently behind the wheel.');
    }
    if ($driverName === '' && $isVip) {
        $driverName = $vehicle['owner_name'];
        $driverRelationship = 'VIP (driver not checked)';
    }
    if ($driverName === '') {
        if ($isApproval) sendResponse(400, null, 'Missing required field: driverName.');
        $driverName = 'Unverified';
    }
    if ($driverRelationship === '') $driverRelationship = $verifiedDriverName ? 'Self (Owner)' : 'Unverified';

    /* ---- Server-side standing re-check (entries only; exits are never blocked) ---- */
    $today = date('Y-m-d');
    if ($action === 'Entry Recorded') {
        if ($vehicle && (int)$vehicle['is_banned'] === 1) {
            sendResponse(403, ['code' => 'VEHICLE_BANNED'], "Entry refused: {$vehicle['plate_number']} is banned until an administrator resolves its violation.");
        }
        if ($vehicle && $vehicle['registration_status'] === 'Suspended') {
            sendResponse(403, ['code' => 'VEHICLE_SUSPENDED'], "Entry refused: registration of {$vehicle['plate_number']} is suspended.");
        }
        if (!$vehicle && $visitor) {
            if ($visitor['status'] === 'Revoked' && empty($visitor['exit_time'])) {
                sendResponse(403, ['code' => 'REVOKED'], 'Entry refused: this visitor pass was revoked.');
            }
            if ($visitor['valid_date'] > $today) {
                sendResponse(403, ['code' => 'NOT_YET_VALID'], "PASS NOT YET VALID - it becomes active on {$visitor['valid_date']}.");
            }
            if ($visitor['valid_date'] !== $today) {
                sendResponse(403, ['code' => 'EXPIRED_TEMP'], "EXPIRED TEMPORARY PASS - valid only on {$visitor['valid_date']}.");
            }
            if ($visitor['status'] !== 'Active' || !empty($visitor['exit_time'])) {
                sendResponse(403, ['code' => 'PASS_USED'], 'This single-day pass has already been used and was revoked when the visitor exited.');
            }
        }
        if ($isApproval && !$vehicle && !$visitor) {
            sendResponse(403, ['code' => 'UNREGISTERED'], "Entry refused: {$plateNumber} has no active registration or visitor pass. Please register visitor first.");
        }
        if ($isApproval) {
            if ($vehicle && $vehicle['status'] === 'Inside Campus') {
                $unregisteredOrOutsideNote = 'Anti-Passback: Vehicle re-entered while recorded inside';
            }
            if ($visitor && !empty($visitor['entry_time']) && empty($visitor['exit_time'])) {
                $unregisteredOrOutsideNote = 'Anti-Passback: Visitor re-entered while recorded inside';
            }
        }
    }

    $unregisteredOrOutsideNote = $unregisteredOrOutsideNote ?? '';
    if ($action === 'Exit Approved') {
        if ($vehicle && $vehicle['status'] !== 'Inside Campus') {
            $unregisteredOrOutsideNote = 'Attention: Vehicle was not recorded as inside campus upon egress';
        }
        if ($visitor && (empty($visitor['entry_time']) || !empty($visitor['exit_time']))) {
            $unregisteredOrOutsideNote = 'Attention: Visitor pass had no prior active entry record';
        }
    }

    /* ---- Items carried by a visitor must be checked on entry and exit ---- */
    $itemsNote = '';
    if ($isApproval && !$vehicle && $visitor) {
        $items = visitorPassItems($pdo, $visitor['id']);
        if ($items) {
            if (!$isScanner && empty($data['items_verified'])) {
                sendResponse(400, ['code' => 'ITEMS_CHECK_REQUIRED', 'items' => $items],
                    'Check the items declared on this visitor pass before approving.');
            }
            if ($isScanner && empty($data['items_verified'])) {
                $itemsNote = 'Declared items not checked by mobile scanner: ' . visitorItemsSummary($items);
            } else {
                $itemsNote = ($gateType === 'Ingress' ? 'Items checked in: ' : 'Items checked out: ')
                    . visitorItemsSummary($items);
            }
        }
    }

    /* ---- Write ---------------------------------------------------------- */
    // gate_logs.status is the outcome label of this passage; vehicles.status is the vehicle's
    // current state, which is "Outside" (never "Exited") once it has left.
    $vehicleState = $gateType === 'Egress' ? 'Outside' : 'Inside Campus';
    if ($isApproval) {
        $status = $gateType === 'Egress' ? 'Exited' : 'Inside Campus';
    } else {
        $status = $gateType === 'Egress' ? 'Inside Campus' : 'Outside';
    }
    $gatePoint = trim((string)($data['gatePoint'] ?? '')) ?: defaultGatePoint($gateType);
    $notes = trim((string)($data['notes'] ?? ''));
    if ($itemsNote !== '') {
        $notes = trim($notes . ' | ' . $itemsNote, ' |');
    }
    if ($isVip) {
        $notes = trim('VIP pass | ' . $notes, ' |');
    }
    if (!empty($unregisteredOrOutsideNote)) {
        $notes = trim($notes . ' | ' . $unregisteredOrOutsideNote, ' |');
    }
    if ($isScanner && !empty($data['guardName'])) {
        $notes = trim($notes . ' [Mobile operator: ' . $data['guardName'] . ']');
    }

    movementBegin($pdo);
    try {
        if ($isApproval && $vehicle) {
            $lock = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql' ? ' FOR UPDATE' : '';
            $fresh = $pdo->prepare("SELECT `status` FROM `vehicles` WHERE `id` = ?" . $lock);
            $fresh->execute([$vehicle['id']]);
            if ($fresh->fetchColumn() !== $vehicle['status'] || movementRevision($pdo, $vehicle['plate_number']) !== $observedRevision) {
                movementEnd($pdo, false);
                sendResponse(409, ['code' => 'STALE_SCAN'], 'Another transaction changed this vehicle. Scan it again before confirming.');
            }
        }
        $logId = recordGateLog($pdo, $actor, [
            'plate' => $vehicle['plate_number'] ?? ($visitor['plate_number'] ?? $plateNumber),
            'vehicleType' => $vehicle['vehicle_type'] ?? ($visitor ? 'Visitor Vehicle' : ($data['vehicleType'] ?? null)),
            'ownerName' => $vehicle['owner_name'] ?? ($visitor['visitor_name'] ?? ($data['ownerName'] ?? $driverName)),
            'driverName' => $driverName,
            'driverRelationship' => $driverRelationship,
            'verifiedDriverName' => $verifiedDriverName,
            'gatePoint' => $gatePoint,
            'action' => $action,
            'gateType' => $gateType,
            'status' => $status,
            'notes' => $notes,
            'clientRef' => $clientRef,
        ]);

        if ($isApproval && $vehicle) {
            if ($gateType === 'Ingress') {
                $upd = $pdo->prepare("UPDATE `vehicles` SET `status` = ?, `last_entry_time` = ?, `last_gate_point` = ? WHERE `id` = ?");
                $upd->execute([$vehicleState, date('Y-m-d H:i:s'), $gatePoint, $vehicle['id']]);
            } else {
                $upd = $pdo->prepare("UPDATE `vehicles` SET `status` = ?, `last_gate_point` = ? WHERE `id` = ?");
                $upd->execute([$vehicleState, $gatePoint, $vehicle['id']]);
            }
        }
        if ($isApproval && !$vehicle && $visitor) {
            if ($gateType === 'Ingress') {
                $pdo->prepare("UPDATE `visitor_passes` SET `entry_time` = COALESCE(`entry_time`, ?) WHERE `id` = ?")
                    ->execute([date('Y-m-d H:i:s'), $visitor['id']]);
            } else {
                $pdo->prepare("UPDATE `visitor_passes` SET `exit_time` = ?, `status` = 'Revoked' WHERE `id` = ?")
                    ->execute([date('Y-m-d H:i:s'), $visitor['id']]);
            }
        }
        movementEnd($pdo, true);
    } catch (Exception $e) {
        movementEnd($pdo, false);
        sendResponse(500, null, 'Failed to record gate log.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }

    sendResponse(201, [
        'id' => $logId,
        'timestamp' => date('M d, Y • h:i A'),
        'loggedAt' => date('Y-m-d H:i:s'),
        'plateNumber' => $vehicle['plate_number'] ?? ($visitor['plate_number'] ?? $plateNumber),
        'vehicleType' => $vehicle['vehicle_type'] ?? ($visitor ? 'Visitor Vehicle' : ($data['vehicleType'] ?? null)),
        'ownerName' => $vehicle['owner_name'] ?? ($visitor['visitor_name'] ?? ($data['ownerName'] ?? $driverName)),
        'driverName' => $driverName,
        'driverRelationship' => $driverRelationship,
        'verifiedDriverName' => $verifiedDriverName,
        'gatePoint' => $gatePoint,
        'action' => $action,
        'gateType' => $gateType,
        'status' => $status,
        'guardName' => gateActorLabel($actor),
        'notes' => $notes,
    ], "Gate passage logged for {$plateNumber}");
}
