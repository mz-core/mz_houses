# Plano Mestre — Propriedades Universais do `mz_houses`

> Documento oficial de arquitetura e execução por fases.
>
> **Workspace alvo:** `D:\git-hub\repo_oficial`
>
> **Resources principais:**
>
> - `D:\git-hub\repo_oficial\mz_houses`
> - `D:\git-hub\repo_oficial\mz_interiors`
>
> **Versão do plano:** 1.0  
> **Data:** 2026-07-11  
> **Status geral:** Fases 0 a 7 concluídas e aprovadas em runtime; Fase 8 implementada e aguardando validação runtime.

---

## 1. Como usar este documento no VS Code/Codex

Este arquivo é a fonte de verdade para a evolução do sistema. Cada execução no
VS Code deve implementar **uma única fase**, testar, documentar o resultado e
parar antes da fase seguinte.

Prompt-base para toda fase:

```text
Leia primeiro e siga integralmente:
D:\git-hub\repo_oficial\mz_houses\docs\UNIVERSAL_PROPERTIES_PLAN.md

Inspecione os arquivos reais do workspace. Não use Git, commits, branches,
histórico ou versões antigas como fonte principal. Ignore as pastas .git.

Implemente somente a Fase X deste documento. Não avance para outras fases.
Preserve compatibilidade, dados existentes, exports públicos e comportamento
já validado em runtime. Atualize a seção “Controle de execução” e registre as
decisões reais encontradas. Execute os validadores disponíveis e entregue um
relatório exato de arquivos, migrations, testes e pendências runtime.
```

Regras obrigatórias para o agente:

1. Inspecionar a estrutura real antes de editar.
2. Não inventar exports do `mz_core`, `mz_org`, `mz_inventory`, `mz_clothing`,
   `mz_garagem`, `mz_menu` ou qualquer outro resource.
3. Criar adapters finos quando contratos externos precisarem variar.
4. Servidor é autoridade sobre acesso, porta, dinheiro, owner, chaves e IPTU.
5. Nunca confiar em preço, grade, grupo, citizenid ou permissão enviados pelo
   client.
6. Não reutilizar `listing_json` ou `realestate_json` como base do novo
   comércio. Esses campos são legado aposentado.
7. Não apagar colunas/tabelas antigas automaticamente.
8. Toda migration deve ser incremental, idempotente e possuir roteiro de
   rollback manual.
9. Não deixar parte de uma fase incompleta escondida atrás de código morto.
10. Não avançar de fase sem o checklist runtime da fase anterior.

---

## 2. Visão final do produto

O `mz_houses` deixará de ser apenas um sistema residencial e será um
**gerenciador universal de propriedades e interiores**, mantendo o nome do
resource para compatibilidade.

Ele deverá suportar, pela mesma arquitetura:

- casas residenciais;
- apartamentos e prédios com entrada compartilhada;
- sedes de gang específica;
- sedes de job específico;
- interiores públicos e abertos;
- interiores administrativos;
- owner e chaves individuais;
- porta trancada, destrancada ou interditada;
- permissões diferentes para entrada, baú, guarda-roupa e garagem;
- preço definido na criação residencial;
- compra direta ou venda administrada;
- preço padrão para unidades de apartamento;
- IPTU por casa/unidade residencial;
- shells temporários providos pelo `mz_interiors`;
- isolamento por routing bucket controlado pelo `mz_houses`.

O projeto **não volta a ser uma imobiliária**. Permanecem fora do sistema:

- corretor;
- agência;
- comissão;
- banco empresarial;
- anúncio em telefone;
- placa comercial;
- galeria de anúncio;
- reserva de imóvel;
- financiamento;
- leilão;
- dependência de `mz_realestate`.

---

## 3. Diagnóstico do código recebido

### 3.1 O que já funciona

O estado atual já possui:

- tabelas `mz_houses`, `mz_house_keys` e `mz_house_logs`;
- criação administrativa de casa, prédio e unidade;
- owner por `citizenid`;
- chaves persistentes;
- shell, entrada, spawn interno, saída, stash e wardrobe;
- garagem integrada ao contrato existente;
- routing bucket por propriedade;
- sessão de entrada pendente e confirmação client/server;
- rollback quando o shell falha;
- painel `/mzhouses`;
- preview administrativo isolado;
- soft delete com `archived`;
- cache e atualização sem restart;
- logs administrativos;
- `public` usado como visibilidade, não como autorização;
- `entrySpawn` padrão ou personalizado;
- conversão de pontos internos baseada na origem lógica do shell;
- aposentadoria funcional do `mz_realestate`.

### 3.2 Auditoria do código dormente

A Fase 7 pesquisou consumidores reais, exports, eventos e callbacks no workspace.
As funções client `CreateOrgBaseHere`, `CreateBusinessHere` e `OpenOrg`, além dos
geradores/blocos server inalcançáveis de criação `org_base`, `gang_base`,
`fac_base`, `business` e `government`, não possuíam consumidor e foram removidos.

A rejeição explícita dos kinds antigos foi preservada:

```lua
if kind == 'org_base' or kind == 'gang_base' or kind == 'fac_base'
  or kind == 'business' or kind == 'government' then
  return false, 'unsupported_administrative_property_type'
end
```

Além disso, `CanSeeHouse()` rejeita categorias antigas de org/business/governo
como `legacy_property_type_retired`.

`CanSeeHouse()` continua bloqueando registros antigos sem política. A conversão
agora ocorre exclusivamente pelo wizard manual da Fase 7, com template,
preview, confirmação e persistência de `access_json`/`door_json`.

### 3.3 Limitações atuais confirmadas

1. Não existe `access_json` persistente.
2. Regras antigas de org dependem principalmente de config e não de registros
   administrativos no banco.
3. `mz_house_keys.role` existe no banco, porém o runtime reduz chaves para
   booleano e perde o papel da chave.
4. Não existe estado persistente de porta.
5. Não existe permissão separada para controlar a porta.
6. Não existe acesso direto por job.
7. Gang/job não podem ser selecionados a partir de uma lista real no menu.
8. Interiores públicos não possuem template próprio.
9. O preço é apenas `metadata.administrativePrice` e não movimenta dinheiro.
10. Não existem `sale_enabled`, `sale_mode` ou `sale_price` autoritativos.
11. Não existe compra pelo jogador.
12. Não existe IPTU.
13. Prédios criam unidades em lote, mas não recebem preço padrão de unidade.
14. A criação em lote pode ficar parcialmente concluída se uma unidade falhar.
15. `listing_json` e `realestate_json` continuam no schema apenas por legado.

### 3.4 Prerequisito crítico encontrado no `mz_interiors`

`mz_houses` cria um bucket compartilhado por propriedade, mas a função atual
`getSpawnBase()` em `mz_interiors/client/shells.lua` acrescenta `PlayerId`,
`SpawnSpacing` e jitter ao `spawnBase`:

```lua
local slot = (PlayerId() % 16)
local jitter = (GetGameTimer() % 7) * 2.0
return vector3(configured.x + (slot * spacing), configured.y + jitter, configured.z)
```

Isso pode fazer duas pessoas da mesma casa criarem o shell e teleportarem para
origens internas diferentes, mesmo estando no mesmo routing bucket. Antes de
expandir acesso para gangs, jobs e locais públicos, essa origem deve ser
validada e tornada determinística para sessões gerenciadas pelo `mz_houses`.

Esse ajuste pertence à **Fase 0** e é bloqueador para locais multiusuário.

---

## 4. Decisões arquiteturais aprovadas

### 4.1 Tipo físico não define acesso

Separar os conceitos:

```text
Tipo físico / subtipo     ≠     Política de acesso
```

Exemplos:

```text
Casa normal:
subtype = house
access.mode = owner

Apartamento:
subtype = apartment_unit
access.mode = owner

Base de gang:
subtype = interior
access.mode = rules (gang específica)

Delegacia:
subtype = interior
access.mode = rules (job específico)

Interior público:
subtype = interior
access.mode = public
```

### 4.2 `public` continua significando visibilidade

A coluna existente `public` **não voltará a conceder acesso**.

- `public` e `visibility` controlam descoberta/visualização.
- `access_json` controla autorização.
- `door_json` controla o estado atual da entrada.

### 4.3 Prédio não é uma unidade vendável

`apartment_building` é agrupador:

- entrada compartilhada;
- interfone/lista de unidades;
- garagem compartilhada opcional;
- defaults de criação;
- sem owner residencial;
- sem compra;
- sem IPTU próprio.

Cada `apartment_unit` é independente:

- owner próprio;
- chaves próprias;
- preço próprio;
- compra própria;
- IPTU próprio;
- shell e pontos próprios.

