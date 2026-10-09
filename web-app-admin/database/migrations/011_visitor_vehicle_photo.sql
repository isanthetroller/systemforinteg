-- 011: the photo of a visitor's vehicle, taken by the guard at entry so the exit guard can compare it.
-- Stored as a JPEG/PNG data URL (the app sends it already shrunk to roughly 100-300 KB; the server accepts up to 600 KB).
ALTER TABLE `visitor_passes` ADD COLUMN `vehicle_photo` MEDIUMTEXT NULL;
