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

## 2. Modelo estrutural

- [ ] `/mhouse_access casa_teste_01` mostra `category=residential`.
- [ ] `/mhouse_access casa_teste_01` mostra `subtype=house`.
- [ ] `/mhouse_access casa_teste_01` mostra `ownerType=player`.
- [ ] `/mhouse_access casa_teste_01` mostra `accessMode=player`.
- [ ] `/mhouse_access casa_teste_01` mostra `features=stash,wardrobe,garage`.
- [ ] `/mhouse_access casa_teste_01` mostra `canBeListed=true` e `listReason=listable`, se `realestate.canBeListed` nao estiver falso.
- [ ] `exports['mz_houses']:GetPublicPropertyInfo('casa_teste_01')` retorna dados sanitizados sem owner/chaves.
- [ ] `exports['mz_houses']:CanPropertyBeListed('casa_teste_01')` retorna `true, 'listable'`.
- [ ] `restart mz_houses` nao exige migracao manual para criar/garantir `category`, `subtype`, `owner_type`, `org_code`, `business_code`, `features_json`.
- [ ] Owner/chaves existentes continuam aparecendo depois do restart.
- [ ] `businessCode` e `ownerType = 'business'` continuam sem regra funcional propria.

## 3. Propriedade org/base

- [ ] Criar uma entrada de teste `base_ballas` no config com `enabled = true`, `category = 'org'`, `ownerType = 'org'`, `orgCode = 'ballas'` e coords reais.
- [ ] Configurar `access.enter = { requireMember = true }`.
- [ ] Configurar `access.features.stash = { requiredCapability = 'storage.open' }`.
- [ ] Configurar `access.features.garage = { requiredCapability = 'vehicle.basic', requiredGradeLevel = 2 }`.
- [ ] Configurar `access.features.wardrobe = {}` para liberar wardrobe a qualquer membro que ja entra.
- [ ] `restart mz_houses`.
- [ ] `/mhouse_access base_ballas` mostra `accessMode=org` e `orgCode=ballas`.
- [ ] `/mhouse_access base_ballas` mostra `featuresAccess=stash:storage.open wardrobe:allowed garage:vehicle.basic+grade>=2`.
- [ ] `/mhouse_access base_ballas` mostra `canBeListed=false` e `listReason=org_property`.
- [ ] `exports['mz_houses']:CanPropertyBeListed('base_ballas')` retorna `false, 'org_property'`.
- [ ] Player membro ativo da org `ballas` entra na base.
- [ ] Player membro ativo sem `storage.open` nao abre bau.
- [ ] Player membro ativo com `storage.open` abre bau.
- [ ] Player membro ativo abre guarda-roupa se a base tiver `wardrobe = true` e ponto configurado.
- [ ] Player membro abaixo de grade 2 nao abre garagem.
- [ ] Player membro grade >= 2 com `vehicle.basic` abre garagem.
- [ ] Player fora da org `ballas` nao entra e recebe erro de acesso negado.
- [ ] Player fora da org `ballas` nao ve marker/interact da entrada.
- [ ] Player fora da org `ballas` nao ve marker/interact da garagem externa.
- [ ] Player fora da org nao abre bau, guarda-roupa ou garagem da base.
- [ ] Admin `group.mz_owner` ve a base mesmo sem membership.
- [ ] Admin `group.mz_owner` entra mesmo sem membership.
- [ ] Admin `group.mz_owner` abre bau, wardrobe e garagem mesmo sem membership.
- [ ] Parar `mz_org` temporariamente bloqueia player normal com `org_access_unavailable`.
- [ ] Chave residencial em `mz_house_keys` nao libera acesso a org base.
- [ ] Se `requiredCapability` for configurado, somente membro com capability real passa.
- [ ] Se `requiredGradeLevel` for configurado, somente membro com grade suficiente passa.
- [ ] Remover uma regra `access.features.<recurso>` confirma que o recurso volta ao fallback de acesso geral.

