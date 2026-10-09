<?php
/**
 * SecurePark - Second-admin approvals
 *
 * Granting VIP (exempts a vehicle from violations, fees and curfew checks) and dismissing a violation
 * (lifts a hold) each need a second administrator. The requester proposes with a reason; a DIFFERENT active
 * administrator approves or rejects. When fewer than two administrators are active there is nobody to ask,
 * so the action is applied directly and the audit log says so.
 */

require_once __DIR__ . '/violations.php';
require_once __DIR__ . '/payments.php';
require_once __DIR__ . '/audit.php';

const SP_APPROVAL_TYPES = ['vip_grant' => 'Grant VIP', 'violation_dismiss' => 'Dismiss violation'];

function activeAdminCount($pdo) {
    return (int)$pdo->query("SELECT COUNT(*) FROM `system_users` WHERE `role` = 'admin' AND `status` = 'Active'")->fetchColumn();
}

function needsSecondAdmin($pdo) {
    return activeAdminCount($pdo) >= 2;
}

function pendingApproval($pdo, $type, $vehicleId = null, $violationId = null) {
    $sql = "SELECT * FROM `approval_requests` WHERE `type` = ? AND `status` = 'Pending'";
    $params = [$type];
    if ($vehicleId !== null) { $sql .= " AND `vehicle_id` = ?"; $params[] = $vehicleId; }
    if ($violationId !== null) { $sql .= " AND `violation_id` = ?"; $params[] = $violationId; }
    $stmt = $pdo->prepare($sql . " LIMIT 1");
    $stmt->execute($params);
    return $stmt->fetch() ?: null;
}

