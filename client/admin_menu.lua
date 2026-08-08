local AdminMenuState = {
  currentCode = nil,
  currentProperty = nil
}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function menuConfig()
  return MZHousesConfig.AdminMenu or {}
end

local function mzMenuStarted()
  return GetResourceState('mz_menu') == 'started'
end

local function mzMenuReady()
  if not mzMenuStarted() then
    return false
  end

  local ok, ready = pcall(function()
    return exports['mz_menu']:IsReady()
  end)

  return ok and ready == true
end

local function directOxReady()
  return lib
    and type(lib.registerContext) == 'function'
    and type(lib.showContext) == 'function'
    and type(lib.inputDialog) == 'function'
end

local function allowDirectOxFallback()
  return menuConfig().fallbackToOxLib == true
end

local function visualMenuReady()
  if mzMenuReady() then
    return true
  end

  return allowDirectOxFallback() and directOxReady()
end

local notifyViaMzMenu = function() return false end
local notify
local openContext
local inputDialog
local alertDialog
local callAdmin

-- IMPORTANTE:
-- Quando o menu e enviado para outro resource via export (`mz_menu`), funcoes Lua
-- como `onSelect = function() ... end` podem nao atravessar a fronteira do resource
-- de forma confiavel. Por isso, antes de enviar o menu para o `mz_menu`,
-- transformamos cada `onSelect` local em um evento client com um actionId.
-- Assim os botoes continuam chamando a logica local do `mz_houses`, mas o
-- payload passado ao `mz_menu` fica serializavel: event + args.
local AdminMenuActionSeq = 0
local AdminMenuActions = {}

local function registerMenuAction(fn)
  if type(fn) ~= 'function' then
    return nil
  end

  AdminMenuActionSeq = AdminMenuActionSeq + 1
  local actionId = ('mz_houses_admin_%s_%s'):format(GetGameTimer(), AdminMenuActionSeq)
  AdminMenuActions[actionId] = fn
  return actionId
end

local function cloneMenuOptionForMzMenu(option)
  option = type(option) == 'table' and option or {}

  local cloned = {}
  for key, value in pairs(option) do
    if key ~= 'onSelect' then
      cloned[key] = value
    end
  end

  if type(option.onSelect) == 'function' then
    local actionId = registerMenuAction(option.onSelect)
    cloned.event = 'mz_houses:client:adminMenuAction'
    cloned.args = { actionId = actionId }
  end

  return cloned
end

local function cloneMenuForMzMenu(menu)
  menu = type(menu) == 'table' and menu or {}

  local cloned = {}
  for key, value in pairs(menu) do
    if key ~= 'options' then
      cloned[key] = value
    end
  end

  cloned.options = {}
  if type(menu.options) == 'table' then
    for index, option in ipairs(menu.options) do
      cloned.options[index] = cloneMenuOptionForMzMenu(option)
    end
  end

  return cloned
end

RegisterNetEvent('mz_houses:client:adminMenuAction', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local actionId = trim(payload.actionId)

  if actionId == '' or type(AdminMenuActions[actionId]) ~= 'function' then
    notify('Acao do menu invalida ou expirada. Abra o menu novamente.', 'error')
    return
  end

  local ok, err = pcall(AdminMenuActions[actionId])
  if not ok then
    notify(('Falha ao executar acao do menu: %s'):format(tostring(err)), 'error')
  end
end)

notify = function(message, kind)
  if notifyViaMzMenu(message, kind) then
    return
  end

  if MZHouses and type(MZHouses.Notify) == 'function' then
    MZHouses.Notify(message, kind or 'inform')
    return
  end

  TriggerEvent('chat:addMessage', {
    color = { 120, 190, 255 },
    args = { 'mz_houses', tostring(message or '') }
  })
end


notifyViaMzMenu = function(message, kind)
  if not mzMenuStarted() then
    return false
  end

  local ok = pcall(function()
    exports['mz_menu']:Notify(tostring(message or ''), kind or 'inform')
  end)

  return ok == true
end

openContext = function(menu)
  menu = type(menu) == 'table' and menu or {}

  if mzMenuStarted() then
    local ok, result, err = pcall(function()
      return exports['mz_menu']:OpenContext(cloneMenuForMzMenu(menu))
    end)

    if ok and result ~= false then
      return true
    end

    notify(('Falha ao abrir menu pelo mz_menu: %s'):format(tostring(err or result or 'unknown')), 'error')
    return false
  end

  if allowDirectOxFallback() and directOxReady() then
    lib.registerContext(menu)
    lib.showContext(menu.id)
    return true
  end

  notify('mz_menu nao esta iniciado. Use os comandos admin como fallback.', 'error')
  return false
end

inputDialog = function(title, rows, options)
  if mzMenuStarted() then
    local ok, result = pcall(function()
      return exports['mz_menu']:InputDialog(title, rows, options)
    end)

    if ok then
      return result
    end

    notify(('Falha no input pelo mz_menu: %s'):format(tostring(result)), 'error')
    return nil
  end

  if allowDirectOxFallback() and lib and type(lib.inputDialog) == 'function' then
    return lib.inputDialog(title, rows, options)
  end

  notify('mz_menu/input indisponivel. Use os comandos admin como fallback.', 'error')
  return nil
end

alertDialog = function(dataOrTitle, content, options)
  if mzMenuStarted() then
    local ok, result = pcall(function()
      return exports['mz_menu']:AlertDialog(dataOrTitle, content, options)
    end)

    if ok then
      return result
    end

    notify(('Falha no alerta pelo mz_menu: %s'):format(tostring(result)), 'error')
    return nil
  end

  if allowDirectOxFallback() and lib and type(lib.alertDialog) == 'function' then
    return lib.alertDialog(dataOrTitle, content, options)
  end

  local message = type(dataOrTitle) == 'table' and (dataOrTitle.content or dataOrTitle.description or dataOrTitle.header) or content or dataOrTitle
  notify(message or 'Alerta', 'inform')
  return nil
end

local function currentPoint(includeHeading)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)

  local payload = {
    x = coords.x + 0.0,
    y = coords.y + 0.0,
    z = coords.z + 0.0
  }

  if includeHeading == true then
    payload.w = heading + 0.0
    payload.heading = heading + 0.0
  end

  return payload
end

local function currentInterior()
  if GetResourceState('mz_interiors') ~= 'started' then
    return nil
  end

  local ok, interior = pcall(function()
    return exports['mz_interiors']:GetCurrentInterior()
  end)

  if ok and type(interior) == 'table' then
    return interior
  end

  return nil
end

