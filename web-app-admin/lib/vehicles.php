<?php
/**
 * SecurePark - Shared vehicle helpers (formatting, lookup, pass identity)
 */

require_once __DIR__ . '/qr.php';

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
        'passId' => $v['pass_id'] ?? null,
        'passValidUntil' => $v['pass_valid_until'] ?? null,
        'warningCount' => (int)($v['warning_count'] ?? 0),
        'isBanned' => (int)($v['is_banned'] ?? 0) === 1,
        'authorizedDrivers' => $drivers
    ];
}

function getDriversForVehicle($pdo, $vehicleId) {
    $stmt = $pdo->prepare("SELECT id, full_name AS fullName, full_name, relationship, license_no AS licenseNo, license_no, phone, photo_url AS photoUrl, photo_url FROM `authorized_drivers` WHERE `vehicle_id` = ? ORDER BY `id` ASC");
    $stmt->execute([$vehicleId]);
    return $stmt->fetchAll();
}

/**
 * Finds a vehicle by plate, tolerating spaces / hyphens / case differences.
 */
function findVehicleByPlate($pdo, $plate) {
    $plate = trim((string)$plate);
    if ($plate === '') return null;

    // If a JSON payload was passed into plate, extract the plate
    if (strlen($plate) > 1 && $plate[0] === '{') {
        $decoded = json_decode($plate, true);
        if (is_array($decoded)) {
            $extracted = $decoded['plateNumber'] ?? $decoded['plate_number'] ?? $decoded['plate'] ?? '';
            if ($extracted !== '') $plate = $extracted;
        }
    }
    // If a preview string was passed, extract the plate at the end
    if (stripos($plate, 'PREVIEW') !== false && preg_match('/([A-Za-z0-9\- ]{3,15})$/', $plate, $m)) {
        $plate = trim($m[1]);
    }

    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `plate_number` = ? LIMIT 1");
    $stmt->execute([strtoupper($plate)]);
    $veh = $stmt->fetch();
    if (!$veh) {
        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? LIMIT 1");
        $stmt->execute([normalizePlate($plate)]);
        $veh = $stmt->fetch();
    }
    return $veh ?: null;
}

function findVehicleById($pdo, $id) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ? LIMIT 1");
    $stmt->execute([(int)$id]);
    return $stmt->fetch() ?: null;
}

/**
 * Makes sure a vehicle row has a pass_id and pass_valid_until (vehicles created
 * before v2 get them lazily the first time they are read). Returns the updated row.
 */
function ensurePassIdentity($pdo, $row) {
    if (!$row) return $row;
    $changed = false;
    if (empty($row['pass_id'])) {
        $row['pass_id'] = newPassId();
        $changed = true;
    }
    if (empty($row['pass_valid_until'])) {
        $row['pass_valid_until'] = defaultPassValidUntil($row['sticker_year'] ?? null);
        $changed = true;
    }
    if ($changed) {
        $stmt = $pdo->prepare("UPDATE `vehicles` SET `pass_id` = ?, `pass_valid_until` = ? WHERE `id` = ?");
        $stmt->execute([$row['pass_id'], $row['pass_valid_until'], $row['id']]);
    }
    return $row;
}

/**
 * Signed QR payload for a registered vehicle's permanent pass.
 */
function vehicleQrPayload($row) {
    return signPassPayload($row['pass_id'], $row['plate_number'], 'permanent', $row['pass_valid_until']);
}

/**
 * Formats a vehicle row for API output; the signed QR payload is only attached when
 * $includeQr is true (admins and the owning student), never for anonymous scanner lookups.
 */
function vehicleForOutput($pdo, $row, $includeQr = false) {
    $row = ensurePassIdentity($pdo, $row);
    $row['authorizedDrivers'] = getDriversForVehicle($pdo, $row['id']);
    $out = formatVehicleRow($row);
    if ($includeQr) {
        $out['qrPayload'] = vehicleQrPayload($row);
    }
    return $out;
}

/**
 * Items declared on a visitor day pass (e.g. "Monobloc chairs x 40").
 */
function visitorPassItems($pdo, $passId) {
    $stmt = $pdo->prepare("SELECT `item_name`, `quantity`, `description` FROM `visitor_pass_items` WHERE `visitor_pass_id` = ? ORDER BY `id` ASC");
    $stmt->execute([(int)$passId]);
    return array_map(function ($r) {
        return ['name' => $r['item_name'], 'quantity' => (int)$r['quantity'], 'description' => $r['description']];
    }, $stmt->fetchAll());
}

/**
 * One-line summary for logs, e.g. "40x Monobloc chairs, 1x Sound system (speakers + mixer)".
 */
function visitorItemsSummary($items) {
    return implode(', ', array_map(function ($i) {
        return $i['quantity'] . 'x ' . $i['name'] . ($i['description'] ? " ({$i['description']})" : '');
    }, $items));
}
