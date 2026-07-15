-- MZ Houses Fase 6: IPTU residencial autoritativo, incremental e nao destrutivo.
ALTER TABLE `mz_houses`
  ADD COLUMN IF NOT EXISTS `tax_enabled` TINYINT(1) NOT NULL DEFAULT 0 AFTER `sale_price`,
  ADD COLUMN IF NOT EXISTS `tax_amount` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `tax_enabled`,
  ADD COLUMN IF NOT EXISTS `tax_interval_days` INT UNSIGNED NOT NULL DEFAULT 7 AFTER `tax_amount`,
  ADD COLUMN IF NOT EXISTS `tax_grace_period_days` INT UNSIGNED NOT NULL DEFAULT 3 AFTER `tax_interval_days`,
  ADD COLUMN IF NOT EXISTS `tax_due_at` DATETIME NULL AFTER `tax_grace_period_days`,
  ADD COLUMN IF NOT EXISTS `tax_grace_until` DATETIME NULL AFTER `tax_due_at`,
  ADD COLUMN IF NOT EXISTS `tax_status` VARCHAR(20) NOT NULL DEFAULT 'disabled' AFTER `tax_grace_until`,
  ADD COLUMN IF NOT EXISTS `tax_last_paid_at` DATETIME NULL AFTER `tax_status`;

CREATE INDEX IF NOT EXISTS `idx_mz_houses_tax_due`
  ON `mz_houses` (`tax_enabled`, `tax_status`, `tax_due_at`);

CREATE INDEX IF NOT EXISTS `idx_mz_houses_tax_owner`
  ON `mz_houses` (`owner_citizenid`, `tax_enabled`);

CREATE TABLE IF NOT EXISTS `mz_house_tax_payments` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `transaction_key` VARCHAR(96) NOT NULL,
  `house_code` VARCHAR(80) NOT NULL,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `amount` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `payment_method` VARCHAR(20) NOT NULL DEFAULT 'bank',
  `period_start` DATETIME NULL,
  `period_end` DATETIME NULL,
  `due_at` DATETIME NOT NULL,
  `paid_at` DATETIME NULL,
  `status` VARCHAR(30) NOT NULL DEFAULT 'initiated',
  `transaction_reference` VARCHAR(96) NOT NULL,
  `metadata_json` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_mz_house_tax_payments_key` (`transaction_key`),
  UNIQUE KEY `uq_mz_house_tax_payments_reference` (`transaction_reference`),
  KEY `idx_mz_house_tax_payments_house` (`house_code`, `id`),
  KEY `idx_mz_house_tax_payments_owner` (`owner_citizenid`, `id`),
  KEY `idx_mz_house_tax_payments_status` (`status`, `updated_at`),
  KEY `idx_mz_house_tax_payments_due` (`due_at`, `id`)
);

UPDATE `mz_house_tax_payments`
SET `transaction_reference` = `transaction_key`
WHERE `transaction_reference` IS NULL OR `transaction_reference` = '';

ALTER TABLE `mz_house_tax_payments`
  MODIFY COLUMN `transaction_reference` VARCHAR(96) NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS `uq_mz_house_tax_payments_reference`
  ON `mz_house_tax_payments` (`transaction_reference`);

CREATE INDEX IF NOT EXISTS `idx_mz_house_tax_payments_due`
  ON `mz_house_tax_payments` (`due_at`, `id`);

-- Rollback manual opcional. Preserve o historico antes de executar:
-- DROP TABLE `mz_house_tax_payments`;
-- DROP INDEX `idx_mz_houses_tax_owner` ON `mz_houses`;
-- DROP INDEX `idx_mz_houses_tax_due` ON `mz_houses`;
-- ALTER TABLE `mz_houses`
--   DROP COLUMN `tax_last_paid_at`, DROP COLUMN `tax_status`,
--   DROP COLUMN `tax_grace_until`, DROP COLUMN `tax_due_at`,
--   DROP COLUMN `tax_grace_period_days`, DROP COLUMN `tax_interval_days`,
--   DROP COLUMN `tax_amount`, DROP COLUMN `tax_enabled`;
