# mz_houses

Sistema administrativo e autoritativo de propriedades do MZ Core.

- Staff abre `/mzhouses` com ACE `group.mz_owner`.
- Jogadores abrem `/house` (alias `/houses`) para consultar propriedades
  proprias, IPTU, chaves, porta, localizacao e imoveis em que possuem chave.
- A entrada usa `access_json`: owner/chaves, regras de gang/job, publico ou admin.
- A porta usa `door_json`: `locked`, `unlocked` ou `blocked`, com estado
  persistente e sincronizado pelo servidor.
- Chaves `access` entram; chaves `control` também podem trancar/destrancar. O
  papel legado `key` é lido como `access`.
- Imoveis residenciais antigos sem `access_json` preservam owner/chaves por fallback.
- `public` controla visibilidade, nunca acesso.
- `mz_interiors` fornece o catalogo e cria shells locais.
- `mz_houses` valida proximidade/acesso e controla routing buckets.
- `mz_core` fornece identidade, gangs/jobs reais, grade/duty e o grant seguro do stash.
- `mz_inventory`, `mz_clothing` e `mz_garagem` mantem suas responsabilidades.
- Casas e unidades residenciais individuais podem usar venda `admin` ou compra
  `direct`; predios, gang/job, publico e administrativo nunca entram no comercio.
- IPTU residencial pode ser configurado para casas e unidades com owner; predios,
  gang/job, publico e administrativo nunca recebem cobranca propria.
- Nao ha aluguel, corretor, agencia, anuncio, placa, comissao ou retomada
  automatica por divida.
- Visitantes entram por uma porta `unlocked`, mas não recebem automaticamente
  acesso a baú, guarda-roupa ou garagem.
- `access_json.features` separa as permissoes de `stash`, `wardrobe` e `garage`
  com os modos `inherit`, `disabled`, `owner`, `keys`, `rules`, `public` e
  `admin`. Toda abertura e revalidada no servidor contra a sessao e o estado
  atual do jogador.
- `mz_realestate` nao e dependencia.
- O spawn interno pode usar o padrao historico do shell ou um offset local
  personalizado por propriedade, separado do ponto de saida.

Ordem minima: `ox_lib`, `oxmysql`, `mz_core`, `mz_interiors`, `mz_menu`,
`mz_inventory`, `mz_garagem`, `mz_houses`.

Consulte [docs/ADMIN_GUIDE.md](docs/ADMIN_GUIDE.md),
[docs/MIGRATION_REALESTATE.md](docs/MIGRATION_REALESTATE.md) e
[docs/TEST_PLAN.md](docs/TEST_PLAN.md). Os contratos finais estao em
[docs/API_REFERENCE.md](docs/API_REFERENCE.md) e a auditoria consolidada em
[docs/FINAL_VALIDATION_REPORT.md](docs/FINAL_VALIDATION_REPORT.md).

## Migracao e auditoria legada

`/mzhouses > Migracao / auditoria legada` converte uma propriedade somente
depois que o admin escolhe explicitamente residencia, predio, unidade, gang,
job, publico ou administrativo. O servidor monta o preview, vincula um token ao
admin por cinco minutos, exige confirmacao exata do code e rele a propriedade
antes de persistir. Alteracao concorrente, owner/chaves incompatíveis, compra,
IPTU, lote ou `manual_review` bloqueiam a aplicacao.

`listing_json` e `realestate_json` sao apenas auditados e preservados. Eles nao
ativam visibilidade, acesso ou venda. Nenhuma migracao acontece no startup ou
na leitura de casas antigas.

O export server-side `CanAccessPropertyFeature(source, houseCode, featureName)`
usa somente a sessao mantida pelo `mz_houses`; o chamador nao fornece flags de
guest, owner, chave ou grupo. Os exports de abertura seguem a mesma validacao.

## Comercio residencial

O comercio usa `sale_enabled`, `sale_mode` (`none`, `admin`, `direct`) e
`sale_price`. Em `direct`, E mostra a confirmacao de compra na entrada e o
servidor rele preço, owner, estado, saldo e elegibilidade antes de debitar o
banco. Em `admin`, a propriedade aparece com preço, mas nao aceita compra por E.

As compras usam lock por propriedade, compare-and-set do owner e historico em
`mz_house_transactions`. Uma falha apos o debito tenta restaurar a venda e
devolver o valor; falhas que nao podem ser compensadas ficam em
`manual_review`, bloqueando nova compra. Atribuir owner sem cobranca continua
como operacao administrativa separada. Os exports novos sao
`SetPropertySale(code, commerce, actorSource)` e
`PurchaseProperty(source, code)`; ambos mantem validacao server-side.

