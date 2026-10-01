-- ==============================================================================
-- SecurePark: Consolidated Migration (Step 2 through 10)
-- Target: EXISTING MySQL database (phpMyAdmin > SQL tab)
-- 
-- Note: 'system_users' already has 'last_login', so it is skipped.
-- This script applies the remaining updates to vehicles, logs, and creates
-- all missing tables.
-- ==============================================================================

SET time_zone = '+08:00';

-- ------------------------------------------------------------------------------
-- 1. Table: vehicles (3-strike tracking, VIP classification, signed passes)
-- ------------------------------------------------------------------------------
ALTER TABLE `vehicles`
  ADD COLUMN `warning_count` INT NOT NULL DEFAULT 0,
  ADD COLUMN `is_banned` TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN `pass_class` VARCHAR(16) NOT NULL DEFAULT 'Standard' COMMENT 'Standard or VIP',
  ADD COLUMN `pass_class_by` VARCHAR(150) NULL,
  ADD COLUMN `pass_class_at` DATETIME NULL,
  ADD COLUMN `pass_id` VARCHAR(40) NULL,
  ADD COLUMN `pass_valid_until` DATE NULL;

UPDATE `vehicles` SET `status` = 'Outside' WHERE `status` = 'Exited';

-- ------------------------------------------------------------------------------
-- 2. Table: gate_logs (Ingress/Egress directions, verified driver, offline sync)
-- ------------------------------------------------------------------------------
UPDATE `gate_logs` SET `action` = 'Entry Denied'
  WHERE `action` NOT IN ('Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied');

ALTER TABLE `gate_logs`
  MODIFY COLUMN `action` ENUM('Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied') NOT NULL DEFAULT 'Entry Recorded',
  ADD COLUMN `gate_type` ENUM('Ingress', 'Egress') NOT NULL DEFAULT 'Ingress',
  ADD COLUMN `verified_driver_name` VARCHAR(150) NULL,
  ADD COLUMN `logged_by_user_id` INT NULL,
  ADD COLUMN `synced_at` DATETIME NULL,
  ADD COLUMN `client_ref` VARCHAR(64) NULL;

UPDATE `gate_logs` SET `gate_type` = 'Egress' WHERE `action` IN ('Exit Approved', 'Exit Denied');

-- ------------------------------------------------------------------------------
-- 3. Table: security_incidents (Officer linking and offline sync)
-- ------------------------------------------------------------------------------
ALTER TABLE `security_incidents`
  ADD COLUMN `logged_by_user_id` INT NULL,
  ADD COLUMN `client_ref` VARCHAR(64) NULL;

-- ------------------------------------------------------------------------------
-- 4. Table: student_accounts (Student & Vehicle Owner portal logins)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `student_accounts` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `owner_id_number` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Login username = NCST student/employee ID',
  `full_name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(100) NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `must_change_password` TINYINT(1) NOT NULL DEFAULT 1,
  `status` ENUM('Active', 'Inactive') NOT NULL DEFAULT 'Active',
  `failed_attempts` INT NOT NULL DEFAULT 0,
  `locked_until` DATETIME NULL,
  `last_login` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 5. Table: auth_tokens (Bearer session tokens for staff and students)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `auth_tokens` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `token_hash` CHAR(64) NOT NULL UNIQUE,
  `user_type` ENUM('staff', 'student') NOT NULL,
  `user_id` INT NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `revoked` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_token_user` (`user_type`, `user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 6. Table: vehicle_violations (Warnings, strikes, violations)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `vehicle_violations` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `vehicle_id` INT NOT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `violation_type` VARCHAR(100) NOT NULL,
  `description` TEXT NULL,
  `severity` ENUM('Warning', 'Violation') NOT NULL DEFAULT 'Warning',
  `logged_by` VARCHAR(100) NOT NULL,
  `logged_by_user_id` INT NULL,
  `status` ENUM('Pending', 'Resolved', 'Dismissed') NOT NULL DEFAULT 'Pending',
  `counts_as_strike` TINYINT(1) NOT NULL DEFAULT 0,
  `cleared_by_violation_id` INT NULL,
  `incident_id` INT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `resolved_at` DATETIME NULL,
  `resolved_by` VARCHAR(100) NULL,
  `resolution_notes` TEXT NULL,
  INDEX `idx_viol_vehicle` (`vehicle_id`),
  INDEX `idx_viol_status` (`status`),
  CONSTRAINT `fk_violations_vehicle` FOREIGN KEY (`vehicle_id`)
    REFERENCES `vehicles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 7. Table: visitor_passes (Single-day temporary passes & offline sync)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `visitor_passes` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `pass_code` VARCHAR(100) NOT NULL UNIQUE,
  `visitor_name` VARCHAR(150) NOT NULL,
  `contact_number` VARCHAR(20) NOT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `vehicle_model` VARCHAR(100) NULL,
  `purpose_of_visit` VARCHAR(255) NOT NULL,
  `person_to_visit` VARCHAR(150) NOT NULL COMMENT 'School insider / department',
  `valid_date` DATE NOT NULL,
  `entry_time` DATETIME NULL,
  `exit_time` DATETIME NULL,
  `status` ENUM('Active', 'Used', 'Expired', 'Revoked') NOT NULL DEFAULT 'Active',
  `created_by` VARCHAR(100) NULL,
  `created_by_user_id` INT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `synced_at` DATETIME NULL,
  INDEX `idx_visitor_date` (`valid_date`),
  INDEX `idx_visitor_plate` (`plate_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 8. Table: visitor_pass_items (Items brought in/out by visitors)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `visitor_pass_items` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `visitor_pass_id` INT NOT NULL,
  `item_name` VARCHAR(100) NOT NULL,
  `quantity` INT NOT NULL DEFAULT 1,
  `description` VARCHAR(255) NULL,
  INDEX `idx_item_pass` (`visitor_pass_id`),
  CONSTRAINT `fk_items_visitor_pass` FOREIGN KEY (`visitor_pass_id`)
    REFERENCES `visitor_passes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 9. Table: system_settings (Configurable gate policies)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `system_settings` (
  `setting_key` VARCHAR(64) PRIMARY KEY,
  `setting_value` VARCHAR(255) NOT NULL,
  `description` VARCHAR(255) NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
