<?php
require_once __DIR__ . '/settings.php';

/** Resolve existing physical checkpoint labels, never account usernames. */
function gateNumber($label) {
    return preg_match('/\b(?:gate|checkpoint)\s*[-#]?\s*([12])\b/i', (string)$label, $m) ? (int)$m[1] : null;
}

function gatePolicy($pdo, $actor, $requestedCheckpoint = null, $direction = null) {
    $assigned = trim((string)($actor['gate_assigned'] ?? ''));
    $number = gateNumber($assigned);
    // An account assigned to Gate 1 or Gate 2 is locked to that gate. Any other assignment (All Gates, Gate 3, blank),
    // and device-key scanners, work at whichever gate matches the passage: entry at Gate 1, exit at Gate 2.
    $flexible = !$number;
    if ($flexible) {
        $number = gateNumber($requestedCheckpoint);
        // A label without a gate number (the phone echoes the account's own "All Gates") is not an explicit choice
        if (!$number && $direction) $number = $direction === 'Egress' ? 2 : 1;
    }
    $event = (int)spSetting($pdo, 'event_gate_mode') === 1;
    if ($number) $allowed = $event ? ['Ingress', 'Egress'] : [$number === 1 ? 'Ingress' : 'Egress'];
    else $allowed = $flexible ? ['Ingress', 'Egress'] : [];
    return ['mode' => $event ? 'event' : 'normal', 'modeLabel' => $event ? 'Event operation' : 'Normal operation',
        'checkpoint' => $number ? 'Gate ' . $number : $assigned, 'gateNumber' => $number,
        'canSelectCheckpoint' => $flexible, 'allowedDirections' => $allowed,
        'message' => $event ? 'Entry and exit are authorized at both gates.'
            : ($flexible && !$number ? 'All gates: entry is recorded at Gate 1 and exit at Gate 2.'
                : 'Gate 1: entry. Gate 2: exit.')];
}

function gateDirectionError($policy, $direction) {
    if (!$policy['gateNumber']) {
        // Flexible accounts get their gate from the direction; only an unknown direction ends up here
        return in_array($direction, $policy['allowedDirections'], true) ? null : 'Could not tell whether this passage is an entry or an exit.';
    }
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
