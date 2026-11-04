# Plano de teste administrativo

## Fase 0 — invariantes multiusuario

Validacao estatica executada em 2026-07-12:

- [x] `spawnBase` explicita retorna a coordenada exata, sem `PlayerId`, `SpawnSpacing` ou jitter.
- [x] Entradas locais/debug sem `spawnBase` preservam o espalhamento legado do `mz_interiors`.
- [x] Casa e preview continuam fornecendo `MZHousesConfig.InteriorSpawnBase` ao `EnterShell`.
- [x] Bucket de casa continua compartilhado por `houseCode`; preview continua em bucket exclusivo por source.
- [x] Casa e preview sao mutuamente exclusivos no servidor.
- [x] Cleanup de casa limpa sessao, state bag e bucket; cleanup de preview limpa state bag e bucket.
- [x] Parada de `mz_interiors` aciona cleanup server-side de casas e previews.
- [x] Validador: 33 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.

Checklist runtime aprovado no servidor FiveM em 2026-07-12:

- [x] Dois jogadores na mesma propriedade compartilham o mesmo interior.
- [x] Propriedades diferentes no mesmo shell permanecem isoladas.
- [x] Spawn e pontos internos permanecem corretos.
- [x] Restart de `mz_interiors` e `mz_houses` executa cleanup.
- [x] Entrada, saida e preview funcionam apos a revisao de rollback.

## Fase 1 — tipos universais e politicas de acesso

Validacao estatica:

- [x] Migration incremental `003_universal_access.sql` adiciona somente `access_json` nullable.
- [x] Repository distingue politica persistida de fallback e nao grava casas antigas ao carregar.
- [x] Adapter usa os exports reais `ListOrgs`, `GetOrgByCode` e `GetPlayerOrgs` do `mz_core`.
- [x] Evaluator unico suporta owner, rules/match any, public, admin e none.
- [x] Politicas e regras enviadas pelo client sao normalizadas e validadas no servidor.
- [x] `public` permanece separado da politica de autorizacao.
- [x] Nenhuma coluna/evento de porta, comercio ou IPTU foi adicionado.

Checklist runtime obrigatorio antes de concluir a Fase 1:

- [ ] Casa antiga com `access_json=NULL`: owner e chave entram como antes.
- [ ] Gang correta entra; gang diferente e jogador sem membership sao bloqueados.
- [ ] Grade igual/acima entra e grade abaixo recebe negacao.
- [ ] Job correto entra; `requireDuty=true` bloqueia off-duty e permite on-duty.
- [ ] Duas ou mais regras com `match=any` permitem qualquer regra valida.
- [ ] Interior publico aparece conforme visibilidade e entra sem owner/chave.
- [ ] Interior administrativo aceita admin e bloqueia jogador comum.
- [ ] Org/business/government legado sem politica continua bloqueado.
- [ ] Salvar politica valida em legado libera somente a audiencia configurada.
- [ ] Stash, wardrobe e garagem habilitados herdam a entrada nesta fase.
- [ ] Restart preserva `access_json` e os templates criados.

## Fase 2 — portas e chaves avancadas

Aprovacao runtime registrada em 2026-07-13: o responsavel confirmou a
implementacao funcional no servidor. Os itens detalhados abaixo permanecem como
roteiro de regressao para futuras alteracoes.

Validacao estatica executada em 2026-07-12:

