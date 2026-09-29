-- ==============================================================================
-- SecurePark Migration 006: offline sync (event time, late-arrival marker, idempotency)
-- Target: EXISTING database, AFTER 005_vip_pass_class.sql. Non-destructive. Run once.
-- ==============================================================================

-- logged_at stays the time the event HAPPENED. synced_at is set only for events the mobile app
-- recorded while offline and sent later. client_ref is the device's unique reference for the
-- event: sending it twice (reply lost, retry) can never create a second row.
ALTER TABLE `gate_logs`
  ADD COLUMN `synced_at` DATETIME NULL AFTER `logged_at`,
  ADD COLUMN `client_ref` VARCHAR(64) NULL AFTER `synced_at`,
  ADD UNIQUE INDEX `uq_gate_logs_client_ref` (`client_ref`);

ALTER TABLE `security_incidents`
  ADD COLUMN `client_ref` VARCHAR(64) NULL AFTER `resolved_at`,
  ADD UNIQUE INDEX `uq_incidents_client_ref` (`client_ref`);

-- A visitor pass a guard issued on a phone without a connection: created_at is when it was issued,
-- synced_at is when it reached the server.
ALTER TABLE `visitor_passes`
  ADD COLUMN `synced_at` DATETIME NULL AFTER `created_at`;
