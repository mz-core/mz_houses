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

local function interiorEditPayload(code, pointName)
  local current = MZHouses and MZHouses.GetCurrentHouse and MZHouses.GetCurrentHouse() or {}
  if current.inside ~= true or trim(current.code) ~= trim(code) then
    return nil, 'Entre neste imovel para definir pontos internos.'
  end

  local interior = currentInterior()
  local spawnCoords = vectorPayload(interior and interior.spawnCoords, false)
  if not spawnCoords then
    return nil, 'Contexto do interior indisponivel.'
  end

  return {
    code = trim(code),
    pointName = pointName,
    inside = true,
    currentHouseCode = trim(current.code),
    shell = trim((interior and interior.shellName) or (current.data and current.data.shell)),
    spawnCoords = spawnCoords,
    point = currentPoint(pointName == 'exit')
  }
end

local function internalStatusText(status)
  status = type(status) == 'table' and status or {}
  return ('%s/%s'):format(tostring(status.state or 'ausente'), tostring(status.source or 'none'))
end

local function internalSummary(property)
  local points = type(property) == 'table' and type(property.internalPoints) == 'table' and property.internalPoints or {}
  return ('shell=%s saida=%s bau=%s armario=%s'):format(
    tostring(points.shell or property.shell or 'nil'),
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

local function callAdmin(name, payload)
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
  return ('%s/%s/%s | public=%s | visibility=%s | garage=%s'):format(
    tostring(property.category or 'nil'),
    tostring(property.subtype or 'nil'),
    tostring(property.ownerType or 'nil'),
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
    ('OrgCode: %s'):format(tostring(property.orgCode or 'nil')),
    ('Shell: %s'):format(tostring(property.shell or 'nil')),
    ('Visibility: %s'):format(tostring(property.visibility or 'auto')),
    ('Public: %s'):format(boolText(property.public == true)),
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
        title = 'Criar imovel aqui',
        icon = 'plus',
        onSelect = function()
          MZHousesAdminMenu.CreateHere()
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
        title = 'Buscar imovel por codigo',
        icon = 'search',
        onSelect = function()
          MZHousesAdminMenu.SearchByCode()
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
          notify('Use o menu para cadastro tecnico. Compra, venda e corretor ficam para fase futura.', 'inform')
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
        title = 'Interior / Pontos Internos',
        description = internalSummary(property),
        icon = 'scan-line',
        onSelect = function()
          MZHousesAdminMenu.OpenInternalPoints(property.code)
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
        title = 'Dono / Chaves',
        icon = 'key-round',
        onSelect = function()
          MZHousesAdminMenu.OpenOwnerKeys(property.code)
        end
      },
      {
        title = 'Visibilidade / Listavel',
        icon = 'eye',
        onSelect = function()
          MZHousesAdminMenu.OpenVisibility(property.code)
        end
      },
      {
        title = 'Org / Base / Gang',
        icon = 'shield',
        onSelect = function()
          MZHousesAdminMenu.OpenOrg(property.code)
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

function MZHousesAdminMenu.CreateHere()
  local input = inputDialog('Criar imovel aqui', {
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
    { type = 'input', label = 'Codigo', required = true, placeholder = 'casa_admin_01' }
  })

  if not input then return end
  MZHousesAdminMenu.OpenProperty(input[1])
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
              { value = 'org', label = 'org' },
              { value = 'business', label = 'business' },
              { value = 'government', label = 'government' },
              { value = 'other', label = 'other' }
            } },
            { type = 'input', label = 'Subtype', required = true, default = tostring(property.subtype or 'house') },
            { type = 'select', label = 'OwnerType', required = true, default = tostring(property.ownerType or 'player'), options = {
              { value = 'player', label = 'player' },
              { value = 'org', label = 'org' },
              { value = 'business', label = 'business' },
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
  local payload, err = interiorEditPayload(code, pointName)
  if not payload then
    notify(err or 'Entre no imovel para definir pontos internos.', 'error')
    return
  end

  handleResponse(callAdmin('mz_houses:server:admin:setInternalPoint', payload), code)
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
  local insideDescription = insideThisHouse and 'Voce esta dentro deste imovel.' or 'Entre no imovel para definir offsets internos.'

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
        title = 'Definir saida aqui',
        description = insideDescription,
        icon = 'door-open',
        disabled = not insideThisHouse,
        onSelect = function()
          MZHousesAdminMenu.SetInternalPoint(code, 'exit')
        end
      },
      {
        title = 'Definir bau aqui',
        description = insideDescription,
        icon = 'package',
        disabled = not insideThisHouse,
        onSelect = function()
          MZHousesAdminMenu.SetInternalPoint(code, 'stash')
        end
      },
      {
        title = 'Definir armario aqui',
        description = insideDescription,
        icon = 'shirt',
        disabled = not insideThisHouse,
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

function MZHousesAdminMenu.OpenOwnerKeys(code)
  local property = getProperty(code)
  if not property then return end

  local keysDescription = 'nenhuma'
  if type(property.keys) == 'table' and #property.keys > 0 then
    keysDescription = table.concat(property.keys, ', ')
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
            { type = 'input', label = 'CitizenID', required = true }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setOwner', {
              code = code,
              citizenid = trim(input[1])
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
        title = 'Dar chave por citizenid',
        icon = 'key-round',
        onSelect = function()
          local input = inputDialog('Dar chave', {
            { type = 'input', label = 'CitizenID', required = true }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:giveKey', {
              code = code,
              citizenid = trim(input[1])
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
      }
    }
  })
