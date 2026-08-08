# Referencia final de APIs do mz_houses

Esta referencia descreve os contratos existentes ao fim da implementacao da
Fase 8. O servidor continua sendo autoridade. Exports administrativos mutaveis
exigem `actorSource` admin; compra, pagamento, abertura de recursos e gestao de
chaves pelo owner usam o `source` real e revalidam contexto.

## Exports client-side

| Export | Assinatura | Uso |
|---|---|---|
| `EnterHouse` | `(houseCode)` | Solicita entrada; distancia, porta e acesso sao revalidados no servidor. |
| `ExitHouse` | `()` | Encerra a sessao atual e limpa shell/bucket. |
| `GetCurrentHouse` | `()` | Retorna o estado local da sessao atual. |
| `GetHouses` | `()` | Retorna o cache local visivel. |
| `IsInsideHouse` | `()` | Informa se existe sessao interna local. |
| `OpenHouseStash` | `(houseCode)` | Abre somente apos revalidacao da feature e sessao. |
| `OpenHouseWardrobe` | `(houseCode)` | Idem para wardrobe. |
| `OpenHouseGarage` | `(houseCode, action)` | Idem para garagem e contexto externo/interno. |
| `OpenPropertyTax` | `(houseCode)` | Abre consulta/pagamento do IPTU do owner. |

## Exports server-side

Leitura e autorizacao:

- `CanEnterHouse(source, houseCode)`
- `GetPropertyByCode(code)` e `GetPublicPropertyInfo(code)`
- `GetIntegrationPropertyContext(code)` retorna contexto minimo server-side para
  vinculos persistentes, sem owner, chaves, policy, coordenadas ou financas.
- `ListProperties(filters)`
- `CanPlayerAccessProperty(source, code)`
- `CanPlayerManageProperty(source, code)`
- `GetPropertyAccessPolicy(code)`
- `GetPropertyDoorState(code)`
- `CanControlPropertyDoor(source, code)` e alias `CanControlDoor(source, code)`
- `CanPropertyBeListed(code)` (legado; sempre respeita o comercio atual)
- `GetHouseAccess(houseCode)`
- `CanAccessPropertyFeature(source, houseCode, featureName)`
- `GetConfirmedInteriorSession(source, houseCode)` retorna somente contexto minimo
  server-side da sessao confirmada (`propertyId`, code, orgCode, type,
  interiorCode/shell, bucket,
  guest e features), sem owner, chaves, policy, metadata ou coordenadas.
- `InvalidateOrganizationFacilitySessions(code, orgCode, reason)` e restrito ao
  `mz_org_activities` e remove ocupantes quando uma instalacao e suspensa.
- `ListPropertyKeys(code, actorSource)`
- `GetPropertyTaxStatus(code, source)`
- `GetPlayerOwnedProperties(source)`
- `GetPlayerKeyedProperties(source)`
- `GetPlayerPropertyPanel(source, houseCode)`
- `GetNearbyPlayersForPropertyKey(source, houseCode)`

Mutacoes administrativas:

- `SetPropertyAccessPolicy(code, policy, actorSource)`
- `SetPropertyDoorState(code, state, actorSource)`
- `SetPropertyOwner(code, citizenid, actorSource, reason, meta)`
- `ClearPropertyOwner(code, actorSource, reason, meta)`
- `GivePropertyKey(code, citizenid, actorSource, reason, meta, role)`
- `RemovePropertyKey(code, citizenid, actorSource, reason, meta)`
- wrappers preservados: `SetHouseOwner`, `ClearHouseOwner`, `GiveHouseKey`, `RemoveHouseKey`
- `CreateProperty(payload, actorSource)`
- `UpdateProperty(code, patch, actorSource)`
- `DeleteProperty(code, actorSource, confirmCode)` (soft delete)
- `SetPropertyEntrance`, `SetPropertyInterior`, `SetPropertyGarage`, `SetPropertyEnabled`
- `SetPropertyIPL(code, interiorCode, interior, actorSource)` aceita somente IPL
  cadastrado no `mz_interiors` com `enabled=true` e `calibrated=true`.
- `SetPropertySale(code, commerce, actorSource)`
- `ConfigurePropertyTax(code, tax, actorSource, options)`

Acoes do jogador e integracoes:

- `PurchaseProperty(source, code)`
- `PayPropertyTax(source, code)`
- `OpenHouseStash(source, houseCode)`
- `OpenHouseWardrobe(source, houseCode)`
- `OpenHouseGarage(source, houseCode, action)`
- `GrantPropertyKeyByOwner(source, houseCode, targetSource, role, targetToken)`
- `RevokePropertyKeyByOwner(source, houseCode, revokeToken)`

Os exports do painel resolvem owner/citizenid no servidor. Os tokens de alvo e
revogacao sao efemeros, vinculados ao source e nao substituem a releitura de
propriedade, role, distancia, limite ou chave atual.

Retornos existentes preservam o primeiro valor booleano quando o contrato ja o
usava. Detalhes e razoes ficam no segundo valor. Nenhum fluxo do jogador aceita
owner, citizenid do target, preco, saldo, tax, grade, duty ou permissao
calculada pelo client.