local function vectorPayload(value, includeHeading)
  if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then
    return nil
  end

  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  if not x or not y or not z then
    return nil
  end

  local out = { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
  if includeHeading == true then
    out.w = tonumber(value.w or value.h or value.heading or value[4]) or 0.0
    out.heading = out.w
  end
  return out
end

local function normalizeHeading(value)
  value = tonumber(value) or 0.0
  return ((value % 360.0) + 360.0) % 360.0
end

local function interiorEditPayload(code, pointName, property)
  local current = MZHouses and MZHouses.GetCurrentHouse and MZHouses.GetCurrentHouse() or {}
  local interior = currentInterior()
  local insideHouse = current.inside == true and trim(current.code) == trim(code)
  local preview = not insideHouse and type(interior) == 'table' and type(interior.metadata) == 'table'
    and interior.metadata.preview == true and trim(interior.shellName) == trim(property and property.shell)
  if not insideHouse and not preview then
    return nil, 'Entre neste imovel ou abra um preview do mesmo shell.'
  end
  local spawnCoords = vectorPayload(interior and interior.spawnCoords, false)
  local object = tonumber(interior and interior.object)
  if not spawnCoords or not object or object == 0 or not DoesEntityExist(object) then
    return nil, 'Contexto do interior indisponivel.'
  end

  local ped = PlayerPedId()
local world = GetEntityCoords(ped)

local ok, relative, captureError = pcall(function()
  return exports['mz_interiors']:CaptureCurrentInteriorPoint({
    x = world.x,
    y = world.y,
    z = world.z
  })
end)

if not ok or not relative then
  return nil, captureError or 'Falha ao capturar o ponto interno.'
end

local shellHeading = tonumber(interior.shellHeading)

if shellHeading == nil then
  shellHeading = GetEntityHeading(object)
end

local relativeHeading = normalizeHeading(
  GetEntityHeading(ped) - shellHeading
)

  return {
    code = trim(code),
    pointName = pointName,
    inside = insideHouse,
    preview = preview,
    currentHouseCode = trim(current.code),
    shell = trim((interior and interior.shellName) or (current.data and current.data.shell)),
    spawnCoords = spawnCoords,
    point = currentPoint(pointName == 'exit' or pointName == 'entrySpawn'),
    relativePoint = vectorPayload(relative, false),
    relativeHeading = relativeHeading
  }
end

local function teleportInside(offset, relativeHeading, useDefault)
  local interior = currentInterior()
  if type(interior) ~= 'table' then return false, 'interior_context_unavailable' end
  local target, heading
  if useDefault == true then
    target = vectorPayload(interior.defaultEntryCoords or interior.exitCoords,true)
    heading = target and target.heading or 0.0
  elseif useDefault == 'absolute' then
    target = vectorPayload(offset, false)
    heading = normalizeHeading(relativeHeading)
  else
    local localOffset = vectorPayload(offset, false)

if not localOffset then
  return false, 'invalid_internal_point'
end

local ok, world, resolveError = pcall(function()
  return exports['mz_interiors']:ResolveCurrentInteriorPoint({
    x = localOffset.x,
    y = localOffset.y,
    z = localOffset.z
  })
end)

if not ok or not world then
  return false, resolveError or 'invalid_internal_point'
end

target = vectorPayload(world, false)

local shellHeading = tonumber(interior.shellHeading) or 0.0

heading = normalizeHeading(
  shellHeading + (tonumber(relativeHeading) or 0.0)
)
  end
  if not target then return false, 'invalid_internal_point' end
  local ped = PlayerPedId()
  DoScreenFadeOut(200)
  local started = GetGameTimer()
  while not IsScreenFadedOut() and GetGameTimer() - started < 1000 do Wait(0) end
  FreezeEntityPosition(ped, true)
  SetEntityCoords(ped, target.x, target.y, target.z, false, false, false, false)
  SetEntityHeading(ped, heading)
  RequestCollisionAtCoord(target.x, target.y, target.z)
  Wait(250)
  FreezeEntityPosition(ped, false)
  DoScreenFadeIn(300)
  return true
end

local function internalStatusText(status)
  status = type(status) == 'table' and status or {}
  return ('%s/%s'):format(tostring(status.state or 'ausente'), tostring(status.source or 'none'))
end

local function internalSummary(property)
  local points = type(property) == 'table' and type(property.internalPoints) == 'table' and property.internalPoints or {}
  local entry = type(property) == 'table' and type(property.entrySpawn) == 'table' and property.entrySpawn or { mode = 'default' }
  return ('shell=%s spawn=%s saida=%s bau=%s armario=%s'):format(
    tostring(points.shell or property.shell or 'nil'),
    tostring(entry.mode == 'custom' and 'personalizado' or 'padrao'),
    internalStatusText(points.exit),
    internalStatusText(points.stash),
    internalStatusText(points.wardrobe)
  )
end

local function getShellOptions(selectedShell)
  local options = {}
  local seen = {}

  if GetResourceState('mz_interiors') == 'started' then
    local ok, shells = pcall(function()
      return exports['mz_interiors']:GetShells()
    end)

    if ok and type(shells) == 'table' then
      for name, shell in pairs(shells) do
        local shellName = nil
        local label = nil
        local enabled = true

        if type(shell) == 'table' and shell.name ~= nil then
          shellName = trim(shell.name)
          label = trim(shell.label) ~= '' and trim(shell.label) or shellName
          enabled = shell.enabled ~= false and shell.selectable ~= false
        elseif type(shell) == 'table' then
          shellName = trim(name)
          label = trim(shell.label) ~= '' and trim(shell.label) or shellName
          enabled = shell.enabled ~= false and shell.exit ~= nil
        end

        if enabled and shellName ~= '' and not seen[shellName] then
          seen[shellName] = true
          options[#options + 1] = {
            value = shellName,
            label = label
          }
        end
      end
    end
  end

  if #options == 0 then
    for shellName, defaults in pairs(MZHousesConfig.InteriorDefaults or {}) do
      local normalizedShellName = trim(shellName)
      if normalizedShellName ~= '' and not seen[normalizedShellName] then
        seen[normalizedShellName] = true
        options[#options + 1] = {
          value = normalizedShellName,
          label = trim(defaults and defaults.label) ~= '' and trim(defaults.label) or normalizedShellName
        }
      end
    end
  end

  local selected = trim(selectedShell)
  if selected ~= '' and not seen[selected] then
    options[#options + 1] = {
      value = selected,
      label = selected
    }
  end

  table.sort(options, function(left, right)
    return tostring(left.label or left.value or '') < tostring(right.label or right.value or '')
  end)

  return options
end

local function shellInputRow(label, defaultShell)
  local options = getShellOptions(defaultShell)
  if #options > 0 then
    return {
      type = 'select',
      label = label or 'Shell / Interior',
      required = true,
      default = trim(defaultShell) ~= '' and trim(defaultShell) or options[1].value,
      options = options
    }
  end

  return {
    type = 'input',
    label = label or 'Shell / Interior',
    required = true,
    default = trim(defaultShell) ~= '' and trim(defaultShell) or 'shell_test'
  }
end

local function boolSelectRow(label, defaultValue)
  return {
    type = 'select',
    label = label,
    required = true,
    default = defaultValue == true and 'true' or 'false',
    options = {
      { value = 'true', label = 'Sim' },
      { value = 'false', label = 'Nao' }
    }
  }
end

local function inputBool(value)
  return tostring(value or '') == 'true'
end

local function splitList(value)
  local out, seen = {}, {}
  for rawItem in tostring(value or ''):gmatch('[^,%s;]+') do
    local item = trim(rawItem)
    if item ~= '' and not seen[item] then
      seen[item] = true
      out[#out + 1] = item
    end
  end
  return out
end

local function apartmentBuildingOptions()
  local response = callAdmin('mz_houses:server:admin:listApartmentBuildings', {})
  local options = {}
  if response.ok == true and type(response.buildings) == 'table' then
    for _, building in ipairs(response.buildings) do
      options[#options + 1] = {
        value = tostring(building.code),
        label = ('%s - %s'):format(tostring(building.code), tostring(building.label or ''))
      }
    end
  end
  return options
end

local function groupOptions(groupType)
  local response = callAdmin('mz_houses:server:admin:listGroups', { type = groupType })
  local options = {}
  if response.ok == true and type(response.groups) == 'table' then
    for _, group in ipairs(response.groups) do
      options[#options + 1] = {
        value = tostring(group.code),
        label = ('%s (%s)'):format(tostring(group.label or group.code), tostring(group.code))
      }
    end
  end
  return options, response.error
end

callAdmin = function(name, payload)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return { ok = false, error = 'ox_lib_callback_unavailable' }
end

  local ok, response = pcall(function()
    return lib.callback.await(name, false, payload or {})
  end)

  if not ok then
    return { ok = false, error = tostring(response or 'callback_failed') }
  end

  if type(response) ~= 'table' then
    return { ok = false, error = 'invalid_response' }
  end

  return response
end

local function handleResponse(response, reopenCode)
  response = type(response) == 'table' and response or { ok = false, error = 'invalid_response' }

  if response.ok ~= true then
    notify(('Erro: %s'):format(tostring(response.error or 'falha')), 'error')
    return false, response
  end

  if trim(response.message) ~= '' then
    notify(response.message, 'success')
  end

  if type(response.property) == 'table' then
    AdminMenuState.currentCode = response.property.code
    AdminMenuState.currentProperty = response.property
    if MZHouses and type(MZHouses.UpdateCurrentHouseData) == 'function' then
      MZHouses.UpdateCurrentHouseData(response.property)
    end
  end

  if reopenCode ~= false then
    local code = trim(reopenCode or AdminMenuState.currentCode)
    if code ~= '' then
      SetTimeout(150, function()
        MZHousesAdminMenu.OpenProperty(code)
      end)
    end
  end

  return true, response
end

local function getProperty(code)
  code = trim(code)
  if code == '' then
    return nil
  end

  local response = callAdmin('mz_houses:server:admin:getPropertyInfo', { code = code })
  if response.ok ~= true then
    notify(('Erro: %s'):format(tostring(response.error or 'house_not_found')), 'error')
    return nil
  end

  AdminMenuState.currentCode = response.property.code
  AdminMenuState.currentProperty = response.property
  if MZHouses and type(MZHouses.UpdateCurrentHouseData) == 'function' then
    MZHouses.UpdateCurrentHouseData(response.property)
  end
  return response.property
end

local function boolText(value)
  return value == true and 'sim' or 'nao'
end

local function garageSummary(property)
  local garage = type(property) == 'table' and type(property.garage) == 'table' and property.garage or {}
  return ('enabled=%s mode=%s slots=%s'):format(
    boolText(garage.enabled == true),
    tostring(garage.mode or 'nil'),
    tostring(garage.slots or 'nil')
  )
end

local function propertyDescription(property)
  property = type(property) == 'table' and property or {}
  local relation = ''
  if trim(property.parentCode) ~= '' then
    relation = (' | parent=%s unit=%s'):format(tostring(property.parentCode), tostring(property.unitNumber or 'nil'))
  end
  return ('%s/%s/%s%s | public=%s | visibility=%s | garage=%s'):format(
    tostring(property.category or 'nil'),
    tostring(property.subtype or 'nil'),
    tostring(property.ownerType or 'nil'),
    relation,
    boolText(property.public == true),
    tostring(property.visibility or 'auto'),
    garageSummary(property)
  )
end

local function showInfo(property)
  property = property or AdminMenuState.currentProperty
  if type(property) ~= 'table' then
    notify('Imovel nao carregado.', 'error')
    return
  end

  local text = table.concat({
    ('Code: %s'):format(tostring(property.code or 'nil')),
    ('Label: %s'):format(tostring(property.label or 'nil')),
    ('Status: %s / enabled=%s'):format(tostring(property.status or 'nil'), boolText(property.enabled == true)),
    ('Category: %s / %s / %s'):format(tostring(property.category or 'nil'), tostring(property.subtype or 'nil'), tostring(property.ownerType or 'nil')),
    ('Parent/Unit: %s / %s'):format(tostring(property.parentCode or 'nil'), tostring(property.unitNumber or 'nil')),
    ('OrgCode: %s'):format(tostring(property.orgCode or 'nil')),
    ('Shell: %s'):format(tostring(property.shell or 'nil')),
    ('Visibility: %s'):format(tostring(property.visibility or 'auto')),
    ('Public: %s'):format(boolText(property.public == true)),
    ('AccessPolicy: %s / rules=%s'):format(
      tostring(property.accessPolicy and property.accessPolicy.mode or 'fallback'),
      tostring(property.accessPolicy and property.accessPolicy.rules and #property.accessPolicy.rules or 0)
    ),
    ('CanBeListed: %s (%s)'):format(boolText(property.canBeListed == true), tostring(property.canBeListedReason or 'nil')),
    ('Owner: %s'):format(property.owner and 'sim' or 'nao'),
    ('Keys: %s'):format(tostring(property.keyCount or 0)),
    ('Garage: %s'):format(garageSummary(property)),
    ('Pontos internos: %s'):format(internalSummary(property))
  }, '\n')

  if visualMenuReady() then
    alertDialog({
      header = tostring(property.label or property.code or 'Imovel'),
      content = text,
      centered = true,
      cancel = false
    })
    return
  end

  notify(text, 'inform')
end

local function openMainMenu()
  openContext({
    id = 'mz_houses_admin_main',
    title = 'Gerenciar Imoveis',
    options = {
      {
        title = 'Criar imovel',
        icon = 'plus',
        onSelect = function()
          MZHousesAdminMenu.OpenCreateMenu()
        end
      },
      {
        title = 'Pre-visualizar interior',
        description = 'Instancia temporaria e isolada, sem salvar propriedade',
        icon = 'scan-eye',
        onSelect = function()
          MZHousesAdminMenu.PreviewShell()
        end
      },
      {
        title = 'Editar imovel proximo',
        icon = 'map-pin',
        onSelect = function()
          MZHousesAdminMenu.OpenNearby()
        end
      },
      {
        title = 'Listar / pesquisar propriedades',
        icon = 'search',
        onSelect = function()
          MZHousesAdminMenu.SearchByCode()
        end
      },
      {
        title = 'Migracao / auditoria legada',
        description = 'Preview manual de conversao e auditoria JSON sem apagar dados',
        icon = 'file-search',
        onSelect = function()
          MZHousesAdminMenu.OpenLegacyTools()
        end
      },
      {
        title = 'Recarregar/Atualizar',
        icon = 'refresh-cw',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:reload', {}), false)
        end
      },
      {
        title = 'Ajuda rapida',
        icon = 'circle-help',
        onSelect = function()
          notify('Sistema administrativo: somente a staff cria, edita, atribui dono e gerencia chaves.', 'inform')
        end
      }
    }
  })
end

function MZHousesAdminMenu_OpenProperty(code)
  local property = getProperty(code)
  if not property then
    return
  end

  openContext({
    id = 'mz_houses_admin_property',
    title = tostring(property.label or property.code),
    menu = 'mz_houses_admin_main',
    options = {
      {
        title = 'Informacoes',
        description = propertyDescription(property),
        icon = 'info',
        onSelect = function()
          showInfo(property)
          MZHousesAdminMenu.OpenProperty(property.code)
        end
      },
      {
        title = 'Logs recentes',
        description = 'Ultimas 20 operacoes administrativas locais',
        icon = 'scroll-text',
        onSelect = function()
          local response = callAdmin('mz_houses:server:admin:getPropertyLogs', { code = property.code })
          if response.ok ~= true then return handleResponse(response, property.code) end
          local options = {}
          for _, log in ipairs(response.logs or {}) do
            options[#options + 1] = {
              title = tostring(log.action or 'acao'),
              description = ('actor=%s target=%s | %s'):format(tostring(log.actor_citizenid or '-'), tostring(log.target_citizenid or '-'), tostring(log.created_at or '-')),
              icon = 'history'
            }
          end
          if #options == 0 then options[1] = { title = 'Sem logs locais', disabled = true } end
          openContext({ id = 'mz_houses_admin_logs', title = 'Logs - ' .. property.code, menu = 'mz_houses_admin_property', options = options })
        end
      },
      {
        title = 'Configuracao basica',
        icon = 'settings',
        onSelect = function()
          MZHousesAdminMenu.OpenBasic(property.code)
        end
      },
      {
        title = 'Entrada / Interior',
        icon = 'door-open',
        onSelect = function()
          MZHousesAdminMenu.OpenInterior(property.code)
        end
      },
      {
        title = 'Teleportar ate a entrada',
        icon = 'navigation',
        onSelect = function()
          local entrance = property.entrance
          if type(entrance) ~= 'table' then return notify('Entrada nao configurada.', 'error') end
          SetEntityCoords(PlayerPedId(), tonumber(entrance.x), tonumber(entrance.y), tonumber(entrance.z), false, false, false, false)
          SetEntityHeading(PlayerPedId(), tonumber(entrance.w or entrance.h) or 0.0)
        end
      },
      {
        title = 'Entrar para manutencao',
        description = 'Teleporta a entrada e abre o interior com autorizacao admin',
        icon = 'scan-eye',
        onSelect = function()
          local entrance = property.entrance
          if type(entrance) ~= 'table' then return notify('Entrada nao configurada.', 'error') end
          SetEntityCoords(PlayerPedId(), tonumber(entrance.x), tonumber(entrance.y), tonumber(entrance.z), false, false, false, false)
          SetEntityHeading(PlayerPedId(), tonumber(entrance.w or entrance.h) or 0.0)
          Wait(150)
          local ok, err = MZHouses.EnterHouse(property.code, { skipPurchase = true })
          if not ok then notify(('Falha ao entrar: %s'):format(tostring(err)), 'error') end
        end
      },
      {
        title = 'Interior / Pontos Internos',
        description = internalSummary(property),
        icon = 'scan-line',
        onSelect = function()
          MZHousesAdminMenu.OpenInternalPoints(property.code)
        end
      },
      {
        title = 'Unidades do predio',
        description = property.subtype == 'apartment_building' and 'Gerenciar apartamentos vinculados' or 'Disponivel apenas para predios',
        icon = 'building',
        disabled = property.subtype ~= 'apartment_building',
        onSelect = function()
          MZHousesAdminMenu.OpenBuildingUnits(property.code)
        end
      },
      {
        title = 'Garagem',
        icon = 'car',
        onSelect = function()
          MZHousesAdminMenu.OpenGarage(property.code)
        end
      },
      {
        title = 'Comercio residencial',
        description = property.saleEnabled == true
          and ('%s | R$ %s'):format(tostring(property.saleMode), tostring(property.salePrice or 0))
          or 'Fora de venda',
        icon = 'badge-dollar-sign',
        disabled = not (property.category == 'residential' and property.ownerType == 'player'
          and (property.subtype == 'house' or property.subtype == 'apartment_unit' or property.subtype == 'apartment')),
        onSelect = function()
          MZHousesAdminMenu.OpenCommerce(property.code)
        end
      },
      {
        title = 'IPTU',
        description = type(property.tax) == 'table'
          and ('%s | %s | vencimento=%s'):format(
            property.tax.enabled and ('R$ ' .. tostring(property.tax.amount or 0)) or 'desativado',
            tostring(property.tax.status or 'disabled'), tostring(property.tax.dueAt or '-'))
          or 'Desativado',
        icon = 'landmark',
        disabled = not (property.category == 'residential' and property.ownerType == 'player'
          and (property.subtype == 'house' or property.subtype == 'apartment_unit' or property.subtype == 'apartment')),
        onSelect = function()
          MZHousesAdminMenu.OpenTax(property.code)
        end
      },
      {
        title = 'Protecao contra lote comercial',
        description = property.subtype == 'apartment_unit'
          and ((property.metadata or {}).bulkCommerceProtected == true and 'Ativa: lotes ignoram esta unidade' or 'Inativa')
          or 'Disponivel somente para unidades',
        icon = 'shield-ban',
        disabled = property.subtype ~= 'apartment_unit',
        onSelect = function()
          local protected = (property.metadata or {}).bulkCommerceProtected == true
          local decision = alertDialog({
            header = protected and 'Remover protecao do lote?' or 'Proteger unidade do lote?',
            content = protected
              and 'A unidade voltara a ser elegivel para operacoes comerciais em lote quando estiver sem owner e sem transacao ambigua.'
              or 'Operacoes comerciais em lote passarao a ignorar esta unidade.',
            centered = true,
            cancel = true
          })
          if decision ~= 'confirm' then return end
          handleResponse(callAdmin('mz_houses:server:admin:setUnitBulkProtection', {
            code = property.code,
            protected = not protected
          }), property.code)
        end
      },
      {
        title = 'Dono / Chaves',
        description = property.accessPolicy and property.accessPolicy.mode ~= 'owner' and 'Disponivel somente para politica owner' or nil,
        icon = 'key-round',
        disabled = property.accessPolicy and property.accessPolicy.mode ~= 'owner' or false,
        onSelect = function()
          MZHousesAdminMenu.OpenOwnerKeys(property.code)
        end
      },
      {
        title = 'Politica de acesso',
        description = tostring(property.accessPolicy and property.accessPolicy.mode or 'fallback legado'),
        icon = 'shield-check',
        onSelect = function()
          MZHousesAdminMenu.OpenAccessPolicy(property.code)
        end
      },
      {
        title = 'Migrar propriedade legada',
        description = 'Conversao explicita com preview; nao limpa JSON nem historico',
        icon = 'replace',
        onSelect = function()
          MZHousesAdminMenu.OpenLegacyMigration(property.code)
        end
      },
      {
        title = 'Recursos e permissoes',
        description = 'Bau, guarda-roupa, garagem e moveis',
        icon = 'sliders-horizontal',
        onSelect = function()
          MZHousesAdminMenu.OpenFeaturePermissions(property.code)
        end
      },
      {
        title = 'Estado da porta',
        description = tostring(property.door and property.door.state or property.doorState or 'fallback'),
        icon = 'door-closed',
        onSelect = function()
          local current = tostring(property.door and property.door.state or 'locked')
          local input = inputDialog('Estado da porta', {
            { type = 'select', label = 'Estado', required = true, default = current, options = {
              { value = 'locked', label = 'Trancada' }, { value = 'unlocked', label = 'Destrancada' }, { value = 'blocked', label = 'Interditada' }
            } }
          })
          if input then handleResponse(callAdmin('mz_houses:server:admin:setDoorState', { code = property.code, state = trim(input[1]) }), property.code) end
        end
      },
      {
        title = 'Visibilidade',
        icon = 'eye',
        onSelect = function()
          MZHousesAdminMenu.OpenVisibility(property.code)
        end
      },
      {
        title = 'Ativar / Desativar / Arquivar',
        icon = 'power',
        onSelect = function()
          MZHousesAdminMenu.OpenState(property.code)
        end
      },
      {
        title = 'Recarregar pontos',
        icon = 'refresh-cw',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:reload', {}), property.code)
        end
      }
    }
  })
end

MZHousesAdminMenu = MZHousesAdminMenu or {}

function MZHousesAdminMenu.Open()
  if menuConfig().enabled == false then
    notify('Menu admin de casas esta desativado.', 'error')
    return
  end

  if not visualMenuReady() then
    notify('mz_menu e necessario para /mhouse_admin. Use os comandos admin como fallback.', 'error')
    return
  end

  local access = callAdmin('mz_houses:server:admin:checkAccess', {})
  if access.ok ~= true then
    notify('Voce nao tem permissao para usar este menu.', 'error')
    return
  end

  openMainMenu()
end

local PreviewActive = false

local function releasePreviewSession()
  local response = callAdmin('mz_houses:server:admin:endPreview', {})
  if response.ok ~= true then
    -- Evento idempotente de fallback: evita prender bucket/state caso o
    -- callback falhe depois que o preview ja foi criado no servidor.
    TriggerServerEvent('mz_houses:server:adminPreviewStopped')
  end
  return response.ok == true
end

function MZHousesAdminMenu.ExitPreview()
  if not PreviewActive then return false end
  pcall(function() exports['mz_interiors']:ExitShell() end)
  releasePreviewSession()
  PreviewActive = false
  notify('Previa encerrada sem salvar alteracoes.', 'success')
  return true
end

function MZHousesAdminMenu.PreviewShell()
  if PreviewActive then return MZHousesAdminMenu.ExitPreview() end
  local input = inputDialog('Pre-visualizar interior', { shellInputRow('Shell / Interior', 'shell_test') })
  if not input then return end
  local shell = trim(input[1])
  local point = currentPoint(true)
  local response = callAdmin('mz_houses:server:admin:beginPreview', { shell = shell })
  if response.ok ~= true then return handleResponse(response, false) end
  local callOk, ok, err = pcall(function()
    return exports['mz_interiors']:EnterShell(shell, point, {
      instanceId = ('house-preview:%s'):format(GetPlayerServerId(PlayerId())),
      spawnBase = MZHousesConfig.InteriorSpawnBase,
      metadata = { preview = true, shell = shell }
    })
  end)
  if not callOk then
    err = ok
    ok = false
  end
  if not ok then
    releasePreviewSession()
    return notify(('Falha na previa: %s'):format(tostring(err)), 'error')
  end
  PreviewActive = true
  notify('Previa isolada aberta. Use /mzhouses_preview_exit para sair.', 'inform')
end

function MZHousesAdminMenu.OpenCreateMenu()
  openContext({
    id = 'mz_houses_admin_create',
    title = 'Criar imovel',
    menu = 'mz_houses_admin_main',
    options = {
      {
        title = 'Casa comum',
        description = 'Code automatico: house_000001',
        icon = 'home',
        onSelect = function()
          MZHousesAdminMenu.CreateHouseHere()
        end
      },
      {
        title = 'Predio de apartamentos',
        description = 'Cria entrada/interfone e unidades opcionais',
        icon = 'building-2',
        onSelect = function()
          MZHousesAdminMenu.CreateApartmentBuildingHere()
        end
      },
      {
        title = 'Unidade em predio existente',
        description = 'Code automatico: apt_000001_101',
        icon = 'door-open',
        onSelect = function()
          MZHousesAdminMenu.CreateApartmentUnit()
        end
      },
      {
        title = 'Sede de gang',
        description = 'Interior por gang real e grade minima',
        icon = 'shield',
        onSelect = function() MZHousesAdminMenu.CreateGroupInterior('gang') end
      },
      {
        title = 'Sede de job',
        description = 'Interior por job real, grade e duty opcional',
        icon = 'briefcase-business',
        onSelect = function() MZHousesAdminMenu.CreateGroupInterior('job') end
      },
      {
        title = 'Interior publico',
        description = 'Sem owner; visibilidade e acesso publicos',
        icon = 'users',
        onSelect = function() MZHousesAdminMenu.CreateUniversalInterior('public') end
      },
      {
        title = 'Interior administrativo',
        description = 'Somente administradores',
        icon = 'shield-lock',
        onSelect = function() MZHousesAdminMenu.CreateUniversalInterior('admin') end
      },
      {
        title = 'Avancado: criar por code manual',
        description = 'Fallback tecnico/debug',
        icon = 'terminal',
        onSelect = function()
          MZHousesAdminMenu.CreateHere()
        end
      }
    }
  })
end

function MZHousesAdminMenu.CreateHere()
  local input = inputDialog('Criar imovel avancado', {
    { type = 'input', label = 'Codigo', required = true, placeholder = 'casa_mirror_01' },
    { type = 'input', label = 'Label', required = true, placeholder = 'Casa Mirror Park 01' },
    shellInputRow('Shell / Interior', 'shell_test')
  })

  if not input then return end

  local response = callAdmin('mz_houses:server:admin:createProperty', {
    code = trim(input[1]),
    label = trim(input[2]),
    shell = trim(input[3]) ~= '' and trim(input[3]) or 'shell_test',
    entrance = currentPoint(true)
  })

  handleResponse(response, response.property and response.property.code or nil)
end

function MZHousesAdminMenu.CreateHouseHere()
  local input = inputDialog('Criar casa comum', {
    { type = 'input', label = 'Label', required = false, placeholder = 'Casa Mirror Park 01' },
    shellInputRow('Shell / Interior', 'shell_test'),
    boolSelectRow('Garagem ativa', false),
    { type = 'select', label = 'Modo de venda', required = true, default = 'none', options = {
      { value = 'none', label = 'Sem venda' }, { value = 'admin', label = 'Venda administrativa' }, { value = 'direct', label = 'Compra direta' }
    } },
    { type = 'number', label = 'Preco real', required = true, default = 0, min = 0 },
    boolSelectRow('Disponibilizar para venda', false),
    boolSelectRow('IPTU habilitado quando houver owner', false),
    { type = 'number', label = 'Valor do IPTU', required = true, default = 0, min = 0 },
    { type = 'number', label = 'Intervalo do IPTU em dias', required = true, default = 7, min = 1 },
    { type = 'number', label = 'Tolerancia em dias', required = true, default = 3, min = 0 }
  })
  if not input then return end

  local response = callAdmin('mz_houses:server:admin:createStructuredProperty', {
    kind = 'house',
    label = trim(input[1]),
    shell = trim(input[2]),
    canBeListed = false,
    garageEnabled = inputBool(input[3]),
    saleMode = trim(input[4]),
    salePrice = tonumber(input[5]) or 0,
    saleEnabled = inputBool(input[6]),
    taxEnabled = inputBool(input[7]),
    taxAmount = tonumber(input[8]) or 0,
    taxIntervalDays = tonumber(input[9]) or 7,
    taxGracePeriodDays = tonumber(input[10]) or 3,
    entrance = currentPoint(true)
  })
  handleResponse(response, response.property and response.property.code or nil)
end

function MZHousesAdminMenu.CreateApartmentBuildingHere()
  local input = inputDialog('Criar predio de apartamentos', {
    { type = 'input', label = 'Nome visual', required = false, placeholder = 'Edificio Mirror Park' },
    { type = 'number', label = 'Andares', required = true, default = 2, min = 1 },
    { type = 'number', label = 'Unidades por andar', required = true, default = 2, min = 1 },
    { type = 'number', label = 'Primeiro andar', required = true, default = 1, min = 0 },
    shellInputRow('Shell padrao das unidades', 'apartment_low'),
    boolSelectRow('Venda habilitada nas novas unidades', false),
    { type = 'select', label = 'Modo padrao das unidades', required = true, default = 'none', options = {
      { value = 'none', label = 'Sem venda' }, { value = 'admin', label = 'Venda administrativa' }, { value = 'direct', label = 'Compra direta' }
    } },
    { type = 'number', label = 'Preco padrao das unidades', required = true, default = 0, min = 0 },
    boolSelectRow('Criar unidades automaticamente', true),
    boolSelectRow('Garagem compartilhada ativa', false),
    boolSelectRow('IPTU padrao das novas unidades', false),
    { type = 'number', label = 'Valor padrao do IPTU', required = true, default = 0, min = 0 },
    { type = 'number', label = 'Intervalo padrao em dias', required = true, default = 7, min = 1 },
    { type = 'number', label = 'Tolerancia padrao em dias', required = true, default = 3, min = 0 }
  })
  if not input then return end

  local summary = ('Criar predio com %d andar(es), %d unidade(s) por andar. Defaults: shell=%s, venda=%s/%s, preco=R$ %d; IPTU=%s R$ %d/%d dias + %d tolerancia.'):format(
    math.floor(tonumber(input[2]) or 1), math.floor(tonumber(input[3]) or 1),
    trim(input[5]), inputBool(input[6]) and 'ativa' or 'inativa', trim(input[7]),
    math.floor(tonumber(input[8]) or 0), inputBool(input[11]) and 'ativo' or 'inativo',
    math.floor(tonumber(input[12]) or 0), math.floor(tonumber(input[13]) or 7), math.floor(tonumber(input[14]) or 3)
  )
  if alertDialog({ header = 'Revisar criacao do predio', content = summary, centered = true, cancel = true }) ~= 'confirm' then return end

  local response = callAdmin('mz_houses:server:admin:createStructuredProperty', {
    kind = 'apartment_building',
    label = trim(input[1]),
    floors = tonumber(input[2]) or 1,
    unitsPerFloor = tonumber(input[3]) or 1,
    firstFloor = tonumber(input[4]) or 1,
    shell = trim(input[5]),
    defaultUnitSaleEnabled = inputBool(input[6]),
    defaultUnitSaleMode = trim(input[7]),
    defaultUnitSalePrice = tonumber(input[8]) or 0,
    createUnits = inputBool(input[9]),
    garageEnabled = inputBool(input[10]),
    defaultUnitTaxEnabled = inputBool(input[11]),
    defaultUnitTaxAmount = tonumber(input[12]) or 0,
    defaultUnitTaxIntervalDays = tonumber(input[13]) or 7,
    defaultUnitTaxGracePeriodDays = tonumber(input[14]) or 3,
    entrance = currentPoint(true)
  })
  handleResponse(response, response.property and response.property.code or nil)
end

function MZHousesAdminMenu.CreateApartmentUnit()
  local buildings = apartmentBuildingOptions()
  if #buildings == 0 then
    notify('Nenhum predio de apartamentos encontrado.', 'error')
    return
  end

  local buildingInput = inputDialog('Selecionar predio', {
    { type = 'select', label = 'Predio', required = true, options = buildings, default = buildings[1].value },
  })
  if not buildingInput then return end
  local buildingCode = trim(buildingInput[1])
  local defaultsResponse = callAdmin('mz_houses:server:admin:getBuildingUnitDefaults', { code = buildingCode })
  if defaultsResponse.ok ~= true then return handleResponse(defaultsResponse) end
  local defaults = defaultsResponse.defaults or {}
  local input = inputDialog('Criar unidade de apartamento', {
    { type = 'input', label = 'Numero da unidade', required = true, placeholder = '305' },
    { type = 'input', label = 'Label', required = false, placeholder = 'Apartamento 305' },
    shellInputRow('Shell / Interior', trim(defaults.shell) ~= '' and trim(defaults.shell) or 'apartment_low'),
    { type = 'select', label = 'Modo de venda', required = true, default = tostring(defaults.saleMode or 'none'), options = {
      { value = 'none', label = 'Sem venda' }, { value = 'admin', label = 'Venda administrativa' }, { value = 'direct', label = 'Compra direta' }
    } },
    { type = 'number', label = 'Preco real da unidade', required = true, default = tonumber(defaults.salePrice) or 0, min = 0 },
    boolSelectRow('Disponibilizar para venda', defaults.saleEnabled == true),
    boolSelectRow('IPTU habilitado quando houver owner', type(defaults.tax) == 'table' and defaults.tax.enabled == true),
    { type = 'number', label = 'Valor do IPTU', required = true, default = type(defaults.tax) == 'table' and tonumber(defaults.tax.amount) or 0, min = 0 },
    { type = 'number', label = 'Intervalo em dias', required = true, default = type(defaults.tax) == 'table' and tonumber(defaults.tax.intervalDays) or 7, min = 1 },
    { type = 'number', label = 'Tolerancia em dias', required = true, default = type(defaults.tax) == 'table' and tonumber(defaults.tax.gracePeriodDays) or 3, min = 0 }
  })
  if not input then return end

  if alertDialog({
    header = 'Revisar nova unidade',
    content = ('Predio %s, unidade %s, shell %s, venda %s/%s, preco R$ %d; IPTU %s R$ %d/%d dias + %d tolerancia.'):format(
      buildingCode, trim(input[1]), trim(input[3]), inputBool(input[6]) and 'ativa' or 'inativa',
      trim(input[4]), math.floor(tonumber(input[5]) or 0), inputBool(input[7]) and 'ativo' or 'inativo',
      math.floor(tonumber(input[8]) or 0), math.floor(tonumber(input[9]) or 7),
      math.floor(tonumber(input[10]) or 3)
    ), centered = true, cancel = true
  }) ~= 'confirm' then return end

  local response = callAdmin('mz_houses:server:admin:createStructuredProperty', {
    kind = 'apartment_unit',
    parentCode = buildingCode,
    unitNumber = trim(input[1]),
    label = trim(input[2]),
    shell = trim(input[3]),
    saleMode = trim(input[4]),
    salePrice = tonumber(input[5]) or 0,
    saleEnabled = inputBool(input[6]),
    taxEnabled = inputBool(input[7]),
    taxAmount = tonumber(input[8]) or 0,
    taxIntervalDays = tonumber(input[9]) or 7,
    taxGracePeriodDays = tonumber(input[10]) or 3,
    entrance = currentPoint(true)
  })
  handleResponse(response, response.property and response.property.code or nil)
end

function MZHousesAdminMenu.CreateGroupInterior(groupType)
  local groups, groupErr = groupOptions(groupType)
  if #groups == 0 then
    notify(('Nenhum %s ativo encontrado: %s'):format(groupType, tostring(groupErr or 'lista_vazia')), 'error')
    return
  end

  local rows = {
    { type = 'select', label = groupType == 'gang' and 'Gang' or 'Job', required = true, options = groups, default = groups[1].value },
    { type = 'number', label = 'Grade minima', required = true, default = 0, min = 0, max = 1000 },
    { type = 'number', label = 'Grade para controlar porta', required = true, default = 0, min = 0, max = 1000 },
    { type = 'input', label = 'Nome visual', required = false },
    shellInputRow('Shell / Interior', groupType == 'gang' and 'container' or 'shell_test')
  }
  if groupType == 'job' then rows[#rows + 1] = boolSelectRow('Exigir em servico', false) end
  rows[#rows + 1] = boolSelectRow('Bau ativo', false)
  rows[#rows + 1] = boolSelectRow('Guarda-roupa ativo', false)
  rows[#rows + 1] = boolSelectRow('Garagem ativa', false)

  local input = inputDialog(groupType == 'gang' and 'Criar sede de gang' or 'Criar sede de job', rows)
  if not input then return end
  local index = 6
  local requireDuty = false
  if groupType == 'job' then requireDuty = inputBool(input[index]); index = index + 1 end
  local response = callAdmin('mz_houses:server:admin:createStructuredProperty', {
    kind = groupType == 'gang' and 'gang_interior' or 'job_interior',
    groupCode = trim(input[1]), minimumGrade = tonumber(input[2]), canControlDoorFromGrade = tonumber(input[3]),
    label = trim(input[4]), shell = trim(input[5]), requireDuty = requireDuty,
    stashEnabled = inputBool(input[index]), wardrobeEnabled = inputBool(input[index + 1]),
    garageEnabled = inputBool(input[index + 2]), entrance = currentPoint(true)
  })
  handleResponse(response, response.property and response.property.code or nil)
end

function MZHousesAdminMenu.CreateUniversalInterior(mode)
  local input = inputDialog(mode == 'public' and 'Criar interior publico' or 'Criar interior administrativo', {
    { type = 'input', label = 'Nome visual', required = false },
    shellInputRow('Shell / Interior', 'shell_test')
  })
  if not input then return end
  local response = callAdmin('mz_houses:server:admin:createStructuredProperty', {
    kind = mode == 'public' and 'public_interior' or 'admin_interior',
    label = trim(input[1]), shell = trim(input[2]), entrance = currentPoint(true)
  })
  handleResponse(response, response.property and response.property.code or nil)
end

function MZHousesAdminMenu.OpenNearby()
  local cfg = menuConfig()
  local response = callAdmin('mz_houses:server:admin:listNearbyProperties', {
    coords = currentPoint(false),
    radius = tonumber(cfg.nearPropertyRadius) or 25.0,
    maxResults = tonumber(cfg.maxNearbyResults) or 10
  })

  if response.ok ~= true then
    notify(('Erro: %s'):format(tostring(response.error or 'nearby_failed')), 'error')
    return
  end

  if type(response.properties) ~= 'table' or #response.properties == 0 then
    notify('Nenhum imovel proximo.', 'error')
    return
  end

  local options = {}
  for _, property in ipairs(response.properties) do
    options[#options + 1] = {
      title = ('%s - %.1fm'):format(tostring(property.code), tonumber(property.distance) or 0.0),
      description = tostring(property.label or ''),
      icon = 'map-pin',
      onSelect = function()
        MZHousesAdminMenu.OpenProperty(property.code)
      end
    }
  end

  openContext({
    id = 'mz_houses_admin_nearby',
    title = 'Imoveis proximos',
    menu = 'mz_houses_admin_main',
    options = options
  })
end

function MZHousesAdminMenu.SearchByCode()
  local input = inputDialog('Buscar imovel', {
    { type = 'input', label = 'Codigo, nome, owner, categoria ou status', required = false }
  })

  if not input then return end
  local response = callAdmin('mz_houses:server:admin:searchProperties', { query = trim(input[1]) })
  if response.ok ~= true then return handleResponse(response, false) end
  if type(response.properties) ~= 'table' or #response.properties == 0 then
    return notify('Nenhuma propriedade encontrada.', 'error')
  end
  local options = {}
  for _, property in ipairs(response.properties) do
    local code = property.code
    options[#options + 1] = {
      title = ('%s - %s'):format(code, tostring(property.label or code)),
      description = ('owner=%s | %s/%s | %s'):format(tostring(property.owner or '-'), tostring(property.category), tostring(property.subtype), tostring(property.status)),
      icon = 'house',
      onSelect = function() MZHousesAdminMenu.OpenProperty(code) end
    }
  end
  openContext({ id = 'mz_houses_admin_search', title = 'Propriedades', menu = 'mz_houses_admin_main', options = options })
end

function MZHousesAdminMenu.OpenProperty(code)
  return MZHousesAdminMenu_OpenProperty(code)
end

function MZHousesAdminMenu.OpenBasic(code)
  local property = getProperty(code)
  if not property then return end

  openContext({
    id = 'mz_houses_admin_basic',
    title = 'Configuracao basica',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = 'Alterar label',
        description = tostring(property.label or ''),
        icon = 'tag',
        onSelect = function()
          local input = inputDialog('Alterar label', {
            { type = 'input', label = 'Label', required = true, default = tostring(property.label or '') }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:updateBasic', {
              code = code,
              field = 'label',
              label = trim(input[1])
            }), code)
          end
        end
      },
      {
        title = 'Alterar shell',
        description = tostring(property.shell or ''),
        icon = 'box',
        onSelect = function()
          local input = inputDialog('Alterar shell', {
            shellInputRow('Shell / Interior', tostring(property.shell or 'shell_test'))
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setShell', {
              code = code,
              shell = trim(input[1])
            }), code)
          end
        end
      },
      {
        title = 'Alterar categoria/tipo',
        description = ('%s / %s / %s'):format(tostring(property.category or ''), tostring(property.subtype or ''), tostring(property.ownerType or '')),
        icon = 'layers',
        onSelect = function()
          local input = inputDialog('Categoria/tipo', {
            { type = 'select', label = 'Category', required = true, default = tostring(property.category or 'residential'), options = {
              { value = 'residential', label = 'residential' },
              { value = 'other', label = 'other' }
            } },
            { type = 'input', label = 'Subtype', required = true, default = tostring(property.subtype or 'house') },
            { type = 'select', label = 'OwnerType', required = true, default = tostring(property.ownerType or 'player'), options = {
              { value = 'player', label = 'player' },
              { value = 'server', label = 'server' }
            } }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setCategory', {
              code = code,
              category = trim(input[1]),
              subtype = trim(input[2]),
              ownerType = trim(input[3])
            }), code)
          end
        end
      },
      {
        title = 'Metadata administrativa',
        description = 'Preco apenas informativo e notas internas',
        icon = 'notebook-tabs',
        onSelect = function()
          local metadata = type(property.metadata) == 'table' and property.metadata or {}
          local input = inputDialog('Metadata administrativa', {
            { type = 'number', label = 'Preco informativo (sem cobranca)', required = false, default = metadata.administrativePrice },
            { type = 'textarea', label = 'Notas internas', required = false, default = tostring(metadata.notes or '') }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:updateBasic', {
              code = code, field = 'metadata', price = input[1], notes = input[2]
            }), code)
          end
        end
      }
    }
  })
end

function MZHousesAdminMenu.OpenInterior(code)
  local property = getProperty(code)
  if not property then return end

  openContext({
    id = 'mz_houses_admin_interior',
    title = 'Entrada / Interior',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = 'Definir entrada aqui',
        description = 'Usa posicao e heading atuais',
        icon = 'map-pin',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setEntrance', {
            code = code,
            entrance = currentPoint(true)
          }), code)
        end
      },
      {
        title = 'Alterar shell',
        description = tostring(property.shell or ''),
        icon = 'box',
        onSelect = function()
          local input = inputDialog('Alterar shell', {
            shellInputRow('Shell / Interior', tostring(property.shell or 'shell_test'))
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setShell', {
              code = code,
              shell = trim(input[1])
            }), code)
          end
        end
      }
    }
  })
