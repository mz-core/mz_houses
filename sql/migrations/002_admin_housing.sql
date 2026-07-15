-- MZ Houses: evolucao nao destrutiva para o sistema administrativo.
-- Execute apenas se o prepare automatico estiver desabilitado.
ALTER TABLE `mz_houses`
  ADD COLUMN IF NOT EXISTS `metadata_json` LONGTEXT NULL AFTER `interior_json`;

CREATE INDEX IF NOT EXISTS `idx_mz_houses_enabled` ON `mz_houses` (`enabled`);

-- Rollback manual (opcional):
-- DROP INDEX `idx_mz_houses_enabled` ON `mz_houses`;
-- ALTER TABLE `mz_houses` DROP COLUMN `metadata_json`;