- [x] Migration incremental `004_property_doors.sql` adiciona somente `door_json` nullable e possui rollback manual.
- [x] `door_json` aceita somente `locked`, `unlocked` e `blocked`; estados invalidos enviados pelo client sao rejeitados no servidor.
- [x] Cache preserva os papeis `access`/`control` e converte o papel legado `key` para `access` na leitura.
- [x] Matriz estatica aprovou owner, access key, control key, grade de gang, visitante `unlocked`, legado e `blocked` administrativo.
- [x] Porta `unlocked` torna visivel somente a interacao de entrada; nao publica listagem nem garagem.
- [x] Sessao `public_unlocked` e marcada como guest e stash, wardrobe e garagem sao negados no servidor.
- [x] Mudanca persiste `door_json`, atualiza cache, sincroniza apenas code/state e registra logs de porta/chave.
- [x] `mz_houses` não registra command/key mapping global para G; o controle 47 é lido somente no raio contextual da porta.
- [x] G só é desabilitado a pé, próximo e com `canControl=true`; em veículo, longe ou sem controle não há callback, notify ou consumo do input.
- [x] Toggle usa animação `anim@mp_player_intmenu@key_fob@`/`fob_click`, busy local e cooldown de 1000 ms.
- [x] Contexto client de porta usa cache de 1 segundo; o callback não é chamado a cada frame.
- [x] Evento de sincronização atualiza cache, propriedade visível e `CurrentHouse.data.doorState` imediatamente.
- [x] `mz_interact` atualiza somente o ponto afetado reutilizando o mesmo id; fallback não cria marcador adicional para G.
- [x] Proximidade externa usa a entrada do código visível mais próximo; proximidade interna usa exatamente o ponto efetivo de saída.
- [x] Matriz real separa `CanSeeHouse` de `CanEnterHouse`: visibilidade pública não concede entrada com porta trancada.
- [x] Entrada visível para autorizado, porta `unlocked`, flag/modo público e interior público; administrativo permanece exclusivo de admin.
- [x] Gang/job restrito permanece oculto para não autorizado; flag/modo público torna apenas a entrada visível.
- [x] Residência vazia continua oculta por padrão; gancho somente de leitura reconhece futuro `sale_enabled=true` sem implementar comércio.
- [x] `doorStateChanged` invalida/recarrega o cache visível e reconcilia a interação afetada sem refresh server duplicado.
- [x] Validador: 36 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.
- [x] Migration e servico de portas nao adicionam comercio, compra ou IPTU.

Checklist runtime obrigatorio antes de concluir a Fase 2:

- [ ] Owner tranca e destranca no ponto externo e o estado sincroniza para dois jogadores.
- [ ] Chave `access` entra com `locked`, mas nao recebe acao de controle.
- [ ] Chave `control` entra, tranca e destranca; troca de role sobrevive ao restart.
- [ ] Papel legado `key` continua entrando e aparece como `access` no painel.
- [ ] Gang/job na grade configurada controla; grade baixa entra pela regra, mas nao controla.
- [ ] Job com `requireDuty=true` nao controla off-duty e controla on-duty quando tambem alcanca a grade.
- [ ] Jogador sem politica/chave entra como guest apenas com `unlocked`.
- [ ] Guest entra e sai, mas nao abre bau, guarda-roupa nem garagem.
- [ ] `blocked` bloqueia owner, chaves, gang/job e visitante; admin entra e pode remover o bloqueio.
- [ ] Restart de `mz_houses` preserva o ultimo estado persistido da porta.
- [ ] Trancar a porta nao expulsa quem ja esta dentro.
- [ ] Duas propriedades com o mesmo shell mantem estados e buckets independentes.
- [ ] Owner fora vê `[E] Entrar | Porta: Trancada | [G] Destrancar` e G alterna o texto imediatamente.
- [ ] Dentro, o texto de saída mostra estado/ação e G funciona somente próximo do ponto efetivo de saída.
- [ ] G longe de qualquer entrada/saída não chama callback, não mostra notify e continua disponível ao cinto.
- [ ] Em veículo próximo da entrada, G controla somente o cinto; ação de porta não aparece e input não é consumido.
- [ ] A pé e com controle, G toca `fob_click` e altera a porta; animação ocorre somente no jogador que acionou.
- [ ] Sem controle, G não aparece, não é desabilitado e não gera notify.
- [ ] Spam de G executa somente uma animação/mutação durante o busy/cooldown.
- [ ] `mz_interact` ativo atualiza o label do mesmo ponto sem duplicar marcador.
- [ ] Fallback marker mostra o mesmo estado/ação e E/G continuam independentes.
- [ ] Prédio usa E para interfone e G para o código do prédio; dentro da unidade, G usa o código da unidade.
- [ ] `blocked` aparece como `Interditada` e não oferece toggle comum.
- [ ] Restart não recria command/key mapping de porta; `Interaction.key` continua sendo fallback apenas de E.
- [ ] Casa com owner, `public=true` e porta locked aparece a jogador comum, mas E recebe negação server-side.
- [ ] Gang/job `visible=false` locked fica oculto; `visible=true` aparece, mas não permite entrada sem regra.
- [ ] Alternar locked/unlocked adiciona/remove imediatamente a interação para um jogador sem acesso.
- [ ] Interior administrativo não aparece para jogador comum mesmo se porta/visibility forem alterados; admin continua vendo.
- [ ] Casa vazia locked e privada não aparece automaticamente.

## Fase 3 — permissoes por recurso

Aprovacao runtime registrada em 2026-07-13: o responsavel confirmou que a
implementacao da Fase 3 esta funcional no servidor FiveM. Os itens detalhados
abaixo permanecem como roteiro de regressao para alteracoes futuras.

