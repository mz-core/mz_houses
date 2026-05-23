# mz_houses

MVP minimo de casas/imoveis para o ecossistema MZ.

Este resource usa `mz_interiors` para entrar e sair de shells. Ele possui controle basico de acesso por owner/chaves e persiste casas, donos e chaves em banco proprio do `mz_houses`. Tambem possui bau por casa via inventario real, guarda-roupa por casa via `mz_clothing` e garagem de casa via `mz_garagem`, sempre com validacao server-side. Ainda nao implementa compra, venda ou imobiliaria.

## Responsabilidade atual

- Ler casas fixas em config.
- Criar ponto de entrada no mundo.
- Entrar na casa usando `exports['mz_interiors']:EnterShell`.
- Sair usando `exports['mz_interiors']:ExitShell`.
- Validar acesso no server usando `citizenid` real do `mz_core`.
- Persistir owner/chaves no banco quando `MZHousesConfig.Database.enabled = true`.
- Criar ponto interno de bau por casa.
- Validar acesso ao bau no server antes de tentar abrir o inventario.
- Criar ponto interno de guarda-roupa por casa.
- Validar acesso ao guarda-roupa no server antes de abrir o `mz_clothing`.
- Criar ponto externo de garagem por casa.
- Validar acesso da casa no server antes de abrir/guardar pela garagem.
- Delegar retirada/guarda de veiculos ao `mz_garagem`.
- Manter cache runtime para performance.
- Expor comandos debug.
- Expor exports basicos para futuras fases.

## Dependencia

No `server.cfg`, garanta:

```txt
ensure mz_core
ensure mz_inventory
ensure mz_vehicles
ensure mz_garagem
ensure mz_interiors
ensure mz_clothing
ensure mz_creator
ensure mz_houses
```

Se usar `mz_interact`, ele pode estar ativo antes do `mz_houses`. Se nao estiver, o resource usa marker/texto fallback.

## Configuracao

Arquivo:

```txt
mz_houses/shared/config.lua
```

Exemplo:

```lua
MZHousesConfig.Houses = {
  casa_teste_01 = {
    label = 'Casa Teste 01',
    type = 'shell',
    shell = 'shell_test',
    entrance = vector4(0.0, 0.0, 72.0, 0.0),
    status = 'debug',
    enabled = true,
    access = {
      public = true,
      owner = nil,
      keys = {}
    },
    garage = {
      enabled = false,
      label = 'Garagem da Casa',
      entry = vector3(0.0, 0.0, 0.0),
      spawn = vector4(0.0, 0.0, 0.0, 0.0),
      store = vector3(0.0, 0.0, 0.0),
      storeRadius = 4.0,
      vehicleTypes = { 'car', 'bike' }
    }
  }
}
```

### Pontos internos por shell

Pontos repetidos entre casas do mesmo shell ficam em:

```lua
MZHousesConfig.InteriorDefaults = {
  shell_test = {
    stash = {
      enabled = true,
      label = 'Bau da Casa',
      coords = vector3(x, y, z),
      slots = 50,
      weight = 100000,
      relative = true
    },
    wardrobe = {
      enabled = true,
      label = 'Guarda-roupa',
      coords = vector3(x, y, z),
      relative = true
    }
  }
}
```

Prioridade:

1. Config especifica da casa, por exemplo `MZHousesConfig.Houses.casa_teste_01.wardrobe`.
2. Default do shell em `MZHousesConfig.InteriorDefaults[house.shell].wardrobe`.
3. Se nenhum existir ou `enabled = false`, o ponto nao aparece.

Use `relative = true` para offsets internos do shell. Os comandos `*_here` imprimem uma sugestao de default relativo por shell.

### Banco

O banco e controlado por:

```lua
MZHousesConfig.Database = {
  enabled = true,
  syncConfigOnStart = true,
  syncPublicFromConfig = false,
  configCanSetOwnerOnFirstInsert = true
}
```

Tabelas criadas automaticamente:

- `mz_houses`
- `mz_house_keys`
- `mz_house_logs`

No start, se `syncConfigOnStart = true`, as casas de `MZHousesConfig.Houses` sao sincronizadas para `mz_houses`.

Regras de sync:

- Se a casa nao existe no banco, ela e inserida.
- Se ja existe, atualiza campos nao sensiveis: label, type, shell, entrance, garage, enabled e status.
- Owner nao e sobrescrito pelo config depois que a casa existe.
- `public` so e atualizado pelo config quando `syncPublicFromConfig = true`.

