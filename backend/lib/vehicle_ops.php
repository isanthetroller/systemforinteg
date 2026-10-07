<?php
/**
 * SecurePark - Vehicle classes, replacement and retirement
 *
 * An ID may register ONE active vehicle per class (four-wheel, two/three-wheel, bicycle). An administrator can
 * allow an extra one with a written reason (logged). When an owner changes vehicle, the old one is RETIRED
 * (history kept, can no longer enter) and any fee already paid for the current pass year is credited to the new one.
 */

require_once __DIR__ . '/payments.php';
require_once __DIR__ . '/audit.php';

function vehicleClassOf($vehicleType, $category = 'plated') {
    $t = strtolower(trim((string)$vehicleType . ' ' . (string)$category));
    if (preg_match('/motor|scooter|tricycle|\b[23]\s*-?\s*wheel/', $t)) return 'two';
    if (preg_match('/bicycle|non-?\s?plated|unplated|\bbike\b/', $t)) return 'bicycle';
    return 'four';
}

function vehicleClassLabel($class) {
    return ['four' => 'four-wheel', 'two' => 'two/three-wheel', 'bicycle' => 'bicycle'][$class] ?? $class;
}

/**
 * The active (not retired) vehicle of this class already registered to the ID, optionally ignoring one vehicle id.
 */
function findOwnerVehicleInClass($pdo, $ownerIdNumber, $class, $exceptVehicleId = 0) {
    $needle = strtoupper(trim((string)$ownerIdNumber));
    if ($needle === '') return null;
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE UPPER(TRIM(`owner_id_number`)) = ? AND `is_retired` = 0 AND `id` <> ? ORDER BY `id` ASC");
    $stmt->execute([$needle, (int)$exceptVehicleId]);
    foreach ($stmt->fetchAll() as $v) {
        if (vehicleClassOf($v['vehicle_type'], $v['category']) === $class) return $v;
    }
    return null;
}

function ownerClassLimitResponse($existing, $class) {
    sendResponse(409, [
        'code' => 'OWNER_CLASS_LIMIT',
        'plateNumber' => $existing['plate_number'],
        'vehicleId' => (int)$existing['id'],
        'vehicleClass' => $class,
        'classLabel' => vehicleClassLabel($class),
    ], "ID {$existing['owner_id_number']} already has a {$existing['plate_number']} registered as a " . vehicleClassLabel($class)
        . " vehicle. Replace it, or an administrator can allow an extra one with a written reason.");
}

/** Marks a vehicle retired. $replacedBy is the new vehicle's id when it was replaced. */
function retireVehicle($pdo, $actor, $vehicle, $reason, $replacedBy = null) {
    $pdo->prepare("UPDATE `vehicles` SET `is_retired` = 1, `retired_at` = ?, `retired_reason` = ?, `replaced_by_vehicle_id` = ? WHERE `id` = ?")
        ->execute([date('Y-m-d H:i:s'), substr($reason, 0, 250), $replacedBy, $vehicle['id']]);
    cancelPendingPayments($pdo, $vehicle['id']);
    auditLog($pdo, $actor, $replacedBy ? 'vehicle.replace' : 'vehicle.retire', [
        'entityType' => 'vehicle', 'entityId' => (int)$vehicle['id'], 'plate' => $vehicle['plate_number'],
        'detail' => $replacedBy ? 'Replaced by vehicle #' . $replacedBy : 'Retired without replacement', 'reason' => $reason,
    ]);
}

/**
 * Fee already paid for the old vehicle's CURRENT pass year, or 0 (free, VIP, unpaid, expired and legacy vehicles carry nothing).
 */
function transferableCredit($pdo, $oldVehicle, $today = null) {
    if (($oldVehicle['payment_status'] ?? '') !== 'Paid' || isVipVehicle($oldVehicle)) return 0.0;
    if (vehiclePassExpired($oldVehicle, $today)) return 0.0;
    return paidTotalForVehicle($pdo, $oldVehicle['id']);
}

/**
 * Applies $credit from the old vehicle to the new one. Writes a 'Transfer credit' payment (receipt included) and
 * activates the new pass when nothing is left to pay; otherwise the new vehicle stays Unpaid for the balance.
 * Returns ['applied' => x, 'balance' => y].
 */
function applyTransferCredit($pdo, $actor, $newVehicleId, $oldVehicle, $credit) {
    $new = findVehicleById($pdo, $newVehicleId);
    $fee = (float)$new['fee_amount']; // amount due on the new vehicle (0 when waived)
    $applied = min($credit, $fee);
    if ($applied <= 0) return ['applied' => 0.0, 'balance' => $fee];

    $now = date('Y-m-d H:i:s');
    $pdo->prepare("INSERT INTO `payments`
        (`vehicle_id`, `plate_number`, `owner_id_number`, `owner_name`, `sticker_year`, `purpose`, `amount`, `method`, `status`, `notes`, `recorded_by`, `recorded_by_user_id`, `created_at`, `paid_at`)
        VALUES (?, ?, ?, ?, ?, 'Transfer credit', ?, 'Credit', 'Paid', ?, ?, ?, ?, ?)")
        ->execute([$new['id'], $new['plate_number'], $new['owner_id_number'], $new['owner_name'], $new['sticker_year'], $applied,
            "Credit carried over from {$oldVehicle['plate_number']}", actorLabel($actor), actorUserId($actor), $now, $now]);
    $paymentId = (int)$pdo->lastInsertId();
    $pdo->prepare("UPDATE `payments` SET `receipt_number` = ? WHERE `id` = ?")->execute([sprintf('OR-%s-%06d', date('Y'), $paymentId), $paymentId]);

    $balance = round($fee - $applied, 2);
    if ($balance <= 0) {
        $pdo->prepare("UPDATE `vehicles` SET `payment_status` = 'Paid', `paid_at` = ?, `fee_amount` = ?, `pass_id` = ? WHERE `id` = ?")
            ->execute([$now, $applied, newPassId(), $new['id']]);
    } else {
        $pdo->prepare("UPDATE `vehicles` SET `fee_amount` = ? WHERE `id` = ?")->execute([$balance, $new['id']]);
    }
    return ['applied' => $applied, 'balance' => max(0.0, $balance)];
}
