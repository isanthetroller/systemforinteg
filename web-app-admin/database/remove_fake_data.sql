-- ==============================================================================
-- SecurePark: Remove Fake / Demo / Test Data
-- Target Database: MySQL 5.7+ / MariaDB 10.3+ / phpMyAdmin (SQL tab)
-- Timezone: Asia/Manila (UTC+8)
--
-- PURPOSE:
-- Cleanses the database of all mock, synthetic, test, and demo data created
-- during testing and development (from demo_seed.php, mobile app mock data,
-- or test gate passes), leaving the system clean and ready for real operations.
--
-- This script provides two operational modes:
--   MODE A (Active Below): COMPLETE FRESH SLATE RESET
--     Wipes all transactional test records (vehicles, logs, visitor passes,
--     violations, incidents, student logins, auth tokens), resets AUTO_INCREMENT
--     counters to 1, preserves the primary 'admin' staff account, and preserves
--     system_settings.
--
--   MODE B (Commented Reference at bottom): TARGETED PURGE
--     Deletes ONLY the specific demo plates, demo student IDs, and demo guard
--     accounts without touching any genuine records you may have added.
-- ==============================================================================

SET FOREIGN_KEY_CHECKS = 0;
SET time_zone = '+08:00';

START TRANSACTION;

-- ------------------------------------------------------------------------------
-- 1. Clear Active Session Tokens
-- Remove all existing bearer tokens (forces clean login across all devices)
-- ------------------------------------------------------------------------------
DELETE FROM `auth_tokens`;

-- ------------------------------------------------------------------------------
-- 2. Clear Gate Operational & Audit History
-- Removes all simulated/test gate passages, check-ins, check-outs, and clip links
-- ------------------------------------------------------------------------------
DELETE FROM `gate_logs`;

-- ------------------------------------------------------------------------------
-- 3. Clear Security Cases & Incidents
-- Removes all test security flags, held records, and manual stops
-- ------------------------------------------------------------------------------
DELETE FROM `security_incidents`;

-- ------------------------------------------------------------------------------
-- 4. Clear Violations & 3-Strike Penalties
-- Removes all test warnings, strikes, and automated violation bans
-- ------------------------------------------------------------------------------
DELETE FROM `vehicle_violations`;

-- ------------------------------------------------------------------------------
-- 5. Clear Temporary Visitor Passes & Inventory Items
-- Removes all test visitor passes, declared equipment, and guest QR codes
-- ------------------------------------------------------------------------------
DELETE FROM `visitor_pass_items`;
DELETE FROM `visitor_passes`;

-- ------------------------------------------------------------------------------
-- 6. Clear Authorized Driver Rosters
-- Removes all secondary and alternate driver profiles linked to test vehicles
-- ------------------------------------------------------------------------------
DELETE FROM `authorized_drivers`;

-- ------------------------------------------------------------------------------
-- 7. Clear Registered Vehicle Fleet
-- Removes all test student, faculty, staff, and VIP vehicles
-- ------------------------------------------------------------------------------
DELETE FROM `vehicles`;

-- ------------------------------------------------------------------------------
-- 8. Clear Student / Owner Web Portal Logins
-- Removes all test student owner accounts generated during testing
-- ------------------------------------------------------------------------------
DELETE FROM `student_accounts`;

-- ------------------------------------------------------------------------------
-- 9. Clean Staff Accounts (Preserving Primary Administrator)
-- Removes test guards (e.g. guard.demo) while keeping the baseline admin
-- ------------------------------------------------------------------------------
DELETE FROM `system_users` WHERE `username` != 'admin';

-- Ensure the baseline administrator exists and is active
-- Default password: Password123! (forced change on first login)
INSERT INTO `system_users` (
  `id`, `username`, `password_hash`, `full_name`, `role`, 
  `badge_number`, `gate_assigned`, `status`, `must_change_password`, `created_at`
) VALUES (
  1,
  'admin',
  '$2y$10$rzNVx9Nx4Sq2hYQD8Fxiae4EEsK4.Zz/c1sgyEa7OW8gPSGQnvv9O',
  'System Administrator',
  'admin',
  'NCST-SEC-01',
  'All Gates',
  'Active',
  1,
  NOW()
)
ON DUPLICATE KEY UPDATE 
  `status` = 'Active';

-- ------------------------------------------------------------------------------
-- 10. Ensure System Settings Defaults are Intact
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

