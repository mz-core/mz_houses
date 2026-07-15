-- MZ Houses Fase 1: politica universal de acesso, sem portas ou comercio.
ALTER TABLE `mz_houses`
  ADD COLUMN IF NOT EXISTS `access_json` LONGTEXT NULL AFTER `metadata_json`;

-- Registros existentes permanecem NULL e usam o fallback residencial/legado.
-- Rollback manual (somente se nenhuma politica da Fase 1 precisar ser mantida):
-- ALTER TABLE `mz_houses` DROP COLUMN `access_json`;
