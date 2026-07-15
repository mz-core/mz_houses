# Aposentadoria do mz_realestate

`mz_houses` nao depende de `mz_realestate`. O app `realestate` do `mz_phone`
esta desabilitado, seus assets nao sao carregados e o wrapper server retorna
`realestate_retired` sem chamar exports externos.

Nao apague dados automaticamente. As colunas comerciais antigas de
`mz_houses` permanecem apenas para compatibilidade de schema e nao concedem
acesso nem habilitam listagem. Registros legados de categoria org/business/
government ficam indisponiveis a jogadores e visiveis apenas para manutencao
administrativa.

Nao existe `ensure/start mz_realestate` ativo no workspace auditado. A pasta
`mz_realestate` foi preservada e nao deve ser apagada por esta fase. A exclusao
so e autorizada depois de auditar a configuracao real de deploy e confirmar que
nenhum resource privado/externo consome seus exports ou dados.

No telefone, as funcoes antigas ainda existem como wrappers de compatibilidade,
mas `realEstateSafeExport` retorna `realestate_retired`; portanto nao chama o
resource em runtime.

O arquivo `sql/optional_cleanup_realestate.sql` e somente um roteiro manual.
