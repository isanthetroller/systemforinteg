-- ==============================================================================
-- SecurePark: Campus Gate Custody & Vehicle Administration System
-- Target Host: InfinityFree MySQL (phpMyAdmin)
-- WARNING: FRESH INSTALL ONLY. This DROPS EVERY TABLE and recreates it empty (all data is lost).
--          Import it once into an empty database (phpMyAdmin > Import) and nothing else is needed:
--          it already contains everything from migrations 001 to 011 (v2 security, visitor items,
--          settings, vehicle status, VIP, offline sync, registration payments, owner notices,
--          renewals / vehicle replacement, audit log & approvals, exit releases, evidence photos, guard shifts, cases).
--          For an EXISTING database that must keep its data, run database/migrations/ instead.
-- First sign-in: admin / Password123!  (you are forced to change it immediately).
-- Timezone: all DATETIME values are Asia/Manila (UTC+8)
-- Engine: InnoDB | Character Set: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ==============================================================================

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `case_events`;
DROP TABLE IF EXISTS `guard_shifts`;
DROP TABLE IF EXISTS `evidence_photos`;
DROP TABLE IF EXISTS `exit_releases`;
DROP TABLE IF EXISTS `approval_requests`;
DROP TABLE IF EXISTS `audit_log`;
DROP TABLE IF EXISTS `owner_notices`;
DROP TABLE IF EXISTS `payments`;
DROP TABLE IF EXISTS `system_settings`;
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
  `warning_count` INT NOT NULL DEFAULT 0 COMMENT 'Retired strike counter, no longer used (kept so older code and data still fit)',
  `is_banned` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = on violation hold: cannot enter or leave until the violation is resolved',
  `pass_class` VARCHAR(16) NOT NULL DEFAULT 'Standard' COMMENT 'Standard or VIP',
  `pass_class_by` VARCHAR(150) NULL COMMENT 'Admin who set the class',
  `pass_class_at` DATETIME NULL,
  `payment_status` VARCHAR(16) NOT NULL DEFAULT 'Paid' COMMENT 'Unpaid (no QR yet) | Paid | Waived (free vehicle or VIP)',
  `fee_amount` DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Amount due while Unpaid; total paid once Paid',
  `paid_at` DATETIME NULL,
  `is_retired` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = replaced / sold: kept for history, can no longer enter',
  `retired_at` DATETIME NULL,
  `retired_reason` VARCHAR(255) NULL,
  `replaced_by_vehicle_id` INT NULL,
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
  `lookup_method` VARCHAR(12) NULL COMMENT 'qr | manual: how the guard identified the vehicle',
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
-- Violations. A pending violation puts the vehicle on hold (no entry, no exit) until an
-- admin resolves it. Only severity 'Violation' is used now; 'Warning' rows can only exist
-- in databases that were upgraded from the old strike system (they are history, not listed).
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
  `counts_as_strike` TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Retired, always 0',
  `cleared_by_violation_id` INT NULL COMMENT 'Retired, unused',
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
  `vehicle_photo` MEDIUMTEXT NULL COMMENT 'Photo of the visitor vehicle taken at entry (data URL), shown to the exit guard',
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
-- 11. Table: system_settings
-- Configurable campus policy values (read by api/settings.php).
-- ------------------------------------------------------------------------------
CREATE TABLE `system_settings` (
  `setting_key` VARCHAR(64) PRIMARY KEY,
  `setting_value` VARCHAR(255) NOT NULL,
  `description` VARCHAR(255) NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 12. Table: payments
-- Registration-fee payments: cash at the cashier or online through PayMongo.
-- Paying activates the vehicle's QR pass (the vehicle becomes 'Paid' and gets a new pass id).
-- ------------------------------------------------------------------------------
CREATE TABLE `payments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `receipt_number` VARCHAR(32) NULL UNIQUE,
  `vehicle_id` INT NOT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `owner_id_number` VARCHAR(50) NOT NULL,
  `owner_name` VARCHAR(150) NOT NULL,
  `sticker_year` VARCHAR(10) NULL,
  `purpose` VARCHAR(20) NOT NULL DEFAULT 'Registration' COMMENT 'Registration | Renewal | Fee difference | Transfer credit',
  `amount` DECIMAL(10,2) NOT NULL,
  `method` VARCHAR(16) NOT NULL COMMENT 'Cash | PayMongo',
  `status` VARCHAR(16) NOT NULL DEFAULT 'Pending' COMMENT 'Pending | Paid | Cancelled',
  `provider_session_id` VARCHAR(100) NULL,
  `provider_payment_id` VARCHAR(100) NULL,
  `provider_method` VARCHAR(32) NULL COMMENT 'gcash, paymaya, card ...',
  `cash_tendered` DECIMAL(10,2) NULL,
  `recorded_by` VARCHAR(150) NULL,
  `recorded_by_user_id` INT NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `paid_at` DATETIME NULL,
  INDEX `idx_payments_vehicle` (`vehicle_id`),
  INDEX `idx_payments_owner` (`owner_id_number`),
  INDEX `idx_payments_status` (`status`),
  INDEX `idx_payments_session` (`provider_session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 13. Table: owner_notices
-- Notices sent to a vehicle owner when the vehicle is blocked at the gate or given a violation
-- (shown in the student portal and e-mailed through SMTP when an address is on file).
-- email_status: Pending | Sent | Failed (email_error says why) | Skipped (no address / SMTP not set up)
-- ------------------------------------------------------------------------------
CREATE TABLE `owner_notices` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `owner_id_number` VARCHAR(50) NOT NULL,
  `vehicle_id` INT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `kind` VARCHAR(16) NOT NULL COMMENT 'Violation | Blocked',
  `title` VARCHAR(150) NOT NULL,
  `message` TEXT NOT NULL,
  `email_to` VARCHAR(150) NULL,
  `email_status` VARCHAR(16) NOT NULL DEFAULT 'Pending',
  `email_error` VARCHAR(255) NULL,
  `emailed_at` DATETIME NULL,
  `violation_id` INT NULL,
  `incident_id` INT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ref_key` VARCHAR(80) NULL UNIQUE COMMENT 'Reminders are sent once per key',
  INDEX `idx_notices_owner` (`owner_id_number`, `id`),
  INDEX `idx_notices_status` (`email_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 14. Table: audit_log
-- Admin action log: who did what, to which record, and why.
-- ------------------------------------------------------------------------------
CREATE TABLE `audit_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `actor_user_id` INT NULL,
  `actor_label` VARCHAR(150) NOT NULL,
  `actor_role` VARCHAR(16) NULL,
  `action` VARCHAR(60) NOT NULL,
  `entity_type` VARCHAR(30) NULL,
  `entity_id` INT NULL,
  `plate_number` VARCHAR(20) NULL,
  `detail` TEXT NULL,
  `reason` TEXT NULL,
  `ip_address` VARCHAR(45) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_audit_time` (`created_at`),
  INDEX `idx_audit_action` (`action`),
  INDEX `idx_audit_plate` (`plate_number`),
  INDEX `idx_audit_actor` (`actor_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 15. Table: approval_requests
-- Second-admin approvals (granting VIP, dismissing a violation).
-- ------------------------------------------------------------------------------
CREATE TABLE `approval_requests` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `type` VARCHAR(30) NOT NULL COMMENT 'vip_grant | violation_dismiss',
  `vehicle_id` INT NULL,
  `violation_id` INT NULL,
  `plate_number` VARCHAR(20) NULL,
  `requested_by_user_id` INT NULL,
  `requested_by_label` VARCHAR(150) NOT NULL,
  `reason` TEXT NOT NULL,
  `status` VARCHAR(12) NOT NULL DEFAULT 'Pending' COMMENT 'Pending | Approved | Rejected',
  `decided_by_user_id` INT NULL,
  `decided_by_label` VARCHAR(150) NULL,
  `decision_note` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `decided_at` DATETIME NULL,
  INDEX `idx_approvals_status` (`status`),
  INDEX `idx_approvals_vehicle` (`vehicle_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 16. Table: exit_releases
-- One-time exit for a vehicle on violation hold (admin override; expires; single use).
-- ------------------------------------------------------------------------------
CREATE TABLE `exit_releases` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `vehicle_id` INT NOT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `reason` TEXT NOT NULL,
  `released_by_user_id` INT NULL,
  `released_by_label` VARCHAR(150) NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `used_at` DATETIME NULL,
  `used_by_label` VARCHAR(150) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_releases_vehicle` (`vehicle_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 17. Table: evidence_photos
-- Photos taken by guards (vehicle / plate at the gate, evidence for a violation or incident).
-- `data` is a base64 JPEG; photos older than the retention setting are purged.
-- ------------------------------------------------------------------------------
CREATE TABLE `evidence_photos` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `kind` VARCHAR(16) NOT NULL COMMENT 'entry | exit | violation | incident',
  `gate_log_id` INT NULL,
  `violation_id` INT NULL,
  `incident_id` INT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `plate_read` VARCHAR(40) NULL COMMENT 'Plate text the phone read from the photo',
  `plate_matches` TINYINT(1) NULL COMMENT '1 = matches the pass, 0 = does not, NULL = not checked',
  `size_bytes` INT NOT NULL DEFAULT 0,
  `data` MEDIUMTEXT NULL,
  `taken_by_user_id` INT NULL,
  `taken_by_label` VARCHAR(150) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `purged_at` DATETIME NULL,
  INDEX `idx_evidence_log` (`gate_log_id`),
  INDEX `idx_evidence_violation` (`violation_id`),
  INDEX `idx_evidence_plate` (`plate_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 18. Table: guard_shifts
-- Guard duty: who is on which gate, and the handover notes for the next guard.
-- ------------------------------------------------------------------------------
CREATE TABLE `guard_shifts` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `guard_label` VARCHAR(150) NOT NULL,
  `gate` VARCHAR(100) NULL,
  `started_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at` DATETIME NULL,
  `handover_notes` TEXT NULL,
  INDEX `idx_shifts_user` (`user_id`),
  INDEX `idx_shifts_open` (`ended_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 19. Table: case_events
-- Cases (violations + security incidents): steps staff log on top of them.
-- ------------------------------------------------------------------------------
CREATE TABLE `case_events` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `case_key` VARCHAR(16) NOT NULL COMMENT 'V<violation id> or I<incident id>',
  `event_type` VARCHAR(20) NOT NULL COMMENT 'contact | awaiting | police | note | closed',
  `method` VARCHAR(30) NULL,
  `result` VARCHAR(40) NULL,
  `reference` VARCHAR(100) NULL,
  `note` TEXT NULL,
  `actor_user_id` INT NULL,
  `actor_label` VARCHAR(150) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_case_events_key` (`case_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- Default policy values (each can be changed in Admin Center > Settings)
-- ------------------------------------------------------------------------------
INSERT INTO `system_settings` (`setting_key`, `setting_value`, `description`) VALUES
  ('parking_capacity', '0', 'Vehicles the campus can hold at once (0 = not limited)'),
  ('renewal_window_days', '60', 'Passes can be renewed this many days before they expire'),
  ('expiry_warning_days', '30', 'Owners get an expiry notice this many days before the pass expires'),
  ('hold_reminder_days', '3', 'Owners are reminded every N days while a violation stays unresolved'),
  ('exit_release_minutes', '30', 'How long an admin-released exit for a vehicle on hold stays valid'),
  ('evidence_retention_days', '90', 'Guard photos are deleted after this many days');

-- ------------------------------------------------------------------------------
-- Baseline Seed Administrator
-- Username: admin | Temporary password: Password123!  (forced change on first login)
-- ------------------------------------------------------------------------------
INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`)
VALUES ('admin', '$2y$10$rzNVx9Nx4Sq2hYQD8Fxiae4EEsK4.Zz/c1sgyEa7OW8gPSGQnvv9O', 'System Administrator', 'admin', 'NCST-SEC-01', 'All Gates', 'Active', 1);