### 4.4 Preço padrão é copiado, não herdado em tempo real

Na criação do prédio:

```text
Preço padrão: R$ 180.000
```

Todas as unidades criadas recebem uma cópia desse valor. Depois disso, cada
unidade passa a ser independente. Alterar o default do prédio não muda unidades
existentes, principalmente unidades já vendidas.

### 4.5 Porta e autorização são conceitos separados

Estados:

```text
unlocked  → qualquer jogador pode entrar
locked    → somente autorizado pela política, owner ou chave
blocked   → somente admin entra
```

Estar `unlocked` não concede automaticamente acesso a recursos internos.
Um visitante pode entrar e continuar sem permissão para stash, wardrobe ou
garagem.

### 4.6 Chaves possuem níveis

Papéis canônicos:

```text
access   → entra quando a porta está locked
control  → entra e pode trancar/destrancar
```

Compatibilidade:

```text
role = key → interpretar como access
```

Owner e admin sempre podem controlar a porta de uma residência. Para gang/job,
o controle depende da regra de grade configurada.

### 4.7 Gang e job são escolhidos de fontes reais

O painel não deve depender apenas de texto livre. A implementação deve
inspecionar os contratos reais de `mz_core`/`mz_org` e listar jobs, gangs ou
organizações existentes.

Se não existir export de listagem:

1. criar um adapter no `mz_houses`;
2. usar a fonte oficial real encontrada no workspace;
3. permitir fallback manual apenas para admin e com validação server-side;
4. registrar no relatório qual contrato real foi adotado.

### 4.8 Uma ou várias regras

A estrutura aceita várias regras com semântica **OR / qualquer regra** no MVP:

```json
{
  "mode": "rules",
  "match": "any",
  "rules": [
    { "type": "gang", "name": "ballas", "minimumGrade": 0 },
    { "type": "gang", "name": "families", "minimumGrade": 2 }
  ]
}
```

O menu simples começa com uma regra. O modo avançado permite adicionar mais.
Semântica AND fica fora do escopo inicial.

---

## 5. Modelo canônico de propriedade

### 5.1 Campos existentes preservados

Continuar usando:

```text
code
label
category
subtype
owner_type
parent_code
unit_number
org_code
business_code
building_json
type
shell
entrance_json
garage_json
features_json
interior_json
metadata_json
visibility
status
enabled
public
owner_citizenid
```

`listing_json` e `realestate_json` permanecem somente por compatibilidade de
schema e não controlam runtime.

### 5.2 Categorias e subtipos alvo

Categorias canônicas:

```text
residential
organization
public
administrative
other
```

Compatibilidade de leitura:

```text
org        → organization
business   → organization ou other conforme migração manual
government → organization/public conforme finalidade
```

Não renomear registros automaticamente na primeira fase. O repository deve
normalizar e preservar o valor persistido até uma migração explícita.

Subtipos principais:

```text
house
apartment_building
apartment_unit
interior
```

Templates de UI podem usar nomes mais claros sem criar novos subtipos técnicos:

```text
Sede de gang       → subtype=interior + regra gang
Sede de job        → subtype=interior + regra job
Interior público   → subtype=interior + modo public
Interior admin     → subtype=interior + modo admin
```

### 5.3 `access_json`

Adicionar na Fase 1:

```sql
access_json LONGTEXT NULL
```

Formato canônico:

```json
{
  "version": 1,
  "mode": "owner",
  "match": "any",
  "rules": [],
  "features": {
    "stash": { "mode": "inherit", "match": "any", "rules": [] },
    "wardrobe": { "mode": "inherit", "match": "any", "rules": [] },
    "garage": { "mode": "inherit", "match": "any", "rules": [] }
  }
}
```

Modos:

```text
owner   → owner e chaves
rules   → job/gang/org conforme rules
public  → audiência pública quando a porta estiver unlocked
admin   → somente administradores
none    → ninguém, exceto admin/chaves explicitamente aceitas
```

Regra de job:

```json
{
  "type": "job",
  "name": "police",
  "minimumGrade": 0,
  "requireDuty": true,
  "canControlDoorFromGrade": 4
}
```

Regra de gang:

```json
{
  "type": "gang",
  "name": "ballas",
  "minimumGrade": 0,
  "canControlDoorFromGrade": 3
}
```

Regra de organização genérica, apenas se os contratos reais do projeto
justificarem:

```json
{
  "type": "org",
  "name": "ballas",
  "minimumGrade": 0,
  "requiredCapability": null,
  "canControlDoorFromGrade": 3
}
```

### 5.4 `door_json`

Adicionar na Fase 2:

```sql
door_json LONGTEXT NULL
```

Formato:

```json
{
  "version": 1,
  "state": "locked",
  "defaultState": "locked",
  "autoLock": false,
  "autoLockSeconds": 0,
  "control": {
    "mode": "policy",
    "minimumGrade": null
  }
}
```

Estados válidos:

```text
locked
unlocked
blocked
```

Nunca aceitar estado livre enviado pelo client sem validação.

### 5.5 `features_json`

Manter booleans existentes:

```json
{
  "stash": true,
  "wardrobe": true,
  "garage": false,
  "furniture": false
}
```

A existência do recurso é controlada aqui. A autorização detalhada fica em
`access_json.features`.

### 5.6 `commerce` residencial

Na Fase 4, usar colunas próprias porque preço e disponibilidade controlam
movimentação real de dinheiro:

```sql
sale_enabled TINYINT(1) NOT NULL DEFAULT 0,
sale_mode VARCHAR(20) NOT NULL DEFAULT 'none',
sale_price BIGINT UNSIGNED NOT NULL DEFAULT 0
```

Modos:

```text
none
admin
direct
```

Não armazenar o preço autoritativo somente em `metadata_json`.

`metadata.administrativePrice` pode ser migrado opcionalmente para
`sale_price`, mas nunca automaticamente habilitar venda.

### 5.7 IPTU

Na Fase 6, adicionar ao imóvel:

```sql
tax_enabled TINYINT(1) NOT NULL DEFAULT 0,
tax_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
tax_interval_days INT UNSIGNED NOT NULL DEFAULT 7,
tax_grace_period_days INT UNSIGNED NOT NULL DEFAULT 3,
tax_due_at DATETIME NULL,
tax_grace_until DATETIME NULL,
tax_status VARCHAR(20) NOT NULL DEFAULT 'disabled',
tax_last_paid_at DATETIME NULL
```

Status:

```text
disabled
paid
due
overdue
blocked
```

Criar histórico separado:

```text
mz_house_tax_payments
```

### 5.8 Histórico de compras

Criar na Fase 4:

```text
mz_house_transactions
```

Campos mínimos:

```text
id
transaction_key
house_code
buyer_citizenid
actor_citizenid
amount
mode
status
meta_json
created_at
updated_at
```

Status:

```text
initiated
money_removed
completed
refunded
manual_review
failed
```

Isso permite detectar falha entre retirada de dinheiro e definição do owner.

---

## 6. Templates do painel

O admin não deve precisar entender todos os campos técnicos. O menu oferece
modelos que preenchem defaults consistentes.

| Template | Subtipo | Acesso | Porta inicial | Owner | Compra | IPTU |
|---|---|---|---|---|---|---|
| Casa residencial | `house` | `owner` | `locked` | player | sim | sim |
| Prédio | `apartment_building` | `public` | `unlocked` | server | não | não |
| Apartamento | `apartment_unit` | `owner` | `locked` | player | sim | sim |
| Sede de gang | `interior` | `rules/gang` | `locked` | none/server | não | não |
| Sede de job | `interior` | `rules/job` | `locked` | none/server | não | não |
| Interior público | `interior` | `public` | `unlocked` | none/server | não | não |
| Interior administrativo | `interior` | `admin` | `blocked` | server | não | não |

### 6.1 Defaults de recursos

Casa/apartamento:

```text
stash=true
wardrobe=true
garage=opcional
```

Gang/job:

```text
stash=opcional
wardrobe=opcional
garage=opcional
```

Público/admin:

```text
stash=false
wardrobe=false
garage=false
```

O admin pode alterar depois.

---

## 7. Avaliação de entrada e porta

### 7.1 Ordem autoritativa

Ao tentar entrar:

1. validar rate limit;
2. validar propriedade existente;
3. validar `enabled` e `status`;
4. validar distância da entrada;
5. validar sessão anterior;
6. consultar estado da porta;
7. avaliar admin;
8. avaliar estado:
   - `blocked`: somente admin;
   - `unlocked`: permitir entrada como visitante;
   - `locked`: avaliar owner, chave e `access_json`;
9. criar sessão pendente;
10. definir routing bucket;
11. enviar somente payload necessário;
12. aguardar confirmação do shell;
13. confirmar sessão ou executar rollback.