Validacao estatica executada em 2026-07-13:

- [x] `access_json.features` normaliza `stash`, `wardrobe` e `garage` nos modos `inherit`, `disabled`, `owner`, `keys`, `rules`, `public` e `admin`.
- [x] Formato legado `{ "inherit": true }` continua sendo lido como `mode=inherit`; `none` de recurso e normalizado para `admin`.
- [x] Um evaluator server-side unico valida player, propriedade ativa, feature fisica, sessao confirmada e politica atual.
- [x] Stash e wardrobe exigem sessao interna do mesmo codigo; garagem externa exige proximidade server-side de `entry`/`store`.
- [x] Callbacks de abertura possuem rate limit separado e nao aceitam flags de owner, key, grupo ou guest do client.
- [x] Matriz Lua aprovou fallback residencial owner/chave, guest negado, `public` explicito, gang por grade, job por grade/duty e `disabled`.
- [x] Entrada `public_unlocked` revalida a relação normal: owner/chave/gang/job autorizados não são classificados como guest; somente o visitante dependente da porta aberta recebe `isGuest=true`.
- [x] Payload de UX contem somente booleans autorizados por recurso; a politica completa permanece no payload administrativo.
- [x] Menu `Recursos e permissoes` usa grupos reais, `match=any`, grade, duty, resumo e confirmacao.
- [x] Stash ID e contratos existentes de `mz_core`/`mz_inventory`, `mz_clothing` e `mz_garagem` foram preservados.
- [x] Nenhuma migration foi criada e nenhum fluxo de porta, comercio, compra ou IPTU foi alterado.
- [x] Validador: 36 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.

Checklist runtime aprovado; manter como roteiro de regressao da Fase 3:

- [ ] Casa antiga: owner usa stash, wardrobe e garagem; chave mantém o comportamento legado.
- [ ] Guest entra por `unlocked`, mas não usa stash, wardrobe ou garagem em `inherit`.
- [ ] Owner usa os três recursos em `inherit`; chave `access` segue o default residencial.
- [ ] Gang grade 0 entra; stash com regra grade 2 bloqueia grade 0 e permite grade 2.
- [ ] Job entra na grade 0; wardrobe grade 1 com duty bloqueia off-duty e permite on-duty.
- [ ] `disabled` remove a interação conhecida pelo client e bloqueia evento manual.
- [ ] `public` explícito permite ao guest somente o recurso configurado.
- [ ] Código de outra propriedade não abre stash, wardrobe ou garagem.
- [ ] Sair e voltar invalida a sessão anterior; tentativa forjada após saída é negada.
- [ ] Remover chave ou membership durante a sessão bloqueia a tentativa seguinte.
- [ ] Restart preserva as políticas e mantém os defaults de propriedades antigas.
- [ ] E e G mantêm exatamente a UX aprovada da Fase 2.
- [ ] Dois jogadores na mesma propriedade têm as políticas avaliadas individualmente.

## Fase 4 — comercio residencial

Runtime principal aprovado em 2026-07-13. A auditoria final encontrou defeitos
funcionais nos caminhos de falha/compensacao e aplicou correcoes. A regressao
posterior foi aprovada pelo responsavel no servidor FiveM; status final:
**Fase 4 — Concluida e aprovada em runtime**.

Runtime aprovado antes da auditoria:

- [x] API publica `MZHousesCommerce` carregada sem erro `nil`.
- [x] Compra direta acionada por E na entrada.
- [x] Callback retornando contrato canonico.
- [x] Compra com saldo bancario, owner definido e venda desativada.
- [x] E, G, animacao de chave, porta e recursos preservados.

Validacao estatica:

