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
- Filtrar visibilidade de pontos externos por player antes de desenhar marker/interact.
- Validar acesso da casa no server antes de abrir/guardar pela garagem.
- Delegar retirada/guarda de veiculos ao `mz_garagem`.
- Manter cache runtime para performance.
- Expor comandos debug.
- Expor exports basicos para futuras fases.

## Dependencia

No `server.cfg`, garanta:

```txt
ensure mz_core
ensure mz_org
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

### Modelo estrutural de propriedade

O `mz_houses` continua sendo o resource de casas/propriedades. Ele nao deve ser renomeado para `mz_properties` nesta fase.

Toda casa pode declarar metadados estruturais para preparar fases futuras:

```lua
category = 'residential',
subtype = 'house',
ownerType = 'player',
orgCode = nil,
businessCode = nil,
features = {
  stash = true,
  wardrobe = true,
  garage = true,
  furniture = false
}
```

Defaults globais ficam em `MZHousesConfig.PropertyDefaults`. Se uma casa antiga nao declarar esses campos, o server aplica defaults retrocompativeis:

- `category`: `residential`, `org`, `business`, `public`.
- `subtype`: `house`, `apartment`, `org_base`, `gang_base`, `business`, `motel`, `hotel`.
- `ownerType`: `player`, `org`, `business`, `none`.
- `orgCode`: reservado para fase futura de org/base.
- `businessCode`: reservado para fase futura de negocios/comercios.
- `features`: flags estruturais para `stash`, `wardrobe`, `garage`, `furniture`.

Comportamento atual:

- `ownerType = 'player'` / `category = 'residential'`: usa public, owner, chaves ou admin.
- `ownerType = 'org'` / `category = 'org'`: usa membership real da org via `mz_core`/`mz_org` ou admin.
- `business` e `none` continuam reservados para fases futuras.

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
    category = 'residential',
    subtype = 'house',
    ownerType = 'player',
    orgCode = nil,
    businessCode = nil,
    features = {
      stash = true,
      wardrobe = true,
      garage = true,
      furniture = false
    },
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

1. Override da propriedade salvo no banco em `interior_json`, por exemplo `property.interior.wardrobe`.
2. Config especifica da casa, por exemplo `MZHousesConfig.Houses.casa_teste_01.wardrobe`.
3. Default do shell em `MZHousesConfig.InteriorDefaults[house.shell].wardrobe`.
4. Se nenhum existir ou `enabled = false`, o ponto nao aparece.

Use `relative = true` para offsets internos do shell. O `mz_interiors` apenas cria/teleporta/remove a shell; o `mz_houses` gerencia os pontos de gameplay da propriedade. O menu admin salva overrides relativos ao `spawnCoords` real do interior.

Ao trocar o shell por `/mhouse_setshell` ou pelo menu, os overrides internos da propriedade sao resetados para evitar coordenadas herdadas do shell anterior. Depois disso, o imovel usa `InteriorDefaults[shell]` ou novos overrides definidos no menu.

Comandos fallback para overrides internos:

```txt
/mhouse_exit_here codigo
/mhouse_stash_here codigo
/mhouse_wardrobe_here codigo
/mhouse_internal_info codigo
/mhouse_internal_reset codigo
```

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

### Visibilidade de markers/interacts

A visibilidade do ponto no mundo e separada da permissao de entrada. O client pede ao server uma lista filtrada por player em `mz_houses:server:listVisibleHouses`; mesmo assim, entrada, bau, guarda-roupa e garagem continuam validando no server quando usados.

Config global:

```lua
MZHousesConfig.Visibility = {
  enabled = true,
  adminSeesAll = true,
  showPublicResidential = true,
  showOwnedResidentialToEveryone = false,
  showUnlistedAvailableResidential = false,
  showOrgPropertiesToNonMembers = false,
  showBusinessPropertiesToPublic = true,
  cacheSeconds = 5
}
```

Regras principais:

- Admin `group.mz_owner` ve tudo quando `adminSeesAll = true`.
- `visibility = 'hidden'` esconde de todos, exceto admin.
- `visibility = 'public'` mostra para todos, mas nao libera entrada sozinho.
- `visibility = 'restricted'` mostra apenas para quem tem relacao visual: owner/chave em residencial, membro em org/base.
- `visibility = 'auto'` aplica a regra do tipo da propriedade.
- Org/gang/fac/base aparece so para membro/admin por padrao.
- Casa residencial comprada/privada aparece so para owner/chave/admin por padrao.
- Casa sem dono e sem `listing.enabled` nao aparece automaticamente.
- `public = true` significa entrada publica, nao venda.

Estrutura preparada para placa/listagem futura:

```lua
visibility = 'auto',
listing = {
  enabled = false,
  type = 'sale',
  price = nil,
  label = 'Imovel a venda',
  sign = {
    enabled = false,
    coords = nil,
    heading = 0.0
  }
}
```

`listing.enabled = true` fica como metadata para consulta futura, mas nao implementa placa ativa, marker de venda, compra, venda, aluguel ou corretor.

### Metadata passiva para imobiliaria futura

O `mz_houses` nao implementa imobiliaria. Para um futuro resource separado, como `mz_realestate` ou `mz_imobiliaria`, cada propriedade pode declarar metadata passiva:

```lua
realestate = {
  enabled = false,
  canBeListed = true,
  defaultPrice = nil,
  listingType = 'sale'
}
```

Essa metadata nao cria placa, nao cria marker, nao vende, nao compra e nao transfere dinheiro. Ela apenas permite que um resource futuro consulte se o imovel pode ser anunciado.

Regra atual de `CanPropertyBeListed`:

- `category = 'residential'` e `ownerType = 'player'` pode ser anunciado.
- `category = 'org'` ou `ownerType = 'org'` nao pode ser anunciado por padrao.
- `enabled = false`, `status = 'archived'`, `status = 'inactive'`, `status = 'disabled'` ou `visibility = 'hidden'` bloqueiam anuncio.
- `realestate.canBeListed = false` bloqueia anuncio.
- `listing.enabled = true` e apenas metadata; nao libera entrada nem compra.

Tabelas criadas automaticamente:

- `mz_houses`
- `mz_house_keys`
- `mz_house_logs`

Campos estruturais atuais em `mz_houses`:

- `category`
- `subtype`
- `owner_type`
- `org_code`
- `business_code`
- `features_json`

No start, se `syncConfigOnStart = true`, as casas de `MZHousesConfig.Houses` sao sincronizadas para `mz_houses`.

Regras de sync:

- Se a casa nao existe no banco, ela e inserida.
- Se ja existe, atualiza campos nao sensiveis: label, category, subtype, owner_type, org_code, business_code, type, shell, entrance, garage, features_json, enabled e status.
- Owner nao e sobrescrito pelo config depois que a casa existe.
- `public` so e atualizado pelo config quando `syncPublicFromConfig = true`.
- `features_json` e atualizado pelo config/defaults, mas nesta fase nao muda sozinho os fluxos ja funcionais.

Com `syncPublicFromConfig = false`, se o config tiver `access.public = true`, mas o banco ja tiver `public = false`, o banco vence no runtime. Isso pode fazer uma casa nao aparecer/entrar para player comum ate que o estado persistido seja ajustado por fluxo admin/futuro painel.

Se `Database.enabled = false`, o resource volta ao modo config/runtime. Nesse modo owner/chaves mudados por comando nao persistem apos restart.

### Logs

O `mz_houses` usa `mz_logs` como destino principal de auditoria quando possivel. A tabela `mz_house_logs` continua existindo como legado/fallback opcional; ela nao e apagada nem migrada automaticamente.

Config:

```lua
MZHousesConfig.Logging = {
  enabled = true,
  mode = 'central', -- central | local | both | none
  localFallback = true,
  debug = false
}
```

Modos:

- `central`: grava em `mz_logs` com `scope = 'house'`; se falhar e `localFallback = true`, grava em `mz_house_logs`.
- `local`: grava somente em `mz_house_logs`.
- `both`: grava nas duas tabelas temporariamente para comparacao/migracao.
- `none`: desliga logs do resource.

Actions padronizadas no log central:

```txt
house.open
house.open.failed
house.owner.set
house.owner.clear
house.key.give
house.key.remove
house.stash.open
house.stash.open.failed
house.wardrobe.open
house.wardrobe.open.failed
house.garage.open
house.garage.open.failed
house.access.denied
house.visibility.refresh
house.realestate.can_list
```

Formato central:

- `scope = 'house'`
- `target = 'house:<codigo>'`
- `data_json.actor`, `data_json.target`, `data_json.context` e `data_json.meta` seguem o formato de `MZLogService.createDetailed`.

Consultas uteis:

```sql
SELECT id, scope, action, actor, target, LEFT(data_json, 256), created_at
FROM mz_logs
WHERE scope = 'house'
ORDER BY id DESC
LIMIT 100;
```

```sql
SELECT *
FROM mz_logs
WHERE scope = 'house'
  AND target = 'house:casa_teste_01'