Se `Database.enabled = false`, o resource volta ao modo config/runtime. Nesse modo owner/chaves mudados por comando nao persistem apos restart.

### Acesso

O acesso fica em:

```lua
access = {
  public = true,
  owner = nil,
  keys = {}
}
```

Campos:

- `public = true`: qualquer player pode entrar. Mantem o MVP facil de testar.
- `public = false`: exige owner, chave ou permissao admin.
- `owner = 'CITIZENID'`: dono da casa.
- `keys = { ['CITIZENID'] = true }`: moradores/chaves.

O client nunca envia o proprio citizenid. O server usa:

```lua
exports['mz_core']:GetPlayer(source)
```

e compara o `player.citizenid` com owner/chaves.

Use `/mhouse_here` no ponto desejado para imprimir uma linha pronta:

```lua
entrance = vector4(x, y, z, h)
```

### Bau por casa

Config global:

```lua
MZHousesConfig.Stash = {
  enabled = true,
  idPrefix = 'house:',
  defaultSlots = 50,
  defaultWeight = 100000,
  maxSlots = 200,
  maxWeight = 1000000,
  interactionDistance = 2.0,
  markerDistance = 10.0,
  requireAccess = true,
  allowAdminDebug = true
}
```

Config por casa:

```lua
stash = {
  enabled = true,
  label = 'Bau da Casa',
  slots = 50,
  weight = 100000,
  coords = vector3(x, y, z)
}
```

Use `/mhouse_stash_here` dentro da casa para imprimir a linha de coordenada do bau:

```lua
stash = { enabled = true, coords = vector3(x, y, z) }
```

Seguranca atual:

- O client envia apenas `houseCode`.
- O server calcula o `citizenid` real via `mz_core`.
- O server valida se a casa existe, se o bau esta ativo e se o player e owner/chave/admin.
- O server monta internamente o `stashId` no formato `house:codigo`.
- O server solicita ao `mz_core` um grant temporario para `house_stash`.
- O `mz_core` so resolve `house_stash` quando o token do grant pertence ao mesmo source.

Contrato atual do inventario:

- `mz_inventory` expoe `OpenTargetView(targetDescriptor)` no client.
- `mz_core` resolve containers de player, veiculo, drop, stash pessoal e stash de org.
- `mz_core` tambem resolve `house_stash` com token temporario emitido por `CreateHouseStashAccessGrant`.

O `mz_houses` valida o acesso e entrega ao client apenas o descriptor autorizado. O client usa esse descriptor em `exports['mz_inventory']:OpenTargetView(...)`, e os itens ficam salvos pelo inventario real em `mz_inventory_items` com `owner_type = 'house'`, `owner_id = 'house:codigo'` e `inventory_type = 'stash'`.

### Guarda-roupa por casa

Config global:

```lua
MZHousesConfig.Wardrobe = {
  enabled = true,
  resource = 'mz_clothing',
  shopId = 'clothing_1',
  interactionDistance = 2.0,
  markerDistance = 10.0,
  requireAccess = true,
  allowAdminDebug = true
}
```

Config por shell:

```lua
MZHousesConfig.InteriorDefaults.shell_test.wardrobe = {
  enabled = true,
  label = 'Guarda-roupa',
  coords = vector3(x, y, z),
  relative = true
}
```

Use `/mhouse_wardrobe_here` dentro da casa para imprimir uma sugestao de coordenada. O `mz_houses` valida acesso no server e dispara o fluxo real do `mz_clothing`; roupas/outfits continuam sendo salvos pelo `mz_clothing`/`mz_creator`, nao pelo `mz_houses`.

### Garagem da casa

Config global:

```lua
MZHousesConfig.Garage = {
  enabled = true,
  interactionDistance = 2.0,
  markerDistance = 15.0,
  storeInteractionDistance = 4.0,
  storeMarkerDistance = 18.0,
  storeRadius = 4.0,
  requireAccess = true,
  allowAdminDebug = true
}
```

Config por casa:

```lua
garage = {
  enabled = true,
  label = 'Garagem da Casa',
  mode = 'private',
  slots = 2,
  entry = vector3(x, y, z),
  spawn = vector4(x, y, z, h),
  store = vector3(x, y, z),
  storeRadius = 4.0,
  vehicleTypes = { 'car', 'bike' }
}
```