- [x] Migration incremental `005_property_commerce.sql` adiciona campos comerciais e tabela de transacoes sem apagar dados.
- [x] `sale_enabled`, `sale_mode` e `sale_price` sao colunas autoritativas; metadata antiga nao ativa venda.
- [x] Elegibilidade server-side aceita somente casa/unidade residencial individual, ativa, owner policy e sem owner.
- [x] Predio, gang, job, publico, administrativo, desativado, arquivado e preço zero sao rejeitados.
- [x] Payload publico contem somente estado/modo/preço comercial necessario; nao inclui access policy, chaves ou owner privado.
- [x] `CanSeeHouse` reconhece residencia ativa à venda sem transformar visibilidade em autorizacao de entrada.
- [x] Compra direta envia somente `houseCode`; preço, modo, owner, citizenid e saldo sao relidos no servidor.
- [x] Lock em memoria e compare-and-set no banco impedem dois owners para a mesma venda.
- [x] Debito usa `GetMoney`/`RemoveMoney` e compensacao usa `AddMoney`, todos contratos reais do `mz_economy`.
- [x] Falha depois do debito executa rollback/refund; impossibilidade de compensacao vira `manual_review` e bloqueia nova compra.
- [x] Owner por compra desativa venda e limpa chaves antigas; remover owner nao reativa venda.
- [x] Venda administrativa cobrada exige comprador online e permanece separada da atribuicao sem cobranca.
- [x] E compra em `direct`, E abre interfone no predio, E entra na propriedade normal e G continua exclusivo da porta.
- [x] Callback de compra possui barreira de excecao externa e sempre responde contrato canonico `{ok, reason/message}` ou `{ok, houseCode, transactionId, message}`.
- [x] `payment_pending`, `money_removed` e `manual_review` bloqueiam nova tentativa imediatamente, sem depender de restart.
- [x] Transicoes de estado usam compare-and-set por status anterior; `completed`, `refunded`, `failed` e `manual_review` sao terminais.
- [x] Excecao no export de debito vira `manual_review`, pois o resultado financeiro e ambiguo.
- [x] Excecao de retorno do CAS rele o owner: compensa somente quando o resultado pode ser provado; duvida vira `manual_review` sem refund automatico.
- [x] Snapshot de chaves e restaurado atomicamente, incluindo roles `key`/`access`/`control` e `created_at`, antes do rollback de owner/venda.
- [x] Refund possui guarda de tentativa unica; falha ou resultado persistente ambiguo continua bloqueando a propriedade.
- [x] Recovery: `initiated` vira `failed`; `payment_pending`/`money_removed` viram `manual_review`; estados terminais nao mudam.
- [x] Logs temporarios controlados por `CommerceDebug` registram somente estagio, source, code, transactionId, status e motivo.
- [x] `CommerceDebug=false` por padrao; logs de erro permanecem ativos.
- [x] `MZHousesCommerce` e uma unica tabela global; `commerce.lua` carrega antes de `main.lua`/`admin_menu.lua`, que validam `purchase`, `configureSale` e recovery no startup.
- [x] Nenhum preço padrao de predio, gestao em lote ou IPTU foi implementado.
- [x] Validador: 38 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.

Checklist runtime aprovado; manter como roteiro de regressao da Fase 4:

- [ ] Criar casa e unidade individual com preço; ativar a propriedade e confirmar persistencia apos restart.
- [ ] Tentar `direct` com preço zero e confirmar rejeicao server-side.
- [ ] Casa `direct`, ativa e sem owner aparece para dois jogadores com `[E] Comprar` e o preço correto.
- [ ] Casa `admin` mostra preço, mas E nao inicia compra direta.
- [ ] Saldo insuficiente nao altera saldo, owner, chaves ou estado da venda.
- [ ] Saldo suficiente debita banco, atribui owner, limpa chaves antigas e desativa venda.
- [ ] O novo owner entra e usa recursos conforme `access_json.features`; guest nao ganha recursos.
- [ ] Dois jogadores confirmando simultaneamente: somente um conclui e o outro nao e debitado; se debitado por corrida, recebe refund.
- [ ] Simular falha apos debito e confirmar `refunded`; falha de refund deve ficar `manual_review` e bloquear nova compra.
- [ ] Forjar callback com preço menor/owner/citizenid: servidor ignora campos e usa somente o codigo.
- [ ] Gang, job, publico, administrativo e predio nao podem ter venda ativada por menu, callback ou export.
- [ ] Venda administrativa cobra o banco do alvo online; atribuicao sem cobranca nao debita saldo.
- [ ] Remover owner mantem `sale_enabled=false`; admin precisa reativar explicitamente.
- [ ] Door state nao muda na compra; E/G, interfone, entrada, saida e preview continuam funcionando.
- [ ] Historico registra `initiated`, `payment_pending`, `money_removed` e `completed` ou a compensacao correspondente.
- [ ] Repetir compra com `CommerceDebug=true`: confirmar `callback_received`, etapas financeiras e `response_sent`; rejeicoes normais nunca mostram `purchase_callback_failed`.
- [ ] Simular/forcar falha do export durante `payment_pending`: confirmar `manual_review`, nenhum owner publicado e nova compra bloqueada.
- [ ] Simular perda de resposta do CAS: confirmar rollback+refund somente quando o owner do comprador for relido; sem prova, manter `manual_review` sem segundo debito.
- [ ] Simular falha na limpeza de chaves: confirmar restauracao integral de `key`/`access`/`control` antes de reabrir venda e executar refund.
- [ ] Reiniciar com transacoes `initiated`, `payment_pending`, `money_removed`, `completed` e `refunded`; confirmar a matriz de recovery sem cobranca ou owner automatico.

