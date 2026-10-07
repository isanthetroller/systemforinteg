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

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'PUT') {
    $admin = requireStaff($pdo, ['admin']);
    $data = getJsonInput();
    $defs = spSettingDefinitions();
    $changes = [];
    foreach ($data as $key => $value) {
        if (!isset($defs[$key])) continue;
        if (!is_numeric($value) || (string)(int)$value !== (string)(int)trim((string)$value)) {
            sendResponse(400, null, "{$defs[$key][3]} must be a whole number.");
        }
        $value = (int)$value;
        if ($value < $defs[$key][1] || $value > $defs[$key][2]) {
            sendResponse(400, null, "{$defs[$key][3]} must be between {$defs[$key][1]} and {$defs[$key][2]}.");
        }
        $changes[$key] = $value;
    }
    if (!$changes) sendResponse(400, null, 'No known setting was provided.');
    foreach ($changes as $key => $value) {
        $old = spSetting($pdo, $key);
        if ((int)$old === $value) continue;
        spSetSetting($pdo, $key, $value);
        auditLog($pdo, $admin, 'settings.update', ['entityType' => 'setting', 'detail' => "{$key}: {$old} -> {$value}"]);
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
];

try {
    $rows = $pdo->query("SELECT `setting_key`, `setting_value` FROM `system_settings`")->fetchAll(PDO::FETCH_KEY_PAIR);
    foreach ($rows as $key => $value) {
        if ($key === 'visitor_pass_validity_hours') continue; // retired setting
        if (isset(spSettingDefinitions()[$key])) continue;    // policy values are exposed through scope=all (admin) only
        $values[$key] = $key === 'overnight_warning_threshold' ? (int)$value : $value;
    }
} catch (Exception $e) {
    // No settings table: the defaults above apply
}

sendResponse(200, $values);
