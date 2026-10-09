-- ==============================================================================
-- SecurePark Migration 007: Registration fee payments (cashier + PayMongo)
-- Target: EXISTING database, AFTER 006_offline_sync.sql. Non-destructive. Run once.
-- ==============================================================================

-- Every vehicle that already exists keeps working: the default is 'Paid'.
-- New registrations are inserted by the API as 'Unpaid' (or 'Waived' when the fee is 0)
-- and get no usable QR pass until the fee is settled.
ALTER TABLE `vehicles`
  ADD COLUMN `payment_status` VARCHAR(16) NOT NULL DEFAULT 'Paid' AFTER `pass_class_at`,
  ADD COLUMN `fee_amount` DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER `payment_status`,
  ADD COLUMN `paid_at` DATETIME NULL AFTER `fee_amount`;

CREATE TABLE IF NOT EXISTS `payments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `receipt_number` VARCHAR(32) NULL UNIQUE,
  `vehicle_id` INT NOT NULL,
  `plate_number` VARCHAR(20) NOT NULL,
  `owner_id_number` VARCHAR(50) NOT NULL,
  `owner_name` VARCHAR(150) NOT NULL,
  `sticker_year` VARCHAR(10) NULL,
  `amount` DECIMAL(10,2) NOT NULL,
  `method` VARCHAR(16) NOT NULL,                       -- Cash | PayMongo
  `status` VARCHAR(16) NOT NULL DEFAULT 'Pending',     -- Pending | Paid | Cancelled
  `provider_session_id` VARCHAR(100) NULL,
  `provider_payment_id` VARCHAR(100) NULL,
  `provider_method` VARCHAR(32) NULL,                  -- gcash, paymaya, card ...
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
