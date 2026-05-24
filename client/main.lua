MZHouses = MZHouses or {}

local CurrentHouse = {
  inside = false,
  code = nil,
  data = nil
}

local VisibleHousesCache = {
  houses = nil,
  expiresAt = 0,
  cacheSeconds = 5
}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for key, child in pairs(value) do
    out[key] = cloneTable(child)
  end
  return out
end

local function asVector3(value)
  if type(value) == 'vector3' then
    return value
  end

  if type(value) == 'vector4' then
    return vector3(value.x, value.y, value.z)
  end

  if type(value) == 'table' then
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if x and y and z then
      return vector3(x, y, z)
    end
  end

  return nil
end

local function asVector4(value)
  if type(value) == 'vector4' then
    return value
  end

  if type(value) == 'vector3' then
    return vector4(value.x, value.y, value.z, 0.0)
  end

  if type(value) == 'table' then
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    local w = tonumber(value.w or value.h or value.heading or value[4]) or 0.0
    if x and y and z then
      return vector4(x, y, z, w)
    end
  end

  return nil
end

function MZHouses.Debug(message, data)
  if MZHousesConfig.Debug ~= true then
    return
  end

  local suffix = ''
  if data ~= nil then
    suffix = (' | %s'):format(json.encode(data))
  end

  print(('[mz_houses] %s%s'):format(tostring(message), suffix))
end

function MZHouses.Notify(message, notifyType)
  local text = tostring(message or '')
  local kind = tostring(notifyType or 'inform')
  local notifyConfig = MZHousesConfig.Notify or {}

  if notifyConfig.useMzNotify == true and GetResourceState('mz_notify') == 'started' then
    local ok = pcall(function()
      exports['mz_notify']:Notify({
        type = kind,
        title = 'Casas',
        message = text
      })
    end)

    if ok then
      return
    end
  end

  if notifyConfig.useOxLib == true and lib and type(lib.notify) == 'function' then
    lib.notify({
      type = kind,
      title = 'Casas',
      description = text
    })
    return
  end

  if notifyConfig.chatFallback ~= false then
    TriggerEvent('chat:addMessage', {
      color = { 120, 190, 255 },
      args = { 'mz_houses', text }
    })
  else
    print(('[mz_houses] %s'):format(text))
  end
end

function MZHouses.GetHouse(houseCode)
  local code = trim(houseCode)
  if code == '' then
    return nil, 'invalid_house'
  end

  local house = (MZHousesConfig.Houses or {})[code]
  if type(house) ~= 'table' then
    return nil, 'house_not_found'
  end

  return house, nil, code
end

function MZHouses.GetHouses()
  return MZHousesConfig.Houses or {}
end

local function visibilityEnabled()
  return (MZHousesConfig.Visibility or {}).enabled == true
end

local function getConfiguredVisibilityCacheSeconds()
  return tonumber((MZHousesConfig.Visibility or {}).cacheSeconds) or 5
end

local function getLocalVisibleHousesFallback()
  return MZHousesConfig.Houses or {}
end

function MZHouses.RefreshVisibleHouses(force)
  if not visibilityEnabled() then
    VisibleHousesCache.houses = getLocalVisibleHousesFallback()
    VisibleHousesCache.expiresAt = GetGameTimer() + (getConfiguredVisibilityCacheSeconds() * 1000)
    VisibleHousesCache.cacheSeconds = getConfiguredVisibilityCacheSeconds()
    return VisibleHousesCache.houses
  end

  local now = GetGameTimer()
  if force ~= true and VisibleHousesCache.houses ~= nil and now < (VisibleHousesCache.expiresAt or 0) then
    return VisibleHousesCache.houses
  end

  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    if MZHousesConfig.Debug == true then
      MZHouses.Debug('visible_houses_callback_unavailable')
      VisibleHousesCache.houses = getLocalVisibleHousesFallback()
    else
      VisibleHousesCache.houses = {}
    end

    VisibleHousesCache.expiresAt = now + (getConfiguredVisibilityCacheSeconds() * 1000)
    return VisibleHousesCache.houses
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:listVisibleHouses', false, {})
  end)

  if ok and type(response) == 'table' and response.ok == true and type(response.houses) == 'table' then
    VisibleHousesCache.houses = response.houses
    VisibleHousesCache.cacheSeconds = tonumber(response.cacheSeconds) or getConfiguredVisibilityCacheSeconds()
    VisibleHousesCache.expiresAt = now + (VisibleHousesCache.cacheSeconds * 1000)

    MZHouses.Debug('visible_houses_refreshed', {
      count = #response.houses,
      cacheSeconds = VisibleHousesCache.cacheSeconds
    })

    return VisibleHousesCache.houses
  end

  MZHouses.Debug('visible_houses_callback_failed', {
    ok = ok,
    response = response
  })

  if MZHousesConfig.Debug == true then
    VisibleHousesCache.houses = getLocalVisibleHousesFallback()
  else
    VisibleHousesCache.houses = {}
  end

  VisibleHousesCache.expiresAt = now + (getConfiguredVisibilityCacheSeconds() * 1000)
  return VisibleHousesCache.houses
