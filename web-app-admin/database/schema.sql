-- ==============================================================================
-- SecurePark: Campus Gate Custody & Vehicle Administration System
-- Target Host: InfinityFree MySQL (phpMyAdmin)
-- WARNING: FRESH INSTALL ONLY. This drops every table. For an existing database
--          run database/migrations/001_v2.sql instead.
-- Timezone: all DATETIME values are Asia/Manila (UTC+8)
-- Engine: InnoDB | Character Set: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ==============================================================================

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `auth_tokens`;
DROP TABLE IF EXISTS `student_accounts`;
DROP TABLE IF EXISTS `visitor_pass_items`;
DROP TABLE IF EXISTS `visitor_passes`;
DROP TABLE IF EXISTS `vehicle_violations`;
DROP TABLE IF EXISTS `authorized_drivers`;
DROP TABLE IF EXISTS `gate_logs`;
DROP TABLE IF EXISTS `security_incidents`;
DROP TABLE IF EXISTS `vehicles`;
DROP TABLE IF EXISTS `system_users`;
SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------------------------
-- 1. Table: vehicles
-- Core vehicle master registry containing registration status and photos.
-- ------------------------------------------------------------------------------
CREATE TABLE `vehicles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `plate_number` VARCHAR(20) NOT NULL UNIQUE,
  `vehicle_type` VARCHAR(50) NOT NULL DEFAULT '4-Wheel (Sedan)',
  `category` VARCHAR(50) NOT NULL DEFAULT 'plated',
  `make_model_color` VARCHAR(150) NOT NULL,
  `owner_name` VARCHAR(100) NOT NULL,
  `owner_role` VARCHAR(50) NOT NULL DEFAULT 'Student',
  `department` VARCHAR(100) NULL,
  `owner_id_number` VARCHAR(50) NOT NULL,
  `owner_phone` VARCHAR(30) NULL,
  `owner_email` VARCHAR(100) NULL,
  `owner_photo` LONGTEXT NULL COMMENT 'Base64 image or URL',
  `vehicle_photo` LONGTEXT NULL COMMENT 'Base64 image or URL',
  `qr_pass_code` VARCHAR(100) NULL UNIQUE,
  `status` ENUM('Inside Campus', 'Exited', 'Blocked / Alert', 'Outside') NOT NULL DEFAULT 'Outside',
  `registration_status` ENUM('Active', 'Suspended') NOT NULL DEFAULT 'Active',
  `sticker_year` VARCHAR(20) NOT NULL DEFAULT '2026',
  `last_entry_time` VARCHAR(50) NULL,
  `last_gate_point` VARCHAR(100) NULL,
  `warning_count` INT NOT NULL DEFAULT 0,
  `is_banned` TINYINT(1) NOT NULL DEFAULT 0,
  `pass_class` VARCHAR(16) NOT NULL DEFAULT 'Standard' COMMENT 'Standard or VIP',
  `pass_class_by` VARCHAR(150) NULL COMMENT 'Admin who set the class',
  `pass_class_at` DATETIME NULL,
  `pass_id` VARCHAR(40) NULL UNIQUE,
  `pass_valid_until` DATE NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_plate` (`plate_number`),
  INDEX `idx_qr` (`qr_pass_code`),
  INDEX `idx_status` (`status`),
  INDEX `idx_reg_status` (`registration_status`),
  INDEX `idx_owner_id` (`owner_id_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 2. Table: authorized_drivers
-- Authorized alternate drivers roster saved in vehicle record and QR pass.
-- ------------------------------------------------------------------------------
CREATE TABLE `authorized_drivers` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `vehicle_id` INT NOT NULL,
  `full_name` VARCHAR(100) NOT NULL,
  `relationship` VARCHAR(100) NOT NULL DEFAULT 'Self (Owner)',
  `license_no` VARCHAR(50) NOT NULL DEFAULT 'N/A',
  `phone` VARCHAR(30) NULL,
  `photo_url` LONGTEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_vehicle_id` (`vehicle_id`),
  CONSTRAINT `fk_drivers_vehicle` FOREIGN KEY (`vehicle_id`) 
    REFERENCES `vehicles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 3. Table: gate_logs
-- Continuous audit log of vehicle movements at all campus gate points.
-- ------------------------------------------------------------------------------
CREATE TABLE `gate_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `plate_number` VARCHAR(20) NOT NULL,
  `vehicle_type` VARCHAR(50) NULL,
  `owner_name` VARCHAR(100) NULL,
  `driver_name` VARCHAR(100) NOT NULL,
  `driver_relationship` VARCHAR(100) NOT NULL DEFAULT 'Self (Owner)',
  `gate_point` VARCHAR(100) NOT NULL DEFAULT 'Gate 1 (Main Ingress)',
  `action` ENUM('Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied') NOT NULL DEFAULT 'Entry Recorded',
  `gate_type` ENUM('Ingress', 'Egress') NOT NULL DEFAULT 'Ingress',
  `verified_driver_name` VARCHAR(150) NULL,
  `status` VARCHAR(50) NOT NULL DEFAULT 'Inside Campus',
  `guard_name` VARCHAR(100) NOT NULL DEFAULT 'Gate Officer',
  `logged_by_user_id` INT NULL,
  `notes` TEXT NULL,
  `logged_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When it happened (event time)',
  `synced_at` DATETIME NULL COMMENT 'When it reached the server, for events recorded offline',
  `client_ref` VARCHAR(64) NULL UNIQUE COMMENT 'Device reference: makes a resend harmless',
  INDEX `idx_log_plate` (`plate_number`),
  INDEX `idx_log_time` (`logged_at`),
  INDEX `idx_log_action` (`action`),
  INDEX `idx_log_gate` (`gate_point`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 4. Table: security_incidents
-- Flagged vehicles, unauthorized driver stops, and custody holds.
-- ------------------------------------------------------------------------------
CREATE TABLE `security_incidents` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `case_number` VARCHAR(50) NOT NULL UNIQUE,
  `plate_number` VARCHAR(20) NOT NULL,
  `vehicle_type` VARCHAR(50) NULL,
  `owner_name` VARCHAR(100) NULL,
  `owner_role` VARCHAR(50) NULL,
  `driver_name` VARCHAR(100) NOT NULL,
  `driver_relationship` VARCHAR(100) NULL,
  `reason` VARCHAR(150) NOT NULL,
  `gate_point` VARCHAR(100) NOT NULL DEFAULT 'Gate 1 (Main Ingress)',
  `officer` VARCHAR(100) NOT NULL DEFAULT 'Gate Officer',
  `logged_by_user_id` INT NULL,
  `status` ENUM('Held', 'Resolved', 'Dismissed') NOT NULL DEFAULT 'Held',
  `notes` TEXT NULL,
  `reported_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `resolved_at` DATETIME NULL,
  `client_ref` VARCHAR(64) NULL UNIQUE COMMENT 'Device reference: makes a resend harmless',
  INDEX `idx_incident_case` (`case_number`),
  INDEX `idx_incident_plate` (`plate_number`),
  INDEX `idx_incident_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 5. Table: system_users
-- Security officers, administrators, and gate guards.
-- ------------------------------------------------------------------------------
CREATE TABLE `system_users` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `username` VARCHAR(50) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL,
  `full_name` VARCHAR(100) NOT NULL,
  `role` ENUM('admin', 'guard') NOT NULL DEFAULT 'guard',
  `badge_number` VARCHAR(50) NULL,
  `gate_assigned` VARCHAR(100) NULL DEFAULT 'Gate 1 (Main Ingress)',
  `status` ENUM('Active', 'Inactive') NOT NULL DEFAULT 'Active',
  `last_login` DATETIME NULL,
  `failed_attempts` INT NOT NULL DEFAULT 0,
  `locked_until` DATETIME NULL,
  `must_change_password` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  `synced_at` DATETIME NULL COMMENT 'Set when the pass was issued offline on a phone and synced later',
  INDEX `idx_visitor_date` (`valid_date`),
  INDEX `idx_visitor_plate` (`plate_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 10. Table: visitor_pass_items
-- Items a visitor brings in (e.g. event chairs). Checked by the guard on entry and exit.
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
-- Baseline Seed Administrator
-- Username: admin | Temporary password: Password123!  (forced change on first login)
-- ------------------------------------------------------------------------------
INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`)
VALUES ('admin', '$2y$10$rzNVx9Nx4Sq2hYQD8Fxiae4EEsK4.Zz/c1sgyEa7OW8gPSGQnvv9O', 'System Administrator', 'admin', 'NCST-SEC-01', 'All Gates', 'Active', 1);