end

function MZHousesAdminMenu.SetInternalPoint(code, pointName)
  local property = getProperty(code)
  if not property then return end
  local payload, err = interiorEditPayload(code, pointName, property)
  if not payload then
    notify(err or 'Entre no imovel para definir pontos internos.', 'error')
    return
  end

  local relative = payload.relativePoint or {}
  local confirmed = alertDialog({
    header = pointName == 'entrySpawn' and 'Confirmar spawn de entrada' or 'Confirmar ponto interno',
    content = ('offset=(%.3f, %.3f, %.3f) heading=%.2f'):format(
      tonumber(relative.x) or 0.0, tonumber(relative.y) or 0.0, tonumber(relative.z) or 0.0,
      tonumber(payload.relativeHeading) or 0.0
    ),
    centered = true,
    cancel = true
  })
  if confirmed ~= 'confirm' then
    if payload.preview == true then MZHousesAdminMenu.ExitPreview() end
    return
  end
  local response = callAdmin('mz_houses:server:admin:setInternalPoint', payload)
  if response.ok == true and payload.preview == true then MZHousesAdminMenu.ExitPreview() end
  handleResponse(response, code)
end

function MZHousesAdminMenu.ShowInternalInfo(code)
  local property = getProperty(code)
  if not property then return end

  alertDialog({
    header = 'Pontos internos',
    content = internalSummary(property),
    centered = true,
    cancel = false
  })

  MZHousesAdminMenu.OpenInternalPoints(code)
