<?php
/**
 * SecurePark API - Gate Logs & Audit Stream Endpoint
 * GET  /api/logs.php             - List gate passage audit logs
 * POST /api/logs.php             - Record gate entry or exit (called by Mobile App & Web Admin)
 */

require_once __DIR__ . '/../config/db.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        handleGetLogs($pdo);
        break;
    case 'POST':
        handleCreateLog($pdo);
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
            status,
            guard_name AS guardName,
            notes,
            logged_at AS loggedAt
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

function handleCreateLog($pdo) {
    $data = getJsonInput();

    $plateNumber = isset($data['plateNumber']) ? strtoupper(trim($data['plateNumber'])) : '';
    $driverName = isset($data['driverName']) ? trim($data['driverName']) : '';
    $action = isset($data['action']) ? trim($data['action']) : 'Entry Recorded';

    if ($plateNumber === '' || $driverName === '') {
        sendResponse(400, null, "Missing required fields: plateNumber and driverName are required.");
    }

    $vehicleType = isset($data['vehicleType']) ? $data['vehicleType'] : '4-Wheel';
    $ownerName = isset($data['ownerName']) ? $data['ownerName'] : $driverName;
    $driverRelationship = isset($data['driverRelationship']) ? $data['driverRelationship'] : 'Self (Owner)';
    $gatePoint = isset($data['gatePoint']) ? $data['gatePoint'] : 'Gate 1 (Main Ingress)';
    $status = isset($data['status']) ? $data['status'] : ($action === 'Exit Approved' ? 'Exited' : 'Inside Campus');
    $guardName = isset($data['guardName']) ? $data['guardName'] : 'Gate Officer';
    $notes = isset($data['notes']) ? $data['notes'] : '';

    $pdo->beginTransaction();
    try {
        $sql = "INSERT INTO `gate_logs` (
            `plate_number`, `vehicle_type`, `owner_name`, `driver_name`, 
            `driver_relationship`, `gate_point`, `action`, `status`, `guard_name`, `notes`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            $plateNumber, $vehicleType, $ownerName, $driverName,
            $driverRelationship, $gatePoint, $action, $status, $guardName, $notes
        ]);
        $newLogId = $pdo->lastInsertId();

        // Synchronously update the vehicle's status in the vehicles registry
        $updSql = "UPDATE `vehicles` SET `status` = ?, `last_entry_time` = NOW(), `last_gate_point` = ? WHERE `plate_number` = ?";
        $updStmt = $pdo->prepare($updSql);
        $updStmt->execute([$status, $gatePoint, $plateNumber]);

        $pdo->commit();

        $logEntry = [
            'id' => (int)$newLogId,
            'timestamp' => 'Just Now',
            'plateNumber' => $plateNumber,
            'vehicleType' => $vehicleType,
            'ownerName' => $ownerName,
            'driverName' => $driverName,
            'driverRelationship' => $driverRelationship,
            'gatePoint' => $gatePoint,
            'action' => $action,
            'status' => $status,
            'guardName' => $guardName,
            'notes' => $notes
        ];

        sendResponse(201, $logEntry, "Gate passage logged for {$plateNumber}");
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, "Failed to record gate log: " . $e->getMessage());
    }
}
