<?php
/**
 * SecurePark API - Campus policy values (read-only)
 *
 * GET /api/settings.php - Current campus policy values (curfew, overnight threshold)
 *
 * Visitor day passes are valid all day on their date, so there is no pass-duration setting.
 * (Older mobile builds that ask for visitor_pass_validity_hours fall back to their own default.)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(405, null, 'Method ' . $_SERVER['REQUEST_METHOD'] . ' not allowed');
}

$values = [
    'curfew_time' => defined('SP_CURFEW_TIME') ? SP_CURFEW_TIME : '22:00',
    'overnight_warning_threshold' => 3,
];

try {
    $rows = $pdo->query("SELECT `setting_key`, `setting_value` FROM `system_settings`")->fetchAll(PDO::FETCH_KEY_PAIR);
    foreach ($rows as $key => $value) {
        if ($key === 'visitor_pass_validity_hours') continue; // retired setting
        $values[$key] = $key === 'overnight_warning_threshold' ? (int)$value : $value;
    }
} catch (Exception $e) {
    // No settings table: the defaults above apply
}

sendResponse(200, $values);