end

function MZHousesAdminMenu.OpenInternalPoints(code)
  local property = getProperty(code)
  if not property then return end

  local current = MZHouses and MZHouses.GetCurrentHouse and MZHouses.GetCurrentHouse() or {}
  local insideThisHouse = current.inside == true and trim(current.code) == trim(code)
  local activeInterior = currentInterior()
  local matchingPreview = not insideThisHouse and type(activeInterior) == 'table' and type(activeInterior.metadata) == 'table'
    and activeInterior.metadata.preview == true and trim(activeInterior.shellName) == trim(property.shell)
  local validContext = insideThisHouse or matchingPreview
  local insideDescription = validContext and (insideThisHouse and 'Sessao administrativa desta propriedade.' or 'Preview do mesmo shell ativo.') or 'Entre no imovel ou abra preview do mesmo shell.'
  local entry = type(property.entrySpawn) == 'table' and property.entrySpawn or { mode = 'default' }
  local customExit = type(property.interior) == 'table' and type(property.interior.exit) == 'table' and property.interior.exit or property.effectiveExit

  openContext({
    id = 'mz_houses_admin_internal_points',
    title = 'Interior / Pontos Internos',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = 'Resumo dos pontos internos',
        description = internalSummary(property),
        icon = 'info',
        onSelect = function()
          MZHousesAdminMenu.ShowInternalInfo(code)
        end
      },
      {
        title = 'Ver shell atual',
        description = tostring(property.shell or 'nil'),
        icon = 'box'
      },
      {
        title = 'Spawn de entrada: ' .. (entry.mode == 'custom' and 'Personalizado' or 'Padrao do shell'),
        description = entry.mode == 'custom' and ('heading relativo %.2f'):format(tonumber(entry.heading) or 0.0) or 'Comportamento historico do mz_interiors',
        icon = 'log-in'
      },
      {
        title = 'Definir spawn de entrada aqui',
        description = insideDescription,
        icon = 'map-pinned',
        disabled = not validContext,
        onSelect = function() MZHousesAdminMenu.SetInternalPoint(code, 'entrySpawn') end
      },
      {
        title = 'Ir ate o spawn de entrada',
        icon = 'navigation',
        disabled = not validContext,
        onSelect = function()
          local ok, err = entry.mode == 'custom'
            and teleportInside(entry.coords, entry.heading, false)
            or teleportInside(nil, nil, true)
          if not ok then notify(('Falha: %s'):format(tostring(err)), 'error') end
        end
      },
      {
        title = 'Ir ate o spawn padrao do shell',
        description = 'Visualizacao sem alterar o modo salvo',
        icon = 'locate-fixed',
        disabled = not validContext,
        onSelect = function()
          local ok, err = teleportInside(nil, nil, true)
          if not ok then notify(('Falha: %s'):format(tostring(err)), 'error') end
        end
      },
      {
        title = 'Restaurar spawn padrao',
        icon = 'rotate-ccw',
        disabled = entry.mode ~= 'custom',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setEntrySpawnDefault', { code = code }), code)
        end
      },
      {
        title = 'Definir saida aqui',
        description = insideDescription,
        icon = 'door-open',
        disabled = not validContext,
        onSelect = function()
          MZHousesAdminMenu.SetInternalPoint(code, 'exit')
        end
      },
      {
        title = 'Ir ate o ponto de saida',
        icon = 'navigation',
        disabled = not validContext,
        onSelect = function()
          local effective = MZHouses.GetEffectiveHouseExit(property)
          local ok, err = effective and teleportInside(effective.coords, effective.heading, effective.relative == false and 'absolute' or false)
          if not ok then notify(('Falha: %s'):format(tostring(err or 'saida_nao_configurada')), 'error') end
        end
      },
      {
        title = 'Copiar spawn de entrada para saida',
        icon = 'copy',
        disabled = entry.mode ~= 'custom',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:copyInteriorPoint', { code = code, direction = 'entry_to_exit' }), code)
        end
      },
      {
        title = 'Copiar saida para spawn de entrada',
        icon = 'copy-check',
        disabled = not customExit,
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:copyInteriorPoint', { code = code, direction = 'exit_to_entry' }), code)
        end
      },
      {
        title = 'Definir bau aqui',
        description = insideDescription,
        icon = 'package',
        disabled = not validContext,
        onSelect = function()
          MZHousesAdminMenu.SetInternalPoint(code, 'stash')
        end
      },
      {
        title = 'Definir armario aqui',
        description = insideDescription,
        icon = 'shirt',
        disabled = not validContext,
        onSelect = function()
          MZHousesAdminMenu.SetInternalPoint(code, 'wardrobe')
        end
      },
      {
        title = 'Resetar pontos para default do shell',
        description = 'Remove overrides da propriedade',
        icon = 'rotate-ccw',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:resetInternalPoints', { code = code }), code)
        end
      }
    }
  })
