-- ==============================================================================
-- SecurePark Migration 008: Owner notices (student portal + e-mail)
-- Target: EXISTING database, AFTER 007_payments.sql. Non-destructive. Run once.
-- ==============================================================================

-- One row per notice sent to a vehicle owner when their vehicle is blocked at the gate or given a violation.
-- email_status: Pending (waiting to be sent), Sent, Failed (email_error says why), Skipped (no address / SMTP not configured)
CREATE TABLE IF NOT EXISTS `owner_notices` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `owner_id_number` VARCHAR(50) NOT NULL,
  `vehicle_id` INT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `kind` VARCHAR(16) NOT NULL,                         -- Violation | Blocked
  `title` VARCHAR(150) NOT NULL,
  `message` TEXT NOT NULL,
  `email_to` VARCHAR(150) NULL,
  `email_status` VARCHAR(16) NOT NULL DEFAULT 'Pending',
  `email_error` VARCHAR(255) NULL,
  `emailed_at` DATETIME NULL,
  `violation_id` INT NULL,
  `incident_id` INT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_notices_owner` (`owner_id_number`, `id`),
  INDEX `idx_notices_status` (`email_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
