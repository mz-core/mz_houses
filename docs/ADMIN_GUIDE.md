# Guia administrativo

## Permissao

O servidor valida `group.mz_owner` em toda callback e mutacao administrativa.
Exemplo de `server.cfg`:

```cfg
add_principal identifier.license:SUA_LICENSE group.mz_owner
add_ace group.mz_owner group.mz_owner allow
```

## Painel

Use `/mzhouses` (alias legado: `/mhouse_admin`). O painel permite criar casas,
predios/unidades, pesquisar por codigo/nome/owner/categoria/status, editar
entrada/shell/pontos internos/garagem, definir owner, gerenciar chaves,
teleportar, ativar, desativar, arquivar e recarregar o cache.

## Templates e politica de acesso

`Criar imovel` oferece casa, predio, unidade, sede de gang, sede de job,
interior publico e interior administrativo. Gang e job sao selecionados da
lista real do `mz_core`; texto livre nao e usado como autoridade. A grade
minima e validada no servidor e jobs podem exigir `duty`.

Em `Politica de acesso`, regras adicionais de gang/job sao combinadas com
`match=any` (OR). O servidor valida novamente tipo, code, grade e duty antes de
persistir. `public` continua controlando visibilidade; o modo `public` de
`access_json` controla autorizacao. Tipos universais nao recebem venda ou IPTU.

Registros residenciais antigos com `access_json=NULL` continuam usando
owner/chaves. Registros legados de org/business/government continuam bloqueados
ate uma politica universal valida ser salva explicitamente pela administracao.

## Migracao manual de propriedades legadas

Abra `Migracao / auditoria legada` no menu principal ou `Migrar propriedade
legada` no detalhe do imovel. Escolha explicitamente um destino: residencia,
predio, unidade, gang, job, publico ou administrativo. Gang/job usam grupos
reais; unidade exige predio canonico e numero ainda livre.

O preview mostra category/subtype/owner type, policy, porta e visibilidade antes
e depois. Para aplicar, confirme o alerta e digite exatamente o code. O token
expira em cinco minutos e a propriedade e relida; qualquer alteracao desde o
preview cancela a operacao.

Owner e chaves devem ser removidos pelo menu normal antes de migrar para predio,
gang, job, publico ou administrativo. Isso evita apagar relacoes silenciosamente.
Transacao de compra/IPTU, `manual_review`, lock de lote ou mutacao concorrente
tambem bloqueiam a migracao. Nao apague historico para contornar a barreira.

A auditoria de `listing_json`/`realestate_json` retorna apenas contagens, estados
e codes de amostra; nao publica o JSON e nao altera nada. Esses campos sao
preservados e nao controlam o runtime.

## Recursos e permissoes

No detalhe da propriedade, `Recursos e permissoes` configura separadamente
baú, guarda-roupa e garagem. As opções são: herdar a política de entrada,
desativar, somente owner, owner/chaves, regras próprias de gang/job, público
dentro da propriedade ou somente admin. Regras próprias usam `match=any`,
grupos reais do `mz_core`, grade mínima e `requireDuty` para jobs. O painel
exibe um resumo e pede confirmação antes de salvar.

`disabled` desativa o recurso inclusive para admin. `public` é a única política
de recurso que permite uso por um guest que entrou por porta destrancada. Nos
demais modos, a sessão guest é bloqueada. Casas residenciais antigas continuam
com `inherit`: owner e chaves mantêm o comportamento anterior sem regravação
automática. Interiores públicos e administrativos nascem com recursos físicos
desligados; habilitá-los exige configuração explícita.

Ocultar uma interação no client é apenas UX. Stash e wardrobe exigem sessão
interna confirmada do mesmo código; garagem externa também exige proximidade do
ponto correto. O servidor revalida owner, chave, gang/job, grade e duty em cada
abertura e não aceita `isGuest` ou código de sessão enviado pelo client.

Para criar uma casa: fique na entrada, abra o painel, opcionalmente use
`Pre-visualizar interior`, escolha `Criar imovel > Casa comum`, selecione o
shell e confirme. A casa nasce como `draft`, privada e sem owner. Abra os
detalhes, entre para manutencao e capture saida, bau e guarda-roupa. Ative-a
somente ao terminar.

Para entregar a casa: `Dono / Chaves > Setar dono por citizenid` ou
`Setar dono por ID online`. O servidor resolve o citizenid quando recebe um ID
online. Remover owner/chave invalida o acesso imediatamente. Limpar todas as
chaves e arquivar exigem digitar o codigo da propriedade.

## Portas e tipos de chave

No detalhe da propriedade, `Estado da porta` permite ao administrador definir
`locked`, `unlocked` ou `blocked`. Owner, chave `control` e membros de gang/job
que alcancem `canControlDoorFromGrade` podem trancar ou destrancar no ponto de
entrada. Chave `access` entra quando a porta está trancada, mas não a controla.