ORDER BY id DESC
LIMIT 100;
```

Se estiver usando `mode = 'both'` ou fallback local:

```sql
SELECT id, house_code, action, actor_citizenid, target_citizenid, LEFT(meta_json, 256), created_at
FROM mz_house_logs
ORDER BY id DESC
LIMIT 100;
```

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

### Acesso de propriedades org/fac/gang

Uma propriedade de org usa `orgCode` como fonte de autorizacao:

```lua
base_ballas = {
  label = 'Base Ballas',
  category = 'org',
  subtype = 'gang_base',
  ownerType = 'org',
  orgCode = 'ballas',
  type = 'shell',
  shell = 'container',
  entrance = vector4(x, y, z, h),
  status = 'active',
  enabled = true,
  access = {
    public = false,
    enter = {
      requireMember = true,
      requiredCapability = nil,
      requiredGradeLevel = nil
    },
    features = {
      stash = {
        requiredCapability = 'storage.open',
        requiredGradeLevel = nil
      },
      wardrobe = {
        requiredCapability = nil,
        requiredGradeLevel = nil
      },
      garage = {
        requiredCapability = 'vehicle.basic',
        requiredGradeLevel = 2
      }
    }
  },
  features = {
    stash = true,
    wardrobe = true,
    garage = true,
    furniture = false
  }
}
```

Regra atual:

- Admin `group.mz_owner` sempre acessa.
- Se `access.public = true`, qualquer player acessa.
- Com `access.public = false`, membro ativo da org `orgCode` acessa.
- `access.enter` permite exigir capability/grade para entrar; se nao existir, qualquer membro ativo entra.
- `access.features.stash`, `access.features.wardrobe` e `access.features.garage` permitem regras por recurso.
- Se `requiredCapability` for configurado, o server exige `exports['mz_core']:CanOrg(source, orgCode, capability)`.
- Se `requiredGradeLevel` for configurado, o server exige `exports['mz_core']:HasGradeOrAbove(source, orgCode, level)`.
- Se capability e grade forem configurados juntos, os dois sao obrigatorios.
- Se a regra do recurso nao existir, basta o acesso geral a propriedade.
- Chaves (`mz_house_keys`) continuam sendo para casas residenciais/player; org base nao usa chave residencial como fallback.

O client continua enviando apenas `houseCode`. `orgCode`, capability e grade sao lidos no server a partir da propriedade/config.

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

### Comandos admin de cadastro tecnico

Esses comandos criam/editam o cadastro tecnico do imovel. Eles exigem `group.mz_owner`, validado manualmente no server. Player/corretor comum nao cria imovel.

```txt
/mhouse_create codigo Label do Imovel
/mhouse_archive codigo
/mhouse_enable codigo
/mhouse_disable codigo
/mhouse_setlabel codigo Novo Label
/mhouse_setentrance codigo
/mhouse_setshell codigo shell_test
/mhouse_setcategory codigo residential house player
/mhouse_setorg codigo orgCode
/mhouse_setpublic codigo true|false
/mhouse_setlistable codigo true|false
/mhouse_setvisibility codigo auto|public|restricted|hidden
/mhouse_garage_enable codigo true|false
/mhouse_garage_entry_here codigo
/mhouse_garage_spawn_here codigo
/mhouse_garage_store_here codigo
/mhouse_garage_slots codigo slots
/mhouse_garage_mode codigo private|shared
/mhouse_info codigo
```

Fluxo exemplo:

```txt
/mhouse_create casa_mirror_01 Casa Mirror Park 01
/mhouse_setshell casa_mirror_01 shell_test
/mhouse_setentrance casa_mirror_01
/mhouse_garage_enable casa_mirror_01 true
/mhouse_garage_entry_here casa_mirror_01
/mhouse_garage_spawn_here casa_mirror_01
/mhouse_garage_store_here casa_mirror_01
/mhouse_setlistable casa_mirror_01 true
/mhouse_info casa_mirror_01
```

`/mhouse_create` usa a posicao atual do admin como entrada e cria residencial/player por padrao: `status = draft`, `visibility = restricted`, `public = false`, sem dono e sem garagem ativa. Nao aparece para todos automaticamente.

`/mhouse_archive` e seguro para fase atual: desativa e esconde. Nao existe delete fisico nesta fase.

`public` controla entrada publica. `listable` controla somente se um futuro `mz_realestate` pode anunciar. `visibility` controla marker/interact.

### Menu admin in-game

O menu `/mhouse_admin` e a camada pratica para admins criarem/editarem imoveis no mundo. Ele usa o resource `mz_menu` como camada visual padronizada do MZ_CORE. O `mz_menu` por baixo usa `ox_lib`, mas o `mz_houses` nao chama mais `ox_lib context/inputDialog` diretamente para o menu. As callbacks server-side continuam reutilizando os mesmos services dos comandos e o server sempre revalida `group.mz_owner`.

```txt
/mhouse_admin
```

Fluxo recomendado:

```txt
/mhouse_admin
Criar imovel aqui
Editar imovel criado
Entrada / Interior -> Definir entrada aqui
Entrada / Interior -> Alterar shell pela lista do mz_interiors
Interior / Pontos Internos -> Definir saida aqui
Interior / Pontos Internos -> Definir bau aqui
Interior / Pontos Internos -> Definir armario aqui
Garagem -> Ativar garagem
Garagem -> Definir ponto de abrir aqui
Garagem -> Definir spawn aqui
Garagem -> Definir ponto de guardar aqui
Visibilidade / Listavel -> Listable true
Informacoes
```

Se `mz_menu` nao estiver iniciado, o menu avisa e os comandos acima continuam como fallback tecnico. Garanta a ordem no `server.cfg`: `ensure ox_lib`, `ensure mz_menu`, depois `ensure mz_houses`. O menu nao implementa compra, venda, corretor, comissao, NUI ou placa de venda.

Na criacao e na troca de shell, o menu consulta
`exports['mz_interiors']:GetShells()` e mostra apenas shells habilitados e
selecionaveis. O servidor tambem valida o shell antes de persistir, entao
eventos/comandos diretos nao conseguem salvar um shell desabilitado por acidente.

Shells habilitados atualmente pelo `mz_interiors`:

```txt
apartment_low
container
house_mid
motel_modern
shell_test
```

Shells streamados mas sem offset seguro ficam desabilitados no `mz_interiors`
ate serem calibrados. Se uma shell nao tiver pontos internos completos em
`MZHousesConfig.InteriorDefaults`, entre no imovel e use
`Interior / Pontos Internos` para definir saida, bau e armario como override da
propriedade.

`/mhouse_access casa_teste_01` mostra tambem o modelo estrutural:

```txt
Casa=casa_teste_01 accessMode=player category=residential subtype=house ownerType=player orgCode=nil businessCode=nil features=stash,wardrobe,garage enterAccess=residential featuresAccess=residential public=true owner=nil key_count=0 currentAccess=true reason=admin canBeListed=true listReason=listable database=true
```

Para org/base, o resumo de regras aparece compacto:

```txt
featuresAccess=stash:storage.open wardrobe:allowed garage:vehicle.basic+grade>=2
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
exports['mz_houses']:GetPropertyByCode(code)
exports['mz_houses']:GetPublicPropertyInfo(code)
exports['mz_houses']:ListProperties(filters)
exports['mz_houses']:CanPlayerAccessProperty(source, code)
exports['mz_houses']:CanPlayerManageProperty(source, code)
exports['mz_houses']:CanPropertyBeListed(code)
exports['mz_houses']:SetPropertyOwner(code, citizenid, actorSource, reason, meta)
exports['mz_houses']:ClearPropertyOwner(code, actorSource, reason, meta)
exports['mz_houses']:GivePropertyKey(code, citizenid, actorSource, reason, meta)
exports['mz_houses']:RemovePropertyKey(code, citizenid, actorSource, reason, meta)
exports['mz_houses']:SetHouseOwner(houseCode, citizenid, actorSource, reason, meta)
exports['mz_houses']:ClearHouseOwner(houseCode, actorSource, reason, meta)
exports['mz_houses']:GiveHouseKey(houseCode, citizenid, actorSource, reason, meta)
exports['mz_houses']:RemoveHouseKey(houseCode, citizenid, actorSource, reason, meta)
exports['mz_houses']:GetHouseAccess(houseCode)
exports['mz_houses']:OpenHouseStash(source, houseCode)
exports['mz_houses']:OpenHouseWardrobe(source, houseCode)
exports['mz_houses']:OpenHouseGarage(source, houseCode, action)
```

Os exports de consulta retornam versoes sanitizadas: `code`, `label`, `category`, `subtype`, `ownerType`, `type`, `shell`, `entrance`, `features`, `garage` publico, `visibility`, `status`, `public`, `listing` metadata, `realestate` metadata e `canBeListed`.

Eles nao retornam `owner_citizenid`, chaves, capabilities, grade minima, tokens de stash/garagem ou dados de sessao.

Os exports de alteracao de owner/chaves exigem `actorSource` admin com `group.mz_owner`. Chamadas sem ator retornam `actor_required`; ator sem permissao retorna `admin_required`. Para um futuro `mz_realestate`, o contrato deve evoluir com modo `trustedResource`/token interno, sem SQL direto.

## Integracao futura: mz_realestate

O `mz_houses` permanece dono da propriedade, entrada, owner/chaves, acesso e validacao server-side. O resource futuro `mz_realestate` deve ser dono de anuncios, placas, visitas, propostas, pagamentos, comissao e painel.

Exemplo seguro:

```lua
local property = exports['mz_houses']:GetPublicPropertyInfo('casa_teste_01')
local canList, reason = exports['mz_houses']:CanPropertyBeListed('casa_teste_01')
```

O futuro `mz_realestate` nao deve escrever direto nas tabelas do `mz_houses`, nao deve setar owner por SQL, nao deve criar entrada/bau/garagem e nao deve ignorar `CanEnterHouse`/`CanPlayerManageProperty`.

## Interacao

O resource tenta registrar entradas usando `mz_interact`:

- `exports['mz_interact']:AddPoint(...)`

Com `MZHousesConfig.Visibility.enabled = true`, os pontos externos sao registrados a partir da lista server-side visivel para o player. Se `mz_interact` nao estiver ativo ou falhar, usa fallback marker/texto com tecla `E` usando a mesma lista visivel.

Refresh recomendado depois de mudar owner/chaves/config:

```txt
restart mz_interact
restart mz_houses
```

O comando `/mhouse_reload` tambem dispara refresh client-side de visibilidade.

## Limitacoes atuais

- Sem venda/compra.
- Bau/stash funcional via `house_stash`.
- Guarda-roupa funcional via `mz_clothing`.
- Garagem de casa funcional via `mz_garagem`.
- Modelo estrutural de `category/subtype/ownerType/features` ja existe.
- `org_base`/`gang_base` tem acesso por membership real da org e regras finas por recurso.
- Business/comercio e apartment especial ainda nao tem regra funcional propria.
- Sem imobiliaria.
- Sem furniture/mobilia dinamica.
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

Validar em jogo o modelo estrutural com `/mhouse_access casa_teste_01` e, depois, seguir para uma fase especifica: org_base com `mz_org`, negocios/comercios ou venda/transferencia. Imobiliaria pode vir depois, sem misturar com `mz_interiors`.
