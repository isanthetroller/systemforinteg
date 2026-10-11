-- Existing installations: default to normal operation without changing a configured mode.
INSERT IGNORE INTO `system_settings` (`setting_key`, `setting_value`, `description`)
VALUES ('event_gate_mode', '0', '0: Gate 1 entry and Gate 2 exit; 1: entry and exit at both gates');
