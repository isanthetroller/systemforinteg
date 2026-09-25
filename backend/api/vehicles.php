<?php
/**
 * SecurePark API - Vehicles Endpoint
 * GET    /api/vehicles.php                - List all vehicles with authorized drivers
 * GET    /api/vehicles.php?plate=XYZ      - Lookup vehicle by plate
 * GET    /api/vehicles.php?qr=CODE        - Lookup vehicle by QR code
 * POST   /api/vehicles.php                - Register new vehicle + drivers
 * PUT    /api/vehicles.php                - Update vehicle info or toggle status
 * DELETE /api/vehicles.php?id=123         - Remove vehicle
 */

require_once __DIR__ . '/../config/db.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        handleGetVehicles($pdo);
        break;
    case 'POST':
        handleRegisterVehicle($pdo);
        break;
    case 'PUT':
        handleUpdateVehicle($pdo);
        break;
    case 'DELETE':
        handleDeleteVehicle($pdo);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function handleGetVehicles($pdo) {
    $plate = isset($_GET['plate']) ? trim($_GET['plate']) : '';
    $qr = isset($_GET['qr']) ? trim($_GET['qr']) : '';
    $query = isset($_GET['q']) ? trim($_GET['q']) : '';

    if ($plate !== '') {
        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `plate_number` = ? LIMIT 1");
        $stmt->execute([$plate]);
        $veh = $stmt->fetch();

        // Fallback: normalized plate (ignoring hyphens and spaces)
        if (!$veh) {
            $norm = strtoupper(preg_replace('/[^A-Z0-9]/', '', $plate));
            $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? LIMIT 1");
            $stmt->execute([$norm]);
            $veh = $stmt->fetch();
        }

        // Fallback: check qr_pass_code or owner_id_number
        if (!$veh) {
            $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `qr_pass_code` = ? OR `owner_id_number` = ? LIMIT 1");
            $stmt->execute([$plate, $plate]);
            $veh = $stmt->fetch();
        }

        // Fallback: If plate parameter is actually a JSON QR payload
        if (!$veh && (strpos($plate, '{') === 0 || strpos($plate, 'plateNumber') !== false || strpos($plate, 'plate') !== false)) {
            $decoded = json_decode($plate, true);
            if ($decoded) {
                $targetPlate = trim($decoded['plateNumber'] ?? $decoded['plate_number'] ?? $decoded['plate'] ?? '');
                if ($targetPlate !== '') {
                    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `plate_number` = ? LIMIT 1");
                    $stmt->execute([$targetPlate]);
                    $veh = $stmt->fetch();
                    if (!$veh) {
                        $norm = strtoupper(preg_replace('/[^A-Z0-9]/', '', $targetPlate));
                        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? LIMIT 1");
                        $stmt->execute([$norm]);
                        $veh = $stmt->fetch();
                    }
                }
            }
        }

        if (!$veh) {
            sendResponse(404, null, "Vehicle with plate {$plate} not found");
        }
        $veh['authorizedDrivers'] = getDriversForVehicle($pdo, $veh['id']);
        sendResponse(200, formatVehicleRow($veh));
    }

    if ($qr !== '') {
        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `qr_pass_code` = ? LIMIT 1");
        $stmt->execute([$qr]);
        $veh = $stmt->fetch();

        // Fallback: If QR is a direct plate number
        if (!$veh) {
            $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `plate_number` = ? LIMIT 1");
            $stmt->execute([$qr]);
            $veh = $stmt->fetch();
        }

        // Fallback: If QR is JSON, parse plate or owner ID
        if (!$veh && (strpos($qr, '{') === 0 || strpos($qr, 'plateNumber') !== false || strpos($qr, 'plate') !== false)) {
            $decoded = json_decode($qr, true);
            if ($decoded) {
                $targetPlate = trim($decoded['plateNumber'] ?? $decoded['plate_number'] ?? $decoded['plate'] ?? '');
                if ($targetPlate !== '') {
                    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `plate_number` = ? LIMIT 1");
                    $stmt->execute([$targetPlate]);
                    $veh = $stmt->fetch();

                    if (!$veh) {
                        $norm = strtoupper(preg_replace('/[^A-Z0-9]/', '', $targetPlate));
                        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? LIMIT 1");
                        $stmt->execute([$norm]);
                        $veh = $stmt->fetch();
                    }
                }
            }
        }

        if (!$veh) {
            sendResponse(404, null, "Pass code not found");
        }
        $veh['authorizedDrivers'] = getDriversForVehicle($pdo, $veh['id']);
        sendResponse(200, formatVehicleRow($veh));
    }

    // Search or list all
    if ($query !== '') {
        $searchTerm = "%{$query}%";
        $stmt = $pdo->prepare("
            SELECT * FROM `vehicles`
            WHERE `plate_number` LIKE ? OR `owner_name` LIKE ? OR `department` LIKE ? OR `owner_id_number` LIKE ?
            ORDER BY `id` DESC
        ");
        $stmt->execute([$searchTerm, $searchTerm, $searchTerm, $searchTerm]);
    } else {
        $stmt = $pdo->query("SELECT * FROM `vehicles` ORDER BY `id` DESC");
    }

    $vehicles = $stmt->fetchAll();

    // Map authorized drivers and normalized format for all vehicles
    $result = [];
    foreach ($vehicles as $v) {
        $v['authorizedDrivers'] = getDriversForVehicle($pdo, $v['id']);
        $result[] = formatVehicleRow($v);
    }

    sendResponse(200, $result);
}

function formatVehicleRow($v) {
    if (!$v) return null;
    $drivers = isset($v['authorizedDrivers']) ? $v['authorizedDrivers'] : [];
    return [
        'id' => (int)$v['id'],
        'plateNumber' => $v['plate_number'] ?? '',
        'plate_number' => $v['plate_number'] ?? '',
        'vehicleType' => $v['vehicle_type'] ?? '4-Wheel',
        'vehicle_type' => $v['vehicle_type'] ?? '4-Wheel',
        'category' => $v['category'] ?? 'plated',
        'makeModelColor' => $v['make_model_color'] ?? '',
        'make_model_color' => $v['make_model_color'] ?? '',
        'ownerName' => $v['owner_name'] ?? '',
        'owner_name' => $v['owner_name'] ?? '',
        'ownerRole' => $v['owner_role'] ?? 'Student',
        'owner_role' => $v['owner_role'] ?? 'Student',
        'department' => $v['department'] ?? '',
        'ownerIdNumber' => $v['owner_id_number'] ?? '',
        'owner_id_number' => $v['owner_id_number'] ?? '',
        'ownerPhone' => $v['owner_phone'] ?? '',
        'owner_phone' => $v['owner_phone'] ?? '',
        'ownerEmail' => $v['owner_email'] ?? '',
        'owner_email' => $v['owner_email'] ?? '',
        'ownerPhoto' => $v['owner_photo'] ?? null,
        'owner_photo' => $v['owner_photo'] ?? null,
        'ownerPhotoUrl' => $v['owner_photo'] ?? null,
        'vehiclePhoto' => $v['vehicle_photo'] ?? null,
        'vehicle_photo' => $v['vehicle_photo'] ?? null,
        'vehiclePicture' => $v['vehicle_photo'] ?? null,
        'qrPassCode' => $v['qr_pass_code'] ?? '',
        'qr_pass_code' => $v['qr_pass_code'] ?? '',
        'status' => $v['status'] ?? 'Outside',
        'registrationStatus' => $v['registration_status'] ?? 'Active',
        'registration_status' => $v['registration_status'] ?? 'Active',
        'stickerYear' => $v['sticker_year'] ?? '2026',
        'sticker_year' => $v['sticker_year'] ?? '2026',
        'lastEntryTime' => $v['last_entry_time'] ?? null,
        'last_entry_time' => $v['last_entry_time'] ?? null,
        'lastGatePoint' => $v['last_gate_point'] ?? null,
        'last_gate_point' => $v['last_gate_point'] ?? null,
        'entryTime' => $v['last_entry_time'] ?? null,
        'gatePoint' => $v['last_gate_point'] ?? '—',
        'authorizedDrivers' => $drivers
    ];
}

function getDriversForVehicle($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT id, full_name AS fullName, full_name, relationship, license_no AS licenseNo, license_no, phone, photo_url AS photoUrl, photo_url FROM `authorized_drivers` WHERE `vehicle_id` = ? ORDER BY `id` ASC");
    $stmt->execute([$vehicleId]);
    return $stmt->fetchAll();
}

function handleRegisterVehicle($pdo) {
    $data = getJsonInput();

    $plateNumber = isset($data['plateNumber']) ? strtoupper(trim($data['plateNumber'])) : '';
    $ownerName = isset($data['ownerName']) ? trim($data['ownerName']) : '';
    $ownerIdNumber = isset($data['ownerIdNumber']) ? trim($data['ownerIdNumber']) : '';

    if ($plateNumber === '' || $ownerName === '' || $ownerIdNumber === '') {
        sendResponse(400, null, "Missing required fields: plateNumber, ownerName, and ownerIdNumber are required.");
    }

    // Check if plate already registered
    $checkStmt = $pdo->prepare("SELECT `id` FROM `vehicles` WHERE `plate_number` = ? LIMIT 1");
    $checkStmt->execute([$plateNumber]);
    if ($checkStmt->fetch()) {
        sendResponse(409, null, "Vehicle with plate {$plateNumber} is already registered.");
    }

    $vehicleType = isset($data['vehicleType']) ? $data['vehicleType'] : '4-Wheel (Sedan)';
    $category = isset($data['category']) ? $data['category'] : 'plated';
    $makeModelColor = isset($data['makeModelColor']) ? $data['makeModelColor'] : 'Vehicle';
    $ownerRole = isset($data['ownerRole']) ? $data['ownerRole'] : 'Student';
    $department = isset($data['department']) ? $data['department'] : '';
    $ownerPhone = isset($data['ownerPhone']) ? $data['ownerPhone'] : (isset($data['owner_phone']) ? $data['owner_phone'] : '');
    $ownerEmail = isset($data['ownerEmail']) ? $data['ownerEmail'] : (isset($data['owner_email']) ? $data['owner_email'] : '');
    $ownerPhoto = isset($data['ownerPhoto']) ? $data['ownerPhoto'] : (isset($data['owner_photo']) ? $data['owner_photo'] : null);
    $vehiclePhoto = isset($data['vehiclePhoto']) ? $data['vehiclePhoto'] : (isset($data['vehicle_photo']) ? $data['vehicle_photo'] : null);
    $stickerYear = isset($data['stickerYear']) ? $data['stickerYear'] : (isset($data['sticker_year']) ? $data['sticker_year'] : '2026');
    $qrPassCode = isset($data['qrPassCode']) ? $data['qrPassCode'] : (isset($data['qr_pass_code']) ? $data['qr_pass_code'] : ('NCST-QR-' . preg_replace('/[^A-Z0-9]/', '', $plateNumber)));

    $pdo->beginTransaction();
    try {
        $sql = "INSERT INTO `vehicles` (
            `plate_number`, `vehicle_type`, `category`, `make_model_color`, `owner_name`, 
            `owner_role`, `department`, `owner_id_number`, `owner_phone`, `owner_email`, 
            `owner_photo`, `vehicle_photo`, `qr_pass_code`, `status`, `registration_status`, `sticker_year`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Outside', 'Active', ?)";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            $plateNumber, $vehicleType, $category, $makeModelColor, $ownerName,
            $ownerRole, $department, $ownerIdNumber, $ownerPhone, $ownerEmail,
            $ownerPhoto, $vehiclePhoto, $qrPassCode, $stickerYear
        ]);
        $newVehicleId = $pdo->lastInsertId();

        // Insert authorized drivers
        $drivers = isset($data['authorizedDrivers']) && is_array($data['authorizedDrivers']) 
            ? $data['authorizedDrivers'] 
            : (isset($data['authorized_drivers']) && is_array($data['authorized_drivers']) ? $data['authorized_drivers'] : []);

        if (empty($drivers)) {
            // Default to owner as primary driver
            $drivers[] = [
                'fullName' => $ownerName,
                'relationship' => 'Self (Owner)',
                'licenseNo' => 'N/A',
                'phone' => $ownerPhone,
                'photoUrl' => $ownerPhoto
            ];
        }

        $drvSql = "INSERT INTO `authorized_drivers` (`vehicle_id`, `full_name`, `relationship`, `license_no`, `phone`, `photo_url`) VALUES (?, ?, ?, ?, ?, ?)";
        $drvStmt = $pdo->prepare($drvSql);

        foreach ($drivers as $drv) {
            $name = isset($drv['fullName']) ? trim($drv['fullName']) : (isset($drv['full_name']) ? trim($drv['full_name']) : '');
            if ($name === '') continue;
            $rel = isset($drv['relationship']) ? trim($drv['relationship']) : 'Designated Driver';
            $lic = isset($drv['licenseNo']) ? trim($drv['licenseNo']) : (isset($drv['license_no']) ? trim($drv['license_no']) : 'N/A');
            $ph = isset($drv['phone']) ? trim($drv['phone']) : null;
            $pic = isset($drv['photoUrl']) ? $drv['photoUrl'] : (isset($drv['photo_url']) ? $drv['photo_url'] : null);
            if (!$pic && (stripos($rel, 'self') !== false || stripos($rel, 'owner') !== false || strtolower($name) === strtolower($ownerName))) {
                $pic = $ownerPhoto;
            }
            $drvStmt->execute([$newVehicleId, $name, $rel, $lic, $ph, $pic]);
        }

        $pdo->commit();

        // Fetch newly created vehicle with drivers
        $newVeh = formatVehicleRow([
            'id' => (int)$newVehicleId,
            'plate_number' => $plateNumber,
            'vehicle_type' => $vehicleType,
            'category' => $category,
            'make_model_color' => $makeModelColor,
            'owner_name' => $ownerName,
            'owner_role' => $ownerRole,
            'department' => $department,
            'owner_id_number' => $ownerIdNumber,
            'owner_phone' => $ownerPhone,
            'owner_email' => $ownerEmail,
            'owner_photo' => $ownerPhoto,
            'vehicle_photo' => $vehiclePhoto,
            'status' => 'Outside',
            'registration_status' => 'Active',
            'sticker_year' => $stickerYear,
            'qr_pass_code' => $qrPassCode,
            'authorizedDrivers' => getDriversForVehicle($pdo, $newVehicleId)
        ]);

        sendResponse(201, $newVeh, "Vehicle {$plateNumber} registered successfully");
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, "Failed to register vehicle: " . $e->getMessage());
    }
}

