# Plano de teste manual do MVP mz_houses

Use este plano antes de seguir para venda, imobiliaria, org_base, business, mobilia ou NUI nova.

## 1. Start/restart

- [ ] `ensure mz_core`
- [ ] `ensure mz_inventory`
- [ ] `ensure mz_vehicles`
- [ ] `ensure mz_garagem`
- [ ] `ensure mz_interiors`
- [ ] `ensure mz_clothing`
- [ ] `ensure mz_creator`
- [ ] `ensure mz_houses`
- [ ] `restart mz_interiors`
- [ ] `restart mz_garagem`
- [ ] `restart mz_inventory`
- [ ] `restart mz_houses`
- [ ] Console/F8 sem erro.
- [ ] Com `Debug = false`, sem spam de descriptor, token, session ou listagem.

## 2. Casa publica

- [ ] Configurar a casa com `access.public = true`.
- [ ] `/mhouse_list` mostra a casa.
- [ ] `/mhouse_enter casa_teste_01` entra.
- [ ] `/mhouse_exit` sai.
- [ ] Marker/interact da entrada aparece no mundo.
- [ ] Tecla `E` entra pela entrada configurada.

## 3. Casa privada com owner

- [ ] Configurar a casa com `access.public = false`.
- [ ] `/mhouse_access casa_teste_01` mostra estado atual.
- [ ] Sem owner/chave, entrada bloqueia.
- [ ] `/mhouse_setowner casa_teste_01 SEU_CITIZENID`.
- [ ] Owner entra pela entrada e pelo comando.
- [ ] `restart mz_houses`.
- [ ] `/mhouse_access casa_teste_01` confirma owner persistido.
- [ ] Owner ainda entra.

## 4. Casa privada com chave

- [ ] `/mhouse_clearowner casa_teste_01`.
- [ ] `/mhouse_givekey casa_teste_01 SEU_CITIZENID`.
- [ ] Player com chave entra.
- [ ] `restart mz_houses`.
- [ ] `/mhouse_keys casa_teste_01` confirma chave persistida.
- [ ] `/mhouse_removekey casa_teste_01 SEU_CITIZENID`.
- [ ] Player sem chave fica bloqueado.

## 5. Bau da casa

- [ ] Entrar como owner/chave.
- [ ] Marker do bau aparece no ponto de `InteriorDefaults` ou override da casa.
- [ ] Tecla `E` abre o inventario real.
- [ ] Colocar um item no bau.
- [ ] Fechar e abrir novamente.
- [ ] Item continua no bau.
- [ ] `restart mz_houses` e abrir de novo.
- [ ] Item continua salvo pelo inventario.
- [ ] Player sem acesso nao abre o bau.

## 6. Guarda-roupa

- [ ] Entrar como owner/chave.
- [ ] Marker do guarda-roupa aparece no ponto configurado.
- [ ] Tecla `E` abre o fluxo real do `mz_clothing`.
- [ ] Salvar/aplicar roupa pelo sistema de clothing.
- [ ] Sair/entrar novamente ou relogar conforme fluxo da base.
- [ ] Roupa/outfit permanece pelo `mz_clothing`/`mz_creator`.
- [ ] Player sem acesso nao abre o guarda-roupa.

## 7. Garagem privada da casa

- [ ] Configurar `garage.enabled = true`.
- [ ] Configurar `garage.mode = 'private'`.
- [ ] Configurar `garage.slots = 2`.
- [ ] Marker/interact da garagem aparece no ponto `garage.entry`.
- [ ] Player sem acesso nao abre a garagem.
- [ ] Owner/chave abre a garagem como "Garagem da Casa".
- [ ] Garagem privada nova aparece vazia ou apenas com veiculos vinculados a `house:casa_teste_01`.
- [ ] Guardar um veiculo no ponto `garage.store`.
- [ ] Abrir novamente e confirmar que esse veiculo aparece.
- [ ] Retirar o veiculo e confirmar spawn em `garage.spawn`.
- [ ] Guardar dois veiculos quando `slots = 2`.
- [ ] Tentar guardar terceiro veiculo e confirmar bloqueio `house_garage_full`.
- [ ] Fuel/health persistem pelo fluxo real da garagem.

## 8. Garagem shared e garagem normal

- [ ] Trocar temporariamente para `garage.mode = 'shared'`.
- [ ] Confirmar comportamento de pool compartilhado.
- [ ] Voltar para `private`.
- [ ] Testar uma garagem normal ja existente.
- [ ] Garagem normal lista, retira e guarda como antes.
- [ ] Anti-duplicacao por placa continua funcionando.

## 9. Debug e permissao

- [ ] `server.cfg` possui `add_ace group.mz_owner group.mz_owner allow`.
- [ ] Admin possui `add_principal identifier.license:SUA_LICENSE group.mz_owner`.
- [ ] `/mhouse_acecheck` mostra `allowed=true`.
- [ ] Player sem ACE nao usa comandos admin.
- [ ] Com `MZHousesConfig.Debug = false`, `/mhouse_testgarage` nao existe.
- [ ] Com `MZHousesConfig.Debug = true`, `/mhouse_testgarage casa_teste_01` exige admin.

## 10. Restart final

- [ ] `restart mz_houses` nao prende player dentro do interior.
- [ ] `restart mz_garagem` nao quebra garagem normal nem garagem da casa.
- [ ] `restart mz_inventory` preserva itens do bau conforme persistencia do inventario.
- [ ] `restart mz_core` em ambiente controlado nao deixa F8/console com erro persistente.