end

function MZHouses.GetVisibleHouses(force)
  return MZHouses.RefreshVisibleHouses(force == true)
end

local function getCurrentInterior()
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

local function shallowMerge(base, override)
  local out = {}

  if type(base) == 'table' then
    for key, value in pairs(base) do
      out[key] = value
    end
  end

  if type(override) == 'table' then
    for key, value in pairs(override) do
      out[key] = value
    end
  end

  return out
end

function MZHouses.GetHouseInteriorDefaults(house)
  if type(house) ~= 'table' then
    return nil
  end

  local shell = trim(house.shell)
  if shell == '' then
    return nil
  end

  local defaults = MZHousesConfig.InteriorDefaults or {}
  return defaults[shell]
end

function MZHouses.GetEffectiveHousePoint(house, pointName)
  if type(house) ~= 'table' then
    return nil
  end

  local defaults = MZHouses.GetHouseInteriorDefaults(house)
  local point = shallowMerge(defaults and defaults[pointName] or nil, house[pointName])

  if next(point) == nil then
    return nil
  end

  return point
end

function MZHouses.GetEffectiveHouseStash(house)
  return MZHouses.GetEffectiveHousePoint(house, 'stash')
end

function MZHouses.GetEffectiveHouseWardrobe(house)
  return MZHouses.GetEffectiveHousePoint(house, 'wardrobe')
end

function MZHouses.GetEffectiveHouseExit(house)
  return MZHouses.GetEffectiveHousePoint(house, 'exit')
end

local function resolveInteriorPointCoords(point)
  local coords = asVector3(point and point.coords)
  if not coords then
    return nil
  end

  local relative = point.relative == true or point.relative == nil
  if relative ~= true then
    return coords
  end

  local interior = getCurrentInterior()
  local spawnCoords = asVector3(interior and interior.spawnCoords)
  if not spawnCoords then
    return coords
  end

  return vector3(spawnCoords.x + coords.x, spawnCoords.y + coords.y, spawnCoords.z + coords.z)
end

function MZHouses.GetCurrentHouse()
  return cloneTable(CurrentHouse)
end

function MZHouses.IsInsideHouse()
  return CurrentHouse.inside == true
end

local function requestHouseAccess(houseCode)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return false, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:canEnterHouse', false, {
      houseCode = houseCode
    })
  end)

  if not ok then
    MZHouses.Debug('access_callback_failed', {
      house = houseCode,
      error = response
    })
    return false, 'access_check_failed'
  end

  if type(response) ~= 'table' then
    return false, 'invalid_access_response'
  end

  if response.ok == true then
    return true, response
  end

  return false, response.error or 'no_house_access'
end

local function requestOpenHouseStash(houseCode)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return false, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:openHouseStash', false, {
      houseCode = houseCode
    })
  end)

  if not ok then
    MZHouses.Debug('stash_callback_failed', {
      house = houseCode,
      error = response
    })
    return false, 'stash_open_failed'
  end

  if type(response) ~= 'table' then
    return false, 'invalid_stash_response'
  end

  if response.ok ~= true then
    return false, response.error or 'stash_open_failed'
  end

  return true, response
end

local function requestOpenHouseWardrobe(houseCode)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return false, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:openHouseWardrobe', false, {
      houseCode = houseCode
    })
  end)

  if not ok then
    MZHouses.Debug('wardrobe_callback_failed', {
      house = houseCode,
      error = response
    })
    return false, 'wardrobe_open_failed'
  end

  if type(response) ~= 'table' then
    return false, 'invalid_wardrobe_response'
  end

  if response.ok ~= true then
    return false, response.error or 'wardrobe_open_failed'
  end

  return true, response
end

