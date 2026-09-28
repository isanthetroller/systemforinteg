-- ==============================================================================
-- SecurePark Migration 003: system_settings (configurable pass rules)
-- Target: EXISTING database, AFTER 002_visitor_items.sql. Non-destructive.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 11. Table: system_settings
-- Configurable campus gate rules (e.g., visitor pass validity hours).
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `system_settings` (
  `setting_key` VARCHAR(64) PRIMARY KEY,
  `setting_value` VARCHAR(255) NOT NULL,
  `description` VARCHAR(255) NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `system_settings` (`setting_key`, `setting_value`, `description`)
VALUES ('visitor_pass_validity_hours', '8', 'Validity duration for temporary visitor passes in hours')
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