-- ------------------------------------------------------------------------------
-- 11. Reset AUTO_INCREMENT Counters to 1
-- Ensures future clean records start cleanly at ID 1
-- ------------------------------------------------------------------------------
ALTER TABLE `vehicles` AUTO_INCREMENT = 1;
ALTER TABLE `authorized_drivers` AUTO_INCREMENT = 1;
ALTER TABLE `gate_logs` AUTO_INCREMENT = 1;
ALTER TABLE `security_incidents` AUTO_INCREMENT = 1;
ALTER TABLE `visitor_passes` AUTO_INCREMENT = 1;
ALTER TABLE `visitor_pass_items` AUTO_INCREMENT = 1;
ALTER TABLE `vehicle_violations` AUTO_INCREMENT = 1;
ALTER TABLE `student_accounts` AUTO_INCREMENT = 1;
ALTER TABLE `auth_tokens` AUTO_INCREMENT = 1;
ALTER TABLE `system_users` AUTO_INCREMENT = 2;

COMMIT;

SET FOREIGN_KEY_CHECKS = 1;

-- ==============================================================================
-- VERIFICATION QUERIES (Optional: Run to confirm database is clean)
-- ==============================================================================
SELECT 'vehicles' AS `table_name`, COUNT(*) AS `row_count` FROM `vehicles`
UNION ALL
SELECT 'authorized_drivers', COUNT(*) FROM `authorized_drivers`
UNION ALL
SELECT 'gate_logs', COUNT(*) FROM `gate_logs`
UNION ALL
SELECT 'security_incidents', COUNT(*) FROM `security_incidents`
UNION ALL
SELECT 'visitor_passes', COUNT(*) FROM `visitor_passes`
UNION ALL
SELECT 'visitor_pass_items', COUNT(*) FROM `visitor_pass_items`
UNION ALL
SELECT 'vehicle_violations', COUNT(*) FROM `vehicle_violations`
UNION ALL
SELECT 'student_accounts', COUNT(*) FROM `student_accounts`
UNION ALL
SELECT 'auth_tokens', COUNT(*) FROM `auth_tokens`
UNION ALL
SELECT 'system_users', COUNT(*) FROM `system_users`;

-- Expected output after execution:
-- All counts should be 0, except `system_users` which should be 1 (admin).


/*
==============================================================================
MODE B: SELECTIVE PURGE OF KNOWN MOCK DATA ONLY (REFERENCE)
==============================================================================
If you have entered real vehicles or users and ONLY want to remove the sample
records inserted by demo_seed.php and mock test fixtures, uncomment and run
the block below INSTEAD of Mode A above:

SET FOREIGN_KEY_CHECKS = 0;
START TRANSACTION;

-- 1. Delete known demo vehicles and their cascaded drivers & violations
DELETE FROM `vehicles` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') IN (
  'NDK4821', 'ABC1234', 'XYZ7788', 'LTO5566', 'MC9012', 'PRES001', 'BAN9999',
  'NKM2024', 'WXY9012', 'NDK1234', 'VISEXPIRED', 'VISBLOCKED', 'VISUSED'
);

-- 2. Delete known demo visitor passes and their items
DELETE FROM `visitor_passes` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') IN (
  'EVT4040', 'VIS2026', 'ACC2030', 'OFF5005', 'VIS1234'
) OR `pass_code` LIKE 'VP-%-EVT1' 
  OR `pass_code` LIKE 'VP-%-DEMO' 
  OR `pass_code` LIKE 'VP-%-SCH1' 
  OR `pass_code` LIKE 'VP-%-OFFL'
  OR `pass_code` LIKE 'NCST-VIS-%';

-- 3. Delete gate logs linked to demo plates
DELETE FROM `gate_logs` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') IN (
  'NDK4821', 'ABC1234', 'XYZ7788', 'LTO5566', 'MC9012', 'PRES001', 'BAN9999',
  'EVT4040', 'VIS2026', 'ACC2030', 'OFF5005', 'NKM2024', 'WXY9012', 'NDK1234'
);

-- 4. Delete security incidents linked to demo plates
DELETE FROM `security_incidents` WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') IN (
  'NDK4821', 'ABC1234', 'XYZ7788', 'LTO5566', 'MC9012', 'PRES001', 'BAN9999',
  'EVT4040', 'VIS2026', 'ACC2030', 'OFF5005'
);

-- 5. Delete student accounts linked to demo student IDs
DELETE FROM `student_accounts` WHERE `owner_id_number` IN (
  'NCST-2024-05182', 'NCST-EMP-0311', 'NCST-2023-01447',
  'NCST-2025-00872', 'NCST-EMP-0977', 'NCST-PRES-001',
  'NCST-FAC-2021-019', 'NCST-STU-2024-001'
);

-- 6. Delete demo staff accounts
DELETE FROM `system_users` WHERE `username` IN ('guard.demo', 'guard1', 'guard2') OR `username` LIKE '%.demo%';

COMMIT;
SET FOREIGN_KEY_CHECKS = 1;
==============================================================================
*/