## 4. Casa publica

- [ ] Configurar a casa com `access.public = true`.
- [ ] `/mhouse_list` mostra a casa.
- [ ] `/mhouse_enter casa_teste_01` entra.
- [ ] `/mhouse_exit` sai.
- [ ] Marker/interact da entrada aparece no mundo.
- [ ] Tecla `E` entra pela entrada configurada.
- [ ] Se `Database.syncPublicFromConfig = false`, confirmar no `/mhouse_access` que o `public` real do banco tambem esta `true`.

## 5. Casa privada com owner

- [ ] Configurar a casa com `access.public = false`.
- [ ] `/mhouse_access casa_teste_01` mostra estado atual.
- [ ] Sem owner/chave, entrada bloqueia.
- [ ] `/mhouse_setowner casa_teste_01 SEU_CITIZENID`.
- [ ] Owner entra pela entrada e pelo comando.
- [ ] Owner ve marker/interact da entrada.
- [ ] Player aleatorio nao ve marker/interact da entrada por padrao.
- [ ] `restart mz_houses`.
- [ ] `/mhouse_access casa_teste_01` confirma owner persistido.
- [ ] Owner ainda entra.

## 6. Casa privada com chave

- [ ] `/mhouse_clearowner casa_teste_01`.
- [ ] `/mhouse_givekey casa_teste_01 SEU_CITIZENID`.
- [ ] Player com chave entra.
- [ ] `restart mz_houses`.
- [ ] `/mhouse_keys casa_teste_01` confirma chave persistida.
- [ ] `/mhouse_removekey casa_teste_01 SEU_CITIZENID`.
- [ ] Player sem chave fica bloqueado.

## 6.1. Listing/placa futura

- [ ] Com `listing.enabled = false`, casa sem dono nao aparece automaticamente para todos.
- [ ] Com `listing.enabled = true`, o metadata aparece em `GetPublicPropertyInfo`, mas nenhum marker/placa e criado nesta fase.
- [ ] Entrada da casa continua validada por `canEnterHouse`.

## 7. Bau da casa

- [ ] Entrar como owner/chave.
- [ ] Marker do bau aparece no ponto de `InteriorDefaults` ou override da casa.
- [ ] Tecla `E` abre o inventario real.
- [ ] Colocar um item no bau.
- [ ] Fechar e abrir novamente.
- [ ] Item continua no bau.
- [ ] `restart mz_houses` e abrir de novo.
- [ ] Item continua salvo pelo inventario.
- [ ] Player sem acesso nao abre o bau.

## 8. Guarda-roupa

- [ ] Entrar como owner/chave.
- [ ] Marker do guarda-roupa aparece no ponto configurado.
- [ ] Tecla `E` abre o fluxo real do `mz_clothing`.
- [ ] Salvar/aplicar roupa pelo sistema de clothing.
- [ ] Sair/entrar novamente ou relogar conforme fluxo da base.
- [ ] Roupa/outfit permanece pelo `mz_clothing`/`mz_creator`.
- [ ] Player sem acesso nao abre o guarda-roupa.

## 9. Garagem privada da casa

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

## 10. Garagem shared e garagem normal

- [ ] Trocar temporariamente para `garage.mode = 'shared'`.
- [ ] Confirmar comportamento de pool compartilhado.
- [ ] Voltar para `private`.
- [ ] Testar uma garagem normal ja existente.
- [ ] Garagem normal lista, retira e guarda como antes.
- [ ] Anti-duplicacao por placa continua funcionando.

## 11. Debug e permissao

- [ ] `server.cfg` possui `add_ace group.mz_owner group.mz_owner allow`.
- [ ] Admin possui `add_principal identifier.license:SUA_LICENSE group.mz_owner`.
- [ ] `/mhouse_acecheck` mostra `allowed=true`.
- [ ] Player sem ACE nao usa comandos admin.
- [ ] Com `MZHousesConfig.Debug = false`, `/mhouse_testgarage` nao existe.
- [ ] Com `MZHousesConfig.Debug = true`, `/mhouse_testgarage casa_teste_01` exige admin.

