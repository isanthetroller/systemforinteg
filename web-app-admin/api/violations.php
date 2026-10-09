<?php
/**
 * SecurePark API - Violations
 *
 * A violation puts the vehicle on hold: it can neither enter nor leave campus until an
 * administrator resolves the violation. There are no warnings and no strikes.
 *
 * GET  /api/violations.php?status=Pending&vehicle_id=&plate=   List violations (staff)
 * POST /api/violations.php  { vehicle_id | plate, type, notes }   Issue a violation (guard or admin)
 * PUT  /api/violations.php  { violation_id, action: "resolve" | "dismiss", notes }   (admin, notes required)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/violations.php';
require_once __DIR__ . '/../lib/approvals.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        requireStaff($pdo);
        handleListViolations($pdo);
        break;
    case 'POST':
        $actor = requireStaff($pdo);
        handleCreateViolation($pdo, $actor);
        break;
    case 'PUT':
        $admin = requireStaff($pdo, ['admin']);
        handleUpdateViolation($pdo, $admin);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function formatViolation($row) {
    return [
        'id' => (int)$row['id'],
        'vehicleId' => (int)$row['vehicle_id'],
        'plateNumber' => $row['plate_number'],
        'violationType' => $row['violation_type'],
        'description' => $row['description'],
        'loggedBy' => $row['logged_by'],
        'status' => $row['status'],
        'incidentId' => $row['incident_id'] !== null ? (int)$row['incident_id'] : null,
        'createdAt' => $row['created_at'],
        'resolvedAt' => $row['resolved_at'],
        'resolvedBy' => $row['resolved_by'],
        'resolutionNotes' => $row['resolution_notes'],
        // Vehicle context for tables
        'ownerName' => $row['owner_name'] ?? null,
        'ownerPhone' => $row['owner_phone'] ?? null,
        'onHold' => isset($row['is_banned']) ? (int)$row['is_banned'] === 1 : null,
        'registrationStatus' => $row['registration_status'] ?? null,
    ];
}

function handleListViolations($pdo) {
    $where = ["vv.`severity` = 'Violation'"]; // historic 'Warning' rows of the retired strike system are not listed
    $params = [];
    if (!empty($_GET['status']) && in_array($_GET['status'], ['Pending', 'Resolved', 'Dismissed'], true)) {
        $where[] = 'vv.`status` = ?';
        $params[] = $_GET['status'];
    }
    if (!empty($_GET['vehicle_id'])) {
        $where[] = 'vv.`vehicle_id` = ?';
        $params[] = (int)$_GET['vehicle_id'];
    }
    if (!empty($_GET['plate'])) {
        $where[] = "REPLACE(REPLACE(UPPER(vv.`plate_number`), '-', ''), ' ', '') = ?";
        $params[] = normalizePlate($_GET['plate']);
    }
    $stmt = $pdo->prepare("SELECT vv.*, v.`owner_name`, v.`owner_phone`, v.`is_banned`, v.`registration_status`
        FROM `vehicle_violations` vv
        LEFT JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
        WHERE " . implode(' AND ', $where) . "
        ORDER BY vv.`id` DESC
        LIMIT 500");
    $stmt->execute($params);
    sendResponse(200, array_map('formatViolation', $stmt->fetchAll()));
}

function resolveVehicleFromBody($pdo, $data) {
    if (!empty($data['vehicle_id'])) return findVehicleById($pdo, $data['vehicle_id']);
    if (!empty($data['plate'])) return findVehicleByPlate($pdo, $data['plate']);
    return null;
}

function handleCreateViolation($pdo, $actor) {
    $data = getJsonInput();
    $vehicle = resolveVehicleFromBody($pdo, $data);
    if (!$vehicle) {
        sendResponse(404, null, 'Registered vehicle not found. Violations can only be issued to registered vehicles.');
    }

    if (isVipVehicle($vehicle)) {
        sendResponse(409, ['code' => 'VIP_EXEMPT'], "{$vehicle['plate_number']} is a VIP vehicle and is exempt from violations. An administrator can change its VIP status in the vehicle record.");
    }

    $type = trim((string)($data['type'] ?? ''));
    $notes = trim((string)($data['notes'] ?? ''));

    if (!in_array($type, violationPresetTypes(), true)) {
        sendResponse(400, null, 'Choose a violation type from the list.');
    }
    if ($type === 'Other' && $notes === '') {
        sendResponse(400, null, 'Describe the violation in the notes when choosing "Other".');
    }

    $pdo->beginTransaction();
    try {
        $outcome = issueViolation($pdo, $actor, $vehicle, $type, $notes);
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, 'Failed to record violation.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }

    auditLog($pdo, $actor, 'violation.issue', ['entityType' => 'violation', 'entityId' => (int)$outcome['violationId'], 'plate' => $vehicle['plate_number'],
        'detail' => $type . ($notes !== '' ? ": {$notes}" : ''), 'reason' => null]);
    sendResponse(201, [
        'violation' => formatViolation(fetchViolation($pdo, $outcome['violationId'])),
        'onHold' => true,
        'incident' => $outcome['incident'],
        'vehicle' => vehicleForOutput($pdo, findVehicleById($pdo, $vehicle['id']), false),
    ], "Violation recorded. {$vehicle['plate_number']} cannot enter or leave campus until an administrator resolves it.");
}

function handleUpdateViolation($pdo, $admin) {
    $data = getJsonInput();
    $action = $data['action'] ?? '';
    $notes = trim((string)($data['notes'] ?? ''));
    if ($notes === '') {
        sendResponse(400, null, 'Resolution notes are required (e.g. "Fine paid / clearance signed").');
    }
    if (!in_array($action, ['resolve', 'dismiss'], true)) {
        sendResponse(400, null, 'Unknown action. Use resolve or dismiss.');
    }
    $violation = fetchViolation($pdo, $data['violation_id'] ?? 0);
    if (!$violation) sendResponse(404, null, 'Violation record not found.');
    if ($violation['status'] !== 'Pending') sendResponse(409, null, "This record is already {$violation['status']}.");

    // Dismissing lifts a hold, so it needs a second administrator (when there is one); resolving is the normal path
    if ($action === 'dismiss' && needsSecondAdmin($pdo)) {
        if (pendingApproval($pdo, 'violation_dismiss', null, (int)$violation['id'])) {
            sendResponse(409, ['code' => 'APPROVAL_PENDING'], 'A dismissal for this violation is already waiting for a second administrator.');
        }
        $approvalId = createApprovalRequest($pdo, $admin, 'violation_dismiss', null, $violation, $notes);
        sendResponse(202, ['approvalPending' => true, 'approvalId' => $approvalId, 'violation' => formatViolation(fetchViolation($pdo, $violation['id']))],
            "Dismissal sent for a second administrator's approval. {$violation['plate_number']} stays on hold until then.");
    }

    $pdo->beginTransaction();
    try {
        $outcome = $action === 'resolve'
            ? resolveViolation($pdo, $admin, $violation, $notes)
            : dismissViolation($pdo, $admin, $violation, $notes);
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, 'Failed to update violation.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }

    $plate = $violation['plate_number'];
    $verb = $action === 'resolve' ? 'resolved' : 'dismissed';
    auditLog($pdo, $admin, $action === 'resolve' ? 'violation.resolve' : 'violation.dismiss', ['entityType' => 'violation', 'entityId' => (int)$violation['id'],
        'plate' => $plate, 'detail' => $violation['violation_type'] . ($action === 'dismiss' ? ' (no second administrator was available to approve)' : ''), 'reason' => $notes]);
    $message = $outcome['holdLifted']
        ? "Violation {$verb}. {$plate} can enter and leave campus again."
        : "Violation {$verb}. {$plate} still has another pending violation.";

    sendResponse(200, [
        'violation' => formatViolation(fetchViolation($pdo, $violation['id'])),
        'holdLifted' => $outcome['holdLifted'],
        'vehicle' => vehicleForOutput($pdo, findVehicleById($pdo, $violation['vehicle_id']), false),
    ], $message);
}