`unlocked` permite entrada como visitante. Essa sessão não concede
automaticamente baú, guarda-roupa ou garagem. `blocked` aceita somente admin e
só pode ser aplicado ou removido por admin. O estado é persistido em
`door_json`; o papel legado `key` é normalizado como `access` na leitura.

O campo antigo em `Metadata administrativa` continua apenas informativo e nao
ativa venda. O preço autoritativo fica em `Comercio residencial`.

## Comercio residencial

Somente `house` e `apartment_unit` residenciais com politica owner podem ser
vendidas. A propriedade deve estar ativa, sem owner, com preço maior que zero.
Predio, gang, job, interior publico e administrativo sao rejeitados no servidor.

Na criacao de casa ou unidade individual, informe modo, preço real e se a venda
ficara disponivel. No detalhe da propriedade, `Comercio residencial` permite:

- ativar, editar ou retirar a venda;
- escolher `admin` ou `direct`;
- vender e cobrar um jogador online pelo banco;
- consultar o historico persistente;
- abrir `Dono / Chaves` para atribuicao sem cobranca, em fluxo separado.

Em `direct`, E na entrada abre uma confirmacao com nome e preço. O client envia
somente o codigo; o servidor rele o preço e a disponibilidade. Em `admin`, a
entrada mostra que esta à venda, mas E nao compra. Depois de uma compra, o owner
e atualizado, as chaves antigas sao limpas e a venda e desativada sem alterar o
estado da porta ou as politicas de recurso.

A cobranca administrativa exige comprador online porque os exports financeiros
reais do `mz_core` trabalham com `source`. Para um citizenid offline, use apenas
a atribuicao sem cobranca. Remover owner nunca reativa a venda automaticamente.

Estados `manual_review` em `mz_house_transactions` exigem auditoria do saldo e
do owner antes de qualquer ajuste manual; enquanto existirem, uma nova compra
da propriedade e bloqueada.

Tambem trate `payment_pending` e `money_removed` como estados bloqueantes. No
restart, o sistema nao cobra nem atribui owner automaticamente: `initiated`
sem debito vira `failed`, enquanto estados que podem ter movimentacao financeira
viram `manual_review`. Confira banco, owner, venda e historico antes de qualquer
correcao manual; nao apague a transacao para liberar uma nova tentativa.

Se uma falha ocorrer depois da limpeza das chaves, o fluxo restaura em uma
transacao unica o snapshot com citizenid, role legado (`key`), `access`,
`control` e data de criacao antes de reabrir a venda e devolver o dinheiro. Se
essa restauracao nao puder ser comprovada, owner/venda permanecem no estado
seguro e a transacao fica em `manual_review`. `CommerceDebug=false` e o padrao;
ative-o apenas durante diagnostico para evitar spam no console.

## Predios, defaults e lotes de unidades

No detalhe de um `apartment_building`, abra `Unidades do predio`. O menu oferece:

- `Defaults de novas unidades`: venda, modo, preco, shell e configuracao fiscal;
- `Copiar shell/interior de unidade modelo`: copia tambem as features somente
  para o modelo de futuras unidades;
- `Criar unidades em lote`: informe numeros separados por virgula, revise o
  plano e confirme a transacao all-or-nothing;
- `Operacoes comerciais em lote`: informe explicitamente os codes e revise
  elegiveis/ignorados antes da confirmacao forte.

Os defaults ficam em `building_json.unitDefaults`. Eles nunca usam as colunas
`sale_*`/`tax_*` do predio como estado proprio e nunca alteram unidades
existentes. Cada unidade continua
com owner, chaves, porta, `access_json`, interior, recursos e comercio
independentes. Repetir um lote completo ja criado retorna idempotencia sem
inserir duplicatas; conflito parcial precisa ser resolvido manualmente e nada e
sobrescrito.

Lotes comerciais ignoram unidades com owner, `payment_pending`,
`money_removed`, `manual_review`, compra/edicao em andamento, estado inativo ou
`Protecao contra lote comercial`. O resultado e item a item: itens ignorados
nao sao alterados. Edicao por andar nao foi disponibilizada porque nao existe
campo explicito e confiavel de andar no schema atual.

No interfone, unidade `direct` pode ser comprada; `admin` aparece apenas com
status/preco. O servidor valida a distancia da entrada do predio e o vinculo da
unidade. O payload nao inclui owner, citizenid, chaves, access rules ou dados
financeiros. A compra usa exatamente o fluxo financeiro da Fase 4.

## IPTU residencial

No detalhe de uma casa ou unidade residencial, abra `IPTU`. O menu permite
consultar valor, vencimento, tolerancia, estado e historico, alem de configurar,
ajustar vencimento e aplicar um estado administrativo. A configuracao aceita
ativacao, valor, intervalo e grace period. Se ja existir owner, a inicializacao
do primeiro vencimento exige uma escolha explicita; atribuir owner manualmente
nao gera cobranca retroativa por padrao.

