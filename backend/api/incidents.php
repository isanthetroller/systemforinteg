<?php
/**
 * SecurePark API - Security Incidents & Holds Endpoint
 * GET  /api/incidents.php         - List security holds & incidents
 * POST /api/incidents.php         - Flag vehicle & report incident
 * PUT  /api/incidents.php         - Resolve security incident / release hold
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/records.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        requireStaff($pdo);
        handleGetIncidents($pdo);
        break;
    case 'POST':
        $actor = requireStaffOrScanner($pdo);
        handleCreateIncident($pdo, $actor);
        break;
    case 'PUT':
        $admin = requireStaff($pdo, ['admin']);
        handleResolveIncident($pdo, $admin);
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

    // The refused passage that raised each case, so the Investigate drawer can play its gate clip
    foreach ($incidents as &$inc) {
        $inc['logId'] = incidentLogId($pdo, ['plate_number' => $inc['plateNumber'], 'reported_at' => $inc['reportedAt']]);
    }
    unset($inc);

    sendResponse(200, $incidents);
}

function handleCreateIncident($pdo, $actor) {
    $data = getJsonInput();

    $plateNumber = isset($data['plateNumber']) ? strtoupper(trim($data['plateNumber'])) : '';
    $reason = isset($data['reason']) ? trim($data['reason']) : 'Security Verification';

    if ($plateNumber === '') {
        sendResponse(400, null, "Plate number is required to flag vehicle");
    }

    $clientRef = trim((string)($data['client_ref'] ?? ''));
    if (!preg_match('/^[A-Za-z0-9._:-]{8,64}$/', $clientRef) || !columnExists($pdo, 'security_incidents', 'client_ref')) {
        $clientRef = '';
    }
    if ($clientRef !== '') {
        $dup = $pdo->prepare("SELECT `id`, `case_number`, `status` FROM `security_incidents` WHERE `client_ref` = ? LIMIT 1");
        $dup->execute([$clientRef]);
        if ($row = $dup->fetch()) {
            sendResponse(200, ['id' => (int)$row['id'], 'caseNumber' => $row['case_number'], 'plateNumber' => $plateNumber, 'status' => $row['status'], 'duplicate' => true], 'Already recorded.');
        }
    }

    $caseNumber = newCaseNumber($pdo);
    $vehicleType = isset($data['vehicleType']) ? $data['vehicleType'] : 'Vehicle';
    $ownerName = isset($data['ownerName']) ? $data['ownerName'] : 'Unknown';
    $ownerRole = isset($data['ownerRole']) ? $data['ownerRole'] : 'Visitor';
    $driverName = isset($data['driverName']) ? $data['driverName'] : 'Unknown';
    $driverRelationship = isset($data['driverRelationship']) ? $data['driverRelationship'] : 'Unregistered Driver';
    $gatePoint = isset($data['gatePoint']) ? $data['gatePoint'] : 'Gate 1 (Main Ingress)';
    // Audit attribution comes from the signed-in account, never from the request body
    $officer = !empty($actor['is_scanner'])
        ? 'Mobile Scanner' . (!empty($data['officer']) ? ' / ' . $data['officer'] : '')
        : actorLabel($actor);
    $loggedByUserId = actorUserId($actor);
    $notes = isset($data['notes']) ? $data['notes'] : '';

    $pdo->beginTransaction();
    try {
        $sql = "INSERT INTO `security_incidents` (
            `case_number`, `plate_number`, `vehicle_type`, `owner_name`, `owner_role`,
            `driver_name`, `driver_relationship`, `reason`, `gate_point`, `officer`, `logged_by_user_id`, `status`, `notes`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Held', ?)";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            $caseNumber, $plateNumber, $vehicleType, $ownerName, $ownerRole,
            $driverName, $driverRelationship, $reason, $gatePoint, $officer, $loggedByUserId, $notes
        ]);
        $newId = $pdo->lastInsertId();
        if ($clientRef !== '') {
            $pdo->prepare("UPDATE `security_incidents` SET `client_ref` = ? WHERE `id` = ?")->execute([$clientRef, $newId]);
        }

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

function handleResolveIncident($pdo, $admin) {
    $data = getJsonInput();
    $id = isset($data['id']) ? (int)$data['id'] : 0;
    if ($id <= 0) {
        sendResponse(400, null, "Missing or invalid incident id");
    }

    $stmt = $pdo->prepare("SELECT `plate_number`, `notes` FROM `security_incidents` WHERE `id` = ?");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if (!$row) {
        sendResponse(404, null, "Incident case not found");
    }

    $plate = $row['plate_number'];

    // Bans from the 3-strike policy / violations are lifted only by resolving the violation
    $linked = $pdo->prepare("SELECT `id` FROM `vehicle_violations` WHERE `incident_id` = ? AND `status` = 'Pending' LIMIT 1");
    $linked->execute([$id]);
    if ($linkedId = $linked->fetchColumn()) {
        sendResponse(409, ['code' => 'VIOLATION_PENDING', 'violationId' => (int)$linkedId],
            "This case is tied to violation #{$linkedId}. Resolve it in Violations & Penalties (resolution notes required).");
    }
    $resolutionNotes = isset($data['notes']) ? trim((string)$data['notes']) : '';
    $resolutionEntry = ' [Resolved by ' . actorLabel($admin) . ' on ' . date('Y-m-d H:i') . ($resolutionNotes !== '' ? ": {$resolutionNotes}" : '') . ']';

    $pdo->beginTransaction();
    try {
        $upd = $pdo->prepare("UPDATE `security_incidents` SET `status` = 'Resolved', `resolved_at` = NOW(), `notes` = ? WHERE `id` = ?");
        $upd->execute([($row['notes'] ?? '') . $resolutionEntry, $id]);

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