### 7.2 Razões de acesso

Padronizar motivos:

```text
admin
owner
key_access
key_control
job_rule
gang_rule
org_rule
public_unlocked
door_blocked
door_locked
no_access_rule
grade_denied
duty_required
group_not_found
```

Essas razões devem aparecer nos logs, não necessariamente em detalhes sensíveis
para jogadores comuns.

### 7.3 Visitante de porta destrancada

Uma sessão aberta por `public_unlocked` deve marcar:

```lua
session.accessReason = 'public_unlocked'
session.isGuest = true
```

O guest pode entrar e sair. Acesso a recursos é reavaliado separadamente.

---

## 8. Controle da porta

### 8.1 Quem pode controlar

Ordem:

1. admin;
2. owner da residência;
3. chave `control`;
4. regra de job/gang cuja grade alcance `canControlDoorFromGrade`;
5. política específica futura.

### 8.2 Ações

No ponto externo e, opcionalmente, no ponto interno:

```text
Entrar
Trancar
Destrancar
```

Só mostrar ação de controle para quem pode controlar.

Mudança deve:

- acontecer no servidor;
- atualizar cache;
- persistir `door_json`;
- emitir evento client somente com `houseCode` e novo estado;
- registrar log;
- não expulsar automaticamente visitantes que já estão dentro quando a porta é
  trancada;
- `blocked` administrativo pode expulsar, conforme confirmação do admin.

### 8.3 Auto-lock

Não implementar na primeira entrega de portas, mas deixar formato preparado.
Ativar somente depois de testes de sincronização.

---

## 9. Chaves avançadas

### 9.1 Compatibilidade

A tabela atual já possui `role`. Evoluir sem apagar dados.

Leitura:

```text
key     → access
access  → access
control → control
```

Runtime não pode continuar como:

```lua
keys[citizenid] = true
```

Deve preservar:

```lua
keys[citizenid] = {
  role = 'access',
  canEnter = true,
  canControlDoor = false
}
```

### 9.2 Menu

```text
Chaves individuais
├─ Dar chave de acesso
├─ Dar chave de controle
├─ Alterar tipo da chave
├─ Remover chave
└─ Limpar todas
```

### 9.3 Regra de recursos

Por compatibilidade inicial, uma chave residencial continua podendo usar os
recursos que já usava. Na Fase 3 isso passa a ser configurável.

---

## 10. Permissões por recurso

Cada feature pode:

```text
inherit → herdar regra de entrada
disabled → recurso desativado, inclusive para admin
owner   → somente owner/admin
keys    → owner e portadores de chave
rules   → regras específicas
public  → qualquer ocupante da sessão
admin   → somente admin (`none` legado é normalizado para este modo)
```

Formato:

```json
{
  "features": {
    "stash": {
      "mode": "rules",
      "match": "any",
      "rules": [
        { "type": "gang", "name": "ballas", "minimumGrade": 1 }
      ]
    },
    "wardrobe": { "mode": "inherit" },
    "garage": {
      "mode": "rules",
      "rules": [
        { "type": "gang", "name": "ballas", "minimumGrade": 0 }
      ]
    }
  }
}
```

Toda abertura de stash, wardrobe e garagem deve validar:

1. sessão dentro da propriedade correta;
2. feature habilitada;
3. política atual do recurso;
4. estado atual de owner/chave/grupo;
5. rate limit.

Não confiar no motivo de acesso salvo na entrada; o grupo pode ter mudado.

---

## 11. Fluxos de criação no `/mzhouses`

### 11.1 Menu principal alvo

```text
Criar propriedade
├─ Casa residencial
├─ Prédio de apartamentos
├─ Unidade em prédio existente
├─ Sede de gang
├─ Sede de job
├─ Interior público
├─ Interior administrativo
└─ Avançado
```

### 11.2 Casa residencial

Fase final do wizard:

```text
1. Nome
2. Shell
3. Garagem
4. Preço
5. Modo de venda
6. Disponível para compra
7. Revisar
```

Defaults seguros:

```text
sale_price=0
sale_enabled=false
sale_mode=none ou admin
```

Nunca criar uma casa gratuita comprável por acidente.

### 11.3 Prédio e unidades

Campos:

```text
Nome do prédio
Andares
Unidades por andar
Primeiro andar
Shell padrão
Criar unidades automaticamente
Garagem compartilhada
Preço padrão das unidades
Modo de venda padrão
Disponíveis para compra
IPTU padrão futuro
```

O prédio não recebe preço de venda. Os valores são copiados às unidades.

Operações posteriores:

```text
Aplicar preço às unidades sem owner
Aplicar preço às unidades selecionadas
Editar unidade individual
```

Nunca alterar automaticamente unidade com owner.

### 11.4 Sede de gang

```text
Nome
Selecionar gang real
Grade mínima para entrar
Grade mínima para controlar porta
Shell
Porta inicial
Stash
Wardrobe
Garagem
Revisar
```

A propriedade não possui compra nem IPTU.

### 11.5 Sede de job

```text
Nome
Selecionar job real
Grade mínima
Exigir em serviço
Grade para controlar porta
Shell
Porta inicial
Recursos
Revisar
```

### 11.6 Interior público

```text
Nome
Shell
Porta inicial unlocked
Spawn e saída
Recursos opcionais, todos desligados por padrão
Revisar
```

### 11.7 Interior administrativo

```text
Nome
Shell
Porta blocked
Somente group.mz_owner
Recursos opcionais
```

---

## 12. Compra residencial

### 12.1 Elegibilidade

Somente:

```text
subtype = house ou apartment_unit
access.mode = owner
owner_citizenid IS NULL
sale_enabled = true
sale_price > 0
sale_mode = direct ou admin
status = active
enabled = true
```

Prédio, gang, job, público e admin nunca são vendáveis.

### 12.2 Compra direta

Casa:

```text
Jogador chega à entrada
→ vê preço
→ confirma
→ servidor bloqueia a propriedade
→ revalida owner/preço/saldo
→ remove dinheiro da conta configurada
→ registra transação
→ define owner
→ desativa venda
→ atualiza cache
→ libera acesso
```

Apartamento:

```text
Jogador abre interfone/lista de unidades
→ vê unidades disponíveis e preços
→ escolhe unidade
→ confirma compra
→ mesmo fluxo autoritativo
```

### 12.3 Venda administrada

No `/mzhouses`:

```text
Vender propriedade
→ selecionar player online ou citizenid
→ mostrar preço autoritativo
→ escolher cobrar ou atribuir sem cobrança
→ confirmar
```

Manter também `Atribuir proprietário sem cobrança` para staff, premiação e
migração.

### 12.4 Integração financeira

Antes de implementar, inspecionar o contrato real do `mz_core` para:

- consultar saldo;
- remover dinheiro;
- adicionar dinheiro/refund;
- account `bank`;
- metadata/reason.

Criar adapter server-side, por exemplo conceitual:

```text
server/integrations/money.lua
```

Não chamar vários frameworks diretamente espalhados no serviço.

### 12.5 Concorrência e compensação

Usar lock em memória por `houseCode` e revalidação no banco.

Se dinheiro for removido e owner falhar:

- tentar refund imediato;
- marcar transação `refunded`;
- se refund falhar, marcar `manual_review` e logar criticamente.

Não depender apenas de cache para confirmar que a casa continua sem owner.

---

## 13. IPTU

### 13.1 Escopo inicial

- somente casa e apartamento com owner;
- valor fixo definido pelo admin;
- intervalo em dias, default 7;
- pagamento manual pelo jogador;
- conta bancária;
- avisos;
- tolerância;
- sem remoção automática de owner no MVP.

### 13.2 Fluxo

```text
Compra concluída
→ tax_due_at = agora + intervalo
→ status paid

Chegou vencimento
→ status due

Passou tolerância
→ status overdue

Admin pode bloquear
→ status blocked
```

`blocked` de IPTU não deve apagar owner. A consequência exata deve ser
configurável:

```text
none
block_purchase_transfer
block_garage
block_entry
```

Default recomendado para primeira versão:

```text
não bloquear entrada automaticamente;
mostrar dívida e permitir decisão administrativa.
```

### 13.3 Processamento

Não criar uma thread por propriedade.

Usar:

- verificação horária global;
- avaliação lazy ao carregar player/propriedade;
- índices em `tax_due_at` e `tax_status`;
- limite por lote.

---

## 14. Plano de execução por fases

# Fase 0 — Estabilização e invariantes multiusuário

**Objetivo:** garantir que a base atual suporta várias pessoas no mesmo local.

### Escopo