function createApprovalRequest($pdo, $actor, $type, $vehicle, $violation, $reason) {
    $stmt = $pdo->prepare("INSERT INTO `approval_requests`
        (`type`, `vehicle_id`, `violation_id`, `plate_number`, `requested_by_user_id`, `requested_by_label`, `reason`, `status`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?)");
    $stmt->execute([$type, $vehicle['id'] ?? ($violation['vehicle_id'] ?? null), $violation['id'] ?? null,
        $vehicle['plate_number'] ?? ($violation['plate_number'] ?? null), actorUserId($actor), actorLabel($actor), $reason, date('Y-m-d H:i:s')]);
    $id = (int)$pdo->lastInsertId();
    auditLog($pdo, $actor, 'approval.requested', ['entityType' => 'approval', 'entityId' => $id, 'plate' => $vehicle['plate_number'] ?? ($violation['plate_number'] ?? null),
        'detail' => SP_APPROVAL_TYPES[$type] ?? $type, 'reason' => $reason]);
    return $id;
}

/** Makes a vehicle VIP (and waives a fee that was still due). */
function applyVipGrant($pdo, $vehicleId, $byLabel) {
    $vehicle = findVehicleById($pdo, $vehicleId);
    if (!$vehicle) return false;
    $pdo->prepare("UPDATE `vehicles` SET `pass_class` = 'VIP', `pass_class_by` = ?, `pass_class_at` = ? WHERE `id` = ?")
        ->execute([$byLabel, date('Y-m-d H:i:s'), $vehicleId]);
    if (($vehicle['payment_status'] ?? 'Paid') === 'Unpaid') {
        $pdo->prepare("UPDATE `vehicles` SET `payment_status` = 'Waived', `fee_amount` = 0 WHERE `id` = ?")->execute([$vehicleId]);
        cancelPendingPayments($pdo, $vehicleId);
    }
    return true;
}

function approvalView($r) {
    return [
        'id' => (int)$r['id'],
        'type' => $r['type'],
        'typeLabel' => SP_APPROVAL_TYPES[$r['type']] ?? $r['type'],
        'vehicleId' => $r['vehicle_id'] !== null ? (int)$r['vehicle_id'] : null,
        'violationId' => $r['violation_id'] !== null ? (int)$r['violation_id'] : null,
        'plateNumber' => $r['plate_number'],
        'requestedBy' => $r['requested_by_label'],
        'requestedByUserId' => $r['requested_by_user_id'] !== null ? (int)$r['requested_by_user_id'] : null,
        'reason' => $r['reason'],
        'status' => $r['status'],
        'decidedBy' => $r['decided_by_label'],
        'decisionNote' => $r['decision_note'],
        'createdAt' => $r['created_at'],
        'decidedAt' => $r['decided_at'],
    ];
}

/**
 * Approve or reject. Returns ['ok' => bool, 'code' => int, 'message' => string, 'request' => row].
 */
function decideApproval($pdo, $admin, $id, $approve, $note) {
    $stmt = $pdo->prepare("SELECT * FROM `approval_requests` WHERE `id` = ?");
    $stmt->execute([(int)$id]);
    $req = $stmt->fetch();
    if (!$req) return ['ok' => false, 'code' => 404, 'message' => 'Approval request not found.'];
    if ($req['status'] !== 'Pending') return ['ok' => false, 'code' => 409, 'message' => "This request was already {$req['status']}."];
    if ((int)$req['requested_by_user_id'] === actorUserId($admin)) {
        return ['ok' => false, 'code' => 403, 'message' => 'You cannot decide your own request. Another administrator must.'];
    }

    $label = actorLabel($admin);
    $now = date('Y-m-d H:i:s');
    $executed = '';
    if ($approve) {
        if ($req['type'] === 'vip_grant') {
            $vehicle = findVehicleById($pdo, $req['vehicle_id']);
            if (!$vehicle) return ['ok' => false, 'code' => 404, 'message' => 'The vehicle no longer exists. Reject this request.'];
            if ((int)$vehicle['is_banned'] === 1) return ['ok' => false, 'code' => 409, 'message' => 'The vehicle is on violation hold and cannot be made VIP. Reject this request.'];
            applyVipGrant($pdo, $vehicle['id'], "{$req['requested_by_label']}, approved by {$label}");
            $executed = "{$vehicle['plate_number']} is now VIP.";
        } elseif ($req['type'] === 'violation_dismiss') {
            $violation = fetchViolation($pdo, $req['violation_id']);
            if (!$violation || $violation['status'] !== 'Pending') {
                $pdo->prepare("UPDATE `approval_requests` SET `status` = 'Rejected', `decided_by_user_id` = ?, `decided_by_label` = ?, `decision_note` = ?, `decided_at` = ? WHERE `id` = ?")
                    ->execute([actorUserId($admin), $label, 'The violation was already closed.', $now, $req['id']]);
                $stmt->execute([(int)$id]);
                return ['ok' => true, 'code' => 200, 'message' => 'That violation was already closed, so the request was closed.', 'request' => $stmt->fetch()];
            }
            $proxy = ['full_name' => "{$req['requested_by_label']}, approved by {$label}", 'badge_number' => null];
            dismissViolation($pdo, $proxy, $violation, $req['reason']);
            $executed = "Violation on {$violation['plate_number']} dismissed.";
        }
    }
    $pdo->prepare("UPDATE `approval_requests` SET `status` = ?, `decided_by_user_id` = ?, `decided_by_label` = ?, `decision_note` = ?, `decided_at` = ? WHERE `id` = ?")
        ->execute([$approve ? 'Approved' : 'Rejected', actorUserId($admin), $label, $note !== '' ? $note : null, $now, $req['id']]);
    auditLog($pdo, $admin, $approve ? 'approval.approved' : 'approval.rejected', ['entityType' => 'approval', 'entityId' => (int)$req['id'], 'plate' => $req['plate_number'],
        'detail' => (SP_APPROVAL_TYPES[$req['type']] ?? $req['type']) . " requested by {$req['requested_by_label']}" . ($executed ? " - {$executed}" : ''), 'reason' => $note !== '' ? $note : $req['reason']]);
    $stmt->execute([(int)$id]);
    return ['ok' => true, 'code' => 200, 'message' => $approve ? ($executed ?: 'Approved.') : 'Request rejected.', 'request' => $stmt->fetch()];
}
