<?php
/**
 * SecurePark API - Vehicles Endpoint
 * GET    /api/vehicles.php                - List all vehicles with authorized drivers (staff; admins also get signed qrPayload)
 * GET    /api/vehicles.php?plate=XYZ      - Lookup vehicle by plate
 * GET    /api/vehicles.php?qr=CODE        - Lookup vehicle by QR code
 * POST   /api/vehicles.php                - Register new vehicle + drivers
 * PUT    /api/vehicles.php                - Update vehicle info or toggle status
 * DELETE /api/vehicles.php?id=123         - Remove vehicle
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/students.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        // Single lookups (plate / QR) are open to the mobile scanner; the full
        // registry (owner personal data) requires a signed-in staff member.
        $isLookup = (isset($_GET['plate']) && trim($_GET['plate']) !== '') || (isset($_GET['qr']) && trim($_GET['qr']) !== '');
        $actor = $isLookup ? requireStaffOrScanner($pdo) : requireStaff($pdo);
        handleGetVehicles($pdo, $actor);
        break;
    case 'POST':
        $admin = requireStaff($pdo, ['admin']);
        handleRegisterVehicle($pdo, $admin);
        break;
    case 'PUT':
        $admin = requireStaff($pdo, ['admin']);
        handleUpdateVehicle($pdo, $admin);
        break;
    case 'DELETE':
        requireStaff($pdo, ['admin']);
        handleDeleteVehicle($pdo);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function handleGetVehicles($pdo, $actor) {
    $plate = isset($_GET['plate']) ? trim($_GET['plate']) : '';
    $qr = isset($_GET['qr']) ? trim($_GET['qr']) : '';
    $query = isset($_GET['q']) ? trim($_GET['q']) : '';

    // Signed QR payloads are only handed to administrators (to print / reissue passes)
    $includeQr = ($actor['role'] ?? '') === 'admin';

    if ($plate !== '' || $qr !== '') {
        $needle = $plate !== '' ? $plate : $qr;
        $veh = lookupVehicleByAnyCode($pdo, $needle);
        if (!$veh) {
            sendResponse(404, null, $plate !== '' ? "Vehicle with plate {$plate} not found" : "Pass code not found");
        }
        sendResponse(200, vehicleForOutput($pdo, $veh, $includeQr));
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

    $result = [];
    foreach ($stmt->fetchAll() as $v) {
        $result[] = vehicleForOutput($pdo, $v, $includeQr);
    }
    sendResponse(200, $result);
}

/**
 * Lookup used by the mobile scanner and manual search: plate (any formatting),
 * signed pass payload, legacy JSON pass, legacy pass code or owner ID.
 * This is a lookup only; gate decisions are made by verify.php.
 */
function lookupVehicleByAnyCode($pdo, $needle) {
    $veh = findVehicleByPlate($pdo, $needle);
    if ($veh) return $veh;

    $parsed = parseScannedQr($needle);
    if ($parsed['kind'] === 'signed') {
        if (!empty($parsed['pass']['pid'])) {
            $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `pass_id` = ? LIMIT 1");
            $stmt->execute([$parsed['pass']['pid']]);
            if ($row = $stmt->fetch()) return $row;
        }
        if (!empty($parsed['pass']['plate_number'])) {
            if ($row = findVehicleByPlate($pdo, $parsed['pass']['plate_number'])) return $row;
        }
    }
    if ($parsed['kind'] === 'legacy' && !empty($parsed['plate'])) {
        if ($row = findVehicleByPlate($pdo, $parsed['plate'])) return $row;
    }

    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `qr_pass_code` = ? OR `owner_id_number` = ? LIMIT 1");
    $stmt->execute([$needle, $needle]);
    return $stmt->fetch() ?: null;
}

function handleRegisterVehicle($pdo, $admin) {
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
    // v2: passes are signed server-side; clients can no longer supply the QR content
    $passId = newPassId();
    $passValidUntil = isValidDate($data['passValidUntil'] ?? '') ? $data['passValidUntil'] : defaultPassValidUntil($stickerYear);
    $passClass = requestedPassClass($data) ?? 'Standard';

    $pdo->beginTransaction();
    try {
        $sql = "INSERT INTO `vehicles` (
            `plate_number`, `vehicle_type`, `category`, `make_model_color`, `owner_name`, 
            `owner_role`, `department`, `owner_id_number`, `owner_phone`, `owner_email`, 
            `owner_photo`, `vehicle_photo`, `pass_id`, `pass_valid_until`, `status`, `registration_status`, `sticker_year`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Outside', 'Active', ?)";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            $plateNumber, $vehicleType, $category, $makeModelColor, $ownerName,
            $ownerRole, $department, $ownerIdNumber, $ownerPhone, $ownerEmail,
            $ownerPhoto, $vehiclePhoto, $passId, $passValidUntil, $stickerYear
        ]);
        $newVehicleId = $pdo->lastInsertId();
        if ($passClass === 'VIP') {
            $pdo->prepare("UPDATE `vehicles` SET `pass_class` = 'VIP', `pass_class_by` = ?, `pass_class_at` = ? WHERE `id` = ?")
                ->execute([actorLabel($admin), date('Y-m-d H:i:s'), $newVehicleId]);
        }

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

        $newVeh = vehicleForOutput($pdo, findVehicleById($pdo, $newVehicleId), true);

        // Student portal login for the owner (created once per owner ID; the temporary
        // password is returned only in this response and shown to the admin once)
        try {
            $newVeh['studentAccount'] = ensureStudentAccount($pdo, $ownerIdNumber, $ownerName, $ownerEmail);
        } catch (Exception $e) {
            // The vehicle is saved; the admin can issue the login later from the dossier
            $newVeh['studentAccount'] = ['ownerIdNumber' => $ownerIdNumber, 'created' => false, 'tempPassword' => null, 'error' => 'Portal account could not be created.'];
        }

        sendResponse(201, $newVeh, "Vehicle {$plateNumber} registered successfully");
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, "Failed to register vehicle: " . $e->getMessage());
    }
}