1. Corrigir/validar origem determinística do shell:
   - quando `mz_houses` fornece `spawnBase`, não adicionar PlayerId/jitter;
   - todos os clients da mesma propriedade usam as mesmas coordenadas internas;
   - previews continuam isolados por bucket.
2. Testar dois jogadores na mesma casa.
3. Testar duas propriedades no mesmo modelo de shell.
4. Consolidar cleanup de sessão e bucket.
5. Confirmar voz por routing bucket.
6. Manter spawn/ícones já calibrados.

### Arquivos prováveis

```text
mz_interiors/client/shells.lua
mz_interiors/shared/config.lua
mz_houses/client/main.lua
mz_houses/server/main.lua
mz_houses/docs/TEST_PLAN.md
```

### Critérios de aceite

- dois jogadores da mesma propriedade se veem e se ouvem;
- ambos possuem `CurrentInterior.spawnCoords` idêntico;
- propriedades distintas não se veem;
- restart/morte/disconnect não deixa bucket preso;
- spawn custom, saída, stash e wardrobe continuam corretos.

### Bloqueio

Nenhuma fase seguinte deve ir para produção sem esse teste.

---

# Fase 1 — Tipos universais e políticas de acesso

**Objetivo:** criar gang, job, público e admin sem comércio.

### Banco

Migration sugerida:

```text
003_universal_access.sql
```

Adicionar:

```text
access_json
idx_mz_houses_category_subtype, se útil após análise
```

### Implementação

1. Normalizar `access_json` no repository.
2. Criar evaluator único server-side.
3. Criar adapter de grupos reais.
4. Reativar criação de gang de forma nova, não pelo legado cego.
5. Adicionar template job.
6. Adicionar template público.
7. Adicionar template administrativo.
8. Remover bloqueio `legacy_property_type_retired` somente para propriedades
   que possuam política nova válida.
9. Registros antigos sem `access_json` continuam com comportamento residencial
   atual.
10. Gang/job não recebem owner, venda ou IPTU.

### Compatibilidade

Fallback de imóveis existentes:

```text
house/apartment + owner_type=player → mode owner
apartment_building → mode public
org antigo sem access_json → continua bloqueado até admin migrar
```

### UI

Menu de criação mostra os novos templates.

Lista de gang/job deve usar dados reais. Não persistir label no lugar do code.

### Critérios de aceite

- gang A entra na sede A;
- gang B é bloqueada;
- job correto entra;
- grade abaixo é bloqueada;
- `requireDuty` funciona conforme contrato real;
- interior público entra sem owner/chave;
- interior admin bloqueia jogador comum;
- casa antiga continua igual;
- nenhuma venda ainda é ativada.

### Implementação registrada — 2026-07-12

- `access_json` nullable e incremental em `003_universal_access.sql`;
- fallback sem gravação para residências antigas e prédios;
- tipos legados sem política permanecem bloqueados;
- evaluator único usa adapter sobre `ListOrgs`, `GetOrgByCode` e
  `GetPlayerOrgs` reais do `mz_core`;
- membership fornece tipo, code, grade e duty, permitindo `minimumGrade`,
  `requireDuty` para job e várias regras com `match=any`;
- templates de residência, apartamento, prédio, gang, job, público e admin no
  `/mzhouses`;
- `public` permanece visibilidade e não substitui `access_json`;
- portas, chaves avançadas, comércio e IPTU não foram implementados.

### Revisão técnica da Fase 1 — 2026-07-12

Auditoria estática concluída após a implementação:

- gang A é comparada por `type+code` e não satisfaz regra da gang B;
- grade e duty são obtidos de `GetPlayerOrgs(source)` no servidor;
- antes de autorizar uma regra, `GetOrgByCode` confirma tipo e estado ativo,
  com cache curto de 10 segundos;
- público não depende de owner/chave e admin depende do ACE calculado no servidor;
- fallback residencial não grava `access_json`; org legada sem política continua
  em `legacy_property_type_retired`;
- payload público não contém política, regras, grade mínima ou duty;
- callback administrativo valida ACE e a política completa no servidor;
- migration permanece nullable, idempotente e não destrutiva;
- corrigida a allowlist para preservar `category=administrative`;
- removido consumo duplicado do rate limit ao salvar política;
- negações passam a usar o log canônico `property.access.denied`;
- nenhuma implementação de porta, compra ou IPTU foi adicionada.

### Aprovação runtime da Fase 1 — 2026-07-12

Após a auditoria, foram validados no servidor FiveM:

- revalidação de gang/job ativo;
- expiração do cache de organização em até 10 segundos;
- `category=administrative` preservada após restart;
- política salva sem consumo duplicado de rate limit;
- negativas registradas em `property.access.denied`;
- residências antigas, gang, job, público e admin continuam funcionando.

---

# Fase 2 — Portas e chaves avançadas

**Objetivo:** porta aberta/fechada e tipos de chave.

### Banco

Migration:

```text
004_property_doors.sql
```

Adicionar:

```text
door_json
índice opcional somente se houver consulta SQL por estado
```

`mz_house_keys.role` já existe; não recriar tabela.

### Implementação

1. Normalizar `door_json`.
2. Preservar role das chaves no cache.
3. Migrar `key` para `access` na leitura.
4. Criar `CanControlDoor`.
5. Criar ações lock/unlock.
6. Sincronizar estado.
7. Logs.
8. Admin pode blocked/unblocked.
9. Quando unlocked, guest entra mas não ganha recursos automaticamente.

### Critérios

- owner tranca/destranca;
- access key entra, mas não controla;
- control key entra e controla;
- líder de gang/job controla conforme grade;
- membro de grade baixa entra, mas não controla;
- jogador sem acesso entra apenas quando unlocked;
- blocked permite somente admin;
- restart preserva estado da porta.

### Implementação da Fase 2 — 2026-07-12

- migration incremental `004_property_doors.sql` adiciona `door_json` nullable,
  sem recriar `mz_house_keys` e com rollback manual documentado;
- repository normaliza/persiste o formato canônico da porta e preserva o role
  das chaves no cache; `key` legado é convertido para `access` na leitura;
- `CanControlDoor` autoritativo permite admin, owner, chave `control` e regra
  gang/job na grade `canControlDoorFromGrade`, revalidando grupo, grade e duty;
- `locked`, `unlocked` e `blocked` são validados no servidor; somente admin
  aplica ou remove `blocked`;
- `unlocked` libera a interação física de entrada para visitante sem publicar
  a propriedade em listagem e sem liberar garagem ou recursos internos;
- sessão `public_unlocked` registra `isGuest=true`; baú, guarda-roupa e garagem
  negam o visitante no servidor;
- mudança de estado persiste no banco, atualiza o cache, sincroniza somente
  `houseCode/state` e registra `property.door.lock`, `.unlock` ou `.block`;
- concessões registram `property.key.access.give`/`.control.give`; mudança de
  papel registra `property.key.role.change`;
- revisão corrigiu a visibilidade da interação externa: antes, o evaluator
  admitia o guest em `unlocked`, mas uma política restrita podia ocultar seu
  ponto de entrada;
- validação estática aprovada: `validate.ps1` validou 36 arquivos Lua e a
  matriz isolada de porta/chaves aprovou owner, roles, grade, guest e blocked;
- revisão de conflito removeu o comando/key mapping global `mz_house_door`;
  E permanece em entrar/interfone/sair e o menu externo continua compatível;
- G (controle 47) é lido somente no loop da porta mais próxima: dentro do raio,
  a pé, em estado locked/unlocked e após `canControl=true` do cache server-side;
  fora desse contexto não há callback, notify ou `DisableControlAction`,
  preservando o G do cinto em `mz_hud`;
- toggle toca `anim@mp_player_intmenu@key_fob@`/`fob_click`, sem prop, antes da
  mutação revalidada pelo servidor; busy local e cooldown de 1000 ms impedem
  callbacks e animações sobrepostos;
- textos externos e internos mostram continuamente `Trancada`, `Destrancada`
  ou `Interditada` e só exibem a ação G após `canControl` server-side;
- contexto client usa cache curto de 1 segundo. G força nova consulta antes da
  mutação; nenhuma decisão de controle é aceita do cache como autoridade;
- proximidade externa resolve o código/entrada visível mais próximo e a interna
  usa exatamente o ponto efetivo de saída da propriedade atual;
- `doorStateChanged` atualiza imediatamente cache, propriedade visível e
  `CurrentHouse.data.doorState`; a reconciliação do `mz_interact` substitui
  somente o ponto afetado pelo mesmo id, sem marcadores E/G sobrepostos;
- prédio mantém E no interfone e G no código do prédio; dentro de unidade, G
  opera somente o código da unidade atual;
- correção de visibilidade externa separou definitivamente descoberta e
  autorização: `CanSeeHouse` pode publicar a entrada, mas `CanEnterHouse`
  continua sendo a única autoridade para entrar com a porta `locked`;
