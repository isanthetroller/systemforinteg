-- ==============================================================================
-- SecurePark Migration 005: VIP pass class (permanent vehicles)
-- Target: EXISTING database, AFTER 004_vehicle_status_outside.sql. Non-destructive. Run once.
-- ==============================================================================

-- A vehicle is Standard unless an administrator marks it VIP (school president, guests of
-- honour with a permanent pass). The class lives in the database, not in the signed QR, so it
-- can be granted or withdrawn without reissuing the pass.
ALTER TABLE `vehicles`
  ADD COLUMN `pass_class` VARCHAR(16) NOT NULL DEFAULT 'Standard' AFTER `is_banned`,
  ADD COLUMN `pass_class_by` VARCHAR(150) NULL AFTER `pass_class`,
  ADD COLUMN `pass_class_at` DATETIME NULL AFTER `pass_class_by`;