Os estados financeiros seguem transicoes condicionais: `initiated` ->
`payment_pending` -> `money_removed` -> `completed`, com saidas terminais para
`failed`, `refunded` ou `manual_review`. `completed`, `refunded` e
`manual_review` nao retrocedem. Excecao com resultado de debito ou CAS incerto
nao libera nova tentativa: a transacao fica bloqueada para revisao. O refund e
tentado no maximo uma vez por execucao e as chaves anteriores sao restauradas
atomicamente a partir de snapshot antes de qualquer rollback de owner/venda.
No restart, `initiated` vira `failed`; `payment_pending` e `money_removed` viram
`manual_review`; estados terminais permanecem inalterados. `CommerceDebug` fica
desligado por padrao e pode ser ativado temporariamente para diagnostico.

## Predios e unidades em lote

O registro do predio continua sendo apenas agrupador, entrada, porta e
interfone. Ele nao recebe owner nem venda propria. Os defaults para futuras
unidades ficam em `building_json.unitDefaults` com venda, modo, preco, shell,
interior, features e configuracao inicial de IPTU. Cada unidade recebe uma copia
no momento da criacao;
alterar o default depois nao recalcula nem altera unidades existentes.

A criacao em lote usa codigos deterministas `apt_<numero_do_predio>_<unidade>`,
preview server-side, token temporario e uma unica transacao SQL. Repetir um lote
ja existente nao cria duplicatas. Operacoes comerciais em lote produzem
resultado item a item e ignoram owner, protecao administrativa, unidade
inativa, compra em andamento ou transacao financeira ambigua. Nao existe filtro
por andar porque o schema atual nao possui campo explicito de andar.

A compra pelo interfone envia somente `buildingCode` e `unitCode`. O servidor
valida proximidade da entrada persistida, interfone, porta do predio e vinculo
da unidade antes de reutilizar `MZHousesCommerce.purchase`. Saldo, CAS, lock,
refund, recovery e maquina financeira permanecem na implementacao da Fase 4.

## IPTU residencial

O IPTU usa campos proprios `tax_*` e os estados `disabled`, `paid`, `due`,
`overdue` e `blocked`. O estado fiscal `blocked` e apenas administrativo: nao
altera `door_json`, nao remove owner/chaves, nao impede saida e nao apaga
recursos. Predios guardam apenas defaults para unidades futuras; cada unidade
recebe uma copia independente na criacao.

O owner consulta e paga pelo comando `/iptu`. O client envia somente o codigo
da propriedade; o servidor rele owner, valor, vencimento e saldo bancario. O
pagamento usa lock por propriedade, historico em `mz_house_tax_payments`, avanco
condicional do vencimento e refund protegido quando a atualizacao fiscal falha.
Estados financeiros ambiguos ficam em `manual_review` e bloqueiam nova tentativa.

O processamento fiscal e global, paginado e tolerante a restart, com verificacao
lazy ao consultar/pagar e uma passagem horaria. Nao existe thread por
propriedade nem retomada automatica. Os exports server-side sao
`GetPropertyTaxStatus`, `PayPropertyTax` e `ConfigurePropertyTax`.

A auditoria final tornou a inicializacao do ciclo idempotente e uniu em uma
unica query o CAS do vencimento com `money_removed -> completed`. Em perda de
resposta, o servidor rele pagamento/owner/ciclo antes de decidir: sucesso
comprovado e recuperado, refund somente com ciclo comprovadamente inalterado ou
`manual_review` quando houver ambiguidade. Revisoes do owner anterior continuam
no historico, mas nao bloqueiam financeiramente o owner atual.

## Painel do proprietario - `/house`

O painel do jogador separa `Meus imoveis` de `Imoveis com chave`. A primeira
lista inclui somente casa ou unidade residencial ativa cujo owner atual e o
jogador; predio, gang, job, publico, administrativo, guest e acesso por regra
nao viram propriedade pessoal. A segunda lista e somente leitura.

O owner consulta resumo, recursos, porta, comercio e IPTU, marca a entrada no
mapa e gerencia chaves `access`/`control`. A entrega exige alvo online proximo,
distancia server-side e limite configuravel. A revogacao aceita jogador offline
e usa token efemero no client, sem publicar citizenid. Quem ja estiver dentro
nao e expulso; a proxima entrada, feature ou tentativa de controle e revalidada.

O painel nao altera porta, comercio, owner, preco, shell, interior ou features.
O pagamento fiscal chama o mesmo `MZHousesTax` e o mesmo callback da Fase 6;
`/iptu` permanece disponivel. Apartamentos marcam a entrada publica do predio e
mostram o numero da unidade, sem enviar coordenadas internas.