/**
 * "VIP" or "Standard" from a request body, or null when the client did not send one.
 */
function requestedPassClass($data) {
    $raw = $data['passClass'] ?? $data['pass_class'] ?? null;
    if ($raw === null) return null;
    $raw = strtolower(trim((string)$raw));
    if ($raw === 'vip') return 'VIP';
    if ($raw === 'standard' || $raw === '') return 'Standard';
    sendResponse(400, null, 'passClass must be Standard or VIP.');
}

function handleUpdateVehicle($pdo, $admin) {
    $data = getJsonInput();
    $id = isset($data['id']) ? (int)$data['id'] : 0;
    if ($id <= 0) {
        sendResponse(400, null, "Missing or invalid vehicle id");
    }

    // Check if toggling registration status
    if (isset($data['action']) && $data['action'] === 'toggle_status') {
        $stmt = $pdo->prepare("SELECT `registration_status`, `is_banned` FROM `vehicles` WHERE `id` = ?");
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, "Vehicle not found");
        if ((int)$row['is_banned'] === 1) {
            sendResponse(409, ['code' => 'VEHICLE_BANNED'], "This vehicle is banned by a violation. Resolve it in Violations & Penalties to lift the suspension.");
        }

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
        'vehicle_photo' => ['vehiclePhoto', 'vehicle_photo', 'vehiclePicture']
        // 'status' (inside / outside) is owned by the gate log and the violations workflow, never by an edit
    ];

    foreach ($updatable as $col => $keys) {
        foreach ($keys as $key) {
            if (array_key_exists($key, $data)) {
                $fields[] = "`{$col}` = ?";
                $params[] = $col === 'plate_number' ? strtoupper(trim($data[$key])) : $data[$key];
                break;
            }
        }
    }

    $current = findVehicleById($pdo, $id);
    if (!$current) {
        sendResponse(404, null, "Vehicle not found");
    }

    // A ban can only be lifted through the violations workflow
    $requestedReg = $data['registrationStatus'] ?? $data['registration_status'] ?? null;
    if ((int)$current['is_banned'] === 1 && $requestedReg !== null && $requestedReg !== 'Suspended') {
        sendResponse(409, ['code' => 'VEHICLE_BANNED'], "This vehicle is banned by a violation. Resolve it in Violations & Penalties to lift the suspension.");
    }

    if (array_key_exists('passValidUntil', $data)) {
        if (!isValidDate($data['passValidUntil'])) {
            sendResponse(400, null, "passValidUntil must be a date in YYYY-MM-DD format");
        }
        $fields[] = "`pass_valid_until` = ?";
        $params[] = $data['passValidUntil'];
    }

    // The plate is part of the signature: a plate change reissues the pass and
    // retires any legacy (pre-v2) QR code for this vehicle.
    $newPlate = $data['plateNumber'] ?? $data['plate_number'] ?? null;
    if ($newPlate !== null && normalizePlate($newPlate) !== normalizePlate($current['plate_number'])) {
        $fields[] = "`pass_id` = ?";
        $params[] = newPassId();
        $fields[] = "`qr_pass_code` = NULL";
    }

    // VIP status: admin-only (this whole endpoint is), recorded with who and when
    $newClass = requestedPassClass($data);
    if ($newClass !== null && $newClass !== (isVipVehicle($current) ? 'VIP' : 'Standard')) {
        if ($newClass === 'VIP' && (int)$current['is_banned'] === 1) {
            sendResponse(409, ['code' => 'VEHICLE_BANNED'], 'This vehicle is banned by a violation. Resolve the ban in Violations & Penalties before marking it VIP.');
        }
        $fields[] = "`pass_class` = ?";
        $params[] = $newClass;
        $fields[] = "`pass_class_by` = ?";
        $params[] = $newClass === 'VIP' ? actorLabel($admin) : null;
        $fields[] = "`pass_class_at` = ?";
        $params[] = $newClass === 'VIP' ? date('Y-m-d H:i:s') : null;
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

        sendResponse(200, vehicleForOutput($pdo, findVehicleById($pdo, $id), true), "Vehicle record updated successfully");
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

function isValidDate($value) {
    if (!is_string($value) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) return false;
    [$y, $m, $d] = array_map('intval', explode('-', $value));
    return checkdate($m, $d, $y);
}