end

function MZHousesAdminMenu.OpenGarage(code)
  local property = getProperty(code)
  if not property then return end
  local garage = type(property.garage) == 'table' and property.garage or {}

  openContext({
    id = 'mz_houses_admin_garage',
    title = 'Garagem',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = garage.enabled == true and 'Desativar garagem' or 'Ativar garagem',
        description = garageSummary(property),
        icon = 'power',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setGarageEnabled', {
            code = code,
            value = garage.enabled ~= true
          }), code)
        end
      },
      {
        title = 'Definir ponto de abrir aqui',
        icon = 'map-pin',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setGaragePoint', {
            code = code,
            kind = 'entry',
            point = currentPoint(false)
          }), code)
        end
      },
      {
        title = 'Definir spawn aqui',
        icon = 'navigation',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setGaragePoint', {
            code = code,
            kind = 'spawn',
            point = currentPoint(true)
          }), code)
        end
      },
      {
        title = 'Definir ponto de guardar aqui',
        icon = 'package-check',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setGaragePoint', {
            code = code,
            kind = 'store',
            point = currentPoint(false)
          }), code)
        end
      },
      {
        title = 'Definir slots',
        description = tostring(garage.slots or ''),
        icon = 'list-plus',
        onSelect = function()
          local input = inputDialog('Slots da garagem', {
            { type = 'number', label = 'Slots', required = true, default = tonumber(garage.slots) or 2, min = 1 }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setGarageSlots', {
              code = code,
              slots = input[1]
            }), code)
          end
        end
      },
      {
        title = 'Definir modo',
        description = tostring(garage.mode or 'private'),
        icon = 'users',
        onSelect = function()
          local input = inputDialog('Modo da garagem', {
            { type = 'select', label = 'Modo', required = true, default = tostring(garage.mode or 'private'), options = {
              { value = 'private', label = 'private' },
              { value = 'shared', label = 'shared' }
            } }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setGarageMode', {
              code = code,
              mode = trim(input[1])
            }), code)
          end
        end
      }
    }
  })
end

local function copyAccessPolicy(policy)
  policy = type(policy) == 'table' and policy or {}
  local out = { mode = tostring(policy.mode or 'owner'), match = 'any', rules = {}, features = {} }
  for _, rule in ipairs(type(policy.rules) == 'table' and policy.rules or {}) do
    out.rules[#out.rules + 1] = {
      type = tostring(rule.type or ''), name = tostring(rule.name or ''),
      minimumGrade = tonumber(rule.minimumGrade) or 0, requireDuty = rule.requireDuty == true,
      canControlDoorFromGrade = tonumber(rule.canControlDoorFromGrade)
    }
  end
  for _, featureName in ipairs({ 'stash', 'wardrobe', 'garage', 'furniture', 'activities' }) do
    local feature = type(policy.features) == 'table' and policy.features[featureName] or nil
    local normalized = { mode = tostring(type(feature) == 'table' and feature.mode or 'inherit'), match = 'any', rules = {} }
    for _, rule in ipairs(type(feature) == 'table' and type(feature.rules) == 'table' and feature.rules or {}) do
      normalized.rules[#normalized.rules + 1] = {
        type = tostring(rule.type or ''), name = tostring(rule.name or ''),
        minimumGrade = tonumber(rule.minimumGrade) or 0, requireDuty = rule.requireDuty == true
      }
    end
    out.features[featureName] = normalized
  end
  return out
end

