-- 010: Cases. Violations and security incidents are handled as one "case" with steps.
-- No existing table changes: a case is derived from vehicle_violations / security_incidents; this table holds the
-- steps staff log on top of them (attempts to reach the owner, police referral, awaiting clearance, notes, closure).
CREATE TABLE IF NOT EXISTS `case_events` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `case_key` VARCHAR(16) NOT NULL,                   -- V<violation id> or I<incident id>
  `event_type` VARCHAR(20) NOT NULL,                 -- contact | awaiting | police | note | closed
  `method` VARCHAR(30) NULL,                         -- contact: phone call, text message, in person, e-mail, other
  `result` VARCHAR(40) NULL,                         -- contact: reached owner, no answer...; closed: the outcome
  `reference` VARCHAR(100) NULL,                     -- police: blotter / report reference
  `note` TEXT NULL,
  `actor_user_id` INT NULL,
  `actor_label` VARCHAR(150) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_case_events_key` (`case_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
