-- MZ Houses Fase 4: comercio residencial autoritativo e nao destrutivo.
ALTER TABLE `mz_houses`
  ADD COLUMN IF NOT EXISTS `sale_enabled` TINYINT(1) NOT NULL DEFAULT 0 AFTER `owner_citizenid`,
  ADD COLUMN IF NOT EXISTS `sale_mode` VARCHAR(20) NOT NULL DEFAULT 'none' AFTER `sale_enabled`,
  ADD COLUMN IF NOT EXISTS `sale_price` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `sale_mode`;

CREATE INDEX IF NOT EXISTS `idx_mz_houses_sale` ON `mz_houses` (`sale_enabled`, `sale_mode`);

CREATE TABLE IF NOT EXISTS `mz_house_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `transaction_key` VARCHAR(96) NOT NULL,
  `house_code` VARCHAR(80) NOT NULL,
  `buyer_citizenid` VARCHAR(64) NOT NULL,
  `actor_citizenid` VARCHAR(64) NULL,
  `seller_type` VARCHAR(30) NOT NULL DEFAULT 'server',
  `amount` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `payment_method` VARCHAR(20) NOT NULL DEFAULT 'bank',
  `mode` VARCHAR(20) NOT NULL,
  `transaction_type` VARCHAR(30) NOT NULL DEFAULT 'purchase',
  `status` VARCHAR(30) NOT NULL DEFAULT 'initiated',
  `meta_json` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_mz_house_transactions_key` (`transaction_key`),
  KEY `idx_mz_house_transactions_house` (`house_code`, `id`),
  KEY `idx_mz_house_transactions_buyer` (`buyer_citizenid`, `id`),
  KEY `idx_mz_house_transactions_status` (`status`, `updated_at`)
);

-- Rollback manual opcional (somente apos confirmar consumidores e preservar historico):
-- DROP TABLE `mz_house_transactions`;
-- DROP INDEX `idx_mz_houses_sale` ON `mz_houses`;
-- ALTER TABLE `mz_houses` DROP COLUMN `sale_price`, DROP COLUMN `sale_mode`, DROP COLUMN `sale_enabled`;
