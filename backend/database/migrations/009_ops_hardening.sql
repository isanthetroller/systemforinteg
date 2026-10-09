-- ==============================================================================
-- SecurePark Migration 009: pass renewal, vehicle replacement, audit log & approvals,
-- exit releases, evidence photos, guard shifts, parking capacity settings
-- Target: EXISTING database, AFTER 008_owner_notices.sql. Non-destructive. Run once.
-- (A fresh install does not need this: database/schema.sql already contains it.)
-- ==============================================================================

-- Vehicles: a replaced / sold vehicle is retired (kept for history, can no longer enter)
ALTER TABLE `vehicles`
  ADD COLUMN `is_retired` TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN `retired_at` DATETIME NULL,
  ADD COLUMN `retired_reason` VARCHAR(255) NULL,
  ADD COLUMN `replaced_by_vehicle_id` INT NULL;

-- Payments: what the payment is for (Registration | Renewal | Fee difference | Transfer credit)
ALTER TABLE `payments`
  ADD COLUMN `purpose` VARCHAR(20) NOT NULL DEFAULT 'Registration' AFTER `sticker_year`;

-- Notices: reminders are sent once per key (e.g. one 30-day expiry warning per pass)
ALTER TABLE `owner_notices`
  ADD COLUMN `ref_key` VARCHAR(80) NULL,
  ADD UNIQUE INDEX `uq_notices_ref_key` (`ref_key`);

-- Gate logs: how the guard identified the vehicle (qr | manual) for the supervisor's guard review
ALTER TABLE `gate_logs`
  ADD COLUMN `lookup_method` VARCHAR(12) NULL;

-- Admin action log: who did what, to which record, and why
CREATE TABLE IF NOT EXISTS `audit_log` (
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

-- Second-admin approvals (granting VIP, dismissing a violation)
CREATE TABLE IF NOT EXISTS `approval_requests` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `type` VARCHAR(30) NOT NULL,                       -- vip_grant | violation_dismiss
  `vehicle_id` INT NULL,
  `violation_id` INT NULL,
  `plate_number` VARCHAR(20) NULL,
  `requested_by_user_id` INT NULL,
  `requested_by_label` VARCHAR(150) NOT NULL,
  `reason` TEXT NOT NULL,
  `status` VARCHAR(12) NOT NULL DEFAULT 'Pending',   -- Pending | Approved | Rejected
  `decided_by_user_id` INT NULL,
  `decided_by_label` VARCHAR(150) NULL,
  `decision_note` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `decided_at` DATETIME NULL,
  INDEX `idx_approvals_status` (`status`),
  INDEX `idx_approvals_vehicle` (`vehicle_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One-time exit for a vehicle that is on violation hold (admin override, expires, single use)
CREATE TABLE IF NOT EXISTS `exit_releases` (
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

-- Photos taken by guards (vehicle / plate at the gate, evidence for a violation or incident).
-- `data` is a base64 JPEG; photos older than the retention setting are purged (purged_at set, data emptied).
CREATE TABLE IF NOT EXISTS `evidence_photos` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `kind` VARCHAR(16) NOT NULL,                       -- entry | exit | violation | incident
  `gate_log_id` INT NULL,
  `violation_id` INT NULL,
  `incident_id` INT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `plate_read` VARCHAR(40) NULL,                     -- plate text the phone read from the photo
  `plate_matches` TINYINT(1) NULL,                   -- 1 = matches the pass, 0 = does not, NULL = not checked
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

-- Guard duty: who is on which gate, and the handover notes for the next guard
CREATE TABLE IF NOT EXISTS `guard_shifts` (
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

-- Default policy values (each can be changed in Admin Center > Settings)
INSERT IGNORE INTO `system_settings` (`setting_key`, `setting_value`, `description`) VALUES
  ('parking_capacity', '0', 'Vehicles the campus can hold at once (0 = not limited)'),
  ('renewal_window_days', '60', 'Passes can be renewed this many days before they expire'),
  ('expiry_warning_days', '30', 'Owners get an expiry notice this many days before the pass expires'),
  ('hold_reminder_days', '3', 'Owners are reminded every N days while a violation stays unresolved'),
  ('exit_release_minutes', '30', 'How long an admin-released exit for a vehicle on hold stays valid'),
  ('evidence_retention_days', '90', 'Guard photos are deleted after this many days');
