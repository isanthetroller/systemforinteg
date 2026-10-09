<?php
/**
 * SecurePark - Admin action log
 *
 * Every sensitive action (granting VIP, dismissing / resolving a violation, editing a pass date, deleting,
 * retiring or replacing a vehicle, cash payments, account changes, overrides, settings...) writes one row:
 * who, what, which record, why. Reasons are mandatory for the actions listed in AUDIT_REASON_REQUIRED.
 * Logging never throws into the caller.
 */

function auditClientIp() {
    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
    $ip = trim(explode(',', (string)$ip)[0]);
    return substr($ip, 0, 45) ?: null;
}

/**
 * $actor: a staff row, or a string label such as 'System'. $o keys: entityType, entityId, plate, detail, reason.
 */
function auditLog($pdo, $actor, $action, array $o = []) {
    try {
        $label = is_array($actor) ? (!empty($actor['is_scanner']) ? 'Mobile Scanner' : actorLabel($actor)) : (string)$actor;
        $stmt = $pdo->prepare("INSERT INTO `audit_log`
            (`actor_user_id`, `actor_label`, `actor_role`, `action`, `entity_type`, `entity_id`, `plate_number`, `detail`, `reason`, `ip_address`, `created_at`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([
            is_array($actor) ? actorUserId($actor) : null, $label, is_array($actor) ? ($actor['role'] ?? null) : 'system', $action,
            $o['entityType'] ?? null, $o['entityId'] ?? null, $o['plate'] ?? null,
            isset($o['detail']) ? (is_string($o['detail']) ? $o['detail'] : json_encode($o['detail'], JSON_UNESCAPED_UNICODE)) : null,
            $o['reason'] ?? null, auditClientIp(), date('Y-m-d H:i:s'),
        ]);
    } catch (Exception $e) {
        error_log('[Audit] could not write ' . $action . ': ' . $e->getMessage());
    }
}

/**
 * Returns the trimmed reason from a request body (key 'reason'), or answers 400 when it is missing / too short.
 */
function requireReason($data, $what, $key = 'reason') {
    $reason = trim((string)($data[$key] ?? ''));
    if (mb_strlen($reason) < 5) {
        sendResponse(400, ['code' => 'REASON_REQUIRED'], "A reason (at least 5 characters) is required for {$what}.");
    }
    return $reason;
}

function auditView($r) {
    return [
        'id' => (int)$r['id'],
        'actor' => $r['actor_label'],
        'actorRole' => $r['actor_role'],
        'action' => $r['action'],
        'entityType' => $r['entity_type'],
        'entityId' => $r['entity_id'] !== null ? (int)$r['entity_id'] : null,
        'plateNumber' => $r['plate_number'],
        'detail' => $r['detail'],
        'reason' => $r['reason'],
        'ip' => $r['ip_address'],
        'createdAt' => $r['created_at'],
    ];
}