## Fase 5 — comercio e gestao em lote de apartamentos

Implementada e aprovada em runtime em 2026-07-13 pelo responsavel do servidor.

Validacao estatica:

- [x] Sem migration: `building_json.unitDefaults` armazena venda, modo, preco, shell, interior e features de novas unidades.
- [x] Predio permanece `ownerType=server`, sem owner e sem uso de `sale_*` como default.
- [x] Cada unidade recebe copia independente dos defaults; alterar o predio nao altera registros existentes.
- [x] Numero aceita somente `a-z`, `0-9`, `_` e `-`, com ate 30 caracteres; code e deterministico e colisao e rejeitada.
- [x] Criacao em lote valida todo o plano e usa uma unica `MySQL.transaction.await`.
- [x] Replay integral e idempotente; conflito parcial ou externo falha sem sobrescrever registros.
- [x] Preview e confirmacao usam token server-side temporario e releitura antes da persistencia.
- [x] Operacao comercial em lote usa resultado item a item, lock por unidade e releitura antes da mutacao.
- [x] Owner, protecao administrativa, estado inativo, compra ativa e `payment_pending`/`money_removed`/`manual_review` sao ignorados.
- [x] Compra pelo interfone valida distancia, predio, interfone, porta e parentCode no servidor.
- [x] Compra da unidade chama `MZHousesCommerce.purchase`; nao duplica saldo, CAS, transacao, refund ou recovery.
- [x] Payload do interfone contem somente code, numero, label, status, disponibilidade, venda/preco, acao e estado resumido da porta.
- [x] Compra nao altera porta, `access_json.features`, stash, wardrobe, garagem ou outras unidades.
- [x] Operacao por andar nao implementada: nao existe campo explicito/confiavel no schema atual.
- [x] Validador: 39 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.
- [x] Nenhum campo, tabela ou fluxo de IPTU foi criado.

Checklist runtime concluido da Fase 5:

- [x] Criar predio com defaults comerciais e confirmar que o predio nao fica vendavel/nem recebe owner.
- [x] Criar lote com varias unidades e confirmar copia independente de preco, modo, shell, interior e features.
- [x] Repetir o mesmo lote e confirmar zero duplicatas.
- [x] Forcar falha SQL em uma unidade e confirmar rollback do lote inteiro.
- [x] Alterar defaults do predio e confirmar que unidades existentes nao mudam, inclusive apos restart.
- [x] Editar uma unidade individual e confirmar que predio e demais unidades nao mudam.
- [x] Lote de preco/mode/enable/disable altera somente unidades explicitamente selecionadas e elegiveis.
- [x] Owner, unidade protegida, `payment_pending`, `money_removed` e `manual_review` aparecem como ignorados e nao mudam.
- [x] Iniciar compra entre preview e confirmacao do lote e confirmar rejeicao na releitura.
- [x] Comprar unidade `direct` pelo interfone estando perto; confirmar owner apenas na unidade e predio sem owner.
- [x] Tentar interfone longe, predio/unidade forjados, modo `admin` e preco zero; confirmar bloqueio server-side.
- [x] Dois jogadores comprando a mesma unidade: somente um conclui; unidades diferentes podem concluir simultaneamente.
- [x] Confirmar que porta do predio, porta da unidade, outras unidades e `access_json.features` nao mudam.
- [x] Confirmar que interfone nao expõe owner/citizenid/regras/chaves/transaction_key.
- [x] Regressao: casa comum da Fase 4, recovery financeiro, E, G, animacao, cinto, guest e recursos continuam funcionando.
- [x] Restart preserva defaults, unidades e precos independentes.

## Fase 6 — IPTU

Teste runtime inicial executado em 2026-07-13. A auditoria encontrou correcoes
funcionais; o responsavel repetiu o runtime e aprovou a Fase 6 em 2026-07-13.

Validacao estatica:

