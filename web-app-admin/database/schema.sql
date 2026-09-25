-- ==============================================================================
-- SecurePark: Campus Gate Custody & Vehicle Administration System
-- Target Host: InfinityFree MySQL (phpMyAdmin)
-- Engine: InnoDB | Character Set: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ==============================================================================

SET FOREIGN_KEY_CHECKS = 0;
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
  `action` VARCHAR(50) NOT NULL DEFAULT 'Entry Recorded' COMMENT 'Entry Recorded, Exit Approved, Flagged & Held',
  `status` VARCHAR(50) NOT NULL DEFAULT 'Inside Campus',
  `guard_name` VARCHAR(100) NOT NULL DEFAULT 'Gate Officer',
  `notes` TEXT NULL,
  `logged_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
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
  `officer` VARCHAR(100) NOT NULL DEFAULT 'Sgt. R. Mendoza',
  `status` ENUM('Held', 'Resolved', 'Dismissed') NOT NULL DEFAULT 'Held',
  `notes` TEXT NULL,
  `reported_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `resolved_at` DATETIME NULL,
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
  `role` VARCHAR(50) NOT NULL DEFAULT 'Gate Officer',
  `badge_number` VARCHAR(50) NULL,
  `gate_assigned` VARCHAR(100) NULL DEFAULT 'Gate 1 (Main Ingress)',
  `status` ENUM('Active', 'Inactive') NOT NULL DEFAULT 'Active',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- Baseline Seed User for Administration (Change password upon deployment)
-- Default username: admin | default password: Password123!
-- ------------------------------------------------------------------------------
INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`)
VALUES ('admin', '$2y$10$wE99J516fM3X0dY36cO89.yPjOq6p2Yp1UoW7rX6Y1C2XkZ0mR3tq', 'Roberto Mendoza', 'Security Administrator', 'NCST-SEC-01', 'All Gates', 'Active');
