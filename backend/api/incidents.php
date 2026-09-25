<?php
/**
 * SecurePark API - Security Incidents & Holds Endpoint
 * GET  /api/incidents.php         - List security holds & incidents
 * POST /api/incidents.php         - Flag vehicle & report incident
 * PUT  /api/incidents.php         - Resolve security incident / release hold
 */

require_once __DIR__ . '/../config/db.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        handleGetIncidents($pdo);
        break;
    case 'POST':
        handleCreateIncident($pdo);
        break;
    case 'PUT':
        handleResolveIncident($pdo);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function handleGetIncidents($pdo) {
    $status = isset($_GET['status']) ? trim($_GET['status']) : '';

    $where = [];
    $params = [];

    if ($status !== '') {
        $where[] = "`status` = ?";
        $params[] = $status;
    }

    $whereSql = !empty($where) ? "WHERE " . implode(' AND ', $where) : "";
    $sql = "
        SELECT 
            id,
            case_number AS caseNumber,
            plate_number AS plateNumber,
            vehicle_type AS vehicleType,
            owner_name AS ownerName,
            owner_role AS ownerRole,
            driver_name AS driverName,
            driver_relationship AS driverRelationship,
            reason,
            gate_point AS gatePoint,
            officer,
            status,
            notes,
            DATE_FORMAT(reported_at, '%b %d, %Y • %h:%i %p') AS timestamp,
            reported_at AS reportedAt,
            resolved_at AS resolvedAt
        FROM `security_incidents`
        {$whereSql}
        ORDER BY `id` DESC
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $incidents = $stmt->fetchAll();

    sendResponse(200, $incidents);
}

function handleCreateIncident($pdo) {
    $data = getJsonInput();

    $plateNumber = isset($data['plateNumber']) ? strtoupper(trim($data['plateNumber'])) : '';
    $reason = isset($data['reason']) ? trim($data['reason']) : 'Security Verification';

    if ($plateNumber === '') {
        sendResponse(400, null, "Plate number is required to flag vehicle");
    }

    $caseNumber = 'CASE-' . date('Y') . '-' . str_pad(mt_rand(1, 99999), 5, '0', STR_PAD_LEFT);
    $vehicleType = isset($data['vehicleType']) ? $data['vehicleType'] : 'Vehicle';
    $ownerName = isset($data['ownerName']) ? $data['ownerName'] : 'Unknown';
    $ownerRole = isset($data['ownerRole']) ? $data['ownerRole'] : 'Visitor';
    $driverName = isset($data['driverName']) ? $data['driverName'] : 'Unknown';
    $driverRelationship = isset($data['driverRelationship']) ? $data['driverRelationship'] : 'Unregistered Driver';
    $gatePoint = isset($data['gatePoint']) ? $data['gatePoint'] : 'Gate 1 (Main Ingress)';
    $officer = isset($data['officer']) ? $data['officer'] : 'Gate Security Officer';
    $notes = isset($data['notes']) ? $data['notes'] : '';

    $pdo->beginTransaction();
    try {
        $sql = "INSERT INTO `security_incidents` (
            `case_number`, `plate_number`, `vehicle_type`, `owner_name`, `owner_role`,
            `driver_name`, `driver_relationship`, `reason`, `gate_point`, `officer`, `status`, `notes`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Held', ?)";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            $caseNumber, $plateNumber, $vehicleType, $ownerName, $ownerRole,
            $driverName, $driverRelationship, $reason, $gatePoint, $officer, $notes
        ]);
        $newId = $pdo->lastInsertId();

        // Update vehicle status to Blocked / Alert
        $upd = $pdo->prepare("UPDATE `vehicles` SET `status` = 'Blocked / Alert' WHERE `plate_number` = ?");
        $upd->execute([$plateNumber]);

        $pdo->commit();

        sendResponse(201, [
            'id' => (int)$newId,
            'caseNumber' => $caseNumber,
            'plateNumber' => $plateNumber,
            'status' => 'Held'
        ], "Vehicle {$plateNumber} flagged and held under case {$caseNumber}");
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, "Failed to create incident: " . $e->getMessage());
    }
}

function handleResolveIncident($pdo) {
    $data = getJsonInput();
    $id = isset($data['id']) ? (int)$data['id'] : 0;
    if ($id <= 0) {
        sendResponse(400, null, "Missing or invalid incident id");
    }

    $stmt = $pdo->prepare("SELECT `plate_number` FROM `security_incidents` WHERE `id` = ?");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if (!$row) {
        sendResponse(404, null, "Incident case not found");
    }

    $plate = $row['plate_number'];

    $pdo->beginTransaction();
    try {
        $upd = $pdo->prepare("UPDATE `security_incidents` SET `status` = 'Resolved', `resolved_at` = NOW() WHERE `id` = ?");
        $upd->execute([$id]);

        // If no other held incidents for this plate, restore vehicle status
        $check = $pdo->prepare("SELECT id FROM `security_incidents` WHERE `plate_number` = ? AND `status` = 'Held'");
        $check->execute([$plate]);
        if (!$check->fetch()) {
            $rest = $pdo->prepare("UPDATE `vehicles` SET `status` = 'Outside' WHERE `plate_number` = ? AND `status` = 'Blocked / Alert'");
            $rest->execute([$plate]);
        }

        $pdo->commit();
        sendResponse(200, ['id' => $id, 'status' => 'Resolved'], "Incident case resolved");
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, "Failed to resolve incident: " . $e->getMessage());
    }
}
