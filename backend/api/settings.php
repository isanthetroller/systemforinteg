<?php
/**
 * SecurePark API - System Settings & Pass Expiration Rules
 *
 * GET  /api/settings.php - Retrieve current campus pass policy rules (Staff & Scanner)
 * POST /api/settings.php - Update pass policy rules (Admin only)
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        handleGetSettings($pdo);
        break;
    case 'POST':
    case 'PUT':
        $admin = requireStaff($pdo, ['admin']);
        handleUpdateSettings($pdo, $admin);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function ensureSettingsTable($pdo) {
    try {
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS `system_settings` (
                `setting_key` VARCHAR(64) PRIMARY KEY,
                `setting_value` VARCHAR(255) NOT NULL,
                `description` VARCHAR(255) NULL,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM `system_settings` WHERE `setting_key` = 'visitor_pass_validity_hours'");
        $stmt->execute();
        if ((int)$stmt->fetchColumn() === 0) {
            $ins = $pdo->prepare("INSERT INTO `system_settings` (`setting_key`, `setting_value`, `description`) VALUES ('visitor_pass_validity_hours', '8', 'Validity duration for temporary visitor passes in hours')");
            $ins->execute();
        }
    } catch (Exception $e) {
        // Table creation fallback handled gracefully
    }
}

function handleGetSettings($pdo) {
    ensureSettingsTable($pdo);

    $defaults = [
        'visitor_pass_validity_hours' => 8,
        'curfew_time' => '22:00',
        'overnight_warning_threshold' => 3,
    ];

    try {
        $stmt = $pdo->query("SELECT `setting_key`, `setting_value` FROM `system_settings`");
        $rows = $stmt->fetchAll(PDO::FETCH_KEY_PAIR);
        if ($rows) {
            foreach ($rows as $k => $v) {
                if ($k === 'visitor_pass_validity_hours' || $k === 'overnight_warning_threshold') {
                    $defaults[$k] = (int)$v;
                } else {
                    $defaults[$k] = $v;
                }
            }
        }
    } catch (Exception $e) {
        // Use defaults if table query fails
    }

    sendResponse(200, $defaults);
}

function handleUpdateSettings($pdo, $actor) {
    ensureSettingsTable($pdo);

    $data = getJsonInput();
    if (empty($data)) {
        sendResponse(400, null, 'No setting values provided to update.');
    }

    $updated = [];

    if (isset($data['visitor_pass_validity_hours'])) {
        $hours = (int)$data['visitor_pass_validity_hours'];
        if ($hours < 1 || $hours > 72) {
            sendResponse(400, null, 'Visitor pass validity must be between 1 and 72 hours.');
        }

        $stmt = $pdo->prepare("
            INSERT INTO `system_settings` (`setting_key`, `setting_value`, `description`, `updated_at`)
            VALUES ('visitor_pass_validity_hours', ?, 'Validity duration for temporary visitor passes in hours', NOW())
            ON DUPLICATE KEY UPDATE `setting_value` = VALUES(`setting_value`), `updated_at` = NOW()
        ");
        try {
            $stmt->execute([(string)$hours]);
        } catch (Exception $e) {
            // SQLite compatibility fallback
            $sqliteStmt = $pdo->prepare("INSERT OR REPLACE INTO `system_settings` (`setting_key`, `setting_value`, `description`, `updated_at`) VALUES ('visitor_pass_validity_hours', ?, 'Validity duration for temporary visitor passes in hours', datetime('now'))");
            $sqliteStmt->execute([(string)$hours]);
        }
        $updated['visitor_pass_validity_hours'] = $hours;
    }

    if (empty($updated)) {
        sendResponse(400, null, 'No valid setting recognized to update.');
    }

    sendResponse(200, $updated, 'System settings updated successfully.');
}
