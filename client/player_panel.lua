MZHousesPlayerPanelClient = MZHousesPlayerPanelClient or {}

local PanelState = { owned = {}, keyed = {} }
local PAGE_SIZE = 8

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function config()
  return type((MZHousesConfig or {}).PlayerPanel) == 'table' and MZHousesConfig.PlayerPanel or {}
end

local function notify(message, kind)
  if MZHouses and type(MZHouses.Notify) == 'function' then
    MZHouses.Notify(message, kind or 'inform')
  else
    TriggerEvent('chat:addMessage', { args = { 'mz_houses', tostring(message or '') } })
  end
end

local function callServer(name, payload)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return nil, 'callback_unavailable'
  end
  local ok, response = pcall(function()
    return lib.callback.await(name, false, payload)
  end)
  if not ok or type(response) ~= 'table' then
    return nil, ok and 'invalid_response' or 'callback_failed'
  end
  if response.ok ~= true then return nil, response.message or response.error or response.reason or 'request_denied' end
  return response, nil
end

local function openContext(menu)
  if GetResourceState('mz_menu') ~= 'started' then
    notify('mz_menu nao esta iniciado.', 'error')
    return false
  end
  local ok, result = pcall(function() return exports['mz_menu']:OpenContext(menu) end)
  if not ok or result == false then
    notify('Nao foi possivel abrir o painel de imoveis.', 'error')
    return false
  end
  return true
end

local function alert(data)
  if GetResourceState('mz_menu') ~= 'started' then return nil end
  local ok, result = pcall(function() return exports['mz_menu']:AlertDialog(data) end)
  return ok and result or nil
end

local function formatMoney(value)
  local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local updated, count = text:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
    text = updated
    if count == 0 then break end
  end
  return ('R$ %s'):format(text)
end

local function typeLabel(value)
  local labels = { house = 'Casa', apartment = 'Apartamento', apartment_unit = 'Apartamento' }
  return labels[trim(value)] or trim(value)
end

local function doorLabel(value)
  return ({ locked = 'Trancada', unlocked = 'Destrancada', blocked = 'Interditada' })[trim(value)] or 'Trancada'
end

local function taxLabel(value)
  return ({ disabled = 'Desabilitado', paid = 'Em dia', due = 'Vencido', overdue = 'Em atraso', blocked = 'Bloqueado' })[trim(value)] or trim(value)
end

local function commerceLabel(commerce)
  commerce = type(commerce) == 'table' and commerce or {}
  if commerce.enabled ~= true then return 'Nao esta a venda' end
  if commerce.mode == 'direct' then return ('Venda direta - %s'):format(formatMoney(commerce.price)) end
  if commerce.mode == 'admin' then return ('Venda administrativa - %s'):format(formatMoney(commerce.price)) end
  return 'Nao esta a venda'
end

local function featureLabel(value) return value == true and 'Habilitado' or 'Desabilitado' end