Somente `house` e `apartment_unit`/`apartment` residenciais com owner sao
elegiveis. Predio, gang, job, publico, administrativo, arquivado ou sem owner
nao pagam. Ao remover owner, a cobranca corrente e suspensa, mas o historico e
preservado. Um comprador novo recebe um novo ciclo e nao herda o vencimento do
owner anterior.

O owner usa `/iptu` para listar e pagar. O pagamento e sempre validado no
servidor e usa o banco; valor, owner, datas e status nunca sao aceitos do client.
Tentativa simultanea usa lock por propriedade. Se o dinheiro sair e o vencimento
nao puder ser atualizado, o sistema tenta refund; resultado ambiguo permanece em
`manual_review` e deve ser auditado, sem apagar a linha de pagamento.

`tax_status=blocked` nao significa `door_json.state=blocked`. O bloqueio fiscal
nao tranca porta, nao remove owner/chaves, nao impede saida, nao desativa stash e
nao executa retomada automatica. O processamento horario apenas atualiza
`paid`/`due`/`overdue`, preservando `blocked` quando definido pelo admin.

No detalhe de um predio, os defaults fiscais servem somente para unidades
criadas depois da alteracao. Unidades existentes mantem valor, intervalo,
tolerancia e vencimento independentes.

Depois da auditoria, uma inicializacao repetida do mesmo owner/ciclo e
idempotente: ela nao empurra o vencimento para frente. Para mudar uma data ja
inicializada use `Ajustar vencimento`. Ao trocar o owner, pagamentos
`manual_review` antigos continuam no historico administrativo, mas nao bloqueiam
o ciclo novo.

O CAS do vencimento e o status `completed` do pagamento sao gravados na mesma
query. Se a resposta do banco/SQL for perdida, nao resolva apagando a linha: o
servidor tenta provar o resultado por releitura. Somente ciclo comprovadamente
inalterado recebe refund; estado incerto permanece em `manual_review`.

## Spawn interno de entrada

Entre na propriedade para manutencao ou abra um preview do mesmo shell. Em
`Interior / Pontos Internos` use `Definir spawn de entrada aqui`, confira o
offset e heading relativos e confirme. `Ir ate o spawn de entrada` visualiza o
ponto ativo; `Ir ate o spawn padrao do shell` permite comparar sem alterar.

`Restaurar spawn padrao` volta ao comportamento historico. O menu tambem copia
spawn para saida ou saida para spawn. Os dois campos continuam independentes:
spawn define onde o ped aparece; saida define apenas onde aparece a interacao
para retornar a entrada externa.

Formato persistido em `interior_json`:

```json
{
  "entrySpawn": {
    "mode": "custom",
    "coords": { "x": 1.2, "y": -3.4, "z": 0.1 },
    "heading": 180.0,
    "relative": true
  },
  "exit": {
    "enabled": true,
    "coords": { "x": 1.2, "y": -3.4, "z": 0.1 },
    "heading": 180.0,
    "relative": true
  }
}
```

Casas sem `entrySpawn` usam implicitamente `mode=default` e nao sao regravadas
apenas por serem carregadas.

## Painel do proprietario - `/house`

O painel pessoal e separado do `/mzhouses`. Ele nao usa ACE administrativo e
mostra como propriedade propria somente `house`, `apartment` ou
`apartment_unit` residencial, ativa, nao arquivada, com `ownerType=player` e
owner igual ao jogador. Predios, gang/job, publico, administrativo, regras e
guest ficam fora. Uma chave aparece em `Imoveis com chave`, sem poderes de owner.

Configuracao em `shared/config.lua`:

```lua
MZHousesConfig.PlayerPanel = {
  enabled = true,
  command = 'house',
  aliases = { 'houses' },
  nearbyPlayerDistance = 3.0,
  maxKeysPerProperty = 10,
  rateLimitMs = 1000
}
```

Nao havia conflito de `/house` no workspace durante a implementacao. O client
tambem consulta os comandos registrados em runtime e nao sobrescreve um comando
ja existente; altere `command`/`aliases` se outro resource do deploy o ocupar.

Para entregar chave, o owner escolhe um jogador online dentro da distancia,
seleciona `access` ou `control` e confirma. `control` recebe aviso forte porque
permite usar G presencialmente. O servidor rele owner, propriedade, target,
citizenid, distancia, role, chave existente e limite sob lock por propriedade.
Para revogar, o menu usa token temporario e nunca envia citizenid ao client.
Revogacao offline funciona; uma pessoa que ja esteja dentro nao e teleportada
nem impedida de sair.

Porta, comercio e features sao somente leitura. A localizacao cria waypoint na
entrada publica; apartamento usa a entrada do predio. IPTU reutiliza o servico
e o pagamento da Fase 6, e `/iptu` continua registrado.