- [x] Migration incremental `006_property_tax.sql` adiciona somente campos `tax_*`, indices e `mz_house_tax_payments`.
- [x] Elegibilidade server-side limita IPTU a `house` e `apartment_unit`/`apartment` residenciais, ativas, nao arquivadas e com owner.
- [x] Predio guarda somente defaults fiscais em `building_json.unitDefaults`; unidades recebem copia independente na criacao.
- [x] Owner manual nao inicializa cobranca retroativa sem opcao explicita; compra inicia novo vencimento.
- [x] Remocao/substituicao de owner suspende o ciclo atual e preserva historico; novo comprador nao herda vencimento antigo.
- [x] Pagamento rele owner, valor, datas, status e saldo no servidor; client envia somente `houseCode`.
- [x] Lock por propriedade, registro pending, debito, CAS fiscal, refund e `manual_review` protegem concorrencia e ambiguidade.
- [x] `tax_status=blocked` nao chama mutacao de porta, owner, chaves, sessao ou recursos.
- [x] Processamento e global, horario e paginado; lazy check ocorre em consulta/pagamento, sem thread por propriedade.
- [x] Estados persistentes usam `disabled`, `paid`, `due`, `overdue` e `blocked`, com datas UTC do servidor.
- [x] Payload do owner omite metadata/referencia financeira; payload publico de propriedades nao inclui politica fiscal.
- [x] Menu admin configura, consulta, ajusta vencimento/status e mostra historico; toda mutacao usa callbacks server-side.
- [x] Validador: 40 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.
- [x] Nenhuma retomada automatica, Fase 7 ou mistura entre bloqueio fiscal e bloqueio da porta foi implementada.

Auditoria final 9B:

- [x] `tax.lua` carrega depois de money/commerce/apartments e antes de todos os consumidores; startup valida a API completa.
- [x] `transaction_reference` e `NOT NULL`/`UNIQUE`; historico possui indices por property, owner, status e due.
- [x] Inicializacao exige `tax_due_at IS NULL`; repeticao reconhece `already_initialized` sem mover o vencimento.
- [x] Barreira persistente usa property + owner atual; `manual_review` antigo nao bloqueia owner novo e continua no historico admin.
- [x] Elegibilidade exige politica `owner`/fallback residencial; mudanca administrativa para public/rules/admin suspende o ciclo sem apagar historico.
- [x] CAS do vencimento e `money_removed -> completed` ocorrem em uma unica query multi-table.
- [x] Perda de resposta rele pagamento/owner/ciclo: recupera completed, permite refund apenas com ciclo inalterado ou marca `manual_review`.
- [x] Refund continua limitado a uma tentativa mesmo se houver exception depois do credito.
- [x] Saldo insuficiente termina `failed`, sem debito, mudanca de datas ou `manual_review` indevido.
- [x] Recovery preserva terminais, converte initiated em failed e pending/money_removed em manual_review sem cobrar/refund/avancar ciclo.
- [x] Logs cobrem started, failed, paid, refunded, manual_review, status changed, recovery e notice; admin registra before/after.
- [x] `Tax.debug=false`; nenhum log publica saldo integral ou politica sensivel.
- [x] Matrizes Lua isoladas aprovaram init idempotente, owner-cycle, lock reentrante, complete atomico, prova de CAS e refund unico.
- [x] Validador apos auditoria: 40 arquivos Lua validos e nenhuma dependencia runtime de `mz_realestate`.

Checklist runtime confirmado pelo responsavel ao liberar a Fase 7:

- [x] Criar/comprar casa com IPTU ativo e confirmar primeiro vencimento em UTC.
- [x] Atribuir owner manualmente sem inicializar e confirmar ausencia de cobranca retroativa; repetir com inicializacao explicita.
- [x] Pagar com saldo e confirmar debito unico, historico completed e avanco do vencimento pelo intervalo configurado.
- [x] Pagar sem saldo e confirmar que vencimento, status e owner nao mudam.
- [x] Dois pagamentos simultaneos da mesma propriedade: somente um debita e conclui.
- [x] Falha/ambiguidade apos debito preserva refund unico ou `manual_review`.
- [x] Repetir inicializacao do mesmo ciclo nao move `due_at`.
- [x] Trocar owner nao herda bloqueio financeiro antigo e preserva historico.
- [x] Grace period e transicoes `paid` -> `due` -> `overdue` foram validados.
- [x] `tax_status=blocked` nao altera porta, E/G, owner, chaves, saida ou recursos.
- [x] Casa/unidade pagam; predio, gang, job, publico, administrativo, sem owner e archived sao rejeitados.
- [x] Remocao de owner suspende ciclo e novo owner nao herda divida.
- [x] Defaults de predio afetam somente novas unidades.
- [x] Restart preserva datas/status e nao duplica pagamento.
- [x] Avisos respeitam cooldown.
- [x] Processamento horario/paginado nao duplica cobranca.
- [x] Regressao das Fases 0 a 5 preservada.

