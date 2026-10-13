-- ==============================================================================
-- SecurePark: remove the Guard Shifts showcase data added by seed_guard_shifts.sql
-- Deletes only: the seed.guard.* demo accounts, their shifts, and the gate passages with client_ref seed-shift-*.
-- ==============================================================================
START TRANSACTION;
DELETE FROM `gate_logs` WHERE `client_ref` LIKE 'seed-shift-%';
DELETE FROM `guard_shifts` WHERE `user_id` IN (SELECT `id` FROM (SELECT `id` FROM `system_users` WHERE `username` LIKE 'seed.guard.%') u);
DELETE FROM `system_users` WHERE `username` LIKE 'seed.guard.%';
COMMIT;
