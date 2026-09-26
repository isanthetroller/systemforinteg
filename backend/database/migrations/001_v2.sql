-- ==============================================================================
-- SecurePark Migration 001: v2 (auth, roles, signed QR, violations, visitors)
-- Target: EXISTING InfinityFree MySQL database (phpMyAdmin > SQL tab)
-- NON-DESTRUCTIVE: keeps all existing vehicles, drivers, logs and incidents.
-- Run ONCE. Back up the database first (phpMyAdmin > Export).
-- ==============================================================================

SET time_zone = '+08:00';

-- ------------------------------------------------------------------------------
-- 1. system_users: explicit admin/guard roles + login tracking
--    (role and status already exist, so convert role instead of adding it)
-- ------------------------------------------------------------------------------
UPDATE `system_users` SET `role` = 'admin' WHERE LOWER(`role`) LIKE '%admin%';
UPDATE `system_users` SET `role` = 'guard' WHERE `role` NOT IN ('admin', 'guard');
ALTER TABLE `system_users`
  MODIFY COLUMN `role` ENUM('admin', 'guard') NOT NULL DEFAULT 'guard',
  ADD COLUMN `last_login` DATETIME NULL AFTER `status`,
  ADD COLUMN `failed_attempts` INT NOT NULL DEFAULT 0 AFTER `last_login`,
  ADD COLUMN `locked_until` DATETIME NULL AFTER `failed_attempts`,
  ADD COLUMN `must_change_password` TINYINT(1) NOT NULL DEFAULT 0 AFTER `locked_until`;

-- The original seed hash never matched its documented password, so reset it.
-- Temporary password: Password123!  (forced change on first login)
UPDATE `system_users`
  SET `password_hash` = '$2y$10$rzNVx9Nx4Sq2hYQD8Fxiae4EEsK4.Zz/c1sgyEa7OW8gPSGQnvv9O',
      `must_change_password` = 1
  WHERE `username` = 'admin';

-- ------------------------------------------------------------------------------
-- 2. vehicles: 3-strike tracking + signed pass identity
-- ------------------------------------------------------------------------------
ALTER TABLE `vehicles`
  ADD COLUMN `warning_count` INT NOT NULL DEFAULT 0 AFTER `last_gate_point`,
  ADD COLUMN `is_banned` TINYINT(1) NOT NULL DEFAULT 0 AFTER `warning_count`,
  ADD COLUMN `pass_id` VARCHAR(40) NULL UNIQUE AFTER `is_banned`,
  ADD COLUMN `pass_valid_until` DATE NULL AFTER `pass_id`;

-- ------------------------------------------------------------------------------
-- 3. gate_logs: precise entry/exit actions, gate direction, verified driver
--    Convert legacy action values first so the ENUM does not reject them.
-- ------------------------------------------------------------------------------
UPDATE `gate_logs` SET `action` = 'Entry Denied'
  WHERE `action` NOT IN ('Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied');
ALTER TABLE `gate_logs`
  MODIFY COLUMN `action` ENUM('Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied') NOT NULL DEFAULT 'Entry Recorded',
  ADD COLUMN `gate_type` ENUM('Ingress', 'Egress') NOT NULL DEFAULT 'Ingress' AFTER `action`,
  ADD COLUMN `verified_driver_name` VARCHAR(150) NULL AFTER `gate_type`,
  ADD COLUMN `logged_by_user_id` INT NULL AFTER `guard_name`;
UPDATE `gate_logs` SET `gate_type` = 'Egress' WHERE `action` IN ('Exit Approved', 'Exit Denied');

-- ------------------------------------------------------------------------------
-- 4. security_incidents: link to the officer's account
-- ------------------------------------------------------------------------------
ALTER TABLE `security_incidents`
  ADD COLUMN `logged_by_user_id` INT NULL AFTER `officer`;

-- ------------------------------------------------------------------------------
-- 6. Table: student_accounts
-- Student / vehicle-owner logins for the Student Portal (separate from staff).
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
-- 7. Table: auth_tokens
-- Bearer session tokens (stored as SHA-256 hashes) for staff and students.
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
-- 8. Table: vehicle_violations
-- Warnings (strikes) and violations. 3 strikes => automatic Violation + ban.
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
-- 9. Table: visitor_passes
-- Single-day temporary passes (valid only on valid_date).
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
  INDEX `idx_visitor_date` (`valid_date`),
  INDEX `idx_visitor_plate` (`plate_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
