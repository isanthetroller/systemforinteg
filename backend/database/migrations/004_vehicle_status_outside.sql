-- ==============================================================================
-- SecurePark Migration 004: one word for "not on campus" (Outside), retire the setting
-- Target: EXISTING database, AFTER 003_system_settings.sql. Non-destructive. Run once.
-- ==============================================================================

-- A vehicle that has left campus is "Outside" (the schema default). Older builds wrote
-- "Exited" into vehicles.status, which broke status filters. gate_logs.status keeps
-- "Exited" as the label of an exit passage; only the vehicle's state is normalised.
UPDATE `vehicles` SET `status` = 'Outside' WHERE `status` = 'Exited';

-- Visitor day passes are valid all day on their date; the pass-duration setting is retired.
DELETE FROM `system_settings` WHERE `setting_key` = 'visitor_pass_validity_hours';