- admin e jogadores autorizados visualizam; `unlocked`, modo/flag público e
  interior público ficam visíveis para todos; interior administrativo continua
  exclusivo de admin;
- gang/job privado continua oculto para não membros quando `locked`; ao marcar
  visibilidade pública, aparece sem conceder entrada;
- residência vazia continua oculta por padrão. Foi deixado somente um gancho de
  leitura para o futuro `sale_enabled=true`, sem schema, preço ou compra;
- mudança locked/unlocked já transmitida por `doorStateChanged` atualiza cache e
  interação; o refresh global duplicado do callback foi removido;
- runtime aprovado pelo responsável em 2026-07-13 após confirmação de que a
  implementação está funcional. Comércio, compra e IPTU não foram implementados.

### Aprovação runtime da Fase 2 — 2026-07-13

O responsável confirmou a Fase 2 como funcional no servidor. A fase está
concluída e libera o início controlado da Fase 3 em uma execução posterior.

---

# Fase 3 — Permissões por recurso

**Objetivo:** separar entrada de stash, wardrobe e garagem.

### Banco

Sem nova coluna: usar `access_json.features`.

### Implementação

1. Evaluator reutilizável por feature.
2. Menu para editar policy de cada recurso.
3. Defaults compatíveis.
4. Revalidar no servidor a cada ação.
5. Ocultar interação quando possível, mas nunca depender do client.

### Critérios

- gang grade 0 entra;
- grade 1 usa stash;
- grade 0 não usa stash;
- wardrobe e garagem respeitam políticas próprias;
- guest de porta unlocked não usa recurso restrito;
- owner/key de casas antigas continuam funcionando pelo fallback.

### Implementação realizada — 2026-07-13

- `MZHousesService.CanAccessPropertyFeature` consolidado como evaluator único;
- sessão interna confirmada obrigatória para stash/wardrobe e contexto externo
  da garagem validado por proximidade no servidor;
- guest revalidado em toda ação e liberado somente por `mode=public` explícito;
- entrada por porta aberta revalida owner/chave/gang/job para que apenas o
  visitante dependente de `unlocked` seja classificado como guest;
- políticas independentes com owner, keys, rules/any, public, admin e disabled;
- menu `Recursos e permissoes` com grupos reais, grade, duty, resumo e confirmação;
- payload client limitado a booleans de UX, sem envio das regras sensíveis;
- logs `property.feature.access.denied` e `property.feature.policy.set`;
- sem migration: propriedades antigas permanecem em fallback e não são
  regravadas automaticamente;
- validador aprovado com 36 arquivos Lua e matriz de políticas aprovada;
- runtime ainda pendente conforme checklist de `docs/TEST_PLAN.md`;
- UX E/G, `door_json`, chaves e autorização principal de entrada preservados.

### Aprovação runtime da Fase 3 — 2026-07-13

O responsável confirmou que a implementação está funcional no servidor FiveM.
A validação runtime da Fase 3 está aprovada; o checklist detalhado permanece em
`docs/TEST_PLAN.md` como roteiro de regressão.

---

# Fase 4 — Comércio residencial

**Objetivo:** preço real, compra direta e venda admin.

### Banco

Migration:

```text
005_property_commerce.sql
```

Adicionar:

```text
sale_enabled
sale_mode
sale_price
mz_house_transactions
```

### Implementação

1. Adapter financeiro do `mz_core`.
2. Preço no wizard de casa.
3. Editar preço/estado de venda.
4. Compra direta na entrada.
5. Venda admin.
6. Lock de concorrência.
7. Compensation/refund.
8. Logs e transação.
9. Owner definido desativa venda.
10. Remover owner não reativa venda automaticamente.

### Critérios

- jogador sem saldo não compra;
- saldo suficiente compra;
- duas pessoas não compram a mesma casa;
- preço do client é ignorado;
- falha de owner devolve dinheiro;
- gang/job/público nunca entram em venda;
- casa com preço zero não pode ficar direct.

### Implementação da Fase 4 — 2026-07-13

Implementação inicial concluída e posteriormente validada em runtime. Foram adicionados os
campos autoritativos `sale_enabled`, `sale_mode` e `sale_price`, a tabela
`mz_house_transactions`, adapter financeiro baseado nos exports reais do
`mz_core`, lock por propriedade, compare-and-set do owner e compensação por
refund. A UX de E prioriza compra `direct`, preserva interfone/entrada/saída e
não altera G ou o estado da porta.

A venda administrativa cobrada exige comprador online; atribuição sem cobrança
continua separada. Owner definido desativa venda, remoção de owner não a reativa
e chaves antigas são limpas somente na compra concluída. Estados interrompidos
após débito viram `manual_review` e bloqueiam nova compra até auditoria.

Correção runtime de callback: o fluxo completo passou a ter barreira de exceção
e retorno canônico; rejeições esperadas recebem `reason/message`, enquanto
`purchase_callback_failed` fica restrito ao transporte client/server. Estados
`payment_pending`, `money_removed` e `manual_review` bloqueiam nova tentativa
imediatamente. Logs temporários controlados por `CommerceDebug` permitem
rastrear a etapa sem registrar saldo ou citizenid.

Correção adicional do runtime: o console identificou `MZHousesCommerce=nil` nos
dois consumidores. `commerce.lua` já possuía a declaração global correta e não
havia tabela local concorrente; a ordem do manifest foi tornada explícita como
money → commerce → main → admin. `main.lua` e `admin_menu.lua` agora validam a
API antes de registrar seus consumidores, e `commerce.lua` registra um marcador
de startup após publicar todas as funções.

Não foram implementados preço padrão de prédio, criação/edição em lote,
apartamentos comerciais ou IPTU. O checklist runtime está em `TEST_PLAN.md`.

### Auditoria final da Fase 4 — 2026-07-13

Antes da auditoria, o responsável aprovou no servidor FiveM: carga da API
pública `MZHousesCommerce`, compra direta pela entrada, contrato canônico do
callback, compra com saldo bancário, definição do owner, desativação da venda,
ausência do erro `MZHousesCommerce nil` e preservação de E, G, animação, porta e
recursos.

A auditoria confirmou a API global única e a ordem money → commerce → main →
admin, os exports financeiros reais do `mz_core`, autoridade server-side,
elegibilidade residencial, lock por propriedade, CAS, payload mínimo, separação
da venda administrativa cobrada e atribuição sem cobrança, schema incremental e
ausência de Fase 5/IPTU.

Foram corrigidos defeitos reais nos caminhos de exceção: normalização de
combinações comerciais inválidas; transições condicionais e terminais da
máquina de estados; `transaction_key` com entropia preservada; resultado
ambíguo do débito/CAS enviado a `manual_review`; refund limitado a uma tentativa;
snapshot e restauração atômica das chaves antigas antes de rollback; e
referência de estado comercial na atribuição administrativa de owner. O recovery
mantém `completed`/`refunded` terminais, transforma `initiated` em `failed` e
envia `payment_pending`/`money_removed` para `manual_review`, sem cobrar ou
atribuir owner automaticamente.

Após as correções funcionais da auditoria, o responsável repetiu a validação no
servidor FiveM e aprovou a regressão em 2026-07-13. O status final é
**Fase 4 — Concluída e aprovada em runtime**. `CommerceDebug` permanece
configurável e está desligado por padrão. O checklist de
`docs/TEST_PLAN.md` permanece como roteiro de regressão.

---

# Fase 5 — Comércio e gestão em lote de apartamentos

**Objetivo:** preço padrão e venda por unidade.

### Implementação

1. Wizard do prédio recebe default de unidade.
2. Unidades automáticas copiam preço e sale mode.
3. Criação em lote segura/transacional.
4. Interfone mostra disponibilidade e preço.
5. Compra de unidade.
6. Edição em lote:
   - unidades sem owner;
   - selecionadas;
   - por andar, opcional.
7. Nunca alterar unidade vendida sem confirmação individual forte.

### Critérios

- prédio não é vendável;
- todas as unidades começam com o default;
- alterar uma unidade não altera as outras;
- mudar default do prédio não altera unidades existentes;
- compra atribui owner somente à unidade;
- garagem compartilhada continua funcionando.

### Implementação da Fase 5 — 2026-07-13

- nenhuma migration foi necessária: `building_json` já era persistente e agora
  normaliza `unitDefaults` com venda, modo, preço, shell, interior e features;
- o prédio permanece agrupador `ownerType=server`, sem owner, compra ou venda
  própria; suas colunas `sale_*` não são usadas como defaults;
- cada unidade recebe uma cópia independente do modelo durante a criação;
  alterações posteriores no prédio não recalculam unidades existentes;
