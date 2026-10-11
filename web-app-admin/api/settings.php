<?php
/**
 * SecurePark API - Campus policy values
 *
 * GET /api/settings.php            Public policy values (curfew, parking capacity) used by the apps
 * GET /api/settings.php?scope=all  (admin) every editable setting with its limits
 * PUT /api/settings.php  { key: value, ... }   (admin) change settings; each change is written to the audit log
 *
 * Visitor day passes are valid all day on their date, so there is no pass-duration setting.
 * (Older mobile builds that ask for visitor_pass_validity_hours fall back to their own default.)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/settings.php';
require_once __DIR__ . '/../lib/audit.php';
require_once __DIR__ . '/../lib/gate_policy.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'PUT') {
    $admin = requireStaff($pdo, ['admin']);
    $data = getJsonInput();
    $defs = spSettingDefinitions();
    $changes = [];
    foreach ($data as $key => $value) {
        if (!isset($defs[$key])) continue;
        if (!is_scalar($value) || !preg_match('/^-?\d+$/', trim((string)$value))) {
            sendResponse(400, null, "{$defs[$key][3]} must be a whole number.");
        }
        $value = (int)$value;
        if ($value < $defs[$key][1] || $value > $defs[$key][2]) {
            sendResponse(400, null, "{$defs[$key][3]} must be between {$defs[$key][1]} and {$defs[$key][2]}.");
        }
        $changes[$key] = $value;
    }
    if (!$changes) sendResponse(400, null, 'No known setting was provided.');
    $reason = trim((string)($data['reason'] ?? ''));
    if (isset($changes['event_gate_mode']) && $changes['event_gate_mode'] !== (int)spSetting($pdo, 'event_gate_mode') && mb_strlen($reason) < 5) {
        sendResponse(400, ['code' => 'REASON_REQUIRED'], 'Explain why gate operation is changing (at least 5 characters).');
    }
    $pdo->beginTransaction();
    try {
        lockGatePolicy($pdo);
        foreach ($changes as $key => $value) {
            $old = spSetting($pdo, $key);
            if ((int)$old === $value) continue;
            if ($key === 'event_gate_mode' && mb_strlen($reason) < 5) throw new RuntimeException('Gate operation changed elsewhere. Provide a reason and try again.');
            spSetSetting($pdo, $key, $value);
            if ($key === 'event_gate_mode') {
                // The authorization record must commit with the operational permission change.
                $pdo->prepare("INSERT INTO `audit_log` (`actor_user_id`, `actor_label`, `actor_role`, `action`, `entity_type`, `detail`, `reason`, `created_at`) VALUES (?, ?, 'admin', 'gate.mode_change', 'setting', ?, ?, ?)")
                    ->execute([$admin['id'], actorLabel($admin), "event_gate_mode: {$old} -> {$value}", $reason, date('Y-m-d H:i:s')]);
            } else auditLog($pdo, $admin, 'settings.update', ['entityType' => 'setting', 'detail' => "{$key}: {$old} -> {$value}"]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        sendResponse(503, null, 'Settings were not saved. Refresh and retry with a reason for any gate mode change.');
    }
} elseif ($method !== 'GET') {
    sendResponse(405, null, 'Method ' . $method . ' not allowed');
}

if ($method === 'GET' && ($_GET['scope'] ?? '') === 'all' || $method === 'PUT') {
    requireStaff($pdo, ['admin']);
    $out = [];
    foreach (spSettingDefinitions() as $key => [$default, $min, $max, $label]) {
        $out[] = ['key' => $key, 'value' => (int)spSetting($pdo, $key), 'default' => $default, 'min' => $min, 'max' => $max, 'label' => $label];
    }
    sendResponse(200, $method === 'PUT' ? ['settings' => $out] : $out, $method === 'PUT' ? 'Settings saved.' : '');
}

$values = [
    'curfew_time' => defined('SP_CURFEW_TIME') ? SP_CURFEW_TIME : '22:00',
    'overnight_warning_threshold' => 3,
    'parking_capacity' => (int)spSetting($pdo, 'parking_capacity'),
    'event_gate_mode' => (int)spSetting($pdo, 'event_gate_mode'),
    'exit_release_minutes' => (int)spSetting($pdo, 'exit_release_minutes'),
];

try {
    $rows = $pdo->query("SELECT `setting_key`, `setting_value` FROM `system_settings`")->fetchAll(PDO::FETCH_KEY_PAIR);
    foreach ($rows as $key => $value) {
        if ($key === 'visitor_pass_validity_hours' || $key === 'maintenance_last_run') continue; // retired / internal
        if (isset(spSettingDefinitions()[$key])) continue;    // policy values are exposed through scope=all (admin) only
        $values[$key] = $key === 'overnight_warning_threshold' ? (int)$value : $value;
    }
} catch (Exception $e) {
    // No settings table: the defaults above apply
}

sendResponse(200, $values);