function MZHousesAdminMenu.OpenAccessPolicy(code)
  local property = getProperty(code)
  if not property then return end
  local policy = copyAccessPolicy(property.accessPolicy or { mode = 'owner', rules = {} })
  local rulesText = 'nenhuma'
  if #policy.rules > 0 then
    local parts = {}
    for _, rule in ipairs(policy.rules) do
      parts[#parts + 1] = ('%s:%s grade>=%s%s'):format(
        rule.type, rule.name, tostring(rule.minimumGrade), rule.requireDuty and ' duty' or ''
      )
    end
    rulesText = table.concat(parts, ' | ')
  end

  local function save(nextPolicy)
    handleResponse(callAdmin('mz_houses:server:admin:setAccessPolicy', {
      code = code, accessPolicy = nextPolicy
    }), code)
  end

  openContext({
    id = 'mz_houses_admin_access_policy',
    title = 'Politica de acesso',
    menu = 'mz_houses_admin_property',
    options = {
      { title = 'Estado atual', description = ('mode=%s match=any | %s'):format(policy.mode, rulesText), disabled = true },
      { title = 'Somente owner/chaves', icon = 'key-round', onSelect = function() local next = copyAccessPolicy(policy); next.mode = 'owner'; next.rules = {}; save(next) end },
      { title = 'Publico', icon = 'users', onSelect = function() local next = copyAccessPolicy(policy); next.mode = 'public'; next.rules = {}; save(next) end },
      { title = 'Somente admin', icon = 'shield-lock', onSelect = function() local next = copyAccessPolicy(policy); next.mode = 'admin'; next.rules = {}; save(next) end },
      {
        title = 'Adicionar regra gang', icon = 'shield', onSelect = function()
          local groups, err = groupOptions('gang')
          if #groups == 0 then return notify(tostring(err or 'Nenhuma gang ativa.'), 'error') end
          local input = inputDialog('Adicionar regra gang (OR)', {
            { type = 'select', label = 'Gang', required = true, options = groups, default = groups[1].value },
            { type = 'number', label = 'Grade minima', required = true, default = 0, min = 0, max = 1000 },
            { type = 'number', label = 'Grade para controlar porta', required = true, default = 0, min = 0, max = 1000 }
          })
          if not input then return end
          local nextPolicy = copyAccessPolicy(policy)
          if policy.mode ~= 'rules' then nextPolicy.mode = 'rules'; nextPolicy.rules = {} end
          nextPolicy.rules[#nextPolicy.rules + 1] = { type = 'gang', name = trim(input[1]), minimumGrade = tonumber(input[2]), canControlDoorFromGrade = tonumber(input[3]), requireDuty = false }
          save(nextPolicy)
        end
      },
      {
        title = 'Adicionar regra job', icon = 'briefcase-business', onSelect = function()
          local groups, err = groupOptions('job')
          if #groups == 0 then return notify(tostring(err or 'Nenhum job ativo.'), 'error') end
          local input = inputDialog('Adicionar regra job (OR)', {
            { type = 'select', label = 'Job', required = true, options = groups, default = groups[1].value },
            { type = 'number', label = 'Grade minima', required = true, default = 0, min = 0, max = 1000 },
            { type = 'number', label = 'Grade para controlar porta', required = true, default = 0, min = 0, max = 1000 },
            boolSelectRow('Exigir em servico', false)
          })
          if not input then return end
          local nextPolicy = copyAccessPolicy(policy)
          if policy.mode ~= 'rules' then nextPolicy.mode = 'rules'; nextPolicy.rules = {} end
          nextPolicy.rules[#nextPolicy.rules + 1] = { type = 'job', name = trim(input[1]), minimumGrade = tonumber(input[2]), canControlDoorFromGrade = tonumber(input[3]), requireDuty = inputBool(input[4]) }
          save(nextPolicy)
        end
      },
      {
        title = 'Remover ultima regra', icon = 'list-x', disabled = policy.mode ~= 'rules' or #policy.rules == 0,
        onSelect = function()
          local nextPolicy = copyAccessPolicy(policy)
          table.remove(nextPolicy.rules, #nextPolicy.rules)
          if #nextPolicy.rules == 0 then nextPolicy.mode = 'admin' end
          save(nextPolicy)
        end
      }
    }
  })
end

local FEATURE_LABELS = {
  stash = 'Bau',
  wardrobe = 'Guarda-roupa',
  garage = 'Garagem',
  furniture = 'Moveis (somente proprietario)',
  activities = 'Atividades da instalacao'
}

local function featurePolicyCopy(property, featureName)
  local policy = copyAccessPolicy(type(property) == 'table' and property.accessPolicy or nil)
  return policy.features[featureName] or { mode = 'inherit', match = 'any', rules = {} }
end

local function featurePolicySummary(policy)
  policy = type(policy) == 'table' and policy or { mode = 'inherit', rules = {} }
  if policy.mode ~= 'rules' then return tostring(policy.mode or 'inherit') end
  local parts = {}
  for _, rule in ipairs(policy.rules or {}) do
    parts[#parts + 1] = ('%s:%s grade>=%s%s'):format(
      tostring(rule.type), tostring(rule.name), tostring(rule.minimumGrade or 0),
      rule.requireDuty == true and ' duty' or ''
    )
  end
  return 'rules(any): ' .. (#parts > 0 and table.concat(parts, ' | ') or 'nenhuma')
end

local function saveFeaturePolicy(code, featureName, policy)
  local confirmed = alertDialog({
    header = ('Confirmar permissao: %s'):format(FEATURE_LABELS[featureName] or featureName),
    content = featurePolicySummary(policy),
    centered = true,
    cancel = true
  })
  if confirmed ~= 'confirm' then return end
  handleResponse(callAdmin('mz_houses:server:admin:setFeaturePolicy', {
    code = code,
    featureName = featureName,
    featurePolicy = policy
  }), code)
end

function MZHousesAdminMenu.OpenFeaturePermissions(code)
  local property = getProperty(code)
  if not property then return end
  local options = {}
  for _, featureName in ipairs({ 'stash', 'wardrobe', 'garage', 'furniture', 'activities' }) do
    local name = featureName
    local policy = featurePolicyCopy(property, name)
    options[#options + 1] = {
      title = FEATURE_LABELS[name],
      description = featurePolicySummary(policy),
      icon = name == 'stash' and 'package-open'
        or name == 'wardrobe' and 'shirt'
        or name == 'furniture' and 'couch'
        or name == 'activities' and 'industry'
        or 'car',
      onSelect = function() MZHousesAdminMenu.OpenFeaturePolicy(code, name) end
    }
  end
  openContext({
    id = 'mz_houses_admin_feature_permissions',
    title = 'Recursos e permissoes',
    menu = 'mz_houses_admin_property',
    options = options
  })
end

function MZHousesAdminMenu.OpenFeaturePolicy(code, featureName)
  local property = getProperty(code)
  if not property then return end
  featureName = trim(featureName):lower()
  local policy = featurePolicyCopy(property, featureName)
  local function fixed(mode)
    saveFeaturePolicy(code, featureName, { mode = mode, match = 'any', rules = {} })
  end
  if featureName == 'furniture' then
    openContext({
      id = 'mz_houses_admin_feature_policy',
      title = FEATURE_LABELS[featureName],
      menu = 'mz_houses_admin_feature_permissions',
      options = {
        { title = 'Estado atual', description = featurePolicySummary(policy), disabled = true },
        {
          title = 'Ativado: somente proprietario',
          description = 'Chaves, guests e Staff sem ownership nao podem decorar.',
          icon = 'user-lock',
          onSelect = function() fixed('owner') end
        },
        { title = 'Desativado', icon = 'ban', onSelect = function() fixed('disabled') end }
      }
    })
    return
  end
  local options = {
    { title = 'Estado atual', description = featurePolicySummary(policy), disabled = true },
    { title = 'Ativado: herdar acesso', icon = 'git-merge', onSelect = function() fixed('inherit') end },
    { title = 'Desativado', icon = 'ban', onSelect = function() fixed('disabled') end }
  }
  if featureName ~= 'activities' then
    options[#options + 1] = { title = 'Somente owner', icon = 'user-round', onSelect = function() fixed('owner') end }
    options[#options + 1] = { title = 'Owner e chaves', icon = 'key-round', onSelect = function() fixed('keys') end }
    options[#options + 1] = { title = 'Publico dentro da propriedade', icon = 'users', onSelect = function() fixed('public') end }
  end
  options[#options + 1] = { title = 'Somente admin', icon = 'shield-lock', onSelect = function() fixed('admin') end }
  options[#options + 1] = {
    title = 'Adicionar regra gang', icon = 'shield', onSelect = function()
      local groups, err = groupOptions('gang')
      if #groups == 0 then return notify(tostring(err or 'Nenhuma gang ativa.'), 'error') end
      local input = inputDialog('Regra do recurso - gang (OR)', {
        { type = 'select', label = 'Gang', required = true, options = groups, default = groups[1].value },
        { type = 'number', label = 'Grade minima', required = true, default = 0, min = 0, max = 1000 }
      })
      if not input then return end
      local next = policy.mode == 'rules' and featurePolicyCopy({ accessPolicy = { features = { [featureName] = policy } } }, featureName)
        or { mode = 'rules', match = 'any', rules = {} }
      next.mode = 'rules'
      next.rules[#next.rules + 1] = { type = 'gang', name = trim(input[1]), minimumGrade = tonumber(input[2]), requireDuty = false }
      saveFeaturePolicy(code, featureName, next)
    end
  }
  options[#options + 1] = {
    title = 'Adicionar regra job', icon = 'briefcase-business', onSelect = function()
      local groups, err = groupOptions('job')
      if #groups == 0 then return notify(tostring(err or 'Nenhum job ativo.'), 'error') end
      local input = inputDialog('Regra do recurso - job (OR)', {
        { type = 'select', label = 'Job', required = true, options = groups, default = groups[1].value },
        { type = 'number', label = 'Grade minima', required = true, default = 0, min = 0, max = 1000 },
        boolSelectRow('Exigir em servico', false)
      })
      if not input then return end
      local next = policy.mode == 'rules' and featurePolicyCopy({ accessPolicy = { features = { [featureName] = policy } } }, featureName)
        or { mode = 'rules', match = 'any', rules = {} }
      next.mode = 'rules'
      next.rules[#next.rules + 1] = { type = 'job', name = trim(input[1]), minimumGrade = tonumber(input[2]), requireDuty = inputBool(input[3]) }
      saveFeaturePolicy(code, featureName, next)
    end
  }
  options[#options + 1] = {
    title = 'Remover ultima regra', icon = 'list-x', disabled = policy.mode ~= 'rules' or #policy.rules == 0,
    onSelect = function()
      local next = featurePolicyCopy({ accessPolicy = { features = { [featureName] = policy } } }, featureName)
      table.remove(next.rules, #next.rules)
      if #next.rules == 0 then next.mode = 'disabled' end
      saveFeaturePolicy(code, featureName, next)
    end
  }
  openContext({
    id = 'mz_houses_admin_feature_policy',
    title = FEATURE_LABELS[featureName] or featureName,
    menu = 'mz_houses_admin_feature_permissions',
    options = options
  })
end

local function phase5Money(value)
  local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local updated, count = text:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
    text = updated
    if count == 0 then break end
  end
  return ('R$ %s'):format(text)
end

function MZHousesAdminMenu.OpenBuildingDefaults(code)
  local response = callAdmin('mz_houses:server:admin:getBuildingUnitDefaults', { code = code })
  if response.ok ~= true then return handleResponse(response, false) end
  local defaults = response.defaults or {}
  local input = inputDialog('Defaults de novas unidades', {
    boolSelectRow('Venda habilitada por padrao', defaults.saleEnabled == true),
    { type = 'select', label = 'Modo padrao', required = true, default = tostring(defaults.saleMode or 'none'), options = {
      { value = 'none', label = 'Sem venda' }, { value = 'admin', label = 'Venda administrativa' }, { value = 'direct', label = 'Compra direta' }
    } },
    { type = 'number', label = 'Preco padrao', required = true, default = tonumber(defaults.salePrice) or 0, min = 0 },
    shellInputRow('Shell padrao', defaults.shell),
    boolSelectRow('IPTU padrao habilitado', type(defaults.tax) == 'table' and defaults.tax.enabled == true),
    { type = 'number', label = 'Valor padrao do IPTU', required = true, default = type(defaults.tax) == 'table' and tonumber(defaults.tax.amount) or 0, min = 0 },
    { type = 'number', label = 'Intervalo padrao em dias', required = true, default = type(defaults.tax) == 'table' and tonumber(defaults.tax.intervalDays) or 7, min = 1 },
    { type = 'number', label = 'Tolerancia padrao em dias', required = true, default = type(defaults.tax) == 'table' and tonumber(defaults.tax.gracePeriodDays) or 3, min = 0 }
  })
  if not input then return end
  local summary = ('Novas unidades: venda=%s, modo=%s, preco=%s, shell=%s; IPTU=%s %s/%d dias + %d tolerancia. Unidades existentes nao serao alteradas.'):format(
    inputBool(input[1]) and 'ativa' or 'inativa', trim(input[2]), phase5Money(input[3]), trim(input[4]),
    inputBool(input[5]) and 'ativo' or 'inativo', phase5Money(input[6]),
    math.floor(tonumber(input[7]) or 7), math.floor(tonumber(input[8]) or 3)
  )
  if alertDialog({ header = 'Confirmar defaults', content = summary, centered = true, cancel = true }) ~= 'confirm' then return end
  local saved = callAdmin('mz_houses:server:admin:updateBuildingUnitDefaults', {
    code = code,
    saleEnabled = inputBool(input[1]),
    saleMode = trim(input[2]),
    salePrice = tonumber(input[3]) or 0,
    shell = trim(input[4]),
    taxEnabled = inputBool(input[5]),
    taxAmount = tonumber(input[6]) or 0,
    taxIntervalDays = tonumber(input[7]) or 7,
    taxGracePeriodDays = tonumber(input[8]) or 3
  })
  handleResponse(saved, false)
  SetTimeout(150, function() MZHousesAdminMenu.OpenBuildingUnits(code) end)
end

function MZHousesAdminMenu.CreateApartmentBatch(code)
  local input = inputDialog('Criar unidades em lote', {
    { type = 'input', label = 'Numeros separados por virgula', required = true, placeholder = '101, 102, 201, 202' }
  })
  if not input then return end
  local unitNumbers = splitList(input[1])
  local preview = callAdmin('mz_houses:server:admin:previewApartmentBatch', {
    buildingCode = code,
    unitNumbers = unitNumbers
  })
  if preview.ok ~= true then return handleResponse(preview, false) end
  local defaults = preview.defaults or {}
  local content = preview.alreadyExists
    and ('As %d unidades deste lote ja existem. Confirmar apenas verificara a idempotencia, sem duplicar.'):format(preview.total or 0)
    or ('Criar %d unidades de forma transacional? Defaults copiados: %s, %s, shell=%s, IPTU=%s %s/%d dias + %d tolerancia.'):format(
      preview.total or 0,
      defaults.saleEnabled and (tostring(defaults.saleMode) .. ' ' .. phase5Money(defaults.salePrice)) or 'sem venda',
      'precos independentes apos a criacao',
      tostring(defaults.shell or '-'),
      type(defaults.tax) == 'table' and defaults.tax.enabled == true and 'ativo' or 'inativo',
      phase5Money(type(defaults.tax) == 'table' and defaults.tax.amount or 0),
      math.floor(type(defaults.tax) == 'table' and tonumber(defaults.tax.intervalDays) or 7),
      math.floor(type(defaults.tax) == 'table' and tonumber(defaults.tax.gracePeriodDays) or 3)
    )
  if alertDialog({ header = 'Revisar lote de unidades', content = content, centered = true, cancel = true }) ~= 'confirm' then return end
  local result = callAdmin('mz_houses:server:admin:createApartmentBatch', { previewToken = preview.previewToken })
  handleResponse(result, false)
  SetTimeout(150, function() MZHousesAdminMenu.OpenBuildingUnits(code) end)
end

function MZHousesAdminMenu.CopyApartmentUnitTemplate(code)
  local input = inputDialog('Copiar modelo de unidade', {
    { type = 'input', label = 'Code de uma unidade deste predio', required = true, placeholder = 'apt_000001_101' }
  })
  if not input then return end
  if alertDialog({
    header = 'Copiar modelo para novas unidades?',
    content = 'Shell, configuracao interna e features da unidade serao copiados somente para os defaults. Nenhuma unidade existente sera alterada.',
    centered = true,
    cancel = true
  }) ~= 'confirm' then return end
  local result = callAdmin('mz_houses:server:admin:copyBuildingUnitTemplate', {
    code = code,
    unitCode = trim(input[1])
  })
  handleResponse(result, false)
  SetTimeout(150, function() MZHousesAdminMenu.OpenBuildingUnits(code) end)
end

function MZHousesAdminMenu.OpenApartmentBulk(code)
  local input = inputDialog('Operacao comercial em lote', {
    { type = 'input', label = 'Codes das unidades separados por virgula', required = true, placeholder = 'apt_000001_101, apt_000001_102' },
    { type = 'select', label = 'Operacao', required = true, default = 'price', options = {
      { value = 'price', label = 'Aplicar preco' },
      { value = 'mode', label = 'Alterar modo de venda ativa' },
      { value = 'enable', label = 'Ativar venda' },
      { value = 'disable', label = 'Desativar venda' }
    } },
    { type = 'select', label = 'Modo (quando aplicavel)', required = true, default = 'direct', options = {
      { value = 'admin', label = 'Venda administrativa' }, { value = 'direct', label = 'Compra direta' }
    } },
    { type = 'number', label = 'Preco (quando aplicavel)', required = true, default = 0, min = 0 }
  })
  if not input then return end
  local preview = callAdmin('mz_houses:server:admin:previewApartmentBulk', {
    buildingCode = code,
    unitCodes = splitList(input[1]),
    operation = trim(input[2]),
    saleMode = trim(input[3]),
    salePrice = tonumber(input[4]) or 0
  })
  if preview.ok ~= true then return handleResponse(preview, false) end
  local ignored = {}
  for index, item in ipairs(preview.skipped or {}) do
    if index > 8 then break end
    ignored[#ignored + 1] = ('%s (%s)'):format(tostring(item.code), tostring(item.reason))
  end
  local content = ('Selecionadas: %d. Elegiveis: %d. Ignoradas: %d.%s Confirmar aplica resultado item a item e rele cada unidade.'):format(
    tonumber(preview.selected) or 0,
    #(preview.eligible or {}),
    #(preview.skipped or {}),
    #ignored > 0 and (' Ignoradas: ' .. table.concat(ignored, ', ') .. '.') or ''
  )
  if alertDialog({ header = 'Confirmacao forte do lote', content = content, centered = true, cancel = true }) ~= 'confirm' then return end
  local result = callAdmin('mz_houses:server:admin:applyApartmentBulk', { previewToken = preview.previewToken })
  handleResponse(result, false)
  SetTimeout(150, function() MZHousesAdminMenu.OpenBuildingUnits(code) end)
end

function MZHousesAdminMenu.OpenBuildingUnits(code)
  local response = callAdmin('mz_houses:server:admin:getPropertyInfo', { code = code })
  if response.ok ~= true or not response.property or response.property.subtype ~= 'apartment_building' then
    notify('Este imovel nao e um predio de apartamentos.', 'error')
    return
  end

  local unitsResponse = callAdmin('mz_houses:server:admin:listBuildingUnits', { code = code })
  if unitsResponse.ok ~= true then
    notify(('Erro: %s'):format(tostring(unitsResponse.error or 'units_failed')), 'error')
    return
  end

  local options = {
    {
      title = 'Defaults de novas unidades',
      description = 'Modelo de criacao; nao altera unidades existentes',
      icon = 'copy-check',
      onSelect = function() MZHousesAdminMenu.OpenBuildingDefaults(code) end
    },
    {
      title = 'Criar unidades em lote',
      description = 'Preview, confirmacao e transacao all-or-nothing',
      icon = 'list-plus',
      onSelect = function() MZHousesAdminMenu.CreateApartmentBatch(code) end
    },
    {
      title = 'Copiar shell/interior de unidade modelo',
      description = 'Atualiza somente defaults para futuras unidades',
      icon = 'copy-plus',
      onSelect = function() MZHousesAdminMenu.CopyApartmentUnitTemplate(code) end
    },
    {
      title = 'Operacoes comerciais em lote',
      description = 'Somente unidades sem owner e sem estado financeiro ambiguo',
      icon = 'list-checks',
      onSelect = function() MZHousesAdminMenu.OpenApartmentBulk(code) end
    },
    {
      title = 'Criar nova unidade',
      icon = 'plus',
      onSelect = function()
        MZHousesAdminMenu.CreateApartmentUnit()
      end
    }
  }

  for _, unit in ipairs(unitsResponse.units or {}) do
    options[#options + 1] = {
      title = ('Apartamento %s'):format(tostring(unit.unitNumber or unit.code)),
      description = ('%s | owner=%s | keys=%s | shell=%s | venda=%s %s%s'):format(
        tostring(unit.code),
        unit.owner and 'sim' or 'nao',
        tostring(unit.keyCount or 0),
        tostring(unit.shell or 'nil'),
        unit.saleEnabled and tostring(unit.saleMode) or 'nao',
        unit.saleEnabled and phase5Money(unit.salePrice) or '',
        unit.bulkCommerceProtected and ' | protegida do lote' or ''
      ),
      icon = 'door-open',
      onSelect = function()
        MZHousesAdminMenu.OpenProperty(unit.code)
      end
    }
  end

  openContext({
    id = 'mz_houses_admin_building_units',
    title = 'Unidades do predio',
    menu = 'mz_houses_admin_property',
    options = options
  })
end

local function commerceMoney(value)
  local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local updated, count = text:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
    text = updated
    if count == 0 then break end
  end
  return ('R$ %s'):format(text)
end

function MZHousesAdminMenu.OpenCommerce(code)
  local property = getProperty(code)
  if not property then return end
  local eligible = property.category == 'residential' and property.ownerType == 'player'
    and (property.subtype == 'house' or property.subtype == 'apartment_unit' or property.subtype == 'apartment')
  if not eligible then
    notify('Comercio permitido somente para casa ou unidade residencial individual.', 'error')
    return
  end

  local enabled = property.saleEnabled == true
  local summary = enabled and ('%s | %s'):format(tostring(property.saleMode), commerceMoney(property.salePrice))
    or ('Fora de venda | preco salvo %s'):format(commerceMoney(property.salePrice))
  openContext({
    id = 'mz_houses_admin_commerce',
    title = 'Comercio residencial',
    menu = 'mz_houses_admin_property',
    options = {
      { title = 'Estado atual', description = summary, icon = 'circle-dollar-sign', disabled = true },
      {
        title = 'Configurar venda e preco',
        description = 'Ativar, retirar da venda ou editar o preco real',
        icon = 'settings',
        onSelect = function()
          local input = inputDialog('Configurar comercio residencial', {
            boolSelectRow('Disponivel para venda', enabled),
            { type = 'select', label = 'Modo', required = true, default = tostring(property.saleMode or 'none'), options = {
              { value = 'none', label = 'Sem venda' }, { value = 'admin', label = 'Venda administrativa' }, { value = 'direct', label = 'Compra direta' }
            } },
            { type = 'number', label = 'Preco real', required = true, default = tonumber(property.salePrice) or 0, min = 0 }
          })
          if not input then return end
          local saleEnabled = inputBool(input[1])
          local saleMode = trim(input[2])
          local salePrice = tonumber(input[3]) or 0
          local confirmed = alertDialog({
            header = 'Confirmar configuracao comercial',
            content = saleEnabled and ('Ativar venda %s por %s?'):format(saleMode, commerceMoney(salePrice))
              or 'Retirar esta propriedade da venda?',
            centered = true,
            cancel = true
          })
          if confirmed ~= 'confirm' then return end
          handleResponse(callAdmin('mz_houses:server:admin:configureSale', {
            code = code, saleEnabled = saleEnabled, saleMode = saleMode, salePrice = salePrice
          }), code)
        end
      },
      {
        title = 'Vender e cobrar pelo banco',
        description = enabled and ('Selecionar comprador online; cobranca de %s'):format(commerceMoney(property.salePrice))
          or 'Ative a venda antes de cobrar',
        icon = 'landmark',
        disabled = not enabled or property.owner ~= nil,
        onSelect = function()
          local response = callAdmin('mz_houses:server:admin:listSaleTargets', {})
          if response.ok ~= true then return handleResponse(response, code) end
          local choices = {}
          for _, player in ipairs(response.players or {}) do
            choices[#choices + 1] = {
              value = tostring(player.source),
              label = ('[%s] %s — %s'):format(tostring(player.source), tostring(player.name), tostring(player.citizenid))
            }
          end
          if #choices == 0 then return notify('Nenhum comprador online disponivel.', 'error') end
          local input = inputDialog('Venda administrativa com cobranca', {
            { type = 'select', label = 'Comprador online', required = true, options = choices, default = choices[1].value }
          })
          if not input then return end
          local confirmed = alertDialog({
            header = 'Confirmar venda e cobranca',
            content = ('O servidor relera o preco e cobrara %s do banco do comprador.'):format(commerceMoney(property.salePrice)),
            centered = true,
            cancel = true
          })
          if confirmed ~= 'confirm' then return end
          handleResponse(callAdmin('mz_houses:server:admin:sellProperty', {
            code = code, targetSource = tonumber(input[1])
          }), code)
        end
      },
      {
        title = 'Atribuir sem cobranca',
        description = 'Fluxo separado em Dono / Chaves; nao cria venda cobrada',
        icon = 'user-plus',
        onSelect = function() MZHousesAdminMenu.OpenOwnerKeys(code) end
      },
      {
        title = 'Historico de transacoes',
        description = 'Ultimas 30 tentativas persistidas',
        icon = 'receipt-text',
        onSelect = function()
          local response = callAdmin('mz_houses:server:admin:getTransactions', { code = code })
          if response.ok ~= true then return handleResponse(response, code) end
          local options = {}
          for _, transaction in ipairs(response.transactions or {}) do
            options[#options + 1] = {
              title = ('#%s — %s'):format(tostring(transaction.id), tostring(transaction.status)),
              description = ('%s | buyer=%s | %s'):format(
                commerceMoney(transaction.amount), tostring(transaction.buyer_citizenid or '-'), tostring(transaction.created_at or '-')
              ),
              icon = transaction.status == 'completed' and 'circle-check' or transaction.status == 'refunded' and 'undo-2' or 'clock'
            }
          end
          if #options == 0 then options[1] = { title = 'Sem transacoes', disabled = true } end
          openContext({ id = 'mz_houses_admin_transactions', title = 'Transacoes - ' .. code, menu = 'mz_houses_admin_commerce', options = options })
        end
      }
    }
  })
end

function MZHousesAdminMenu.OpenTax(code)
  local response = callAdmin('mz_houses:server:admin:getTaxStatus', { code = code })
  if response.ok ~= true then return handleResponse(response, code) end
  local tax = response.tax or {}
  local options = {
    {
      title = 'Situacao atual',
      description = ('status=%s | valor=%s | vencimento=%s | tolerancia=%s | ultimo pagamento=%s'):format(
        tostring(tax.status or 'disabled'), phase5Money(tax.amount), tostring(tax.dueAt or '-'),
        tostring(tax.graceUntil or '-'), tostring(tax.lastPaidAt or '-')),
      icon = 'circle-dollar-sign', disabled = true
    },
    {
      title = 'Configurar IPTU',
      description = 'Valor, intervalo e tolerancia; inicializacao e sempre explicita',
      icon = 'settings-2',
      onSelect = function()
        local input = inputDialog('Configurar IPTU', {
          boolSelectRow('Habilitado', tax.enabled == true),
          { type = 'number', label = 'Valor', required = true, default = tonumber(tax.amount) or 0, min = 0 },
          { type = 'number', label = 'Intervalo em dias', required = true, default = tonumber(tax.intervalDays) or 7, min = 1 },
          { type = 'number', label = 'Tolerancia em dias', required = true, default = tonumber(tax.gracePeriodDays) or 3, min = 0 },
          boolSelectRow('Inicializar novo vencimento para o owner atual', false),
          { type = 'input', label = 'Primeiro vencimento UTC (opcional)', required = false, placeholder = '2026-08-01 18:00:00' }
        })
        if not input then return end
        if alertDialog({
          header = 'Confirmar configuracao de IPTU',
          content = ('IPTU=%s, valor=%s, intervalo=%d dias, tolerancia=%d dias, inicializar=%s. Porta, owner, chaves e recursos nao serao alterados.'):format(
            inputBool(input[1]) and 'ativo' or 'inativo', phase5Money(input[2]),
            math.floor(tonumber(input[3]) or 7), math.floor(tonumber(input[4]) or 3),
            inputBool(input[5]) and 'sim' or 'nao'),
          centered = true, cancel = true
        }) ~= 'confirm' then return end
        handleResponse(callAdmin('mz_houses:server:admin:configureTax', {
          code = code, enabled = inputBool(input[1]), amount = tonumber(input[2]) or 0,
          intervalDays = tonumber(input[3]) or 7, gracePeriodDays = tonumber(input[4]) or 3,
          initialize = inputBool(input[5]), dueAt = trim(input[6]) ~= '' and trim(input[6]) or nil
        }), code)
      end
    },
    {
      title = 'Ajustar vencimento/tolerancia atual',
      description = 'Data UTC; recalcula due/overdue sem alterar a porta',
      icon = 'calendar-clock',
      disabled = tax.enabled ~= true or tax.hasOwner ~= true or tax.initialized ~= true,
      onSelect = function()
        local input = inputDialog('Novo vencimento UTC', {
          { type = 'input', label = 'YYYY-MM-DD HH:MM:SS', required = true, default = tostring(tax.dueAt or '') }
        })
        if input then handleResponse(callAdmin('mz_houses:server:admin:setTaxDueAt', { code = code, dueAt = trim(input[1]) }), code) end
      end
    },
    {
      title = 'Ajuste administrativo de status',
      description = 'Blocked e somente status fiscal; door_json permanece intacto',
      icon = 'shield-alert',
      disabled = tax.enabled ~= true or tax.hasOwner ~= true or tax.initialized ~= true,
      onSelect = function()
        local input = inputDialog('Status fiscal', {
          { type = 'select', label = 'Status', required = true, default = tostring(tax.status or 'paid'), options = {
            { value = 'paid', label = 'paid' }, { value = 'due', label = 'due' },
            { value = 'overdue', label = 'overdue' }, { value = 'blocked', label = 'blocked administrativo' }
          } }
        })
        if input then handleResponse(callAdmin('mz_houses:server:admin:setTaxStatus', { code = code, status = trim(input[1]) }), code) end
      end
    }
  }
  for _, payment in ipairs(tax.payments or {}) do
    options[#options + 1] = {
      title = ('Pagamento #%s — %s'):format(tostring(payment.id or '?'), tostring(payment.status or '?')),
      description = ('%s | vencimento=%s | pago=%s | referencia=%s'):format(
        phase5Money(payment.amount), tostring(payment.due_at or '-'),
        tostring(payment.paid_at or '-'), tostring(payment.transaction_reference or '-')),
      icon = 'receipt-text'
    }
  end
  openContext({ id = 'mz_houses_admin_tax', title = 'IPTU - ' .. code, menu = 'mz_houses_admin_property', options = options })
end

function MZHousesAdminMenu.OpenOwnerKeys(code)
  local property = getProperty(code)
  if not property then return end

  if property.subtype == 'apartment_building' then
    alertDialog({
      header = 'Dono / Chaves',
      content = 'Predio nao recebe dono/chaves de moradia. Gerencie uma unidade, exemplo apt_000001_101.',
      centered = true,
      cancel = false
    })
    MZHousesAdminMenu.OpenBuildingUnits(code)
    return
  end

  local keysDescription = 'nenhuma'
  if type(property.keys) == 'table' and #property.keys > 0 then
    local parts = {}
    for _, key in ipairs(property.keys) do parts[#parts + 1] = ('%s:%s'):format(tostring(key.citizenid), tostring(key.role)) end
    keysDescription = table.concat(parts, ', ')
  end

  openContext({
    id = 'mz_houses_admin_owner_keys',
    title = 'Dono / Chaves',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = 'Setar dono por citizenid',
        description = tostring(property.owner or 'sem dono'),
        icon = 'user-check',
        onSelect = function()
          local input = inputDialog('Setar dono', {
            { type = 'input', label = 'CitizenID', required = true },
            boolSelectRow('Inicializar IPTU configurado', false),
            { type = 'input', label = 'Primeiro vencimento UTC (opcional)', required = false, placeholder = '2026-08-01 18:00:00' }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setOwner', {
              code = code,
              citizenid = trim(input[1]),
              initializeTax = inputBool(input[2]),
              taxDueAt = trim(input[3]) ~= '' and trim(input[3]) or nil
            }), code)
          end
        end
      },
      {
        title = 'Limpar dono',
        icon = 'user-x',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:clearOwner', { code = code }), code)
        end
      },
      {
        title = 'Setar dono por ID online',
        description = 'O servidor resolve o citizenid do jogador',
        icon = 'user-round-search',
        onSelect = function()
          local input = inputDialog('Setar dono por jogador online', {
            { type = 'number', label = 'ID / source', required = true, min = 1 },
            boolSelectRow('Inicializar IPTU configurado', false),
            { type = 'input', label = 'Primeiro vencimento UTC (opcional)', required = false, placeholder = '2026-08-01 18:00:00' }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setOwnerBySource', {
              code = code, targetSource = tonumber(input[1]),
              initializeTax = inputBool(input[2]),
              taxDueAt = trim(input[3]) ~= '' and trim(input[3]) or nil
            }), code)
          end
        end
      },
      {
        title = 'Dar/alterar chave por citizenid',
        icon = 'key-round',
        onSelect = function()
          local input = inputDialog('Dar chave', {
            { type = 'input', label = 'CitizenID', required = true },
            { type = 'select', label = 'Role', required = true, default = 'access', options = {
              { value = 'access', label = 'Acesso' }, { value = 'control', label = 'Controle' }
            } }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:giveKey', {
              code = code,
              citizenid = trim(input[1]),
              role = trim(input[2])
            }), code)
          end
        end
      },
      {
        title = 'Remover chave por citizenid',
        icon = 'key-square',
        onSelect = function()
          local input = inputDialog('Remover chave', {
            { type = 'input', label = 'CitizenID', required = true }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:removeKey', {
              code = code,
              citizenid = trim(input[1])
            }), code)
          end
        end
      },
      {
        title = 'Listar chaves',
        description = keysDescription,
        icon = 'list'
      },
      {
        title = 'Remover todas as chaves',
        description = 'Confirmacao forte: digite o codigo da propriedade',
        icon = 'key-round-x',
        onSelect = function()
          local input = inputDialog('Remover todas as chaves', {
            { type = 'input', label = ('Digite %s'):format(code), required = true }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:clearKeys', {
              code = code, confirmCode = trim(input[1])
            }), code)
          end
        end
      }
    }
  })
end

function MZHousesAdminMenu.OpenVisibility(code)
  local property = getProperty(code)
  if not property then return end

  openContext({
    id = 'mz_houses_admin_visibility',
    title = 'Visibilidade',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = property.public == true and 'Public false' or 'Public true',
        description = 'Public controla apenas visibilidade; nao concede acesso',
        icon = 'door-open',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setPublic', {
            code = code,
            value = property.public ~= true
          }), code)
        end
      },
      {
        title = 'Visibility',
        description = tostring(property.visibility or 'auto'),
        icon = 'eye',
        onSelect = function()
          local input = inputDialog('Visibility', {
            { type = 'select', label = 'Visibility', required = true, default = tostring(property.visibility or 'auto'), options = {
              { value = 'auto', label = 'auto' },
              { value = 'public', label = 'public' },
              { value = 'restricted', label = 'restricted' },
              { value = 'hidden', label = 'hidden' }
            } }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setVisibility', {
              code = code,
              visibility = trim(input[1])
            }), code)
          end
        end
      }
    }
  })
