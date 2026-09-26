<?php
/**
 * SecurePark API - Violations & Penalties
 *
 * GET  /api/violations.php?status=Pending&vehicle_id=&plate=   List warnings / violations (staff)
 * POST /api/violations.php  { vehicle_id | plate, type, severity: "Warning" | "Violation", notes }
 *        Guards may issue Warnings only; admins may issue both.
 * PUT  /api/violations.php  { violation_id, action: "resolve" | "dismiss", notes }      (admin, notes required)
 * PUT  /api/violations.php  { vehicle_id, action: "reset", notes }                      (admin, notes required)
 *        "Reset Strikes & Lift Suspension"
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/strikes.php';

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
        'severity' => $row['severity'],
        'loggedBy' => $row['logged_by'],
        'status' => $row['status'],
        'countsAsStrike' => (int)$row['counts_as_strike'] === 1,
        'clearedByViolationId' => $row['cleared_by_violation_id'] !== null ? (int)$row['cleared_by_violation_id'] : null,
        'incidentId' => $row['incident_id'] !== null ? (int)$row['incident_id'] : null,
        'createdAt' => $row['created_at'],
        'resolvedAt' => $row['resolved_at'],
        'resolvedBy' => $row['resolved_by'],
        'resolutionNotes' => $row['resolution_notes'],
        // Vehicle context for tables
        'ownerName' => $row['owner_name'] ?? null,
        'ownerPhone' => $row['owner_phone'] ?? null,
        'warningCount' => isset($row['warning_count']) ? (int)$row['warning_count'] : null,
        'isBanned' => isset($row['is_banned']) ? (int)$row['is_banned'] === 1 : null,
        'registrationStatus' => $row['registration_status'] ?? null,
    ];
}

function handleListViolations($pdo) {
    $where = [];
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
    $whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';
    $stmt = $pdo->prepare("SELECT vv.*, v.`owner_name`, v.`owner_phone`, v.`warning_count`, v.`is_banned`, v.`registration_status`
        FROM `vehicle_violations` vv
        LEFT JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
        {$whereSql}
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

    $type = trim((string)($data['type'] ?? ''));
    $severity = $data['severity'] ?? 'Warning';
    $notes = trim((string)($data['notes'] ?? ''));

    if (!in_array($type, violationPresetTypes(), true)) {
        sendResponse(400, null, 'Choose a violation type from the list.');
    }
    if ($type === 'Other' && $notes === '') {
        sendResponse(400, null, 'Describe the violation in the notes when choosing "Other".');
    }
    if (!in_array($severity, ['Warning', 'Violation'], true)) {
        sendResponse(400, null, 'Severity must be Warning or Violation.');
    }
    if ($severity === 'Violation' && $actor['role'] !== 'admin') {
        sendResponse(403, ['code' => 'FORBIDDEN'], 'Guards can issue warnings only. Ask an administrator to issue a violation.');
    }

    $pdo->beginTransaction();
    try {
        $outcome = $severity === 'Violation'
            ? issueViolation($pdo, $actor, $vehicle, $type, $notes)
            : addWarning($pdo, $actor, $vehicle, $type, $notes);
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, 'Failed to record violation.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }

    if ($outcome['autoViolationId']) {
        $message = "Strike {$outcome['strikes']} of " . SP_STRIKE_LIMIT . " for {$vehicle['plate_number']}: 3-strike policy enforced. The vehicle is banned until an administrator resolves the violation.";
    } elseif ($severity === 'Violation') {
        $message = "Violation recorded. {$vehicle['plate_number']} is banned until an administrator resolves it.";
    } else {
        $message = "Warning recorded for {$vehicle['plate_number']} (strike {$outcome['strikes']} of " . SP_STRIKE_LIMIT . ").";
    }

    sendResponse(201, [
        'violation' => formatViolation(fetchViolation($pdo, $outcome['violationId'])),
        'strikes' => $outcome['strikes'],
        'strikeLimit' => SP_STRIKE_LIMIT,
        'banned' => $outcome['banned'],
        'autoViolationId' => $outcome['autoViolationId'],
        'incident' => $outcome['incident'],
        'vehicle' => vehicleForOutput($pdo, findVehicleById($pdo, $vehicle['id']), false),
    ], $message);
}

function handleUpdateViolation($pdo, $admin) {
    $data = getJsonInput();
    $action = $data['action'] ?? '';
    $notes = trim((string)($data['notes'] ?? ''));
    if ($notes === '') {
        sendResponse(400, null, 'Resolution notes are required (e.g. "Fine paid / clearance signed").');
    }

    if ($action === 'reset') {
        $vehicle = resolveVehicleFromBody($pdo, $data);
        if (!$vehicle) sendResponse(404, null, 'Vehicle not found.');
        $pdo->beginTransaction();
        try {
            resetStrikes($pdo, $admin, $vehicle, $notes);
            $pdo->commit();
        } catch (Exception $e) {
            $pdo->rollBack();
            sendResponse(500, null, 'Failed to reset strikes.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
        }
        sendResponse(200, ['vehicle' => vehicleForOutput($pdo, findVehicleById($pdo, $vehicle['id']), false), 'banLifted' => true],
            "Strikes reset and suspension lifted for {$vehicle['plate_number']}.");
    }

    if (!in_array($action, ['resolve', 'dismiss'], true)) {
        sendResponse(400, null, 'Unknown action. Use resolve, dismiss or reset.');
    }
    $violation = fetchViolation($pdo, $data['violation_id'] ?? 0);
    if (!$violation) sendResponse(404, null, 'Violation record not found.');
    if ($violation['status'] !== 'Pending') sendResponse(409, null, "This record is already {$violation['status']}.");
    if ($action === 'resolve' && $violation['severity'] !== 'Violation') {
        sendResponse(400, null, 'Warnings are cleared by resolving the vehicle\'s violation (or dismissed if issued by mistake).');
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
    $message = $action === 'resolve'
        ? ($outcome['banLifted'] ? "Violation resolved. Strikes reset and suspension lifted for {$plate}." : "Violation resolved. {$plate} still has another pending violation.")
        : ($outcome['banLifted'] ? "Record dismissed and suspension lifted for {$plate}." : "Record dismissed.");

    sendResponse(200, [
        'violation' => formatViolation(fetchViolation($pdo, $violation['id'])),
        'banLifted' => $outcome['banLifted'],
        'vehicle' => vehicleForOutput($pdo, findVehicleById($pdo, $violation['vehicle_id']), false),
    ], $message);
}