Comandos de coordenada:

```txt
/mhouse_garage_entry_here casa_teste_01
/mhouse_garage_spawn_here casa_teste_01
/mhouse_garage_store_here casa_teste_01
```

Seguranca atual:

- O client envia apenas `houseCode` e acao (`open`/`store`).
- O server do `mz_houses` valida owner/chave/admin.
- O server monta `entry`, `spawn`, `store` e `storeRadius` a partir do config.
- O `mz_houses` chama `exports['mz_garagem']:OpenHouseGarage(...)`.
- O `mz_garagem` cria uma sessao temporaria para aquele source e executa o fluxo real de garagem.
- `mode = 'private'` usa `garageId = house:<codigo>` e lista apenas veiculos guardados nessa garagem.
- `mode = 'shared'` mantem o comportamento de pool compartilhado da garagem.
- `slots` limita quantos veiculos podem ficar guardados na garagem privada da casa.
- Veiculos, fuel, health, spawn e store continuam sendo responsabilidade de `mz_garagem`/`mz_core`/`mz_vehicles`.

## Comandos debug

```txt
/mhouse_list
/mhouse_enter casa_teste_01
/mhouse_exit
/mhouse_here
/mhouse_stash_here
/mhouse_wardrobe_here
/mhouse_garage_entry_here casa_teste_01
/mhouse_garage_spawn_here casa_teste_01
/mhouse_garage_store_here casa_teste_01
```

Por padrao, comandos debug nao exigem ACE. Em producao, ajuste:

```lua
MZHousesConfig.Commands.requireAce = true
MZHousesConfig.Commands.ace = 'group.mz_owner'
```

O comando temporario de diagnostico da garagem da casa, `/mhouse_testgarage`, so e registrado quando `MZHousesConfig.Debug = true` e ainda exige permissao admin `group.mz_owner`. Ele existe apenas para validar a integracao `mz_houses` -> `mz_garagem`.

## Comandos admin/runtime

Com banco ativo, estes comandos persistem em `mz_houses`/`mz_house_keys` e atualizam o cache runtime. Com banco desativado, alteram apenas memoria runtime.

```txt
/mhouse_setowner casa_teste_01 CITIZENID
/mhouse_clearowner casa_teste_01
/mhouse_givekey casa_teste_01 CITIZENID
/mhouse_removekey casa_teste_01 CITIZENID
/mhouse_keys casa_teste_01
/mhouse_access casa_teste_01
/mhouse_acecheck
/mhouse_reload
```

Por padrao eles exigem:

```lua
MZHousesConfig.Admin.requireAce = true
MZHousesConfig.Admin.ace = 'group.mz_owner'
```

### Permissao no server.cfg

`group.mz_owner` e a permissao administrativa do `mz_houses`. Quem tiver essa ACE pode usar os comandos admin/runtime.

Exemplo:

```txt
# Permissao administrativa do mz_houses
add_ace group.mz_owner group.mz_owner allow
add_principal identifier.license:SUA_LICENSE_AQUI group.mz_owner
```

Se sua base usa `license2`, tambem pode usar:

```txt
add_principal identifier.license2:SUA_LICENSE2_AQUI group.mz_owner
```

Os comandos do `mz_houses` sao registrados com `restricted = false`. Nao precisa liberar `command.mhouse_setowner`, `command.mhouse_givekey` ou qualquer outra ACE de comando. O script executa o comando e valida manualmente `group.mz_owner`.

Comandos de entrada/saida e interacao usam a regra da casa (`public`, owner ou chave), nao a ACE admin.

Depois reinicie o servidor ou garanta que as permissoes foram carregadas antes de testar:

```txt
/mhouse_acecheck
/mhouse_access casa_teste_01
/mhouse_setowner casa_teste_01 CITIZENID
```

## Exports client-side

```lua
exports['mz_houses']:EnterHouse(houseCode)
exports['mz_houses']:ExitHouse()
exports['mz_houses']:GetCurrentHouse()
exports['mz_houses']:GetHouses()
exports['mz_houses']:IsInsideHouse()
exports['mz_houses']:OpenHouseStash(houseCode)
exports['mz_houses']:OpenHouseWardrobe(houseCode)
exports['mz_houses']:OpenHouseGarage(houseCode, action)
```

## Exports server-side

