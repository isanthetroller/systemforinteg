-- ==============================================================================
-- SecurePark Migration 002: items carried in by visitors (e.g. event chairs)
-- Target: EXISTING database, AFTER 001_v2.sql. Non-destructive. Run ONCE.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 10. Table: visitor_pass_items
-- Items a visitor brings in (e.g. event chairs). Checked by the guard on entry and exit.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `visitor_pass_items` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `visitor_pass_id` INT NOT NULL,
  `item_name` VARCHAR(100) NOT NULL,
  `quantity` INT NOT NULL DEFAULT 1,
  `description` VARCHAR(255) NULL,
  INDEX `idx_item_pass` (`visitor_pass_id`),
  CONSTRAINT `fk_items_visitor_pass` FOREIGN KEY (`visitor_pass_id`)
    REFERENCES `visitor_passes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