local function requestOpenHouseGarage(houseCode, action)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return false, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:openHouseGarage', false, {
      houseCode = houseCode,
      action = action or 'open'
    })
  end)

  if not ok then
    MZHouses.Debug('garage_callback_failed', {
      house = houseCode,
      action = action,
      error = response
    })
    return false, 'garage_open_failed'
  end

  if type(response) ~= 'table' then
    return false, 'invalid_garage_response'
  end

  if response.ok ~= true then
    MZHouses.Debug('garage_open_failed', {
      house = houseCode,
      action = action,
      error = response.error,
      detail = response.detail
    })
    return false, response.error or 'garage_open_failed'
  end

  return true, response
end

function MZHouses.EnterHouse(houseCode)
  local house, err, code = MZHouses.GetHouse(houseCode)
  if not house then
    return false, err or 'house_not_found'
  end

  if house.enabled == false then
    return false, 'house_disabled'
  end

  if CurrentHouse.inside == true then
    return false, 'already_inside_house'
  end

  if GetResourceState('mz_interiors') ~= 'started' then
    return false, 'interiors_unavailable'
  end

  if tostring(house.type or 'shell') ~= 'shell' then
    return false, 'unsupported_house_type'
  end

  local shellName = trim(house.shell)
  if shellName == '' then
    return false, 'missing_shell'
  end

  local entrance = asVector4(house.entrance)
  if not entrance then
    return false, 'invalid_entrance'
  end

  local allowed, accessOrErr = requestHouseAccess(code)
  if not allowed then
    return false, accessOrErr or 'no_house_access'
  end

  MZHouses.Notify(('Entrando: %s'):format(tostring(house.label or code)), 'inform')

  local ok, resultOrErr = exports['mz_interiors']:EnterShell(shellName, entrance, {
    instanceId = ('house:%s'):format(code),
    heading = entrance.w,
    metadata = {
      houseCode = code,
      houseLabel = house.label or code,
      status = house.status or 'debug',
      accessReason = type(accessOrErr) == 'table' and accessOrErr.reason or nil
    }
  })

  if not ok then
    MZHouses.Debug('enter_house_failed', {
      house = code,
      shell = shellName,
      error = resultOrErr
    })
    return false, resultOrErr or 'enter_failed'
  end

  CurrentHouse.inside = true
  CurrentHouse.code = code
  CurrentHouse.data = cloneTable(house)

  MZHouses.Debug('entered_house', {
    house = code,
    shell = shellName
  })

  MZHouses.Notify(('Voce entrou em %s.'):format(tostring(house.label or code)), 'success')
  return true, MZHouses.GetCurrentHouse()
end

function MZHouses.ExitHouse()
  if GetResourceState('mz_interiors') ~= 'started' then
    return false, 'interiors_unavailable'
  end

  local insideByHouse = CurrentHouse.inside == true
  local insideByInteriors = false

  local insideOk, insideResult = pcall(function()
    return exports['mz_interiors']:IsInsideInterior()
  end)

  if insideOk then
    insideByInteriors = insideResult == true
  end

  if not insideByHouse and not insideByInteriors then
    return false, 'not_inside'
  end

  local ok, resultOrErr = exports['mz_interiors']:ExitShell()
  if not ok then
    return false, resultOrErr or 'exit_failed'
  end

  CurrentHouse.inside = false
  CurrentHouse.code = nil
  CurrentHouse.data = nil

  MZHouses.Notify('Voce saiu da casa.', 'success')
  return true
end

function MZHouses.OpenHouseStash(houseCode)
  local code = trim(houseCode)
  if code == '' and CurrentHouse.inside == true then
    code = trim(CurrentHouse.code)
  end

  if code == '' then
    return false, 'house_not_found'
  end

  local ok, responseOrErr = requestOpenHouseStash(code)
  if not ok then
    return false, responseOrErr or 'stash_open_failed'
  end

  if type(responseOrErr.inventoryTarget) ~= 'table' then
    return false, 'inventory_stash_not_available'
  end

  if GetResourceState('mz_inventory') ~= 'started' then
    return false, 'inventory_stash_not_available'
  end

  local callOk, openOk, openErr = pcall(function()
    return exports['mz_inventory']:OpenTargetView(responseOrErr.inventoryTarget)
  end)

  if not callOk or openOk == false then
    MZHouses.Debug('inventory_open_failed', {
      house = code,
      error = openErr
    })
    return false, 'stash_open_failed'
  end

  return true, responseOrErr
end

function MZHouses.OpenHouseWardrobe(houseCode)
  local code = trim(houseCode)
  if code == '' and CurrentHouse.inside == true then
    code = trim(CurrentHouse.code)
  end

  if code == '' then
    return false, 'house_not_found'
  end

  return requestOpenHouseWardrobe(code)