local function propertySubtitle(property, keyed)
  local parts = { typeLabel(property.subtype) }
  if trim(property.unitNumber) ~= '' then parts[#parts + 1] = ('unidade %s'):format(property.unitNumber) end
  if keyed == true then parts[#parts + 1] = ('chave %s'):format(property.keyRole == 'control' and 'controle' or 'acesso') end
  return table.concat(parts, ' | ')
end

local function waypoint(property)
  local entrance = type(property) == 'table' and property.entrance or nil
  local x, y = type(entrance) == 'table' and tonumber(entrance.x), type(entrance) == 'table' and tonumber(entrance.y)
  if not x or not y then return notify('Esta propriedade nao possui entrada publica valida.', 'error') end
  SetNewWaypoint(x, y)
  if trim(property.unitNumber) ~= '' then
    notify(('Entrada do predio marcada. Unidade: %s.'):format(property.unitNumber), 'success')
  else
    notify('Entrada da propriedade marcada no mapa.', 'success')
  end
end

local function pageOptions(items, page, eventName, keyed)
  page = math.max(1, math.floor(tonumber(page) or 1))
  local totalPages = math.max(1, math.ceil(#items / PAGE_SIZE))
  if page > totalPages then page = totalPages end
  local options = {}
  local first = (page - 1) * PAGE_SIZE + 1
  local last = math.min(#items, first + PAGE_SIZE - 1)
  for index = first, last do
    local property = items[index]
    options[#options + 1] = {
      title = tostring(property.label or property.code),
      description = propertySubtitle(property, keyed),
      icon = property.subtype == 'house' and 'house' or 'building',
      event = eventName,
      args = { property = property }
    }
  end
  if #items == 0 then options[1] = { title = 'Nenhuma propriedade encontrada', disabled = true, icon = 'circle-info' } end
  if page > 1 then
    options[#options + 1] = { title = 'Pagina anterior', icon = 'arrow-left', event = keyed and 'mz_houses:client:playerPanelKeyedPage' or 'mz_houses:client:playerPanelOwnedPage', args = { page = page - 1 } }
  end
  if page < totalPages then
    options[#options + 1] = { title = 'Proxima pagina', icon = 'arrow-right', event = keyed and 'mz_houses:client:playerPanelKeyedPage' or 'mz_houses:client:playerPanelOwnedPage', args = { page = page + 1 } }
  end
  return options, page, totalPages
end

function MZHousesPlayerPanelClient.Open()
  if config().enabled == false then return notify('O painel de imoveis esta desabilitado.', 'error') end
  local response, err = callServer('mz_houses:server:playerPanel:open')
  if not response then return notify(('Nao foi possivel abrir /house: %s'):format(tostring(err)), 'error') end
  PanelState.owned = type(response.owned) == 'table' and response.owned or {}
  PanelState.keyed = type(response.keyed) == 'table' and response.keyed or {}
  openContext({
    id = 'mz_houses_player_panel',
    title = 'Painel de imoveis',
    options = {
      { title = ('Meus imoveis (%d)'):format(#PanelState.owned), description = 'Propriedades residenciais em seu nome', icon = 'house-user', event = 'mz_houses:client:playerPanelOwnedPage', args = { page = 1 } },
      { title = ('Imoveis com chave (%d)'):format(#PanelState.keyed), description = 'Consulta e localizacao, sem poderes de proprietario', icon = 'key', event = 'mz_houses:client:playerPanelKeyedPage', args = { page = 1 } },
      { title = 'Fechar', icon = 'xmark', event = 'mz_houses:client:playerPanelClose' }
    }
  })
end

RegisterNetEvent('mz_houses:client:playerPanelOwnedPage', function(payload)
  local options, page, total = pageOptions(PanelState.owned, type(payload) == 'table' and payload.page or 1, 'mz_houses:client:playerPanelOwnedProperty', false)
  openContext({ id = 'mz_houses_player_owned', title = ('Meus imoveis - %d/%d'):format(page, total), menu = 'mz_houses_player_panel', options = options })
end)

RegisterNetEvent('mz_houses:client:playerPanelKeyedPage', function(payload)
  local options, page, total = pageOptions(PanelState.keyed, type(payload) == 'table' and payload.page or 1, 'mz_houses:client:playerPanelKeyedProperty', true)
  openContext({ id = 'mz_houses_player_keyed', title = ('Imoveis com chave - %d/%d'):format(page, total), menu = 'mz_houses_player_panel', options = options })
end)

RegisterNetEvent('mz_houses:client:playerPanelKeyedProperty', function(payload)
  local property = type(payload) == 'table' and payload.property or nil
  if type(property) ~= 'table' then return end
  local building = type(property.building) == 'table' and property.building.label or '-'
  openContext({
    id = 'mz_houses_player_keyed_' .. tostring(property.code),
    title = tostring(property.label or property.code),
    menu = 'mz_houses_player_keyed',
    options = {
      { title = 'Informacoes', description = ('%s | unidade=%s | predio=%s | chave=%s'):format(typeLabel(property.subtype), tostring(property.unitNumber or '-'), tostring(building), property.keyRole == 'control' and 'Controle' or 'Acesso'), icon = 'circle-info', disabled = true },
      { title = 'Porta', description = doorLabel(property.doorState), icon = 'door-closed', disabled = true },
      { title = 'Marcar entrada no mapa', description = trim(property.unitNumber) ~= '' and ('Entrada do predio | unidade %s'):format(property.unitNumber) or 'Entrada da propriedade', icon = 'location-dot', event = 'mz_houses:client:playerPanelWaypoint', args = { property = property } }
    }
  })
end)

RegisterNetEvent('mz_houses:client:playerPanelOwnedProperty', function(payload)
  local summary = type(payload) == 'table' and payload.property or nil
  local response, err = callServer('mz_houses:server:playerPanel:getProperty', { houseCode = summary and summary.code })
  if not response then return notify(('Nao foi possivel atualizar o imovel: %s'):format(tostring(err)), 'error') end
  local property = response.property
  openContext({
    id = 'mz_houses_player_owned_' .. tostring(property.code),
    title = tostring(property.label or property.code),
    menu = 'mz_houses_player_owned',
    options = {
      { title = 'Informacoes', description = propertySubtitle(property, false), icon = 'circle-info', event = 'mz_houses:client:playerPanelInfo', args = { property = property } },
      { title = ('IPTU - %s'):format(taxLabel(property.tax and property.tax.status)), description = property.tax and property.tax.enabled and ('Vence: %s'):format(tostring(property.tax.dueAt or '-')) or 'Desabilitado', icon = 'landmark', event = 'mz_houses:client:playerPanelTax', args = { code = property.code } },
      { title = ('Chaves - %d'):format(tonumber(property.keyCount) or 0), description = 'Listar, entregar ou revogar', icon = 'key', event = 'mz_houses:client:playerPanelKeys', args = { code = property.code, label = property.label } },
      { title = ('Porta - %s'):format(doorLabel(property.doorState)), description = 'Somente leitura; controle presencial continua no G', icon = 'door-closed', disabled = true },
      { title = 'Marcar entrada no mapa', description = trim(property.unitNumber) ~= '' and ('Entrada do predio | unidade %s'):format(property.unitNumber) or 'Nao teleporta', icon = 'location-dot', event = 'mz_houses:client:playerPanelWaypoint', args = { property = property } },
      { title = ('Comercio - %s'):format(commerceLabel(property.commerce)), description = 'Somente leitura', icon = 'tag', disabled = true }
    }
  })
end)

RegisterNetEvent('mz_houses:client:playerPanelInfo', function(payload)
  local property = type(payload) == 'table' and payload.property or nil
  if type(property) ~= 'table' then return end
  local building = type(property.building) == 'table' and property.building.label or '-'
  local features = type(property.features) == 'table' and property.features or {}
  openContext({
    id = 'mz_houses_player_info_' .. tostring(property.code), title = 'Informacoes - ' .. tostring(property.label),
    options = {
      { title = 'Identificacao', description = ('Codigo: %s | tipo: %s | owner: Voce'):format(tostring(property.code), typeLabel(property.subtype)), disabled = true, icon = 'id-card' },
      { title = 'Unidade / predio', description = ('Unidade: %s | Predio: %s'):format(tostring(property.unitNumber or '-'), tostring(building)), disabled = true, icon = 'building' },
      { title = 'Estado', description = ('Ativo | Porta: %s | Chaves: %d'):format(doorLabel(property.doorState), tonumber(property.keyCount) or 0), disabled = true, icon = 'shield' },
      { title = 'Recursos', description = ('Bau: %s | Guarda-roupa: %s | Garagem: %s'):format(featureLabel(features.stash), featureLabel(features.wardrobe), featureLabel(features.garage)), disabled = true, icon = 'boxes-stacked' },
      { title = 'Fiscal', description = ('%s | Vencimento: %s'):format(taxLabel(property.tax and property.tax.status), tostring(property.tax and property.tax.dueAt or '-')), disabled = true, icon = 'landmark' },
      { title = 'Comercio', description = commerceLabel(property.commerce), disabled = true, icon = 'tag' }
    }
  })
end)

RegisterNetEvent('mz_houses:client:playerPanelTax', function(payload)
  local code = trim(type(payload) == 'table' and payload.code)
  local response, err = callServer('mz_houses:server:playerPanel:getTaxStatus', { houseCode = code })
  if not response then return notify(('Nao foi possivel consultar IPTU: %s'):format(tostring(err)), 'error') end
  local tax = response.tax or {}
  local options = {
    { title = ('Status - %s'):format(taxLabel(tax.status)), description = ('Valor: %s | Vencimento: %s | Tolerancia: %s | Ultimo pagamento: %s'):format(formatMoney(tax.amount), tostring(tax.dueAt or '-'), tostring(tax.graceUntil or '-'), tostring(tax.lastPaidAt or '-')), icon = 'landmark', disabled = true },
    { title = 'Pagar pelo banco', description = ('O servidor relera owner, valor e vencimento: %s'):format(formatMoney(tax.amount)), icon = 'credit-card', disabled = tax.enabled ~= true or tax.initialized ~= true or tax.status == 'blocked', event = 'mz_houses:client:playerPanelPayTax', args = { code = code, amount = tax.amount, label = tax.label } }
  }
  for _, payment in ipairs(tax.payments or {}) do
    options[#options + 1] = { title = ('Pagamento - %s'):format(tostring(payment.status or '-')), description = ('%s | vencimento=%s | pago=%s'):format(formatMoney(payment.amount), tostring(payment.due_at or '-'), tostring(payment.paid_at or '-')), icon = 'receipt', disabled = true }
  end
  openContext({ id = 'mz_houses_player_tax_' .. code, title = 'IPTU - ' .. tostring(tax.label or code), options = options })
end)

RegisterNetEvent('mz_houses:client:playerPanelPayTax', function(payload)
  payload = type(payload) == 'table' and payload or {}
  if alert({ header = 'Confirmar pagamento do IPTU', content = ('Pagar %s pelo banco? O valor sera relido no servidor.'):format(formatMoney(payload.amount)), centered = true, cancel = true }) ~= 'confirm' then return end
  local response, err = callServer('mz_houses:server:payPropertyTax', { houseCode = payload.code })
  if not response then return notify(('Pagamento recusado: %s'):format(tostring(err)), 'error') end
  notify(response.message or 'IPTU pago pelo banco.', 'success')
  SetTimeout(math.max(1000, tonumber(config().rateLimitMs) or 1000) + 50, function()
    TriggerEvent('mz_houses:client:playerPanelTax', { code = payload.code })
  end)
end)

RegisterNetEvent('mz_houses:client:playerPanelKeys', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local response, err = callServer('mz_houses:server:playerPanel:listKeys', { houseCode = payload.code })
  if not response then return notify(('Nao foi possivel listar chaves: %s'):format(tostring(err)), 'error') end
  local options = {
    { title = 'Entregar chave', description = 'Somente para jogador online a ate a distancia configurada', icon = 'key', event = 'mz_houses:client:playerPanelNearby', args = { code = payload.code, label = payload.label } }
  }
  for _, key in ipairs(response.keys or {}) do
    options[#options + 1] = {
      title = tostring(key.name or 'Portador da chave'),
      description = ('%s | %s | criada=%s'):format(key.role == 'control' and 'Controle' or 'Acesso', key.online and 'Online' or 'Offline', tostring(key.createdAt or '-')),
      icon = key.role == 'control' and 'key-skeleton-left-right' or 'key',
      event = 'mz_houses:client:playerPanelRevokeKey',
      args = { code = payload.code, label = payload.label, token = key.token, name = key.name, role = key.role }
    }
  end
  openContext({ id = 'mz_houses_player_keys_' .. tostring(payload.code), title = 'Chaves - ' .. tostring(payload.label or payload.code), options = options })
end)

RegisterNetEvent('mz_houses:client:playerPanelNearby', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local response, err = callServer('mz_houses:server:playerPanel:nearbyPlayers', { houseCode = payload.code })
  if not response then return notify(('Nao foi possivel listar jogadores proximos: %s'):format(tostring(err)), 'error') end
  local options = {}
  for _, player in ipairs(response.players or {}) do
    options[#options + 1] = { title = tostring(player.name), description = ('Distancia: %.1f m'):format(tonumber(player.distance) or 0.0), icon = 'user', event = 'mz_houses:client:playerPanelChooseRole', args = { code = payload.code, label = payload.label, targetSource = player.source, targetToken = player.token, targetName = player.name } }
  end
  if #options == 0 then options[1] = { title = 'Nenhum jogador proximo', disabled = true, icon = 'users-slash' } end
  openContext({ id = 'mz_houses_player_nearby_' .. tostring(payload.code), title = 'Entregar chave', options = options })
end)

RegisterNetEvent('mz_houses:client:playerPanelChooseRole', function(payload)
  payload = type(payload) == 'table' and payload or {}
  openContext({ id = 'mz_houses_player_key_role_' .. tostring(payload.code), title = 'Tipo da chave - ' .. tostring(payload.targetName), options = {
    { title = 'Acesso', description = 'Permite entrar; nao controla a porta com G', icon = 'key', event = 'mz_houses:client:playerPanelConfirmGrant', args = { code = payload.code, label = payload.label, targetSource = payload.targetSource, targetToken = payload.targetToken, targetName = payload.targetName, role = 'access' } },
    { title = 'Controle', description = 'Permite entrar, trancar e destrancar a porta com G', icon = 'key-skeleton-left-right', event = 'mz_houses:client:playerPanelConfirmGrant', args = { code = payload.code, label = payload.label, targetSource = payload.targetSource, targetToken = payload.targetToken, targetName = payload.targetName, role = 'control' } }
  } })
end)

RegisterNetEvent('mz_houses:client:playerPanelConfirmGrant', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local warning = payload.role == 'control' and '\n\n**Esta chave permite trancar e destrancar a porta.**' or ''
  if alert({ header = 'Confirmar entrega de chave', content = ('Entregar chave de %s para **%s**?%s'):format(payload.role == 'control' and 'controle' or 'acesso', tostring(payload.targetName), warning), centered = true, cancel = true }) ~= 'confirm' then return end
  local response, err = callServer('mz_houses:server:playerPanel:grantKey', { houseCode = payload.code, targetSource = payload.targetSource, targetToken = payload.targetToken, role = payload.role })
  if not response then return notify(('Chave nao entregue: %s'):format(tostring(err)), 'error') end
  notify('Chave entregue e permissoes atualizadas.', 'success')
  SetTimeout(math.max(1000, tonumber(config().rateLimitMs) or 1000) + 50, function()
    TriggerEvent('mz_houses:client:playerPanelKeys', { code = payload.code, label = payload.label })
  end)
end)

RegisterNetEvent('mz_houses:client:playerPanelRevokeKey', function(payload)
  payload = type(payload) == 'table' and payload or {}
  if alert({ header = 'Revogar chave', content = ('Revogar a chave de **%s**? A pessoa nao sera expulsa se estiver dentro.'):format(tostring(payload.name)), centered = true, cancel = true }) ~= 'confirm' then return end
  local response, err = callServer('mz_houses:server:playerPanel:revokeKey', { houseCode = payload.code, revokeToken = payload.token })
  if not response then return notify(('Chave nao revogada: %s'):format(tostring(err)), 'error') end
  notify('Chave revogada. O proximo acesso sera revalidado.', 'success')
  SetTimeout(math.max(1000, tonumber(config().rateLimitMs) or 1000) + 50, function()
    TriggerEvent('mz_houses:client:playerPanelKeys', { code = payload.code, label = payload.label })
  end)
end)

RegisterNetEvent('mz_houses:client:playerPanelWaypoint', function(payload)
  waypoint(type(payload) == 'table' and payload.property or nil)
end)

RegisterNetEvent('mz_houses:client:playerPanelClose', function()
  if GetResourceState('mz_menu') == 'started' then pcall(function() exports['mz_menu']:CloseMenu() end) end
end)

RegisterNetEvent('mz_houses:client:playerPanelKeyNotice', function(payload)
  payload = type(payload) == 'table' and payload or {}
  if payload.action == 'granted' then
    notify(('Voce recebeu uma chave de %s (%s).'):format(tostring(payload.propertyLabel), payload.role == 'control' and 'controle' or 'acesso'), 'success')
  elseif payload.action == 'revoked' then
    notify(('Sua chave de %s foi revogada.'):format(tostring(payload.propertyLabel)), 'inform')
  end
end)

local function commandRegistered(name)
  name = trim(name):lower()
  if name == '' then return true end
  local ok, commands = pcall(GetRegisteredCommands)
  if not ok or type(commands) ~= 'table' then return false end
  for _, command in ipairs(commands) do
    if trim(type(command) == 'table' and command.name or command):lower() == name then return true end
  end
  return false
end

local function registerPanelCommand(name)
  name = trim(name):lower()
  if name == '' then return false end
  if commandRegistered(name) then
    print(('[mz_houses][player_panel] comando /%s ja registrado; ajuste MZHousesConfig.PlayerPanel.'):format(name))
    return false
  end
  RegisterCommand(name, function() MZHousesPlayerPanelClient.Open() end, false)
  return true
end

CreateThread(function()
  Wait(0)
  if config().enabled == false then return end
  registerPanelCommand(config().command or 'house')
  local seen = { [trim(config().command or 'house'):lower()] = true }
  for _, alias in ipairs(type(config().aliases) == 'table' and config().aliases or {}) do
    alias = trim(alias):lower()
    if alias ~= '' and not seen[alias] then
      seen[alias] = true
      registerPanelCommand(alias)
    end
  end
end)
