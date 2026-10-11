<?php
require_once __DIR__ . '/settings.php';

/** Resolve existing physical checkpoint labels, never account usernames. */
function gateNumber($label) {
    return preg_match('/\b(?:gate|checkpoint)\s*[-#]?\s*([12])\b/i', (string)$label, $m) ? (int)$m[1] : null;
}

function gatePolicy($pdo, $actor, $requestedCheckpoint = null, $direction = null) {
    $assigned = trim((string)($actor['gate_assigned'] ?? ''));
    $number = gateNumber($assigned);
    $canSelect = ($actor['role'] ?? '') === 'admin' || !empty($actor['is_scanner']);
    if ($canSelect && !$number) {
        $number = gateNumber($requestedCheckpoint);
        if (!$number && !$requestedCheckpoint && $direction) $number = $direction === 'Egress' ? 2 : 1;
    }
    $event = (int)spSetting($pdo, 'event_gate_mode') === 1;
    $allowed = !$number ? [] : ($event ? ['Ingress', 'Egress'] : [$number === 1 ? 'Ingress' : 'Egress']);
    return ['mode' => $event ? 'event' : 'normal', 'modeLabel' => $event ? 'Event operation' : 'Normal operation',
        'checkpoint' => $number ? 'Gate ' . $number : $assigned, 'gateNumber' => $number,
        'canSelectCheckpoint' => $canSelect && !gateNumber($assigned), 'allowedDirections' => $allowed,
        'message' => !$number ? 'Ask an administrator to assign Gate 1 or Gate 2 before recording a passage.'
            : ($event ? 'Entry and exit are authorized at both gates.' : 'Gate 1: entry. Gate 2: exit.')];
}

function gateDirectionError($policy, $direction) {
    if (!$policy['gateNumber']) return $policy['message'];
    return in_array($direction, $policy['allowedDirections'], true) ? null
        : $policy['checkpoint'] . ' does not permit ' . ($direction === 'Egress' ? 'exit' : 'entry') . ' in normal operation. Use the authorized gate or ask an administrator to enable event operation.';
}

/** Serialize mode changes and fresh confirmations on the policy row. */
function lockGatePolicy($pdo) {
    if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql') {
        if ($pdo->query("SELECT `setting_value` FROM `system_settings` WHERE `setting_key` = 'event_gate_mode' FOR UPDATE")->fetchColumn() === false) {
            throw new RuntimeException('Gate policy migration 012 is required.');
        }
    }
    unset($GLOBALS['sp_settings_cache']);
}
