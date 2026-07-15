-- MZ Houses Fase 2: estado persistente de porta.
ALTER TABLE `mz_houses`
  ADD COLUMN IF NOT EXISTS `door_json` LONGTEXT NULL AFTER `access_json`;

-- mz_house_keys.role ja existe. `key` e normalizado para `access` na leitura.
-- Rollback manual (somente se nenhum estado de porta precisar ser mantido):
-- ALTER TABLE `mz_houses` DROP COLUMN `door_json`;