## Callbacks de jogador

Os callbacks ox_lib expostos ao client sao:

- descoberta: `listVisibleHouses`, `getPublicPropertyInfo`, `listProperties`,
  `listApartmentUnits`;
- entrada: `resolveEntryContext`, `canPlayerAccessProperty`,
  `canPlayerManageProperty`, `canPropertyBeListed`, `canEnterHouse`,
  `beginEnterHouse`, `confirmEnterHouse`, `leaveHouse`;
- porta/recursos: `getFeatureContext`, `getDoorContext`, `setDoorState`,
  `openHouseStash`, `openHouseWardrobe`, `openHouseGarage`;
- comercio: `purchaseProperty`, `purchaseApartmentUnit`;
- IPTU: `listMyPropertyTaxes`, `getPropertyTaxStatus`, `payPropertyTax`;
- painel `/house`: `playerPanel:open`, `playerPanel:getProperty`,
  `playerPanel:listKeys`, `playerPanel:nearbyPlayers`, `playerPanel:grantKey`,
  `playerPanel:revokeKey`, `playerPanel:getTaxStatus`.

Todos usam o prefixo `mz_houses:server:`. Rejeicoes normais retornam uma tabela
com `ok=false` e razao canonica; falha de transporte fica separada no client.

## Callbacks administrativos

Todos usam o prefixo `mz_houses:server:admin:` e validam ACE no servidor:

- acesso e leitura: `checkAccess`, `listGroups`, `listNearbyProperties`,
  `searchProperties`, `getPropertyInfo`, `getPropertyLogs`, `reload`;
- migracao final: `previewLegacyMigration`, `applyLegacyMigration`,
  `auditLegacyData`;
- propriedade: `createProperty`, `createStructuredProperty`, `updateBasic`,
  `setEntrance`, `setShell`, `setCategory`, `setOrg`, `setPublic`,
  `setListable`, `setVisibility`;
- policy/porta: `setAccessPolicy`, `setFeaturePolicy`, `setDoorState`;
- preview/interior: `beginPreview`, `endPreview`, `setInternalPoint`,
  `setEntrySpawnDefault`, `copyInteriorPoint`, `resetInternalPoints`;
- garagem: `setGarageEnabled`, `setGaragePoint`, `setGarageSlots`,
  `setGarageMode`;
- owner/chaves: `setOwner`, `setOwnerBySource`, `clearOwner`, `giveKey`,
  `removeKey`, `clearKeys`;
- comercio: `configureSale`, `listSaleTargets`, `sellProperty`,
  `getTransactions`;
- apartamentos: `listApartmentBuildings`, `listBuildingUnits`,
  `getBuildingUnitDefaults`, `updateBuildingUnitDefaults`,
  `copyBuildingUnitTemplate`, `previewApartmentBatch`,
  `createApartmentBatch`, `previewApartmentBulk`, `applyApartmentBulk`,
  `setUnitBulkProtection`;
- IPTU: `getTaxStatus`, `configureTax`, `setTaxDueAt`, `setTaxStatus`.

O wizard legado nao e exportado. Ele existe somente no painel admin, usa token
temporario vinculado ao source e exige confirmacao exata do code.

## Eventos

Client recebidos/publicados pelo resource:

- `mz_houses:client:enterHouse`, `exitHouse`, `forceExit`, `doorMenu`;
- `mz_houses:client:doorStateChanged`, `doorPresentationChanged`,
  `doorVisibilityRefreshed`;
- `mz_houses:client:refreshVisibility`, `visibilityUpdated`;
- `mz_houses:client:featurePolicyChanged`, `taxNotice`;
- selecao de apartamento: `apartmentUnitSelected`,
  `apartmentUnitPurchaseSelected`, `apartmentGarageSelected`;
- suporte administrativo: `adminMenuAction`, `runCommand`, `commandDenied`;
- painel pessoal: `playerPanelOwnedPage`, `playerPanelKeyedPage`,
  `playerPanelOwnedProperty`, `playerPanelKeyedProperty`, `playerPanelInfo`,
  `playerPanelTax`, `playerPanelPayTax`, `playerPanelKeys`,
  `playerPanelNearby`, `playerPanelChooseRole`, `playerPanelConfirmGrant`,
  `playerPanelRevokeKey`, `playerPanelWaypoint`, `playerPanelKeyNotice`.

Eventos server recebidos:

- `mz_houses:server:abortEnterHouse`;
- `mz_houses:server:taxPlayerReady`;
- `mz_houses:server:adminPreviewStopped`;
- fallbacks administrativos protegidos: `runCommand`, `createAdminProperty`,
  `setAdminEntrance`, `setAdminGaragePoint`.

Evento interno do resource:

- `mz_houses:server:propertyAccessChanged(code, reason)` encerra sessoes que
  perderam acesso e invalida o contexto correspondente. A razao
  `owner_key_revoked` preserva o ocupante atual; capacidades e a proxima acao
  continuam sendo revalidadas.

Eventos e callbacks administrativos nao devem ser tratados como uma API de
integracao externa. Para outros resources, prefira os exports documentados.