## Fase 7 — consolidacao, migracao e documentacao

Validacao estatica:

- [x] Wizard manual oferece residencia, predio, unidade, gang, job, publico e administrativo.
- [x] Preview e calculado no servidor, expira em cinco minutos e fica vinculado ao admin/source.
- [x] Aplicacao exige confirmacao exata do code e cancela se a propriedade mudou desde o preview.
- [x] Owner/chaves incompatíveis nao sao apagados; devem ser removidos explicitamente antes da conversao.
- [x] Compra, IPTU, lote e estados financeiros pending/manual_review bloqueiam a migracao.
- [x] `listing_json`/`realestate_json` sao somente contados/classificados e nunca retornados integralmente ao client.
- [x] Nenhuma migracao automatica ocorre no bootstrap, repository ou leitura.
- [x] Codigo morto de criadores org/business antigos foi removido somente apos busca de consumidores, exports, eventos e callbacks.
- [x] Rejeicao de tipos administrativos antigos e fallbacks residenciais foram preservados.
- [x] Migrations 002-006 foram revisadas como incrementais e nao destrutivas.
- [x] SQL opcional esta separado, fora do manifest e com comandos destrutivos comentados.
- [x] Exports, callbacks e eventos finais estao documentados em `API_REFERENCE.md`.
- [x] Caches, rate limits, payload publico, logs, locks, rollback e cleanup foram auditados.
- [x] `mz_houses` nao chama `mz_realestate`; telefone retorna `realestate_retired`; nao existe ensure/start ativo no workspace.

Checklist runtime aprovado da Fase 7 em 2026-07-13 por confirmacao do
responsavel do servidor:

- [x] Abrir `/mzhouses > Migracao / auditoria legada` como admin; player comum recebe negacao.
- [x] Auditar JSON e confirmar contagens/amostras sem alteracao no banco.
- [x] Preview de cada template mostra antes/depois correto e nao persiste ao cancelar.
- [x] Confirmacao diferente do code e token expirado sao rejeitados.
- [x] Alterar a propriedade entre preview/aplicacao e confirmar `property_changed_since_preview`.
- [x] Migrar residencia legada e confirmar owner/chaves, shell, entrada, pontos e garagem preservados.
- [x] Migrar unidade com predio/numero validos; parent ou numero duplicado e rejeitado.
- [x] Migrar gang/job e validar grupo real, grade, duty, controle de porta e visibilidade.
- [x] Migrar publico/admin e confirmar recursos restritos, porta unlocked/blocked e visibilidade correta.
- [x] Tentar migrar tipo nao residencial com owner/chaves e confirmar bloqueio sem apagar relacoes.
- [x] Tentar migrar durante compra/IPTU/lote/manual_review e confirmar bloqueio.
- [x] Reiniciar e confirmar policy, door e metadata de auditoria persistentes.
- [x] Repetir a matriz final das Fases 0 a 6, incluindo cleanup de sessao/bucket/preview.
- [x] Iniciar sem `mz_realestate` e confirmar houses/telefone sem erro.

## Fase 8 - painel do proprietario `/house`

Validacao estatica executada em 2026-07-13:

- [x] `/house` e `/houses` usam configuracao propria; busca no workspace nao encontrou conflito.
- [x] Listas de owner e chave usam consultas separadas e payloads minimos.
- [x] Somente residencia individual ativa, nao arquivada, `ownerType=player` e policy owner e aceita.
- [x] Citizenids de chaves e targets nao sao enviados ao client; tokens temporarios vinculam as acoes.
- [x] Entrega rele owner, target, role, distancia e limite dentro de lock por propriedade.
- [x] Revogacao rele owner/chave, funciona offline e preserva ocupante interno.
- [x] IPTU chama `MZHousesTax.getStatus` e o callback `payPropertyTax` existente.
- [x] Porta, comercio e features nao possuem mutacao no client do painel.
- [x] Waypoint recebe somente entrada publica; unidade usa a entrada do predio.
- [x] Validador: 43 arquivos Lua validos, sem migration nova e sem dependencia de `mz_realestate`.

Checklist runtime obrigatorio da Fase 8:

