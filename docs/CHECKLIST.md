# Checklist mz_houses MVP

## Validacao local

- [ ] `luac -p mz_houses/fxmanifest.lua`
- [ ] `luac -p mz_houses/shared/config.lua`
- [ ] `luac -p mz_houses/client/main.lua`
- [ ] `luac -p mz_houses/client/interactions.lua`
- [ ] `luac -p mz_houses/server/prepare.lua`
- [ ] `luac -p mz_houses/server/repository.lua`
- [ ] `luac -p mz_houses/server/service.lua`
- [ ] `luac -p mz_houses/server/main.lua`

## Teste no jogo

- [ ] `ensure mz_interiors`
- [ ] `ensure mz_houses`
- [ ] `restart mz_interiors`
- [ ] `restart mz_houses`
- [ ] `/mhouse_list` lista `casa_teste_01`.
- [ ] `/mhouse_here` imprime coords em formato config.
- [ ] `/mhouse_enter casa_teste_01` entra via `mz_interiors`.
- [ ] `/mhouse_stash_here` imprime coords do bau quando usado dentro da casa.
- [ ] `/mhouse_wardrobe_here` imprime coords do guarda-roupa quando usado dentro da casa.
- [ ] `/mhouse_garage_entry_here casa_teste_01` imprime coords de entrada da garagem.
- [ ] `/mhouse_garage_spawn_here casa_teste_01` imprime coords de spawn da garagem.
- [ ] `/mhouse_garage_store_here casa_teste_01` imprime coords de guardar veiculo.
- [ ] `/mhouse_exit` sai via `mz_interiors`.
- [ ] Marker ou `mz_interact` aparece na entrada configurada.
- [ ] Tecla `E` entra na casa pelo ponto.
- [ ] Com `access.public = true`, a entrada continua liberada.
- [ ] Com `access.public = false`, player sem owner/chave e bloqueado.
- [ ] `server.cfg` contem `add_ace group.mz_owner group.mz_owner allow`.
- [ ] Admin tem `add_principal identifier.license:SUA_LICENSE group.mz_owner`.
- [ ] Se necessario, admin tem `add_principal identifier.license2:SUA_LICENSE2 group.mz_owner`.
- [ ] `/mhouse_acecheck` mostra `allowed=true` para admin.
- [ ] `/mhouse_setowner casa_teste_01 CITIZENID` permite entrada ao dono.
- [ ] `/mhouse_clearowner casa_teste_01` remove acesso de dono.
- [ ] `/mhouse_givekey casa_teste_01 CITIZENID` permite entrada por chave.
- [ ] `/mhouse_removekey casa_teste_01 CITIZENID` bloqueia novamente.
- [ ] `/mhouse_keys casa_teste_01` lista owner/chaves runtime.
- [ ] `/mhouse_reload` recarrega cache do banco/config.
- [ ] Com `MZHousesConfig.Debug = false`, `/mhouse_testgarage` nao fica disponivel.
- [ ] Com `MZHousesConfig.Debug = true`, `/mhouse_testgarage casa_teste_01` exige `group.mz_owner`.
- [ ] `restart mz_houses` mantem owner salvo.
- [ ] `restart mz_houses` mantem chaves salvas.
- [ ] Marker do bau aparece dentro da casa quando `stash.enabled = true`.
- [ ] Tecla `E` no bau chama validacao server-side.
- [ ] Player sem owner/chave/admin nao consegue abrir bau.
- [ ] Bau abre a UI real do `mz_inventory` usando `house_stash`.
- [ ] Item colocado no bau continua ao fechar e abrir novamente.
- [ ] Item persiste apos `restart mz_houses`.
- [ ] Marker do guarda-roupa aparece dentro da casa quando `wardrobe.enabled = true`.
- [ ] Tecla `E` no guarda-roupa chama validacao server-side.
- [ ] Player sem owner/chave/admin nao consegue abrir guarda-roupa.
- [ ] Guarda-roupa abre a UI real do `mz_clothing`.
- [ ] Roupa/outfit continua sendo salvo pelo `mz_clothing`/`mz_creator`, nao pelo `mz_houses`.
- [ ] Marker da garagem da casa aparece quando `garage.enabled = true`.
- [ ] Player sem owner/chave/admin nao consegue abrir a garagem da casa.
- [ ] Garagem da casa abre a UI real do `mz_garagem`.
- [ ] Com `garage.mode = 'private'`, a garagem lista apenas veiculos com `garage = house:casa_teste_01`.
- [ ] Com `garage.slots = 2`, dois veiculos podem ser guardados e o terceiro bloqueia com `house_garage_full`.
- [ ] Com `garage.mode = 'shared'`, a garagem volta ao pool compartilhado.
- [ ] Retirar veiculo usa o spawn configurado na casa.
- [ ] Guardar veiculo funciona apenas perto do ponto `garage.store`.
- [ ] Fuel/health continuam persistindo pelo fluxo real da garagem.
- [ ] Garagem normal existente continua funcionando.
- [ ] Com `MZHousesConfig.Debug = false` e `MZGaragemConfig.debug = false`, console/F8 nao fica recebendo logs de descriptor, token, listagem ou debug build.
- [ ] F8 sem erro.

## Antes de producao

- [ ] Ajustar coords reais em `shared/config.lua`.
- [ ] Ativar ACE ou desativar comandos debug.
- [ ] Manter comandos admin com ACE ativo.
- [ ] Manter `MZHousesConfig.Debug = false` e `MZGaragemConfig.debug = false`, exceto durante diagnostico.
- [ ] Confirmar `mz_interiors` com stream dos shells.
- [ ] Executar `mz_houses/docs/MVP_TEST_PLAN.md`.
- [ ] Definir proxima fase: venda ou categorias de propriedade.