function handleUpdateVehicle($pdo) {
    $data = getJsonInput();
    $id = isset($data['id']) ? (int)$data['id'] : 0;
    if ($id <= 0) {
        sendResponse(400, null, "Missing or invalid vehicle id");
    }

    // Check if toggling registration status
    if (isset($data['action']) && $data['action'] === 'toggle_status') {
        $stmt = $pdo->prepare("SELECT `registration_status` FROM `vehicles` WHERE `id` = ?");
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, "Vehicle not found");

        $nextStatus = $row['registration_status'] === 'Active' ? 'Suspended' : 'Active';
        $upd = $pdo->prepare("UPDATE `vehicles` SET `registration_status` = ? WHERE `id` = ?");
        $upd->execute([$nextStatus, $id]);

        sendResponse(200, ['id' => $id, 'registration_status' => $nextStatus, 'registrationStatus' => $nextStatus], "Vehicle registration status updated to {$nextStatus}");
    }

    // Full detail update
    $fields = [];
    $params = [];

    $updatable = [
        'plate_number' => ['plateNumber', 'plate_number'],
        'vehicle_type' => ['vehicleType', 'vehicle_type'],
        'category' => ['category'],
        'make_model_color' => ['makeModelColor', 'make_model_color'],
        'owner_name' => ['ownerName', 'owner_name'],
        'owner_role' => ['ownerRole', 'owner_role'],
        'department' => ['department'],
        'owner_id_number' => ['ownerIdNumber', 'owner_id_number'],
        'sticker_year' => ['stickerYear', 'sticker_year'],
        'registration_status' => ['registrationStatus', 'registration_status'],
        'owner_phone' => ['ownerPhone', 'owner_phone'],
        'owner_email' => ['ownerEmail', 'owner_email'],
        'owner_photo' => ['ownerPhoto', 'owner_photo', 'ownerPhotoUrl'],
        'vehicle_photo' => ['vehiclePhoto', 'vehicle_photo', 'vehiclePicture'],
        'status' => ['status'],
        'qr_pass_code' => ['qrPassCode', 'qr_pass_code']
    ];

    foreach ($updatable as $col => $keys) {
        foreach ($keys as $key) {
            if (array_key_exists($key, $data)) {
                $fields[] = "`{$col}` = ?";
                $params[] = $data[$key];
                break;
            }
        }
    }

    $drivers = isset($data['authorizedDrivers']) && is_array($data['authorizedDrivers'])
        ? $data['authorizedDrivers']
        : (isset($data['authorized_drivers']) && is_array($data['authorized_drivers']) ? $data['authorized_drivers'] : null);

    if (empty($fields) && $drivers === null) {
        sendResponse(400, null, "No fields provided to update");
    }

    $pdo->beginTransaction();
    try {
        if (!empty($fields)) {
            $params[] = $id;
            $sql = "UPDATE `vehicles` SET " . implode(', ', $fields) . " WHERE `id` = ?";
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
        }

        // Update authorized drivers if supplied
        if ($drivers !== null) {
            $delStmt = $pdo->prepare("DELETE FROM `authorized_drivers` WHERE `vehicle_id` = ?");
            $delStmt->execute([$id]);

            // Fetch current owner details to inherit photo if needed
            $vStmt = $pdo->prepare("SELECT `owner_name`, `owner_photo`, `owner_phone` FROM `vehicles` WHERE `id` = ?");
            $vStmt->execute([$id]);
            $ownerRow = $vStmt->fetch();
            $ownerName = $ownerRow ? $ownerRow['owner_name'] : '';
            $ownerPhoto = $ownerRow ? $ownerRow['owner_photo'] : null;

            if (empty($drivers) && $ownerRow) {
                $drivers[] = [
                    'fullName' => $ownerName,
                    'relationship' => 'Self (Owner)',
                    'licenseNo' => 'N/A',
                    'phone' => $ownerRow['owner_phone'],
                    'photoUrl' => $ownerPhoto
                ];
            }

            $drvSql = "INSERT INTO `authorized_drivers` (`vehicle_id`, `full_name`, `relationship`, `license_no`, `phone`, `photo_url`) VALUES (?, ?, ?, ?, ?, ?)";
            $drvStmt = $pdo->prepare($drvSql);

            foreach ($drivers as $drv) {
                $name = isset($drv['fullName']) ? trim($drv['fullName']) : (isset($drv['full_name']) ? trim($drv['full_name']) : '');
                if ($name === '') continue;
                $rel = isset($drv['relationship']) ? trim($drv['relationship']) : 'Designated Driver';
                $lic = isset($drv['licenseNo']) ? trim($drv['licenseNo']) : (isset($drv['license_no']) ? trim($drv['license_no']) : 'N/A');
                $ph = isset($drv['phone']) ? trim($drv['phone']) : null;
                $pic = isset($drv['photoUrl']) ? $drv['photoUrl'] : (isset($drv['photo_url']) ? $drv['photo_url'] : null);
                if (!$pic && (stripos($rel, 'self') !== false || stripos($rel, 'owner') !== false || strtolower($name) === strtolower($ownerName))) {
                    $pic = $ownerPhoto;
                }
                $drvStmt->execute([$id, $name, $rel, $lic, $ph, $pic]);
            }
        }

        $pdo->commit();

        // Fetch updated vehicle
        $fetchStmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ?");
        $fetchStmt->execute([$id]);
        $updatedVeh = $fetchStmt->fetch();
        if ($updatedVeh) {
            $updatedVeh['authorizedDrivers'] = getDriversForVehicle($pdo, $id);
            sendResponse(200, formatVehicleRow($updatedVeh), "Vehicle record updated successfully");
        } else {
            sendResponse(200, ['id' => $id], "Vehicle record updated");
        }
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, "Failed to update vehicle: " . $e->getMessage());
    }
}

function handleDeleteVehicle($pdo) {
    $id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
    if ($id <= 0) {
        sendResponse(400, null, "Missing or invalid vehicle id");
    }
    $stmt = $pdo->prepare("DELETE FROM `vehicles` WHERE `id` = ?");
    $stmt->execute([$id]);
    sendResponse(200, ['id' => $id], "Vehicle deleted successfully");
}