- [ ] 1. Player sem imovel abre o painel com listas vazias.
- [ ] 2. Player com uma casa ve a casa em `Meus imoveis`.
- [ ] 3. Player com apartamento ve a unidade e o predio vinculado.
- [ ] 4. Player com casa e apartamento ve ambos, com paginacao correta.
- [ ] 5. Imovel com chave aparece somente na secao separada.
- [ ] 6. Acesso guest nao aparece nas listas.
- [ ] 7. Gang, job, publico, administrativo e predio nao aparecem como pessoais.
- [ ] 8. Consulta/pagamento de IPTU reutiliza a Fase 6 e `/iptu` continua funcionando.
- [ ] 9. Saldo insuficiente nao altera imposto, owner ou saldo.
- [ ] 10. Entregar chave `access` atualiza acesso sem liberar controle G.
- [ ] 11. Entregar chave `control` mostra confirmacao forte e libera controle G presencial.
- [ ] 12. Alvo acima da distancia configurada e bloqueado.
- [ ] 13. `targetSource` ou token forjado e bloqueado.
- [ ] 14. Role diferente de `access`/`control` e bloqueado.
- [ ] 15. Limite de chaves e preservado sob tentativas concorrentes.
- [ ] 16. Revogar chave remove somente a chave selecionada.
- [ ] 17. Revogar jogador dentro nao expulsa nem bloqueia a saida.
- [ ] 18. Owner perde o imovel com menu aberto e a acao seguinte e rejeitada.
- [ ] 19. Duas entregas simultaneas nao ultrapassam o limite nem corrompem roles.
- [ ] 20. Waypoint de casa usa a entrada publica.
- [ ] 21. Waypoint de apartamento usa a entrada do predio e informa a unidade.
- [ ] 22. Porta permanece somente leitura; G presencial nao sofre regressao.
- [ ] 23. Comercio permanece somente leitura e nao altera preco/venda.
- [ ] 24. Features mostram apenas habilitado/desabilitado.
- [ ] 25. Restart preserva chaves e roles.
- [ ] 26. Revogacao de chave de player offline funciona.
- [ ] 27. E, G, animacao de chave e cinto permanecem funcionais.
- [ ] 28. Stash, wardrobe e garage permanecem funcionais e revalidados.
- [ ] 29. Compra, interfone e IPTU permanecem funcionais.
- [ ] 30. Callbacks/eventos manuais para imovel alheio sao bloqueados.

## Regressao administrativa geral

- [ ] Iniciar sem `mz_realestate`; telefone e casas nao geram erro.
- [ ] Migration adiciona metadata/index sem apagar registros, owners ou keys.
- [ ] Admin abre `/mzhouses`; jogador comum recebe negacao.
- [ ] Preview cria shell isolado e `mzhouses_preview_exit` restaura bucket 0.
- [ ] Criar casa completa; code/shell invalido ou duplicado e rejeitado.
- [ ] Pesquisa encontra por code, label, citizenid, categoria e status.
- [ ] Jogador longe nao forja entrada; sem owner/key nao entra.
- [ ] Owner e key entram; casas distintas recebem buckets distintos.
- [ ] Saida, falha de shell, morte, disconnect e restart limpam shell/bucket.
- [ ] Owner/key removido perde acesso imediatamente.
- [ ] Bau/guarda-roupa exigem sessao dentro da mesma propriedade.
- [ ] Garagem exige acesso e usa somente o contrato do mz_garagem.
- [ ] Editar shell expulsa ocupantes e nao deixa shell antigo ativo.
- [ ] Desativar/arquivar bloqueia uso; reativar restaura acesso persistido.
- [ ] Limpar keys/arquivar rejeita confirmacao diferente do code.
- [ ] Restart preserva owner, keys, entrada, shell, interior, garagem e metadata.
- [ ] `rg "exports\\['mz_realestate'\\]" mz_phone mz_houses` nao retorna chamada.
- [ ] Casa antiga sem `entrySpawn` aparece exatamente no ponto historico.
- [ ] Spawn custom persiste como offset relativo e aplica heading relativo.
- [ ] Dois jogadores na mesma casa aparecem no mesmo spawn customizado.
- [ ] Duas casas com o mesmo shell usam offsets independentes.
- [ ] Spawn e saida permanecem independentes; testar copia nas duas direcoes.
- [ ] Restaurar padrao remove o uso do offset customizado.
- [ ] Offset acima de `Admin.MaxInteriorPointOffset` e heading invalido sao rejeitados.
- [ ] Preview de shell diferente nao permite captura.
- [ ] Falha de colisao no spawn custom executa rollback e restaura bucket 0.
- [ ] Morte, cancelamento e resource stop durante preview limpam shell e bucket.
