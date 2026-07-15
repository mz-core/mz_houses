-- OPCIONAL E DESTRUTIVO. Nao e executado pelo resource.
-- Faca backup e confirme que o legado nao sera mais usado.
-- Revise os nomes reais no seu banco antes de descomentar.
--
-- Auditoria segura antes de qualquer decisao:
SELECT
  COUNT(*) AS properties_total,
  SUM(CASE WHEN listing_json IS NOT NULL AND TRIM(listing_json) NOT IN ('', '{}', 'null') THEN 1 ELSE 0 END) AS listing_json_preserved,
  SUM(CASE WHEN realestate_json IS NOT NULL AND TRIM(realestate_json) NOT IN ('', '{}', 'null') THEN 1 ELSE 0 END) AS realestate_json_preserved
FROM mz_houses;

-- Os comandos destrutivos permanecem deliberadamente comentados.
-- DROP TABLE IF EXISTS mz_realestate_listing_photos;
-- DROP TABLE IF EXISTS mz_realestate_listings;
-- DROP TABLE IF EXISTS mz_realestate_agencies;
-- As colunas listing_json/realestate_json de mz_houses devem ser preservadas
-- durante a migracao; remova-as somente numa manutencao futura planejada.