- a criação em lote monta plano imutável, valida números/codes/duplicatas,
  apresenta preview com token server-side e persiste todas as unidades em uma
  única transação SQL;
- codes seguem a regra determinística já existente
  `apt_<numero_do_predio>_<unit_number>`; `unit_number` aceita somente caracteres
  alfanuméricos, `_` e `-`, até 30 caracteres;
- replay integral de um lote é idempotente e não insere duplicatas; conflito
  parcial/externo falha sem sobrescrever ou apagar registros;
- defaults podem copiar shell, interior e features de uma unidade modelo do
  mesmo prédio, sempre apenas para criações futuras;
- operações comerciais em lote usam preview forte, lock e releitura por unidade,
  com resultado item a item; owner, proteção administrativa, estado inativo,
  compra ativa e transação financeira ambígua são ignorados;
- operação por andar não foi implementada porque não existe coluna explícita de
  andar nem parser contratual seguro no modelo atual;
- o interfone publica payload mínimo e compra unidade `direct` somente após
  validar proximidade da entrada persistida, prédio, interfone, porta e vínculo
  `parentCode` no servidor;
- a compra reutiliza diretamente `MZHousesCommerce.purchase`; a máquina de
  estados, CAS, lock financeiro, refund, `manual_review` e recovery da Fase 4
  não foram duplicados nem modificados;
- locks administrativos de prédio/unidade impedem disputa silenciosa com lote;
  compras de unidades diferentes continuam independentes;
- validador aprovado com 39 arquivos Lua e matrizes de defaults, lote
  transacional/idempotente, proteção de owner/estado financeiro e contexto do
  interfone;
- nenhum campo, tabela ou fluxo de IPTU foi criado na implementação original da
  fase. Status: **Fase 5 — Concluída e aprovada em runtime**.

### Aprovação runtime da Fase 5 — 2026-07-13

O responsável pelo servidor confirmou a Fase 5 funcional em runtime e autorizou
o avanço. Foram mantidos o prédio agrupador sem owner/venda, a independência das
unidades, os defaults apenas para novas unidades, a criação/lote idempotente, a
compra pelo interfone e os locks por unidade.

---

# Fase 6 — IPTU

**Objetivo:** cobrança periódica residencial segura.

### Banco

Migration:

```text
006_property_tax.sql
```

Adicionar colunas de tax e tabela:

```text
mz_house_tax_payments
```

### Implementação

1. Configurar IPTU na criação/edição residencial.
2. Prédio possui apenas default para novas unidades.
3. Compra inicializa vencimento.
4. Menu do jogador mostra situação.
5. Pagamento bank server-side.
6. Atualização horária/lazy.
7. Avisos.
8. Admin consulta e ajusta.
9. Sem retomada automática no MVP.

### Critérios

- apenas owner paga;
- pagamento errado/duplicado é bloqueado;
- reinício preserva datas;
- unidade tem IPTU independente;
- job/gang/público não têm IPTU;
- atraso não apaga owner.

### Implementação da Fase 6 — 2026-07-13

- a migration incremental `006_property_tax.sql` adiciona os campos
  `tax_enabled`, `tax_amount`, `tax_interval_days`, `tax_grace_period_days`,
  `tax_due_at`, `tax_grace_until`, `tax_status` e `tax_last_paid_at`, sem apagar
  dados existentes, e cria `mz_house_tax_payments` com chave idempotente e
  índices por propriedade, owner, estado e vencimento;
- a elegibilidade server-side aceita apenas `house` e
  `apartment_unit`/`apartment` residenciais, ativos, não arquivados e com owner;
  prédio, gang, job, público, administrativo e imóvel sem owner são recusados;
- `building_json.unitDefaults.tax` mantém somente o modelo fiscal de futuras
  unidades. Cada unidade recebe cópia independente no momento da criação e não
  acompanha alterações posteriores do prédio;
- a criação/edição residencial configura ativação, valor, intervalo, grace
  period e primeiro vencimento. Atribuição manual de owner usa o padrão seguro
  sem cobrança retroativa e só inicializa quando o admin confirma explicitamente;
- compra concluída inicializa novo vencimento para o comprador. Remoção ou troca
  de owner suspende o ciclo corrente e preserva o histórico, impedindo herança
  automática da dívida pelo próximo owner;
- `MZHousesTax.pay` relê propriedade, owner, configuração, datas e saldo no
  servidor, adquire lock por propriedade, cria pagamento, remove banco, avança
  vencimento por compare-and-set e conclui o histórico. Falha após débito tenta
  refund único; resultado financeiro ambíguo permanece em `manual_review` e
  bloqueia nova tentativa;
- o client envia apenas `houseCode`; valor, datas, status, citizenid e owner não
  são aceitos do client. O histórico do owner não publica metadata nem referência
  financeira interna;
- o processamento fiscal usa uma única passagem global horária, páginas
  configuráveis e lazy check em consulta/pagamento. Não existe timer por imóvel;
- avisos próximos ao vencimento, `due`, `overdue` e `blocked` usam cooldown para
  evitar spam; o owner consulta e paga pelo comando `/iptu`;
- o `/mzhouses` ganhou configuração, consulta, ajuste de vencimento/status e
  histórico. Alterações administrativas geram logs fiscais;
- `tax_status=blocked` fica estritamente no namespace fiscal: não altera
  `door_json`, owner, chaves, entrada/saída, stash, wardrobe ou garagem. Não há
  retomada automática no MVP;
- contratos públicos: `GetPropertyTaxStatus`, `PayPropertyTax` e
  `ConfigurePropertyTax`; todos mantêm autoridade server-side;
- validações locais aprovadas: 40 arquivos Lua, ordem de carregamento, migration,
  contratos posicionais SQL, elegibilidade, pagamento único, janela
  anti-duplicação, isolamento do bloqueio fiscal e rejeição de prédio. Status:
  **Fase 6 — Implementada, aguardando runtime**.

### Auditoria final da Fase 6 — 2026-07-13

A auditoria foi executada após o teste runtime inicial e encontrou defeitos
funcionais nos caminhos de idempotência e ambiguidade financeira:

- `initializeTaxForOwner` podia recalcular `due_at` em uma segunda chamada. A
  query agora exige `tax_due_at IS NULL` e reconhece o ciclo já inicializado sem
  modificar suas datas;
- `manual_review` era consultado apenas por propriedade e uma tentativa do owner
  anterior podia bloquear o owner novo. A barreira persistente agora considera
  o owner atual; o histórico antigo permanece visível ao admin e não é apagado;
- categoria/subtipo/owner type eram validados, mas uma residência com política
  persistida não residencial ainda podia manter ciclo. A elegibilidade agora
  exige política `owner` ou fallback residencial equivalente e suspende o ciclo
  quando uma atualização administrativa torna a propriedade inelegível;
- avanço do vencimento e transição `money_removed -> completed` usavam duas
  queries. Agora uma única atualização SQL multi-table executa o CAS do ciclo e
  conclui o pagamento atomicamente;
- perda de resposta desse CAS não dispara refund por suposição. O servidor relê
  pagamento, owner e vencimento: recupera sucesso comprovado, devolve somente
  quando `money_removed` e ciclo inalterado provam que nada avançou, e envia os
  demais casos para `manual_review`;
- a chave `transaction_reference` passou a ser `NOT NULL` e `UNIQUE`, com
  preenchimento incremental a partir de `transaction_key`; foi adicionado índice
  do histórico por `due_at` e o `prepare.lua` aplica a mesma forma do schema;
- logs fiscais passaram a cobrir início/falha do pagamento, mudança de status,
  recovery e aviso enviado. Ajustes administrativos registram `before/after` e
  o debug fiscal permanece desligado por padrão;
- validações de startup agora conferem todas as funções fiscais consumidas por
  `main.lua` e `admin_menu.lua`, além dos exports públicos existentes;
- matrizes isoladas aprovaram inicialização idempotente, owner novo sem bloqueio
  herdado, saldo insuficiente, lock reentrante, conclusão atômica, refund único,
  prova após perda de resposta, recovery seguro e isolamento de `tax blocked`.

Como houve correção funcional, o status é
**Fase 6 — Corrigida, aguardando novo runtime**. Nenhuma regra de porta, compra,
apartamentos, recursos ou fases anteriores foi removida; não há retomada
automática e a Fase 7 não foi iniciada.

### Aprovação runtime da Fase 6 — 2026-07-13

O responsável repetiu a validação após a auditoria e confirmou o runtime. Foram
aprovados inicialização idempotente, ciclo por owner, pagamento/refund protegido,
recovery, grace/status, isolamento entre IPTU e porta e regressão das Fases 0 a
5. A Fase 6 está **Concluída e aprovada em runtime**, sem retomada automática.

