<?php
/**
 * SecurePark - Policy settings stored in system_settings (editable in Admin Center > Settings)
 */

/** Allowed settings: key => [default, min, max, label] */
function spSettingDefinitions() {
    return [
        'parking_capacity' => [0, 0, 100000, 'Parking capacity (0 = not limited)'],
        'renewal_window_days' => [60, 1, 365, 'Renewal opens this many days before expiry'],
        'expiry_warning_days' => [30, 1, 365, 'Expiry notice to the owner, days before expiry'],
        'hold_reminder_days' => [3, 1, 60, 'Remind the owner every N days while a violation is unresolved'],
        'exit_release_minutes' => [30, 5, 1440, 'Validity of an admin-released exit (minutes)'],
        'evidence_retention_days' => [90, 7, 3650, 'Delete guard photos after this many days'],
    ];
}

function spSetting($pdo, $key, $default = null) {
    $defs = spSettingDefinitions();
    if ($default === null && isset($defs[$key])) $default = $defs[$key][0];
    if (!isset($GLOBALS['sp_settings_cache'])) {
        try {
            $GLOBALS['sp_settings_cache'] = $pdo->query("SELECT `setting_key`, `setting_value` FROM `system_settings`")->fetchAll(PDO::FETCH_KEY_PAIR);
        } catch (Exception $e) {
            $GLOBALS['sp_settings_cache'] = [];
        }
    }
    $value = $GLOBALS['sp_settings_cache'][$key] ?? null;
    if ($value === null || $value === '') return $default;
    return is_int($default) ? (int)$value : $value;
}

function spSetSetting($pdo, $key, $value) {
    $stmt = $pdo->prepare("UPDATE `system_settings` SET `setting_value` = ? WHERE `setting_key` = ?");
    $stmt->execute([(string)$value, $key]);
    if ($stmt->rowCount() === 0) {
        $exists = $pdo->prepare("SELECT COUNT(*) FROM `system_settings` WHERE `setting_key` = ?");
        $exists->execute([$key]);
        if ((int)$exists->fetchColumn() === 0) {
            $pdo->prepare("INSERT INTO `system_settings` (`setting_key`, `setting_value`, `description`) VALUES (?, ?, ?)")
                ->execute([$key, (string)$value, spSettingDefinitions()[$key][3] ?? null]);
        }
    }
    unset($GLOBALS['sp_settings_cache']); // the next read sees the new value
}