## 11.1. Logs

- [ ] `MZHousesConfig.Logging.mode = 'central'`.
- [ ] Entrar em `casa_teste_01` grava `house.open` em `mz_logs`.
- [ ] Tentar entrar sem acesso grava `house.access.denied`.
- [ ] Abrir bau grava `house.stash.open`; falhas gravam `house.stash.open.failed`.
- [ ] Abrir wardrobe grava `house.wardrobe.open`; falhas gravam `house.wardrobe.open.failed`.
- [ ] Abrir garagem grava `house.garage.open`; falhas gravam `house.garage.open.failed`.
- [ ] `/mhouse_setowner`, `/mhouse_clearowner`, `/mhouse_givekey` e `/mhouse_removekey` gravam actions de owner/key.
- [ ] Conferir log central:

```sql
SELECT id, scope, action, actor, target, LEFT(data_json, 256), created_at
FROM mz_logs
WHERE scope = 'house'
ORDER BY id DESC
LIMIT 100;
```

- [ ] Se `mode = 'both'`, conferir fallback/local:

```sql
SELECT id, house_code, action, actor_citizenid, target_citizenid, LEFT(meta_json, 256), created_at
FROM mz_house_logs
ORDER BY id DESC
LIMIT 100;
```

## 11.2. Cadastro tecnico admin

- [ ] Como admin, executar `/mhouse_create casa_admin_01 Casa Admin 01`.
- [ ] `/mhouse_info casa_admin_01` mostra `status=draft`, `public=false`, `visibility=restricted`.
- [ ] `/mhouse_setentrance casa_admin_01` persiste a entrada atual.
- [ ] `/mhouse_setshell casa_admin_01 shell_test` persiste o shell.
- [ ] `/mhouse_garage_enable casa_admin_01 true`.
- [ ] `/mhouse_garage_entry_here casa_admin_01`.
- [ ] `/mhouse_garage_spawn_here casa_admin_01`.
- [ ] `/mhouse_garage_store_here casa_admin_01`.
- [ ] `/mhouse_garage_slots casa_admin_01 2`.
- [ ] `/mhouse_garage_mode casa_admin_01 private`.
- [ ] `/mhouse_setlistable casa_admin_01 true`.
- [ ] `/mhouse_access casa_admin_01` mostra `canBeListed=true`.
- [ ] Player sem admin nao consegue usar `/mhouse_create`, `/mhouse_setentrance` ou comandos admin.
- [ ] Reiniciar `mz_houses` e confirmar `/mhouse_info casa_admin_01`.
- [ ] Conferir `mz_logs` com actions `house.admin.create`, `house.admin.entrance.set`, `house.admin.garage.*`.

## 11.3. Menu admin in-game

- [ ] Como admin, executar `/mhouse_admin`.
- [ ] Criar imovel pelo menu em posicao atual.
- [ ] Buscar o imovel criado por codigo.
- [ ] Editar label, shell e entrada pelo menu.
- [ ] Ativar garagem e definir entry/spawn/store pelo menu.
- [ ] Alterar slots/mode da garagem pelo menu.
- [ ] Alterar public, visibility e listable pelo menu.
- [ ] Setar dono, limpar dono, dar/remover chave pelo menu.
- [ ] Player sem admin nao abre `/mhouse_admin`.
- [ ] Conferir `mz_logs` com actions `house.admin.*`, `house.owner.*` e `house.key.*`.

## 12. Restart final

- [ ] `restart mz_houses` nao prende player dentro do interior.
- [ ] `restart mz_garagem` nao quebra garagem normal nem garagem da casa.
- [ ] `restart mz_inventory` preserva itens do bau conforme persistencia do inventario.
- [ ] `restart mz_core` em ambiente controlado nao deixa F8/console com erro persistente.
