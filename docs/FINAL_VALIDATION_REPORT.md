# Relatorio de validacao final

Data: 2026-07-13  
Escopo: Fases 0 a 7 do plano de propriedades universais.

## Resultado

A consolidacao preserva as fases aprovadas e adiciona apenas o fluxo manual de
migracao/auditoria. Nenhum dado legado e apagado ou convertido ao carregar. O
SQL de limpeza continua opcional, separado e totalmente comentado.

## Auditoria por fase

- Fase 0: `spawnBase` gerenciado permanece deterministico; bucket e sessao sao
  limpos em saida, falha, morte, disconnect e restart; preview usa bucket
  proprio e nao interfere numa sessao de casa.
- Fase 1: policy server-side unica cobre owner, gang, job, public e admin;
  grupos, grade e duty sao obtidos do contrato real do `mz_core`.
- Fase 2: porta persistente, roles `access`/`control`, guest e separacao entre
  visibilidade e entrada foram preservados; E/G continuam contextuais.
- Fase 3: stash, wardrobe e garagem passam pelo mesmo evaluator e revalidam a
  sessao/grupo atual. Payload publico contem somente booleans/coords de UX.
- Fase 4: compra rele banco/propriedade, usa lock, CAS e historico; refund e
  `manual_review` permanecem barreiras financeiras.
- Fase 5: predio e agrupador; unidades sao independentes; lote usa preview,
  transacao/locks e nao altera owner.
- Fase 6: IPTU e residencial, paginado e idempotente; pagamento usa lock,
  conclusao atomica e prova por releitura; `tax blocked` nao altera porta.
- Fase 7: migracao e explicitamente escolhida, mostrada em preview, confirmada
  pelo code e revalidada antes da persistencia.

## Seguranca

Confirmado por inspecao estatica:

- owner, preco, tax, porta e feature permission nao sao aceitos como autoridade
  do client;
- code, source, citizenid, distancia, sessao, grupo, grade, duty e saldo sao
  revalidados nos fluxos correspondentes;
- entrada, porta, recursos, compra, IPTU e mutacoes admin possuem rate limit;
- compra/IPTU mantem locks distintos e estados persistentes bloqueantes;
- migracao recusa compra, pagamento fiscal, lote ou revisao financeira ativa;
- logs removem chaves sensiveis e registram negativas/mutacoes canonicas;
- payload publico nao inclui `accessPolicy`, owner, chaves, metadata ou tax.

## Performance e caches

- nao existe thread por propriedade nem consulta SQL por frame;
- `RuntimeHouses`/`RuntimeAccess` sao atualizados por propriedade apos mutacao;
- visibilidade client usa cache curto configuravel e recebe invalidacao;
- grupos usam cache curto e revalidacao server-side;
- contexto de porta e curto e a mutacao sempre revalida;
- IPTU usa uma passagem global horaria, paginacao e lazy checks;
- shells sao criados somente durante sessao/preview;
- migrations possuem indices para owner, categoria, parent, sale, vencimento,
  pagamentos e transacoes.

## Legado e mz_realestate

`listing_json` e `realestate_json` sao preservados. O runtime de listagem esta
aposentado (`isListingEnabled=false`) e comercio usa somente `sale_*`.

A busca no workspace encontrou a pasta `mz_realestate` e referencias em
documentacao, mas nenhum `ensure/start mz_realestate`. `mz_houses` nao chama o
resource. O telefone conserva a superficie antiga, porem o adapter
`realEstateSafeExport` retorna `realestate_retired` antes de qualquer export.

A pasta nao foi excluida. Ela so pode ser removida depois de auditar configuracao
de deploy e consumers privados fora deste workspace.

## Codigo morto

Foram removidos somente consumidores comprovadamente inexistentes no workspace:

- `CreateOrgBaseHere` e `CreateBusinessHere` do client;
- `OpenOrg`, que podia voltar a gravar o modelo aposentado;
- geradores/blocos inalcançaveis de criacao `org_base`, `gang_base`, `fac_base`,
  `business` e `government` no service.

Foi preservada a rejeicao explicita `unsupported_administrative_property_type`,
os fallbacks residenciais, wrappers publicos de owner/chaves, leitura de role
`key`, colunas JSON legadas e normalizacao de categorias antigas.

## Migrations

Revisadas: `002_admin_housing.sql`, `003_universal_access.sql`,
`004_property_doors.sql`, `005_property_commerce.sql` e
`006_property_tax.sql`. Sao incrementais, possuem rollback apenas comentado e
nao apagam colunas/dados na execucao normal. A Fase 7 nao exige migration nova.

## Validacao automatizada

`tools/validate.ps1` agora valida sintaxe Lua, ordem do manifest, contratos das
migrations 002-006, ausencia de SQL destrutivo ativo, aposentadoria do
`mz_realestate`, payload publico, protecoes do wizard e documentos finais.

O resultado exato da ultima execucao fica registrado na secao Fase 7 de
`UNIVERSAL_PROPERTIES_PLAN.md` e deve ser repetido depois do restart de runtime.

Execucao local final:

```text
OK: 41 arquivos Lua validos; migrations 002-006, manifest, payload publico,
migracao legada e aposentadoria de mz_realestate validados.
```