---

# Fase 7 — Consolidação, migração e documentação

**Objetivo:** limpar legado sem quebrar compatibilidade.

### Escopo

1. Wizard de migração manual para orgs antigas.
2. Auditoria de `listing_json`/`realestate_json` sem apagar.
3. Atualizar README e guias.
4. Atualizar validador PowerShell.
5. Teste de carga/cache.
6. Documentar exports finais.
7. Remover código morto somente quando comprovadamente sem consumidor.
8. SQL opcional de limpeza separado.

### Implementação da Fase 7 — 2026-07-13

- o `/mzhouses` ganhou migração manual para residência, prédio, unidade,
  gang, job, público e administrativo;
- o servidor monta preview com token de 5 minutos vinculado ao admin, exige o
  code como confirmação e compara o snapshot antes de persistir;
- owner/chaves incompatíveis nunca são apagados; compra, IPTU, lote e estados
  financeiros ambíguos bloqueiam a migração;
- `listing_json` e `realestate_json` são auditados por contagem/estado sem
  publicar conteúdo e permanecem preservados sem controlar runtime;
- código morto antigo foi removido somente após pesquisa de consumidores; a
  rejeição de tipos aposentados e wrappers compatíveis foi mantida;
- migrations 002-006 foram revisadas; não houve migration nova;
- `optional_cleanup_realestate.sql` permanece separado, fora do manifest e com
  comandos destrutivos comentados;
- exports, callbacks e eventos finais estão em `docs/API_REFERENCE.md`; a
  auditoria consolidada está em `docs/FINAL_VALIDATION_REPORT.md`;
- `validate.ps1` passou a conferir Lua, manifest, migrations, SQL opcional,
  payload público, wizard, documentos e aposentadoria de `mz_realestate`;
- a pasta `mz_realestate` não foi excluída. A remoção depende de auditoria de
  deploy e consumidores externos ao workspace.

Status anterior: **Fase 7 — Implementada, aguardando runtime final**.

### Aprovação runtime da Fase 7 — 2026-07-13

O responsável confirmou a validação final no servidor FiveM. O wizard manual,
auditoria não destrutiva, bloqueios concorrentes, persistência e regressão das
Fases 0 a 6 foram aprovados. Status final: **Fase 7 — Concluída e aprovada em
runtime**.

---

# Fase 8 — Painel do proprietário e gestão pessoal de imóveis

**Objetivo:** oferecer `/house` sem transformar o jogador em administrador.

### Implementação da Fase 8 — 2026-07-13

- `MZHousesConfig.PlayerPanel` registra `/house`, alias `/houses`, distância de
  3 metros, limite de 10 chaves e rate limit de 1000 ms;
- a busca no workspace não encontrou conflito de `/house`; o client também
  evita sobrescrever comando já registrado em runtime;
- `Meus imóveis` aceita somente residência individual ativa, não arquivada,
  `ownerType=player`, policy owner e owner atual igual ao jogador;
- `Imóveis com chave` usa consulta e payload separados, somente leitura, sem
  citizenid, policy, tax, features, dados financeiros ou coordenadas internas;
- o detalhe do owner publica apenas resumo seguro de identificação, unidade,
  prédio, porta, quantidade de chaves, IPTU, comércio e features;
- IPTU reutiliza `MZHousesTax.getStatus` e o callback `payPropertyTax` da Fase 6;
  `/iptu` permanece inalterado;
- entrega de chave exige alvo online próximo, token temporário, role
  `access`/`control`, confirmação forte para `control`, releitura server-side e
  limite sob lock por propriedade;
- revogação usa token temporário sem citizenid no client, funciona offline e
  não expulsa ocupante atual; a próxima capacidade é revalidada;
- waypoint usa somente entrada pública e, para unidade, a entrada do prédio;
- porta, comércio e features são estritamente somente leitura. Não foram
  adicionados revenda, transferência, aluguel, co-owner ou edição de interior;
- nenhuma migration foi criada. O validador aprovou 43 arquivos Lua, ordem do
  manifest, payload, contratos e ausência de `mz_realestate`.

Status: **Fase 8 — Implementada, aguardando runtime**.

---

## 15. Organização de código recomendada

Não reorganizar tudo de uma vez. Evoluir incrementalmente.

Arquivos novos recomendados quando a fase exigir:

```text
mz_houses/server/access_policy.lua
mz_houses/server/door_service.lua
mz_houses/server/commerce.lua
mz_houses/server/tax.lua
mz_houses/server/player_panel.lua
mz_houses/server/integrations/groups.lua
mz_houses/server/integrations/money.lua
mz_houses/client/door.lua
mz_houses/client/player_panel.lua
```

Caso a arquitetura atual prefira manter em `service.lua`, extrair apenas quando
isso reduzir risco e duplicação. Não fazer refactor cosmético junto com regra
de negócio crítica.

Ordem no `fxmanifest.lua` deve respeitar dependências entre arquivos.

---

## 16. Contratos e exports

### 16.1 Preservar

Client:

```text
EnterHouse
ExitHouse
GetCurrentHouse
GetHouses
IsInsideHouse
OpenHouseStash
OpenHouseWardrobe
OpenHouseGarage
```

Server:

```text
CanEnterHouse
GetPropertyByCode
GetPublicPropertyInfo
ListProperties
CanPlayerAccessProperty
CanPlayerManageProperty
SetPropertyOwner
ClearPropertyOwner
GivePropertyKey
RemovePropertyKey
OpenHouseStash
OpenHouseWardrobe
OpenHouseGarage
CreateProperty
UpdateProperty
DeleteProperty
SetPropertyEntrance
SetPropertyInterior
SetPropertyGarage
SetPropertyEnabled
ListPropertyKeys
```

### 16.2 Adicionar quando necessário

```text
CanControlPropertyDoor
SetPropertyDoorState
GetPropertyDoorState
GetPropertyAccessPolicy
SetPropertyAccessPolicy
SetPropertySale
PurchaseProperty
GetPropertyTaxStatus
PayPropertyTax
GetPlayerOwnedProperties
GetPlayerKeyedProperties
GetPlayerPropertyPanel
GetNearbyPlayersForPropertyKey
GrantPropertyKeyByOwner
RevokePropertyKeyByOwner
```

Exports mutáveis continuam exigindo `actorSource` admin, exceto ações explícitas
do próprio jogador como compra, pagamento e gestão de chaves pelo owner. Esses
fluxos validam source, citizenid e todo o contexto no servidor.

### 16.3 Compatibilidade de retorno

Não trocar boolean por tabela silenciosamente em export já consumido. Quando
for necessário enriquecer retorno, preservar primeiro valor boolean e usar o
segundo como detalhe:

```lua
return true, { reason = 'owner' }
```

---

## 17. Segurança

Obrigatório em todas as fases:

- permissão admin no server;
- source válido;
- citizenid resolvido pelo server;
- grupo/grade consultado no provider real;
- distância validada no server;
- property code normalizado;
- strings limitadas;
- JSON normalizado;
- números finitos e limites;
- preço inteiro não negativo;
- money adapter server-only;
- lock por propriedade em compra;
- lock por propriedade em compra e mutação de chave pelo owner;
- rate limit em entrada, porta, compra, tax, recursos e painel do owner;
- cache invalidado após mutação;
- logs de falha e sucesso;
- payload público sem políticas sensíveis completas;
- nenhuma confiança em grade ou preço do client.

---

## 18. Performance

- nenhuma thread por casa;
- nenhuma consulta SQL por frame;
- cache de políticas e portas;
- atualização por propriedade alterada;
- lista de grupos carregada sob demanda/cache curto;
- processamento de IPTU em lotes;
- não enviar todas as regras internas para todos os jogadores;
- interações somente próximas;
- shell instanciado somente durante sessão.

---

## 19. Logs obrigatórios

Ações mínimas:

```text
property.access.policy.set
property.access.denied
property.door.lock
property.door.unlock
property.door.block
property.key.access.give
property.key.control.give
property.key.role.change
property.sale.configure
property.purchase.started
property.purchase.completed
property.purchase.refunded
property.purchase.manual_review
property.tax.configure
property.tax.paid
property.tax.overdue
property.tax.blocked
property.player_panel.opened
property.key.owner_granted
property.key.owner_revoked
property.key.owner_grant_failed
property.key.owner_revoke_failed
property.owner_tax_viewed
```

Metadata deve conter códigos/valores necessários, sem dados desnecessários.

---

## 20. Matriz de testes final

### Base e shells