```lua
exports['mz_houses']:CanEnterHouse(source, houseCode)
exports['mz_houses']:SetHouseOwner(houseCode, citizenid)
exports['mz_houses']:ClearHouseOwner(houseCode)
exports['mz_houses']:GiveHouseKey(houseCode, citizenid)
exports['mz_houses']:RemoveHouseKey(houseCode, citizenid)
exports['mz_houses']:GetHouseAccess(houseCode)
exports['mz_houses']:OpenHouseStash(source, houseCode)
exports['mz_houses']:OpenHouseWardrobe(source, houseCode)
exports['mz_houses']:OpenHouseGarage(source, houseCode, action)
```

## Interacao

O resource tenta registrar entradas usando `mz_interact`:

- `exports['mz_interact']:AddPoint(...)`

Se `mz_interact` nao estiver ativo ou falhar, usa fallback marker/texto com tecla `E`.

## Limitacoes atuais

- Sem venda/compra.
- Bau/stash funcional via `house_stash`.
- Guarda-roupa funcional via `mz_clothing`.
- Garagem de casa funcional via `mz_garagem`.
- Sem imobiliaria.
- Sem NUI.

## Teste rapido

```txt
restart mz_interiors
restart mz_houses

/mhouse_list
/mhouse_here
/mhouse_enter casa_teste_01
/mhouse_stash_here
/mhouse_wardrobe_here
/mhouse_garage_entry_here casa_teste_01
/mhouse_garage_spawn_here casa_teste_01
/mhouse_garage_store_here casa_teste_01
/mhouse_exit
```

Depois ajuste a `entrance` da `casa_teste_01`, reinicie `mz_houses`, aproxime da entrada e pressione `E`.

Para validar o MVP inteiro antes de novas features, use tambem:

```txt
mz_houses/docs/MVP_TEST_PLAN.md
```

### Teste de acesso

Com `public = true`, a casa deve entrar normalmente.

Para testar bloqueio, altere a casa para:

```lua
access = {
  public = false,
  owner = nil,
  keys = {}
}
```

Depois:

```txt
restart mz_houses
/mhouse_enter casa_teste_01
```

Deve bloquear. Em seguida, use comandos admin com seu citizenid:

```txt
/mhouse_setowner casa_teste_01 SEU_CITIZENID
/mhouse_enter casa_teste_01
/mhouse_exit
/mhouse_access casa_teste_01
restart mz_houses
/mhouse_access casa_teste_01
/mhouse_clearowner casa_teste_01
/mhouse_givekey casa_teste_01 SEU_CITIZENID
/mhouse_enter casa_teste_01
```

### Teste do bau

```txt
ensure mz_interiors
ensure mz_inventory
ensure mz_houses

restart mz_inventory
restart mz_houses

/mhouse_enter casa_teste_01
/mhouse_stash_here
```

Copie a coordenada gerada para `shared/config.lua`, reinicie `mz_houses` e pressione `E` no marker do bau. O inventario deve abrir usando o container `house_stash`; coloque um item, feche e abra de novo para confirmar persistencia.

### Teste do guarda-roupa

```txt
ensure mz_clothing
ensure mz_creator
ensure mz_houses

restart mz_clothing
restart mz_creator
restart mz_houses

/mhouse_enter casa_teste_01
/mhouse_wardrobe_here
```

Copie a coordenada relativa gerada para `MZHousesConfig.InteriorDefaults.shell_test.wardrobe`, reinicie `mz_houses` e pressione `E` no marker do guarda-roupa. A UI do `mz_clothing` deve abrir sem o `mz_houses` salvar roupa.

### Teste da garagem

```txt
ensure mz_core
ensure mz_vehicles
ensure mz_garagem
ensure mz_houses

restart mz_garagem
restart mz_houses

/mhouse_garage_entry_here casa_teste_01
/mhouse_garage_spawn_here casa_teste_01
/mhouse_garage_store_here casa_teste_01
```

Cole as coordenadas em `garage` da casa, deixe `enabled = true`, reinicie `mz_houses` e use o ponto externo da garagem. Como owner/chave/admin, a garagem deve abrir pelo `mz_garagem`; ao guardar, o veiculo precisa estar no ponto `store`.

## Proximo passo recomendado

Seguir para venda/transferencia ou modelo de categorias (`residential`, `org`, `business`). Imobiliaria pode vir depois, sem misturar com `mz_interiors`.