end

function MZHousesAdminMenu.OpenVisibility(code)
  local property = getProperty(code)
  if not property then return end

  openContext({
    id = 'mz_houses_admin_visibility',
    title = 'Visibilidade / Listavel',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = property.public == true and 'Public false' or 'Public true',
        description = 'Public controla entrada publica, nao venda',
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
      },
      {
        title = property.canBeListed == true and 'Listable false' or 'Listable true',
        description = ('%s (%s)'):format(boolText(property.canBeListed == true), tostring(property.canBeListedReason or 'nil')),
        icon = 'badge-dollar-sign',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setListable', {
            code = code,
            value = property.canBeListed ~= true
          }), code)
        end
      }
    }
  })
end

function MZHousesAdminMenu.OpenOrg(code)
  local property = getProperty(code)
  if not property then return end

  openContext({
    id = 'mz_houses_admin_org',
    title = 'Org / Base / Gang',
    menu = 'mz_houses_admin_property',
    options = {
      {
        title = 'Definir como org/gang_base',
        description = 'category=org subtype=gang_base ownerType=org',
        icon = 'shield',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setCategory', {
            code = code,
            category = 'org',
            subtype = 'gang_base',
            ownerType = 'org'
          }), code)
        end
      },
      {
        title = 'Definir orgCode',
        description = tostring(property.orgCode or 'nil'),
        icon = 'building',
        onSelect = function()
          local input = inputDialog('Org code', {
            { type = 'input', label = 'OrgCode', required = true, default = tostring(property.orgCode or '') }
          })
          if input then
            handleResponse(callAdmin('mz_houses:server:admin:setOrg', {
              code = code,
              orgCode = trim(input[1])
            }), code)
          end
        end
      },
      {
        title = 'Voltar para residencial/player',
        icon = 'home',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:setCategory', {
            code = code,
            category = 'residential',
            subtype = 'house',
            ownerType = 'player'
          }), code)
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
        description = 'Desativa e esconde, sem deletar do banco',
        icon = 'archive',
        onSelect = function()
          handleResponse(callAdmin('mz_houses:server:admin:updateBasic', { code = code, field = 'archive' }), code)
        end
      }
    }
  })
end

CreateThread(function()
  local cfg = menuConfig()
  RegisterCommand(tostring(cfg.command or 'mhouse_admin'), function()
    MZHousesAdminMenu.Open()
  end, false)

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