- [ ] Dois players na mesma casa usam origem idêntica.
- [ ] Duas casas no mesmo shell ficam isoladas.
- [ ] Spawn padrão funciona.
- [ ] Spawn custom funciona.
- [ ] Ícones ficam no local correto.
- [ ] Morte/disconnect/restart limpa sessão.

### Acesso

- [ ] Owner entra.
- [ ] Chave access entra.
- [ ] Gang correta entra.
- [ ] Gang errada não entra.
- [ ] Job correto entra.
- [ ] Duty é respeitado.
- [ ] Grade é respeitada.
- [ ] Público entra quando unlocked.
- [ ] Admin entra em blocked.

### Porta

- [ ] Owner controla.
- [ ] Access key não controla.
- [ ] Control key controla.
- [ ] Grade de controle funciona.
- [ ] Estado persiste após restart.
- [ ] Guest interno não é expulso ao trancar.

### Recursos

- [ ] Stash respeita regra.
- [ ] Wardrobe respeita regra.
- [ ] Garagem respeita regra.
- [ ] Guest não acessa recurso restrito.
- [ ] Mudança de grupo revoga imediatamente.

### Compra

- [ ] Preço aparece correto.
- [ ] Client não altera preço.
- [ ] Sem saldo é negado.
- [ ] Compra conclui e owner atualiza.
- [ ] Concorrência não duplica venda.
- [ ] Falha gera refund.
- [ ] Não residencial não pode ser vendido.

### Apartamentos

- [ ] Default é copiado às unidades.
- [ ] Exceção individual funciona.
- [ ] Unidade vendida não muda em lote.
- [ ] Prédio não é comprado.
- [ ] Compra pelo interfone funciona.

### IPTU

- [ ] Vencimento calculado.
- [ ] Pagamento persiste.
- [ ] Histórico criado.
- [ ] Atraso não remove owner.
- [ ] Prédio/gang/job/público não recebem tax.

---

## 21. Estratégia de migração

### Imóveis residenciais existentes

Sem `access_json`:

```text
mode=owner
porta default=locked
```

Não gravar automaticamente apenas ao carregar. Persistir quando o admin editar
ou em migration explícita segura.

### Chaves existentes

```text
role=key → access
```

Pode ser normalizado em leitura. Migration opcional pode atualizar valores,
mas não é obrigatória.

### Org/business/government legados

Continuam bloqueados até migração administrativa porque não há política
persistente confiável.

Criar ação futura:

```text
Migrar propriedade legada
→ escolher template gang/job/public/admin
→ selecionar grupo
→ revisar
→ salvar access_json/door_json
```

### Preço informativo existente

`metadata.administrativePrice` pode ser sugerido como `sale_price`, mas:

- `sale_enabled=false`;
- `sale_mode=none`;
- admin confirma antes de ativar.

---

## 22. Itens fora do escopo até o plano principal estar estável

- aluguel;
- financiamento;
- hipoteca;
- leilão;
- revenda direta entre jogadores;
- comissão;
- corretor;
- imobiliária;
- banco empresarial;
- anúncio no telefone;
- placa de venda;
- invasão/arrombamento;
- chave como item físico;
- decoração/furniture avançada;
- MLO editor;
- remoção automática de imóvel por IPTU.

---

## 23. Controle de execução

O agente deve atualizar esta tabela ao terminar cada fase.

| Fase | Status | Migration | Validação estática | Runtime | Data | Observações |
|---|---|---|---|---|---|---|
| 0 — Estabilização | Concluída | Não prevista | Aprovada (`validate.ps1`: 33 Lua) | Aprovada em runtime | 2026-07-12 | Validado no servidor FiveM: dois jogadores na mesma propriedade compartilhando o interior; propriedades diferentes no mesmo shell isoladas; spawn e pontos internos corretos; restart de `mz_interiors` e `mz_houses`; entrada, saída e preview após a revisão de rollback |
| 1 — Acesso universal | Concluída | `003_universal_access.sql` | Aprovada após revisão (`validate.ps1`: 35 Lua + evaluator) | Aprovada em runtime | 2026-07-12 | Validado: gang/job ativo, cache até 10s, categoria administrative após restart, rate limit único, `property.access.denied` e regressão dos modos de acesso |
| 2 — Portas/chaves | Concluída | `004_property_doors.sql` | Aprovada (`validate.ps1`: 36 Lua + matrizes porta/chaves e visibilidade/entrada + UX E/G contextual) | Aprovada em runtime | 2026-07-13 | Responsável confirmou a implementação funcional; estados persistentes, visibilidade separada da entrada, roles access/control, guest sem recursos, G contextual e animação de chave validados no fluxo runtime |
| 3 — Recursos | Concluída | Não prevista | Aprovada (`validate.ps1`: 36 Lua + matriz legacy/guest/public/gang/job/duty/disabled) | Aprovada em runtime | 2026-07-13 | Responsável confirmou a implementação funcional; evaluator único, políticas por recurso, sessões/guest, contratos de stash/wardrobe/garage e UX E/G preservados |
| 4 — Comércio | Concluída | `005_property_commerce.sql` | Aprovada após auditoria (`validate.ps1`: 38 Lua + elegibilidade/normalização/estados/CAS/refund único/recovery/chaves/schema/API) | Aprovada em runtime | 2026-07-13 | Runtime final aprovado após a auditoria: API pública, compra E, callback canônico, banco, owner, venda desativada, estados/compensação e UX preservada; sem Fase 5 ou IPTU |
| 5 — Apartamentos | Concluída | Não necessária (`building_json.unitDefaults`) | Aprovada (`validate.ps1`: 39 Lua + defaults/lote transacional/idempotência/bulk/interfone/locks) | Aprovada em runtime | 2026-07-13 | Responsável confirmou a fase funcional: prédio agrupador sem owner/venda, unidades independentes, defaults copiados, lotes/interfone e locks por unidade preservados |
| 6 — IPTU | Concluída | `006_property_tax.sql` | Aprovada após auditoria (`validate.ps1`: 40 Lua + schema/ordem/elegibilidade/init idempotente/owner-cycle/complete atômico/prova de CAS/refund único/recovery/paginação/isolamento fiscal) | Aprovada em runtime | 2026-07-13 | Responsável confirmou novamente o runtime após a auditoria: ciclo, pagamento/refund, recovery, status fiscal e regressão aprovados; sem retomada automática |
| 7 — Consolidação | Concluída | Não necessária; SQL opcional separado | Aprovada (`validate.ps1`: 41 Lua + manifest/migrations/payload/wizard/mz_realestate/docs) | Aprovada em runtime | 2026-07-13 | Responsável confirmou o runtime final: wizard manual, auditoria não destrutiva, bloqueios, persistência e regressão das Fases 0 a 6 aprovados; pasta `mz_realestate` preservada até auditoria externa |
| 8 — Painel do proprietário | Implementada — aguardando runtime | Não necessária | Aprovada (`validate.ps1`: 43 Lua + manifest/payload/contratos `/house`/segurança/mz_realestate) | Checklist de 30 casos pendente | 2026-07-13 | `/house` e `/houses`; owner e keyed separados; IPTU da Fase 6; chaves access/control com proximidade, tokens, limite e lock; porta/comércio/features somente leitura; sem revenda, transferência ou aluguel |

Status permitidos:

```text
Pendente
Em implementação
Implementada — aguardando runtime
Corrigida — aguardando novo runtime
Concluída
Bloqueada
```

---

## 24. Formato obrigatório do relatório de cada fase

1. Diagnóstico real encontrado.
2. Decisões adotadas.
3. Arquivos criados.
4. Arquivos alterados.
5. Migration criada.
6. Contratos externos encontrados.
7. Exports/eventos adicionados ou alterados.
8. Compatibilidade mantida.
9. Testes estáticos executados.
10. Checklist runtime.
11. Riscos e pendências.
12. Atualização deste MD.
13. Declaração explícita de que não avançou para a próxima fase.

---

## 25. Primeira execução recomendada

Começar pela **Fase 0**.

Prompt sugerido:

```text
Leia integralmente:
D:\git-hub\repo_oficial\mz_houses\docs\UNIVERSAL_PROPERTIES_PLAN.md

Implemente somente a Fase 0 — Estabilização e invariantes multiusuário.

Inspecione os arquivos reais de mz_houses e mz_interiors. Não use Git/histórico.
Valide a divergência entre o bucket compartilhado do mz_houses e o getSpawnBase
por PlayerId/jitter do mz_interiors. Corrija de forma compatível para que todos
os jogadores da mesma propriedade criem o shell na mesma origem lógica, sem
quebrar preview, debug, spawn custom ou pontos internos.

Não implemente gang, job, portas, compra ou IPTU nesta execução.
Atualize o controle de execução do plano e entregue relatório completo.
```

Depois do runtime da Fase 0, executar a Fase 1.