end

function MZHousesAdminMenu.OpenState(code)
  local property = getProperty(code)
  if not property then return end

  openContext({
    id = 'mz_houses_admin_state',
    title = 'Ativar / Desativar / Arquivar',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = 'Ativar',
        icon = 'power',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:updateBasic', { code = code, field = 'enable' }), code)
        end
      },
      {
        title = 'Desativar',
        icon = 'power-off',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:updateBasic', { code = code, field = 'disable' }), code)
        end
      },
      {
        title = 'Arquivar',
        description = 'Soft delete: digite o codigo para confirmar',
        icon = 'archive',
        onSelect = function()
          local input = inputDialog('Arquivar propriedade', {
            { type = 'input', label = ('Digite %s'):format(code), required = true }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:updateBasic', {
              code = code, field = 'archive', confirmCode = trim(input[1])
            }), code)
          end
        end
      }
    }
  })
end

local function legacyAuditLine(name, values)
  values = type(values) == 'table' and values or {}
  return ('%s: vazios=%d, preservados=%d, enabled=%d, invalidos=%d'):format(
    name, tonumber(values.empty) or 0, tonumber(values.preserved) or 0,
    tonumber(values.enabled) or 0, tonumber(values.invalid) or 0)
end

function MZHousesAdminMenu.OpenLegacyAudit()
  local response = callAdmin('mz_houses:server:admin:auditLegacyData', {})
  if response.ok ~= true then return handleResponse(response) end
  local report = response.report or {}
  local counts = report.counts or {}
  local lines = {
    ('Propriedades: %d'):format(tonumber(counts.total) or 0),
    ('Tipos legados bloqueados: %d'):format(tonumber(counts.legacyTypes) or 0),
    ('Sem access_json valido/persistido: %d'):format(tonumber(counts.missingAccessPolicy) or 0),
    legacyAuditLine('listing_json', counts.listing),
    legacyAuditLine('realestate_json', counts.realestate),
    'Acoes destrutivas executadas: 0'
  }
  local samples = report.samples or {}
  if #samples > 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Amostras (sem conteudo JSON):'
    for index = 1, math.min(#samples, 20) do
      local item = samples[index]
      lines[#lines + 1] = ('%s | %s/%s | access=%s listing=%s realestate=%s'):format(
        tostring(item.code), tostring(item.category), tostring(item.subtype),
        tostring(item.access), tostring(item.listing), tostring(item.realestate))
    end
    if #samples > 20 then lines[#lines + 1] = ('... mais %d amostras no relatorio server-side.'):format(#samples - 20) end
  end
  alertDialog({ header = 'Auditoria de legado (somente leitura)', content = table.concat(lines, '\n'), centered = true, cancel = false })
  MZHousesAdminMenu.OpenLegacyTools()
end

function MZHousesAdminMenu.OpenLegacyTools()
  openContext({
    id = 'mz_houses_admin_legacy',
    title = 'Migracao / auditoria legada',
    menu = 'mz_houses_admin_main',
    options = {
      {
        title = 'Migrar propriedade por codigo',
        description = 'Escolha explicita, preview server-side e confirmacao forte',
        icon = 'replace',
        onSelect = function()
          local input = inputDialog('Migrar propriedade legada', {
            { type = 'input', label = 'Codigo da propriedade', required = true }
          })
          if input then MZHousesAdminMenu.OpenLegacyMigration(trim(input[1])) end
        end
      },
      {
        title = 'Auditar listing_json / realestate_json',
        description = 'Conta e classifica sem retornar ou alterar o conteudo',
        icon = 'file-search',
        onSelect = function() MZHousesAdminMenu.OpenLegacyAudit() end
      }
    }
  })
end

local function legacyTemplateInput(code, template)
  local payload = { code = code, template = template }
  if template == 'gang' or template == 'job' then
    local groups = groupOptions(template)
    if #groups == 0 then notify(('Nenhum %s real disponivel.'):format(template), 'error') return nil end
    local rows = {
      { type = 'select', label = template == 'gang' and 'Gang' or 'Job', required = true, options = groups, default = groups[1].value },
      { type = 'number', label = 'Grade minima para entrar', required = true, default = 0, min = 0, max = 1000 },
      { type = 'number', label = 'Grade minima para controlar porta', required = true, default = 0, min = 0, max = 1000 },
      boolSelectRow('Visivel para nao autorizados', false)
    }
    if template == 'job' then rows[#rows + 1] = boolSelectRow('Exigir duty', false) end
    local input = inputDialog('Politica da propriedade legada', rows)
    if not input then return nil end
    payload.groupCode = trim(input[1])
    payload.minimumGrade = tonumber(input[2]) or 0
    payload.controlGrade = tonumber(input[3]) or payload.minimumGrade
    payload.visible = inputBool(input[4])
    payload.requireDuty = template == 'job' and inputBool(input[5]) or false
  elseif template == 'unit' then
    local buildings = apartmentBuildingOptions()
    if #buildings == 0 then notify('Nenhum predio canonico encontrado.', 'error') return nil end
    local input = inputDialog('Vincular unidade legada', {
      { type = 'select', label = 'Predio', required = true, options = buildings, default = buildings[1].value },
      { type = 'input', label = 'Numero da unidade', required = true, placeholder = '101' }
    })
    if not input then return nil end
    payload.parentCode = trim(input[1])
    payload.unitNumber = trim(input[2])
  end
  return payload
end

function MZHousesAdminMenu.OpenLegacyMigration(code)
  code = trim(code)
  local property = getProperty(code)
  if not property then return end
  local input = inputDialog(('Migrar %s'):format(code), {
    { type = 'select', label = 'Template final explicito', required = true, default = 'residence', options = {
      { value = 'residence', label = 'Residencia antiga' },
      { value = 'building', label = 'Predio antigo' },
      { value = 'unit', label = 'Unidade antiga' },
      { value = 'gang', label = 'Org/Gang antiga' },
      { value = 'job', label = 'Job antigo' },
      { value = 'public', label = 'Interior publico' },
      { value = 'administrative', label = 'Interior administrativo' }
    } }
  })
  if not input then return end
  local payload = legacyTemplateInput(code, trim(input[1]))
  if not payload then return end
  local response = callAdmin('mz_houses:server:admin:previewLegacyMigration', payload)
  if response.ok ~= true then return handleResponse(response, code) end
  local preview = response.preview or {}
  local before, after = preview.before or {}, preview.after or {}
  local lines = {
    ('ANTES: %s / %s / %s | access=%s | porta=%s'):format(
      tostring(before.category), tostring(before.subtype), tostring(before.ownerType),
      tostring(before.accessMode), tostring(before.doorState)),
    ('DEPOIS: %s / %s / %s | access=%s | porta=%s | visibilidade=%s'):format(
      tostring(after.category), tostring(after.subtype), tostring(after.ownerType),
      tostring(after.accessMode), tostring(after.doorState), tostring(after.visibility))
  }
  for _, line in ipairs(preview.summary or {}) do lines[#lines + 1] = line end
  if #(preview.warnings or {}) > 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Avisos:'
    for _, warning in ipairs(preview.warnings) do lines[#lines + 1] = '- ' .. tostring(warning) end
  end
  if alertDialog({ header = 'Preview da migracao', content = table.concat(lines, '\n'), centered = true, cancel = true }) ~= 'confirm' then return end
  local confirmation = inputDialog('Confirmacao forte', {
    { type = 'input', label = ('Digite exatamente %s'):format(code), required = true }
  })
  if not confirmation then return end
  handleResponse(callAdmin('mz_houses:server:admin:applyLegacyMigration', {
    token = preview.token,
    confirmCode = trim(confirmation[1])
  }), code)
end

CreateThread(function()
  local cfg = menuConfig()
  RegisterCommand(tostring(cfg.command or 'mhouse_admin'), function()
    MZHousesAdminMenu.Open()
  end, false)

  for _, alias in ipairs(type(cfg.aliases) == 'table' and cfg.aliases or {}) do
    if trim(alias) ~= '' and trim(alias) ~= trim(cfg.command) then
      RegisterCommand(trim(alias), function() MZHousesAdminMenu.Open() end, false)
    end
  end
  RegisterCommand('mzhouses_preview_exit', function() MZHousesAdminMenu.ExitPreview() end, false)

  local admin = MZHousesConfig.Admin or {}
  RegisterCommand(tostring(admin.exitHere or 'mhouse_exit_here'), function(_, args)
    local code = trim(args and args[1])
    if code == '' then
      notify('Uso: /mhouse_exit_here codigo', 'error')
      return
    end
    MZHousesAdminMenu.SetInternalPoint(code, 'exit')
  end, false)

  RegisterCommand(tostring(admin.internalStashHere or 'mhouse_stash_here'), function(_, args)
    local code = trim(args and args[1])
    if code == '' then
      local current = MZHouses and MZHouses.GetCurrentHouse and MZHouses.GetCurrentHouse() or {}
      code = trim(current.code)
    end
    if code == '' then
      notify('Uso: /mhouse_stash_here codigo', 'error')
      return
    end
    MZHousesAdminMenu.SetInternalPoint(code, 'stash')
  end, false)

  RegisterCommand(tostring(admin.internalWardrobeHere or 'mhouse_wardrobe_here'), function(_, args)
    local code = trim(args and args[1])
    if code == '' then
      local current = MZHouses and MZHouses.GetCurrentHouse and MZHouses.GetCurrentHouse() or {}
      code = trim(current.code)
    end
    if code == '' then
      notify('Uso: /mhouse_wardrobe_here codigo', 'error')
      return
    end
    MZHousesAdminMenu.SetInternalPoint(code, 'wardrobe')
  end, false)

  RegisterCommand(tostring(admin.internalInfo or 'mhouse_internal_info'), function(_, args)
    local code = trim(args and args[1])
    if code == '' then
      notify('Uso: /mhouse_internal_info codigo', 'error')
      return
    end
    MZHousesAdminMenu.ShowInternalInfo(code)
  end, false)

  RegisterCommand(tostring(admin.internalReset or 'mhouse_internal_reset'), function(_, args)
    local code = trim(args and args[1])
    if code == '' then
      notify('Uso: /mhouse_internal_reset codigo', 'error')
      return
    end
    handleResponse(callAdmin('mz_houses:server:admin:resetInternalPoints', { code = code }), code)
  end, false)
end)

CreateThread(function()
  while true do
    Wait(PreviewActive and 500 or 1500)
    if PreviewActive and IsEntityDead(PlayerPedId()) then MZHousesAdminMenu.ExitPreview() end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if not PreviewActive then return end
  if resource ~= GetCurrentResourceName() and resource ~= 'mz_interiors' then return end
  if resource == GetCurrentResourceName() and GetResourceState('mz_interiors') == 'started' then
    pcall(function() exports['mz_interiors']:DestroyCurrentInterior({ teleportBack = true, reason = 'houses_stop_preview' }) end)
  end
  PreviewActive = false
  TriggerServerEvent('mz_houses:server:adminPreviewStopped')
end)