end

function MZHouses.OpenHouseGarage(houseCode, action)
  local code = trim(houseCode)
  if code == '' and CurrentHouse.inside == true then
    code = trim(CurrentHouse.code)
  end

  if code == '' then
    return false, 'house_not_found'
  end

  return requestOpenHouseGarage(code, action or 'open')
end

local function listHouses()
  local names = {}
  for code in pairs(MZHousesConfig.Houses or {}) do
    names[#names + 1] = code
  end
  table.sort(names)

  if #names == 0 then
    MZHouses.Notify('Nenhuma casa configurada.', 'error')
    return
  end

  MZHouses.Notify(('Casas: %s'):format(table.concat(names, ', ')), 'inform')

  for _, code in ipairs(names) do
    local house = MZHousesConfig.Houses[code] or {}
    print(('[mz_houses] %s - %s | shell=%s | enabled=%s | status=%s'):format(
      code,
      tostring(house.label or 'Sem label'),
      tostring(house.shell or ''),
      tostring(house.enabled ~= false),
      tostring(house.status or '')
    ))
  end
end

local function printHere()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local line = ('entrance = vector4(%.3f, %.3f, %.3f, %.3f)'):format(coords.x, coords.y, coords.z, heading)

  print(('[mz_houses] %s'):format(line))
  MZHouses.Notify(line, 'inform')
end

local function printStashHere()
  if CurrentHouse.inside ~= true then
    MZHouses.Notify('Entre em uma casa para marcar o bau.', 'error')
    return
  end

  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local interior = getCurrentInterior()
  local spawnCoords = asVector3(interior and interior.spawnCoords)
  local shell = trim(CurrentHouse.data and CurrentHouse.data.shell)
  local relative = spawnCoords and vector3(coords.x - spawnCoords.x, coords.y - spawnCoords.y, coords.z - spawnCoords.z) or nil
  local line = ('stash = { enabled = true, coords = vector3(%.3f, %.3f, %.3f), relative = false }'):format(coords.x, coords.y, coords.z)
  local defaultLine = nil

  if relative and shell ~= '' then
    defaultLine = ("MZHousesConfig.InteriorDefaults['%s'].stash = { enabled = true, label = 'Bau da Casa', coords = vector3(%.3f, %.3f, %.3f), slots = 50, weight = 100000, relative = true }"):format(
      shell,
      relative.x,
      relative.y,
      relative.z
    )
  end

  print(('[mz_houses] %s'):format(line))
  MZHouses.Notify(line, 'inform')

  if defaultLine then
    print(('[mz_houses] %s'):format(defaultLine))
  end
end

local function printWardrobeHere()
  if CurrentHouse.inside ~= true then
    MZHouses.Notify('Entre em uma casa para marcar o guarda-roupa.', 'error')
    return
  end

  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local interior = getCurrentInterior()
  local spawnCoords = asVector3(interior and interior.spawnCoords)
  local shell = trim(CurrentHouse.data and CurrentHouse.data.shell)
  local relative = spawnCoords and vector3(coords.x - spawnCoords.x, coords.y - spawnCoords.y, coords.z - spawnCoords.z) or nil
  local line = ('wardrobe = { enabled = true, coords = vector3(%.3f, %.3f, %.3f), relative = false }'):format(coords.x, coords.y, coords.z)
  local defaultLine = nil

  if relative and shell ~= '' then
    defaultLine = ("MZHousesConfig.InteriorDefaults['%s'].wardrobe = { enabled = true, label = 'Guarda-roupa', coords = vector3(%.3f, %.3f, %.3f), relative = true }"):format(
      shell,
      relative.x,
      relative.y,
      relative.z
    )
  end

  print(('[mz_houses] %s'):format(line))
  MZHouses.Notify(line, 'inform')

  if defaultLine then
    print(('[mz_houses] %s'):format(defaultLine))
  end
end

local function printGaragePointHere(kind, houseCode)
  local code = trim(houseCode)
  if code == '' and CurrentHouse.inside == true then
    code = trim(CurrentHouse.code)
  end

  if code == '' then
    MZHouses.Notify('Informe o codigo da casa. Ex: /mhouse_garage_entry_here casa_teste_01', 'error')
    return
  end

  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local line = nil

  if kind == 'entry' then
    line = ('MZHousesConfig.Houses.%s.garage.entry = vector3(%.3f, %.3f, %.3f)'):format(code, coords.x, coords.y, coords.z)
  elseif kind == 'spawn' then
    line = ('MZHousesConfig.Houses.%s.garage.spawn = vector4(%.3f, %.3f, %.3f, %.3f)'):format(code, coords.x, coords.y, coords.z, heading)
  elseif kind == 'store' then
    line = ('MZHousesConfig.Houses.%s.garage.store = vector3(%.3f, %.3f, %.3f)'):format(code, coords.x, coords.y, coords.z)
  end

  local block = ([[
garage = {
  enabled = true,
  label = 'Garagem da Casa',
  entry = vector3(%.3f, %.3f, %.3f),
  spawn = vector4(%.3f, %.3f, %.3f, %.3f),
  store = vector3(%.3f, %.3f, %.3f),
  storeRadius = 4.0,
  vehicleTypes = { 'car', 'bike' }
}]]):format(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z, heading, coords.x, coords.y, coords.z)

  if line then
    print(('[mz_houses] %s'):format(line))
    MZHouses.Notify(line, 'inform')
  end

  print(('[mz_houses] Sugestao completa para %s:\n%s'):format(code, block))
end

local function drawText3d(coords, text, scale)
  local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
  if not onScreen then
    return
  end

  SetTextScale(scale or 0.32, scale or 0.32)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextColour(255, 255, 255, 230)
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(text)
  DrawText(x, y)

  local factor = string.len(text) / 370
  DrawRect(x, y + 0.0125, 0.018 + factor, 0.03, 0, 0, 0, 95)
end

local function drawStashMarker(coords)
  local stash = MZHousesConfig.Stash or {}
  local marker = stash.marker or {}
  if marker.enabled == false then
    return
  end

  local color = marker.color or {}
  local size = marker.size or vector3(0.3, 0.3, 0.3)
  local z = coords.z + (tonumber(marker.offsetZ) or 0.1)

  DrawMarker(
    tonumber(marker.type) or 2,
    coords.x, coords.y, z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    size.x, size.y, size.z,
    tonumber(color.r) or 255,
    tonumber(color.g) or 190,
    tonumber(color.b) or 80,
    tonumber(color.a) or 180,
    false,
    true,
    2,
    false,
    nil,
    nil,
    false
  )
end

local function drawWardrobeMarker(coords)
  local wardrobe = MZHousesConfig.Wardrobe or {}
  local marker = wardrobe.marker or {}
  if marker.enabled == false then
    return
  end

  local color = marker.color or {}
  local size = marker.size or vector3(0.3, 0.3, 0.3)
  local z = coords.z + (tonumber(marker.offsetZ) or 0.1)

  DrawMarker(
    tonumber(marker.type) or 2,
    coords.x, coords.y, z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    size.x, size.y, size.z,
    tonumber(color.r) or 180,
    tonumber(color.g) or 120,
    tonumber(color.b) or 255,
    tonumber(color.a) or 180,
    false,
    true,
    2,
    false,
    nil,
    nil,
    false
  )
end

local function drawExitMarker(coords)
  local exitConfig = MZHousesConfig.Exit or {}
  local marker = exitConfig.marker or {}
  if marker.enabled == false then
    return
  end

  local color = marker.color or {}
  local size = marker.size or vector3(0.3, 0.3, 0.3)
  local z = coords.z + (tonumber(marker.offsetZ) or 0.1)

  DrawMarker(
    tonumber(marker.type) or 2,
    coords.x, coords.y, z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    size.x, size.y, size.z,
    tonumber(color.r) or 255,
    tonumber(color.g) or 90,
    tonumber(color.b) or 90,
    tonumber(color.a) or 180,
    false,
    true,
    2,
    false,
    nil,
    nil,
    false
  )
end

local function drawGarageMarker(coords, markerConfig)
  markerConfig = type(markerConfig) == 'table' and markerConfig or {}
  if markerConfig.enabled == false then
    return
  end

  local color = markerConfig.color or {}
  local size = markerConfig.size or vector3(0.55, 0.55, 0.55)
  local z = coords.z + (tonumber(markerConfig.offsetZ) or 0.1)

  DrawMarker(
    tonumber(markerConfig.type) or 36,
    coords.x, coords.y, z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    size.x, size.y, size.z,
    tonumber(color.r) or 57,
    tonumber(color.g) or 229,
    tonumber(color.b) or 140,
    tonumber(color.a) or 130,
    false,
    true,
    2,
    false,
    nil,
    nil,
    false
  )
end

local function runStashMarkerLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      local stashConfig = MZHousesConfig.Stash or {}

      if stashConfig.enabled == true and CurrentHouse.inside == true and type(CurrentHouse.data) == 'table' then
        local houseStash = MZHouses.GetEffectiveHouseStash(CurrentHouse.data) or {}
        if houseStash.enabled == true then
          local coords = resolveInteriorPointCoords(houseStash)
          if coords then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local markerDistance = tonumber(stashConfig.markerDistance) or 10.0
            local interactDistance = tonumber(stashConfig.interactionDistance) or 2.0
            local key = tonumber((MZHousesConfig.Interaction or {}).key) or 38
            local distance = #(playerCoords - coords)

            if distance <= markerDistance then
              waitMs = 0
              drawStashMarker(coords)

              if distance <= interactDistance then
                local textConfig = stashConfig.text or {}
                if textConfig.enabled ~= false then
                  drawText3d(
                    vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.4)),
                    ('[E] %s'):format(tostring(houseStash.label or 'Abrir bau')),
                    tonumber(textConfig.scale) or 0.32
                  )
                end

                if IsControlJustReleased(0, key) then
                  local opened, err = MZHouses.OpenHouseStash(CurrentHouse.code)
                  if not opened then
                    MZHouses.Notify(('Nao foi possivel abrir o bau: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
                  end
                  Wait(500)
                end
              end
            end
          end
        end
      end

      Wait(waitMs)
    end
  end)
end

local function runWardrobeMarkerLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      local wardrobeConfig = MZHousesConfig.Wardrobe or {}

      if wardrobeConfig.enabled == true and CurrentHouse.inside == true and type(CurrentHouse.data) == 'table' then
        local houseWardrobe = MZHouses.GetEffectiveHouseWardrobe(CurrentHouse.data) or {}
        if houseWardrobe.enabled == true then
          local coords = resolveInteriorPointCoords(houseWardrobe)
          if coords then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local markerDistance = tonumber(wardrobeConfig.markerDistance) or 10.0
            local interactDistance = tonumber(wardrobeConfig.interactionDistance) or 2.0
            local key = tonumber((MZHousesConfig.Interaction or {}).key) or 38
            local distance = #(playerCoords - coords)

            if distance <= markerDistance then
              waitMs = 0
              drawWardrobeMarker(coords)

              if distance <= interactDistance then
                local textConfig = wardrobeConfig.text or {}
                if textConfig.enabled ~= false then
                  drawText3d(
                    vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.4)),
                    ('[E] %s'):format(tostring(houseWardrobe.label or 'Guarda-roupa')),
                    tonumber(textConfig.scale) or 0.32
                  )
                end

                if IsControlJustReleased(0, key) then
                  local opened, err = MZHouses.OpenHouseWardrobe(CurrentHouse.code)
                  if not opened then
                    MZHouses.Notify(('Nao foi possivel abrir o guarda-roupa: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
                  end
                  Wait(500)
                end
              end
            end
          end
        end
      end

      Wait(waitMs)
    end
  end)
end

local function runExitMarkerLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      local exitConfig = MZHousesConfig.Exit or {}

      if exitConfig.enabled == true and CurrentHouse.inside == true and type(CurrentHouse.data) == 'table' then
        local houseExit = MZHouses.GetEffectiveHouseExit(CurrentHouse.data) or {}
        if houseExit.enabled == true then
          local coords = resolveInteriorPointCoords(houseExit)
          if coords then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local markerDistance = tonumber(exitConfig.markerDistance) or 10.0
            local interactDistance = tonumber(exitConfig.interactionDistance) or 2.0
            local key = tonumber((MZHousesConfig.Interaction or {}).key) or 38
            local distance = #(playerCoords - coords)

            if distance <= markerDistance then
              waitMs = 0
              drawExitMarker(coords)

              if distance <= interactDistance then
                local textConfig = exitConfig.text or {}
                if textConfig.enabled ~= false then
                  drawText3d(
                    vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.4)),
                    ('[E] %s'):format(tostring(houseExit.label or 'Sair da casa')),
                    tonumber(textConfig.scale) or 0.32
                  )
                end

                if IsControlJustReleased(0, key) then
                  local exited, err = MZHouses.ExitHouse()
                  if not exited then
                    MZHouses.Notify(('Nao foi possivel sair: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
                  end
                  Wait(500)
                end
              end
            end
          end
        end
      end

      Wait(waitMs)
    end
  end)
end

local function runGarageMarkerLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      local garageConfig = MZHousesConfig.Garage or {}

      if garageConfig.enabled == true and not MZHouses.IsInsideHouse() then
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local vehicle = GetVehiclePedIsIn(ped, false)
        local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped

        local visibleHouses = MZHouses.GetVisibleHouses and MZHouses.GetVisibleHouses(false) or (MZHousesConfig.Houses or {})
        for houseKey, house in pairs(visibleHouses or {}) do
          local code = type(houseKey) == 'number' and trim(house and house.code) or trim(houseKey)
          local houseGarage = type(house) == 'table' and type(house.garage) == 'table' and house.garage or nil
          if code ~= '' and houseGarage and houseGarage.enabled == true then
            local entry = asVector3(houseGarage.entry)
            local store = asVector3(houseGarage.store)
            local key = tonumber((MZHousesConfig.Interaction or {}).key) or 38

            if not isDriver and entry then
              local distance = #(playerCoords - entry)
              local markerDistance = tonumber(garageConfig.markerDistance) or 15.0
              local interactDistance = tonumber(garageConfig.interactionDistance) or 2.0

              if distance <= markerDistance then
                waitMs = 0
                drawGarageMarker(entry, garageConfig.marker)

                if distance <= interactDistance then
                  local textConfig = garageConfig.text or {}
                  if textConfig.enabled ~= false then
                    drawText3d(
                      vector3(entry.x, entry.y, entry.z + (tonumber(textConfig.offsetZ) or 0.45)),
                      ('[E] %s'):format(tostring(houseGarage.label or ('Garagem - ' .. tostring(house.label or code)))),
                      tonumber(textConfig.scale) or 0.32
                    )
                  end

                  if IsControlJustReleased(0, key) then
                    local opened, err = MZHouses.OpenHouseGarage(code, 'open')
                    if not opened then
                      MZHouses.Notify(('Nao foi possivel abrir a garagem: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
                    end
                    Wait(500)
                  end
                end
              end
            end

            if isDriver and store then
              local distance = #(playerCoords - store)
              local markerDistance = tonumber(garageConfig.storeMarkerDistance) or 18.0
              local interactDistance = tonumber(houseGarage.storeRadius or garageConfig.storeInteractionDistance) or 4.0

              if distance <= markerDistance then
                waitMs = 0
                drawGarageMarker(store, garageConfig.storeMarker)

                if distance <= interactDistance then
                  local textConfig = garageConfig.text or {}
                  if textConfig.enabled ~= false then
                    drawText3d(
                      vector3(store.x, store.y, store.z + (tonumber(textConfig.offsetZ) or 0.45)),
                      '[E] Guardar veiculo',
                      tonumber(textConfig.scale) or 0.32
                    )
                  end

                  if IsControlJustReleased(0, key) then
                    local opened, err = MZHouses.OpenHouseGarage(code, 'store')
                    if not opened then
                      MZHouses.Notify(('Nao foi possivel guardar pela garagem da casa: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
                    end
                    Wait(500)
                  end
                end
              end
            end
          end
        end
      end

      Wait(waitMs)
    end
  end)
end

function MZHouses.RunCommandAction(action, args)
  action = trim(action)
  args = type(args) == 'table' and args or {}

  if action == 'list' then
    listHouses()
    return
  end

  if action == 'enter' then
    local houseCode = trim(args[1])
    if houseCode == '' then
      MZHouses.Notify('Uso: /' .. tostring((MZHousesConfig.Commands or {}).enter or 'mhouse_enter') .. ' codigo_da_casa', 'error')
      return
    end

    local ok, err = MZHouses.EnterHouse(houseCode)
    if not ok then
      MZHouses.Notify(('Nao foi possivel entrar: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
    end
    return
  end

  if action == 'exit' then
    local ok, err = MZHouses.ExitHouse()
    if not ok then
      MZHouses.Notify(('Nao foi possivel sair: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
    end
    return
  end

  if action == 'here' then
    printHere()
    return
  end

  if action == 'stash_here' then
    printStashHere()
    return
  end

  if action == 'wardrobe_here' then
    printWardrobeHere()
    return
  end

  if action == 'garage_entry_here' then
    printGaragePointHere('entry', args[1])
    return
  end

  if action == 'garage_spawn_here' then
    printGaragePointHere('spawn', args[1])
    return
  end

  if action == 'garage_store_here' then
    printGaragePointHere('store', args[1])
    return
  end
end

local function requestCommand(action, args)
  local commands = MZHousesConfig.Commands or {}
  if commands.requireAce == true then
    TriggerServerEvent('mz_houses:server:runCommand', action, args or {})
    return
  end

  MZHouses.RunCommandAction(action, args)
end

local function registerDebugCommands()
  local commands = MZHousesConfig.Commands or {}
  if commands.enabled ~= true then
    return
  end

  RegisterCommand(tostring(commands.list or 'mhouse_list'), function()
    requestCommand('list', {})
  end, false)

  RegisterCommand(tostring(commands.enter or 'mhouse_enter'), function(_, args)
    requestCommand('enter', args or {})
  end, false)

  RegisterCommand(tostring(commands.exit or 'mhouse_exit'), function()
    requestCommand('exit', {})
  end, false)

  RegisterCommand(tostring(commands.here or 'mhouse_here'), function()
    requestCommand('here', {})
  end, false)

  RegisterCommand(tostring(commands.stashHere or 'mhouse_stash_here'), function()
    requestCommand('stash_here', {})
  end, false)

  RegisterCommand(tostring(commands.wardrobeHere or 'mhouse_wardrobe_here'), function()
    requestCommand('wardrobe_here', {})
  end, false)

  RegisterCommand(tostring(commands.garageEntryHere or 'mhouse_garage_entry_here'), function(_, args)
    requestCommand('garage_entry_here', args or {})
  end, false)

  RegisterCommand(tostring(commands.garageSpawnHere or 'mhouse_garage_spawn_here'), function(_, args)
    requestCommand('garage_spawn_here', args or {})
  end, false)

  RegisterCommand(tostring(commands.garageStoreHere or 'mhouse_garage_store_here'), function(_, args)
    requestCommand('garage_store_here', args or {})
  end, false)
end

RegisterNetEvent('mz_houses:client:runCommand', function(action, args)
  MZHouses.RunCommandAction(action, args)
end)

RegisterNetEvent('mz_houses:client:commandDenied', function(reason)
  MZHouses.Notify(('Comando negado: %s'):format(tostring(reason or 'sem_permissao')), 'error')
end)

RegisterNetEvent('mz_houses:client:refreshVisibility', function(reason)
  MZHouses.RefreshVisibleHouses(true)
  TriggerEvent('mz_houses:client:visibilityUpdated', reason or 'refresh')
end)

RegisterNetEvent('mz_core:client:playerLoaded', function()
  MZHouses.RefreshVisibleHouses(true)
  TriggerEvent('mz_houses:client:visibilityUpdated', 'player_loaded')
end)

RegisterNetEvent('mz_houses:client:enterHouse', function(houseCode)
  local ok, err = MZHouses.EnterHouse(houseCode)
  if not ok then
    MZHouses.Notify(('Nao foi possivel entrar: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
  end
end)

RegisterNetEvent('mz_houses:client:listingInfo', function(houseCode)
  local code = trim(houseCode)
  if code == '' then
    return
  end

  -- TODO: fase futura mz_realestate / corretor: abrir menu de compra/visita.
  MZHouses.Notify(('Imovel listado: %s. Compra/visita ainda nao implementada.'):format(code), 'inform')
end)

RegisterNetEvent('mz_houses:client:exitHouse', function()
  local ok, err = MZHouses.ExitHouse()
  if not ok then
    MZHouses.Notify(('Nao foi possivel sair: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
  end
end)

exports('EnterHouse', function(houseCode)
  return MZHouses.EnterHouse(houseCode)
end)

exports('ExitHouse', function()
  return MZHouses.ExitHouse()
end)

exports('GetCurrentHouse', function()
  return MZHouses.GetCurrentHouse()
end)

exports('GetHouses', function()
  return MZHouses.GetHouses()
end)

exports('IsInsideHouse', function()
  return MZHouses.IsInsideHouse()
end)

exports('OpenHouseStash', function(houseCode)
  return MZHouses.OpenHouseStash(houseCode)
end)

exports('OpenHouseWardrobe', function(houseCode)
  return MZHouses.OpenHouseWardrobe(houseCode)
end)

exports('OpenHouseGarage', function(houseCode, action)
  return MZHouses.OpenHouseGarage(houseCode, action)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then
    return
  end

  if CurrentHouse.inside == true and GetResourceState('mz_interiors') == 'started' then
    pcall(function()
      exports['mz_interiors']:ExitShell()
    end)
  end
end)

MZHouses.AsVector3 = asVector3
MZHouses.AsVector4 = asVector4

registerDebugCommands()
runStashMarkerLoop()
runWardrobeMarkerLoop()
runExitMarkerLoop()
runGarageMarkerLoop()
