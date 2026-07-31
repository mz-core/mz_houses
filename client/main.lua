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

local DoorContextCache = {
  entries = {},
  ttlMs = 1000
}

local DoorAnimationBusy = false
local DoorToggleBusy = false
local DoorToggleCooldownUntil = 0

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizeDoorState(value)
  local state = trim(value):lower()
  if state == 'unlocked' or state == 'blocked' then return state end
  return 'locked'
end

function MZHouses.DoorStateLabel(state)
  state = normalizeDoorState(state)
  if state == 'unlocked' then return 'Destrancada' end
  if state == 'blocked' then return 'Interditada' end
  return 'Trancada'
end

function MZHouses.DoorActionLabel(state)
  state = normalizeDoorState(state)
  if state == 'unlocked' then return 'Trancar' end
  if state == 'locked' then return 'Destrancar' end
  return nil
end

local function findVisibleHouse(code)
  code = trim(code)
  for key, house in pairs(type(VisibleHousesCache.houses) == 'table' and VisibleHousesCache.houses or {}) do
    local candidateCode = type(key) == 'number' and trim(house and house.code) or trim(key)
    if candidateCode == code then return house, key end
  end
  return nil
end

function MZHouses.GetVisibleHouseByCode(houseCode)
  return findVisibleHouse(trim(houseCode))
end

local function applyDoorContext(code, state, canControl, expiresAt)
  code = trim(code)
  if code == '' then return nil end
  local previous = DoorContextCache.entries[code] or {}
  local nextCanControl = previous.canControl == true
  if canControl ~= nil then nextCanControl = canControl == true end
  local entry = {
    state = normalizeDoorState(state or previous.state),
    canControl = nextCanControl,
    expiresAt = tonumber(expiresAt) or (GetGameTimer() + DoorContextCache.ttlMs)
  }
  DoorContextCache.entries[code] = entry
  local presentationChanged = previous.state ~= entry.state or previous.canControl ~= entry.canControl

  local visible = findVisibleHouse(code)
  if type(visible) == 'table' then visible.doorState = entry.state end
  if CurrentHouse.inside == true and trim(CurrentHouse.code) == code then
    CurrentHouse.data = type(CurrentHouse.data) == 'table' and CurrentHouse.data or {}
    CurrentHouse.data.doorState = entry.state
  end

  if presentationChanged then
    TriggerEvent('mz_houses:client:doorPresentationChanged', {
      houseCode = code,
      state = entry.state,
      canControl = entry.canControl
    })
  end
  return entry
end

function MZHouses.GetDoorPresentation(houseCode, house)
  local code = trim(houseCode)
  local cached = DoorContextCache.entries[code]
  local state = normalizeDoorState(cached and cached.state or type(house) == 'table' and house.doorState or 'locked')
  return {
    state = state,
    stateLabel = MZHouses.DoorStateLabel(state),
    canControl = cached and cached.canControl == true or false,
    actionLabel = cached and cached.canControl == true and MZHouses.DoorActionLabel(state) or nil
  }
end

function MZHouses.GetDoorContext(houseCode, force)
  local code = trim(houseCode)
  if code == '' then return nil, 'invalid_house' end
  local now = GetGameTimer()
  local cached = DoorContextCache.entries[code]
  if force ~= true and cached and now < (cached.expiresAt or 0) then return cached end
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then return nil, 'callback_unavailable' end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:getDoorContext', false, { houseCode = code })
  end)
  if not ok or type(response) ~= 'table' or response.ok ~= true then
    MZHouses.Debug('door_context_failed', { house = code, response = response })
    return nil, type(response) == 'table' and response.error or 'door_context_failed'
  end
  return applyDoorContext(code, response.state, response.canControl, now + DoorContextCache.ttlMs)
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

local visibilityEnabled

local function fetchPublicPropertyInfo(code)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return nil
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:getPublicPropertyInfo', false, {
      houseCode = code
    })
  end)

  if ok and type(response) == 'table' and response.ok == true and type(response.property) == 'table' then
    VisibleHousesCache.houses = type(VisibleHousesCache.houses) == 'table' and VisibleHousesCache.houses or {}
    VisibleHousesCache.houses[code] = response.property
    return response.property
  end

  return nil
end

function MZHouses.GetHouse(houseCode)
  local code = trim(houseCode)
  if code == '' then
    return nil, 'invalid_house'
  end

  local visibleHouses = nil
  if visibilityEnabled() then
    visibleHouses = VisibleHousesCache.houses
  end

  if visibilityEnabled() and type(visibleHouses) ~= 'table' then
    visibleHouses = MZHouses.RefreshVisibleHouses and MZHouses.RefreshVisibleHouses(true) or nil
  end

  if type(visibleHouses) == 'table' then
    local visibleHouse = visibleHouses[code]
    if type(visibleHouse) == 'table' then
      return visibleHouse, nil, code
    end

    for _, candidate in pairs(visibleHouses) do
      if type(candidate) == 'table' and trim(candidate.code) == code then
        return candidate, nil, code
      end
    end
  end

  local house = (MZHousesConfig.Houses or {})[code]
  if type(house) == 'table' then
    return house, nil, code
  end

  local fetched = fetchPublicPropertyInfo(code)
  if type(fetched) == 'table' then
    return fetched, nil, code
  end

  return nil, 'house_not_found'
end

function MZHouses.GetHouses()
  return MZHousesConfig.Houses or {}
end

visibilityEnabled = function()
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
  local interior = type(house.interior) == 'table' and house.interior or {}
  local override = type(interior[pointName]) == 'table' and interior[pointName] or house[pointName]
  local point = shallowMerge(defaults and defaults[pointName] or nil, override)

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

  if GetResourceState('mz_interiors') == 'started' then
    local ok, resolved = pcall(function()
      return exports['mz_interiors']:ResolveCurrentInteriorPoint({
        x = coords.x,
        y = coords.y,
        z = coords.z
      })
    end)

    local world = ok and asVector3(resolved) or nil

    if world then
      return world
    end
  end

  -- Fallback para shells antigos com heading 0.
  local interior = getCurrentInterior()
  local spawnCoords = asVector3(interior and interior.spawnCoords)

  if not spawnCoords then
    return coords
  end

  return vector3(
    spawnCoords.x + coords.x,
    spawnCoords.y + coords.y,
    spawnCoords.z + coords.z
  )
end

local function friendlyDoorError(err)
  local messages = {
    door_blocked = 'A porta está interditada.',
    admin_required = 'A porta está interditada.',
    door_control_denied = 'Você não possui controle desta porta.',
    no_house_access = 'Você não possui controle desta porta.'
  }
  return messages[tostring(err or '')] or 'Não foi possível alterar a porta.'
end

local function requestAnimDict(dict, timeoutMs)
  RequestAnimDict(dict)
  local deadline = GetGameTimer() + (tonumber(timeoutMs) or 2000)
  while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
  return HasAnimDictLoaded(dict)
end

local function playDoorKeyAnimation()
  local config = MZHousesConfig.DoorAnimation or {}
  if config.enabled == false or DoorAnimationBusy then return nil end
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false) then
    return nil
  end

  DoorAnimationBusy = true
  local dict = trim(config.dict)
  local clip = trim(config.clip)
  if dict == '' then dict = 'anim@mp_player_intmenu@key_fob@' end
  if clip == '' then clip = 'fob_click' end
  if not requestAnimDict(dict, tonumber(config.loadTimeoutMs) or 2000) then
    DoorAnimationBusy = false
    return nil
  end

  local duration = math.max(250, tonumber(config.duration) or 900)
  TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration, tonumber(config.flag) or 48, 0.0, false, false, false)
  local startedAt = GetGameTimer()
  Wait(math.min(duration, math.max(0, tonumber(config.triggerAt) or 500)))
  return { ped = ped, dict = dict, clip = clip, duration = duration, startedAt = startedAt }
end

local function finishDoorKeyAnimation(animation)
  if type(animation) == 'table' then
    local remaining = animation.duration - (GetGameTimer() - animation.startedAt)
    if remaining > 0 then Wait(remaining) end
    if DoesEntityExist(animation.ped) then
      StopAnimTask(animation.ped, animation.dict, animation.clip, 1.0)
    end
    RemoveAnimDict(animation.dict)
  end
  DoorAnimationBusy = false
end

function MZHouses.ToggleDoor(houseCode)
  local code = trim(houseCode)
  if code == '' then return false, 'invalid_house' end
  local now = GetGameTimer()
  if DoorToggleBusy or now < DoorToggleCooldownUntil then return false, 'door_toggle_busy' end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return false, 'in_vehicle' end

  DoorToggleBusy = true
  DoorToggleCooldownUntil = now + (tonumber((MZHousesConfig.DoorAnimation or {}).cooldownMs) or 1000)
  local function releaseToggle()
    DoorToggleBusy = false
  end

  local context, contextErr = MZHouses.GetDoorContext(code, true)
  if not context then
    MZHouses.Notify(friendlyDoorError(contextErr), 'error')
    releaseToggle()
    return false, contextErr
  end
  if context.state == 'blocked' then
    MZHouses.Notify('A porta está interditada.', 'warning')
    releaseToggle()
    return false, 'door_blocked'
  end
  if context.canControl ~= true then
    MZHouses.Notify('Você não possui controle desta porta.', 'error')
    releaseToggle()
    return false, 'door_control_denied'
  end

  local nextState = context.state == 'unlocked' and 'locked' or 'unlocked'
  local animation = playDoorKeyAnimation()
  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:setDoorState', false, { houseCode = code, state = nextState })
  end)
  finishDoorKeyAnimation(animation)
  if not ok or type(response) ~= 'table' or response.ok ~= true then
    local err = type(response) == 'table' and response.error or 'door_update_failed'
    MZHouses.Debug('door_toggle_failed', { house = code, state = nextState, response = response })
    MZHouses.Notify(friendlyDoorError(err), 'error')
    releaseToggle()
    return false, err
  end

  applyDoorContext(code, response.state or nextState, true)
  MZHouses.Notify(nextState == 'locked' and 'Porta trancada.' or 'Porta destrancada.', 'success')
  releaseToggle()
  return true, response
end

function MZHouses.GetCurrentHouse()
  return cloneTable(CurrentHouse)
end

function MZHouses.UpdateCurrentHouseData(house)
  if CurrentHouse.inside ~= true or type(house) ~= 'table' then
    return false
  end

  local code = trim(house.code)
  if code == '' or trim(CurrentHouse.code) ~= code then
    return false
  end

  local featureAccess = type(CurrentHouse.data) == 'table' and cloneTable(CurrentHouse.data.featureAccess) or nil
  CurrentHouse.data = cloneTable(house)
  if type(featureAccess) == 'table' then CurrentHouse.data.featureAccess = featureAccess end
  return true
end

function MZHouses.IsInsideHouse()
  return CurrentHouse.inside == true
end

local function requestHouseAccess(houseCode)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return false, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:beginEnterHouse', false, {
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

local function requestEntryContext(houseCode)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return nil, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:resolveEntryContext', false, {
      houseCode = houseCode
    })
  end)

  if not ok or type(response) ~= 'table' then
    return nil, 'entry_context_failed'
  end

  if response.ok ~= true then
    return nil, response.error or response.reason or 'entry_context_failed'
  end

  return response, nil
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

function MZHouses.RefreshCurrentFeatureAccess()
  if CurrentHouse.inside ~= true or trim(CurrentHouse.code) == '' then return false, 'not_inside_property' end
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return false, 'callback_unavailable'
  end

  local code = trim(CurrentHouse.code)
  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:getFeatureContext', false, { houseCode = code })
  end)
  if not ok or type(response) ~= 'table' or response.ok ~= true or trim(response.houseCode) ~= code then
    return false, type(response) == 'table' and response.error or 'feature_context_failed'
  end

  CurrentHouse.data = type(CurrentHouse.data) == 'table' and CurrentHouse.data or {}
  CurrentHouse.data.featureAccess = {
    stash = type(response.features) == 'table' and response.features.stash == true,
    wardrobe = type(response.features) == 'table' and response.features.wardrobe == true,
    garage = type(response.features) == 'table' and response.features.garage == true,
    furniture = type(response.features) == 'table' and response.features.furniture == true
  }
  return true, cloneTable(CurrentHouse.data.featureAccess)
end

local function openMzContext(menu)
  if GetResourceState('mz_menu') ~= 'started' then
    return false
  end

  local ok, result = pcall(function()
    return exports['mz_menu']:OpenContext(menu)
  end)

  return ok == true and result ~= false
end

local function closeMzMenu()
  if GetResourceState('mz_menu') == 'started' then
    local ok = pcall(function()
      return exports['mz_menu']:CloseMenu()
    end)

    if ok then
      return true
    end

    ok = pcall(function()
      return exports['mz_menu']:CloseContext()
    end)

    if ok then
      return true
    end
  end

  if lib and type(lib.hideContext) == 'function' then
    pcall(function()
      lib.hideContext(true)
    end)
    return true
  end

  return false
end

local function getApartmentUnits(buildingCode, contextType)
  if not lib or not lib.callback or type(lib.callback.await) ~= 'function' then
    return nil, 'callback_unavailable'
  end

  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:listApartmentUnits', false, {
      buildingCode = buildingCode,
      context = contextType
    })
  end)

  if not ok or type(response) ~= 'table' then
    return nil, 'apartment_units_failed'
  end

  if response.ok ~= true then
    return nil, response.error or 'apartment_units_failed'
  end

  return response.units or {}, nil, response.building
end

local function formatCurrency(value)
  local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local updated, count = text:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
    text = updated
    if count == 0 then break end
  end
  return ('R$ %s'):format(text)
end

function MZHouses.ConfirmPropertyPurchase(houseCode, house, purchaseContext)
  houseCode = trim(houseCode)
  house = type(house) == 'table' and house or MZHouses.GetVisibleHouseByCode(houseCode)
  if houseCode == '' or type(house) ~= 'table' then return false, 'house_not_found' end
  if house.saleEnabled ~= true or tostring(house.saleMode) ~= 'direct' then return false, 'property_not_for_direct_sale' end
  if not lib or type(lib.alertDialog) ~= 'function' then return false, 'confirmation_unavailable' end

  local decision = lib.alertDialog({
    header = 'Confirmar compra',
    content = ('Comprar **%s** por **%s** usando o saldo bancario?'):format(
      tostring(house.label or houseCode), formatCurrency(house.salePrice)
    ),
    centered = true,
    cancel = true,
    labels = { confirm = 'Comprar', cancel = 'Cancelar' }
  })
  if decision ~= 'confirm' then return false, 'purchase_cancelled' end

  local ok, response = pcall(function()
    if type(purchaseContext) == 'table' and trim(purchaseContext.buildingCode) ~= '' then
      return lib.callback.await('mz_houses:server:purchaseApartmentUnit', false, {
        buildingCode = trim(purchaseContext.buildingCode),
        unitCode = houseCode
      })
    end
    return lib.callback.await('mz_houses:server:purchaseProperty', false, { houseCode = houseCode })
  end)
  if not ok or type(response) ~= 'table' then
    MZHouses.Debug('purchase_callback_transport_failed', {
      houseCode = houseCode,
      error = ok and 'invalid_response' or tostring(response)
    })
    return false, 'purchase_callback_failed'
  end
  if response.ok ~= true then
    MZHouses.Debug('purchase_rejected', { houseCode = houseCode, reason = response.reason })
    return false, tostring(response.message or 'Não foi possível concluir a compra.')
  end
  MZHouses.Notify(tostring(response.message or 'Compra concluída com sucesso.'), 'success')
  MZHouses.RefreshVisibleHouses(true)
  return true, response
end

function MZHouses.OpenApartmentIntercom(buildingCode)
  local units, err = getApartmentUnits(buildingCode, 'intercom')
  if not units then
    MZHouses.Notify(('Nao foi possivel abrir interfone: %s'):format(tostring(err)), 'error')
    return false, err
  end

  local options = {}
  for _, unit in ipairs(units) do
    local allowed = unit.allowed == true
    local canPurchase = unit.canPurchase == true and unit.saleEnabled == true and unit.saleMode == 'direct'
    local forSale = unit.saleEnabled == true
    local description = allowed and tostring(unit.label or unit.code)
      or canPurchase and ('Disponivel para compra: %s'):format(formatCurrency(unit.salePrice))
      or forSale and ('Venda administrativa: %s'):format(formatCurrency(unit.salePrice))
      or unit.occupied == true and 'Ocupada'
      or ('Bloqueado: %s'):format(tostring(unit.reason or 'sem_acesso'))
    options[#options + 1] = {
      title = ('Apartamento %s'):format(tostring(unit.unitNumber or unit.code)),
      description = description,
      icon = allowed and 'door-open' or canPurchase and 'house-circle-check' or 'lock',
      disabled = not allowed and not canPurchase,
      event = canPurchase and 'mz_houses:client:apartmentUnitPurchaseSelected' or 'mz_houses:client:apartmentUnitSelected',
      args = { code = unit.code, house = unit, buildingCode = buildingCode }
    }
  end

  if #options == 0 then
    MZHouses.Notify('Nenhuma unidade cadastrada neste predio.', 'error')
    return false, 'no_units'
  end

  if not openMzContext({
    id = ('mz_houses_apartment_intercom_%s'):format(tostring(buildingCode)),
    title = 'Interfone',
    options = options
  }) then
    MZHouses.Notify('mz_menu indisponivel para o interfone.', 'error')
    return false, 'menu_unavailable'
  end

  return true
end

function MZHouses.OpenApartmentGarage(buildingCode, action)
  local units, err = getApartmentUnits(buildingCode, 'garage')
  if not units then
    MZHouses.Notify(('Nao foi possivel abrir garagem: %s'):format(tostring(err)), 'error')
    return false, err
  end

  local options = {}
  for _, unit in ipairs(units) do
    local allowed = unit.allowed == true
    options[#options + 1] = {
      title = ('Apartamento %s'):format(tostring(unit.unitNumber or unit.code)),
      description = allowed and 'Abrir garagem desta unidade' or ('Bloqueado: %s'):format(tostring(unit.reason or 'sem_acesso')),
      icon = allowed and 'car' or 'lock',
      disabled = not allowed,
      event = 'mz_houses:client:apartmentGarageSelected',
      args = { code = unit.code, action = action or 'open' }
    }
  end

  if #options == 0 then
    MZHouses.Notify('Nenhuma unidade cadastrada neste predio.', 'error')
    return false, 'no_units'
  end

  if not openMzContext({
    id = ('mz_houses_apartment_garage_%s'):format(tostring(buildingCode)),
    title = 'Garagem do Predio',
    options = options
  }) then
    MZHouses.Notify('mz_menu indisponivel para selecionar unidade.', 'error')
    return false, 'menu_unavailable'
  end

  return true
end

RegisterNetEvent('mz_houses:client:apartmentUnitSelected', function(payload)
  payload = type(payload) == 'table' and payload or {}
  closeMzMenu()
  TriggerEvent('mz_houses:client:enterHouse', payload.code)
end)

RegisterNetEvent('mz_houses:client:apartmentUnitPurchaseSelected', function(payload)
  payload = type(payload) == 'table' and payload or {}
  closeMzMenu()
  local ok, err = MZHouses.ConfirmPropertyPurchase(payload.code, payload.house, {
    buildingCode = payload.buildingCode
  })
  if not ok and err ~= 'purchase_cancelled' then
    MZHouses.Notify(('Nao foi possivel comprar: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
  elseif ok and trim(payload.buildingCode) ~= '' then
    Wait(150)
    MZHouses.OpenApartmentIntercom(payload.buildingCode)
  end
end)

local function taxMoney(value)
  local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local updated, count = text:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
    text = updated
    if count == 0 then break end
  end
  return ('R$ %s'):format(text)
end

function MZHouses.OpenPropertyTax(houseCode)
  local code = trim(houseCode)
  if code == '' or not lib or not lib.callback then return false, 'invalid_house' end
  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:getPropertyTaxStatus', false, { houseCode = code })
  end)
  if not ok or type(response) ~= 'table' or response.ok ~= true then
    return false, type(response) == 'table' and response.error or 'tax_status_failed'
  end
  local tax = response.tax or {}
  local options = {
    {
      title = ('Status: %s'):format(tostring(tax.status or 'disabled')),
      description = ('Valor: %s | Vencimento UTC: %s | Tolerancia: %s'):format(
        taxMoney(tax.amount), tostring(tax.dueAt or '-'), tostring(tax.graceUntil or '-')),
      icon = 'landmark', disabled = true
    },
    {
      title = 'Pagar pelo banco',
      description = ('O servidor confirmara owner, valor e vencimento: %s'):format(taxMoney(tax.amount)),
      icon = 'credit-card',
      disabled = tax.enabled ~= true or tax.initialized ~= true or tax.status == 'blocked',
      onSelect = function()
        local decision = lib.alertDialog({
          header = 'Confirmar pagamento do IPTU',
          content = ('Pagar %s referente a %s? O valor sera relido no servidor.'):format(
            taxMoney(tax.amount), tostring(tax.label or code)),
          centered = true, cancel = true
        })
        if decision ~= 'confirm' then return end
        local payOk, payResponse = pcall(function()
          return lib.callback.await('mz_houses:server:payPropertyTax', false, { houseCode = code })
        end)
        if not payOk or type(payResponse) ~= 'table' then
          return MZHouses.Notify('Falha de comunicacao ao pagar IPTU.', 'error')
        end
        MZHouses.Notify(payResponse.message or (payResponse.ok and 'IPTU pago.' or 'Pagamento recusado.'), payResponse.ok and 'success' or 'error')
        if payResponse.ok then SetTimeout(150, function() MZHouses.OpenPropertyTax(code) end) end
      end
    }
  }
  for _, payment in ipairs(tax.payments or {}) do
    options[#options + 1] = {
      title = ('Pagamento #%s — %s'):format(tostring(payment.id or '?'), tostring(payment.status or '?')),
      description = ('%s | vencimento=%s | pago=%s'):format(
        taxMoney(payment.amount), tostring(payment.due_at or '-'), tostring(payment.paid_at or '-')),
      icon = 'receipt-text'
    }
  end
  openMzContext({ id = 'mz_houses_tax_' .. code, title = 'IPTU - ' .. tostring(tax.label or code), options = options })
  return true
end

function MZHouses.OpenPropertyTaxes()
  if not lib or not lib.callback then return false, 'callback_unavailable' end
  local ok, response = pcall(function()
    return lib.callback.await('mz_houses:server:listMyPropertyTaxes', false)
  end)
  if not ok or type(response) ~= 'table' or response.ok ~= true then
    return false, type(response) == 'table' and response.error or 'tax_list_failed'
  end
  local options = {}
  for _, tax in ipairs(response.taxes or {}) do
    options[#options + 1] = {
      title = tostring(tax.label or tax.houseCode),
      description = ('%s | %s | vence=%s'):format(
        taxMoney(tax.amount), tostring(tax.status or 'disabled'), tostring(tax.dueAt or '-')),
      icon = (tax.status == 'overdue' or tax.status == 'blocked') and 'triangle-alert' or 'landmark',
      onSelect = function() MZHouses.OpenPropertyTax(tax.houseCode) end
    }
  end
  if #options == 0 then options[1] = { title = 'Nenhum IPTU ativo', disabled = true } end
  openMzContext({ id = 'mz_houses_my_taxes', title = 'Meus IPTUs', options = options })
  return true
end

RegisterCommand(tostring(((MZHousesConfig or {}).Tax or {}).command or 'iptu'), function()
  local ok, err = MZHouses.OpenPropertyTaxes()
  if not ok then MZHouses.Notify(('Nao foi possivel consultar IPTU: %s'):format(tostring(err)), 'error') end
end, false)

CreateThread(function()
  Wait(5000)
  TriggerServerEvent('mz_houses:server:taxPlayerReady')
end)

RegisterNetEvent('mz_houses:client:apartmentGarageSelected', function(payload)
  payload = type(payload) == 'table' and payload or {}
  closeMzMenu()
  local ok, err = requestOpenHouseGarage(payload.code, payload.action or 'open')
  if not ok then
    MZHouses.Notify(('Nao foi possivel abrir a garagem: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
  end
end)

function MZHouses.EnterHouse(houseCode, options)
  options = type(options) == 'table' and options or {}
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

  if options.skipPurchase ~= true and house.saleEnabled == true and tostring(house.saleMode) == 'direct' then
    return MZHouses.ConfirmPropertyPurchase(code, house)
  end

  if GetResourceState('mz_interiors') ~= 'started' then
    return false, 'interiors_unavailable'
  end

  if tostring(house.subtype or '') == 'apartment_building' then
    return MZHouses.OpenApartmentIntercom(code)
  end

  closeMzMenu()

  if tostring(house.type or 'shell') ~= 'shell' then
    return false, 'unsupported_house_type'
  end

  local shellName = trim(house.shell)
  if shellName == '' then
    return false, 'missing_shell'
  end

  local entryContext = nil
  local entrance = asVector4(house.entrance)
  if tostring(house.subtype or '') == 'apartment_unit' or not entrance then
    local context, contextErr = requestEntryContext(code)
    if not context then
      return false, contextErr or 'invalid_entrance'
    end

    entryContext = context
    if type(context.property) == 'table' then
      house = context.property
    end
    entrance = asVector4(context.entrance)
  end

  if not entrance then
    return false, tostring(house.subtype or '') == 'apartment_unit' and 'invalid_building_entrance' or 'invalid_entrance'
  end

  local allowed, accessOrErr = requestHouseAccess(code)
  if not allowed then
    return false, accessOrErr or 'no_house_access'
  end

  MZHouses.Notify(('Entrando: %s'):format(tostring(house.label or code)), 'inform')

  local authorizedEntry = type(accessOrErr) == 'table' and type(accessOrErr.entrySpawn) == 'table'
    and accessOrErr.entrySpawn or { mode = 'default' }
  local customEntryOffset = authorizedEntry.mode == 'custom' and asVector3(authorizedEntry.coords) or nil

  local callOk, ok, resultOrErr = pcall(function()
    return exports['mz_interiors']:EnterShell(shellName, entrance, {
      instanceId = ('house:%s'):format(code),
      spawnBase = MZHousesConfig.InteriorSpawnBase,
      --heading = entrance.w,
      entryOffset = customEntryOffset,
      entryHeading = customEntryOffset and (tonumber(authorizedEntry.heading) or 0.0) or nil,
      metadata = {
        houseCode = code,
        houseLabel = house.label or code,
        buildingCode = entryContext and entryContext.building and entryContext.building.code or nil,
        unitNumber = house.unitNumber,
        status = house.status or 'debug',
        accessReason = type(accessOrErr) == 'table' and accessOrErr.reason or nil
      }
    })
  end)

  if not callOk then
    resultOrErr = ok
    ok = false
  end

  if not ok then
    TriggerServerEvent('mz_houses:server:abortEnterHouse')
    MZHouses.Debug('enter_house_failed', {
      house = code,
      shell = shellName,
      error = resultOrErr
    })
    return false, resultOrErr or 'enter_failed'
  end

  local confirmed = false
  if lib and lib.callback and type(lib.callback.await) == 'function' then
    local confirmOk, confirmResponse = pcall(function()
      return lib.callback.await('mz_houses:server:confirmEnterHouse', false, { houseCode = code })
    end)
    confirmed = confirmOk and type(confirmResponse) == 'table' and confirmResponse.ok == true
  end
  if not confirmed then
    pcall(function() exports['mz_interiors']:DestroyCurrentInterior({ teleportBack = true, reason = 'house_confirm_failed' }) end)
    TriggerServerEvent('mz_houses:server:abortEnterHouse')
    return false, 'entry_confirmation_failed'
  end

  CurrentHouse.inside = true
  CurrentHouse.code = code
  CurrentHouse.data = cloneTable(house)
  MZHouses.RefreshCurrentFeatureAccess()

  local effectiveExit = MZHouses.GetEffectiveHouseExit(CurrentHouse.data)
  if type(effectiveExit) ~= 'table' or not asVector3(effectiveExit.coords) then
    local interior = getCurrentInterior()
    local exitCoords = asVector4(interior and interior.exitCoords)
    if exitCoords then
      CurrentHouse.data.interior = type(CurrentHouse.data.interior) == 'table' and CurrentHouse.data.interior or {}
      CurrentHouse.data.interior.exit = {
        enabled = true,
        label = 'Sair da casa',
        coords = vector3(exitCoords.x, exitCoords.y, exitCoords.z),
        heading = exitCoords.w,
        relative = false
      }
      MZHouses.Notify(('Shell sem InteriorDefaults para saida: %s. Use /mhouse_admin para ajustar pontos internos.'):format(shellName), 'warning')
    end
  end

  MZHouses.Debug('entered_house', {
    house = code,
    shell = shellName,
    entrySpawnMode = customEntryOffset and 'custom' or 'default'
  })

  MZHouses.Notify(('Voce entrou em %s.'):format(tostring(house.label or code)), 'success')
  return true, MZHouses.GetCurrentHouse()
end

local function resetCurrentHouse()
  CurrentHouse.inside = false
  CurrentHouse.code = nil
  CurrentHouse.data = nil
end

local function releaseHouseSession(useCallback)
  local released = false
  if useCallback ~= false and lib and lib.callback and type(lib.callback.await) == 'function' then
    local ok, response = pcall(function()
      return lib.callback.await('mz_houses:server:leaveHouse', false, {})
    end)
    released = ok and type(response) == 'table' and response.ok == true
  end

  if not released then
    TriggerServerEvent('mz_houses:server:abortEnterHouse')
  end
end

local function currentInteriorHouseCode()
  local interior = getCurrentInterior()
  local metadata = type(interior) == 'table' and type(interior.metadata) == 'table' and interior.metadata or nil
  local code = metadata and trim(metadata.houseCode) or ''
  return code ~= '' and code or nil
end

local function cleanupHouse(options)
  options = type(options) == 'table' and options or {}
  local interiorHouseCode = currentInteriorHouseCode()
  local belongsToHouse = CurrentHouse.inside == true or interiorHouseCode ~= nil
  if not belongsToHouse and options.force ~= true then
    return false, 'not_inside'
  end

  local shellOk, shellErr = true, nil
  if options.skipInterior ~= true and GetResourceState('mz_interiors') == 'started' then
    local callOk, ok, err = pcall(function()
      if options.destroy == true then
        return exports['mz_interiors']:DestroyCurrentInterior({
          teleportBack = options.teleportBack ~= false,
          reason = options.reason or 'house_cleanup'
        })
      end
      return exports['mz_interiors']:ExitShell()
    end)
    shellOk = callOk and ok == true
    shellErr = callOk and err or ok
  end

  releaseHouseSession(options.useCallback)
  resetCurrentHouse()

  if not shellOk then
    return false, shellErr or 'exit_failed'
  end
  return true
end

function MZHouses.ExitHouse()
  local ok, err = cleanupHouse({ reason = 'house_exit' })
  if not ok then return false, err end

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

  closeMzMenu()

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

  closeMzMenu()

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

  local house = MZHouses.GetHouse(code)
  if type(house) == 'table' and tostring(house.subtype or '') == 'apartment_building' then
    return MZHouses.OpenApartmentGarage(code, action or 'open')
  end

  closeMzMenu()

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

  TriggerServerEvent('mz_houses:server:setAdminGaragePoint', {
    code = code,
    kind = kind,
    point = {
      x = coords.x,
      y = coords.y,
      z = coords.z,
      w = heading,
      heading = heading
    }
  })
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

      if stashConfig.enabled == true and CurrentHouse.inside == true and type(CurrentHouse.data) == 'table'
        and (type(CurrentHouse.data.featureAccess) ~= 'table' or CurrentHouse.data.featureAccess.stash == true) then
        local houseStash = MZHouses.GetEffectiveHouseStash(CurrentHouse.data) or {}
        if houseStash.enabled == true then
          local coords = resolveInteriorPointCoords(houseStash)
          if coords then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local markerDistance = tonumber(stashConfig.markerDistance) or 10.0
            local interactDistance = tonumber(stashConfig.interactionDistance) or 2.0
            local interaction = MZHousesConfig.Interaction or {}
            local key = tonumber(interaction.enterKey or interaction.key) or 38
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

      if wardrobeConfig.enabled == true and CurrentHouse.inside == true and type(CurrentHouse.data) == 'table'
        and (type(CurrentHouse.data.featureAccess) ~= 'table' or CurrentHouse.data.featureAccess.wardrobe == true) then
        local houseWardrobe = MZHouses.GetEffectiveHouseWardrobe(CurrentHouse.data) or {}
        if houseWardrobe.enabled == true then
          local coords = resolveInteriorPointCoords(houseWardrobe)
          if coords then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local markerDistance = tonumber(wardrobeConfig.markerDistance) or 10.0
            local interactDistance = tonumber(wardrobeConfig.interactionDistance) or 2.0
            local interaction = MZHousesConfig.Interaction or {}
            local key = tonumber(interaction.enterKey or interaction.key) or 38
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
            local interaction = MZHousesConfig.Interaction or {}
            local key = tonumber(interaction.enterKey or interaction.key) or 38
            local doorKey = tonumber(interaction.doorKey) or 47
            local doorDistance = tonumber(interaction.distance) or 2.0
            local distance = #(playerCoords - coords)

            if distance <= markerDistance then
              waitMs = 0
              drawExitMarker(coords)

              local onFoot = not IsPedInAnyVehicle(ped, false)
              if onFoot and distance <= doorDistance then
                MZHouses.GetDoorContext(CurrentHouse.code, false)
              end
              local door = MZHouses.GetDoorPresentation(CurrentHouse.code, CurrentHouse.data)
              local canUseDoorKey = onFoot and distance <= doorDistance and door.canControl == true
                and (door.state == 'locked' or door.state == 'unlocked')

              if distance <= interactDistance then
                local doorText = ('Porta: %s'):format(door.stateLabel)
                if canUseDoorKey and door.actionLabel then
                  doorText = ('%s | [%s] %s'):format(
                    doorText,
                    tostring((MZHousesConfig.Interaction or {}).doorKeyLabel or 'G'),
                    door.actionLabel
                  )
                end
                local textConfig = exitConfig.text or {}
                if textConfig.enabled ~= false then
                  drawText3d(
                    vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.4)),
                    ('[E] %s | %s'):format(tostring(houseExit.label or 'Sair da casa'), doorText),
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

              if canUseDoorKey then
                DisableControlAction(0, doorKey, true)
                if IsDisabledControlJustReleased(0, doorKey) then
                  MZHouses.ToggleDoor(CurrentHouse.code)
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
            local interaction = MZHousesConfig.Interaction or {}
            local key = tonumber(interaction.enterKey or interaction.key) or 38

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

local function registerAdminEditCommands()
  local admin = MZHousesConfig.Admin or {}
  local commands = MZHousesConfig.Commands or {}

  RegisterCommand(tostring(admin.create or 'mhouse_create'), function(_, args)
    args = type(args) == 'table' and args or {}
    local code = trim(args[1])
    local labelParts = {}
    for index = 2, #args do
      labelParts[#labelParts + 1] = tostring(args[index])
    end
    local label = table.concat(labelParts, ' ')

    if code == '' or trim(label) == '' then
      MZHouses.Notify('Uso: /mhouse_create codigo Label do Imovel', 'error')
      return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    TriggerServerEvent('mz_houses:server:createAdminProperty', {
      code = code,
      label = label,
      entrance = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = heading,
        heading = heading
      }
    })
  end, false)

  RegisterCommand(tostring(admin.setEntrance or 'mhouse_setentrance'), function(_, args)
    args = type(args) == 'table' and args or {}
    local code = trim(args[1])
    if code == '' then
      MZHouses.Notify('Uso: /mhouse_setentrance codigo', 'error')
      return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    TriggerServerEvent('mz_houses:server:setAdminEntrance', {
      code = code,
      entrance = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = heading,
        heading = heading
      }
    })
  end, false)

  if commands.enabled ~= true then
    RegisterCommand(tostring(commands.garageEntryHere or 'mhouse_garage_entry_here'), function(_, args)
      printGaragePointHere('entry', args and args[1])
    end, false)

    RegisterCommand(tostring(commands.garageSpawnHere or 'mhouse_garage_spawn_here'), function(_, args)
      printGaragePointHere('spawn', args and args[1])
    end, false)

    RegisterCommand(tostring(commands.garageStoreHere or 'mhouse_garage_store_here'), function(_, args)
      printGaragePointHere('store', args and args[1])
    end, false)
  end
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
  TriggerServerEvent('mz_houses:server:taxPlayerReady')
end)

RegisterNetEvent('mz_houses:client:taxNotice', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local status = tostring(payload.status or 'due')
  local message
  if payload.nearDue == true then
    message = ('IPTU de %s vence em breve: %s, vencimento %s. Use /%s.'):format(
      tostring(payload.label or payload.houseCode), taxMoney(payload.amount), tostring(payload.dueAt or '-'),
      tostring(((MZHousesConfig or {}).Tax or {}).command or 'iptu'))
  else
    message = ('IPTU de %s: status %s, valor %s, vencimento %s. Use /%s.'):format(
      tostring(payload.label or payload.houseCode), status, taxMoney(payload.amount),
      tostring(payload.dueAt or '-'), tostring(((MZHousesConfig or {}).Tax or {}).command or 'iptu'))
  end
  MZHouses.Notify(message, (status == 'overdue' or status == 'blocked') and 'error' or 'warning')
end)

RegisterNetEvent('mz_houses:client:enterHouse', function(houseCode)
  local ok, err = MZHouses.EnterHouse(houseCode)
  if not ok then
    MZHouses.Notify(('Nao foi possivel entrar: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
  end
end)

function MZHouses.OpenDoorMenu(houseCode)
  local code = trim(houseCode)
  local context, contextErr = MZHouses.GetDoorContext(code, true)
  if not context then return false, contextErr or 'door_context_failed' end
  local stateLabel = MZHouses.DoorStateLabel(context.state)
  local options = {
    { title = 'Entrar', description = ('Porta: %s'):format(stateLabel), icon = 'door-open', onSelect = function()
      TriggerEvent('mz_houses:client:enterHouse', code)
    end }
  }
  if context.canControl == true and context.state ~= 'blocked' then
    local actionLabel = MZHouses.DoorActionLabel(context.state)
    options[#options + 1] = {
      title = actionLabel, icon = context.state == 'unlocked' and 'lock' or 'lock-open',
      onSelect = function()
        MZHouses.ToggleDoor(code)
      end
    }
  end
  openMzContext({ id = 'mz_houses_door_' .. code, title = ('Entrada — Porta %s'):format(stateLabel:lower()), options = options })
  return true
end

RegisterNetEvent('mz_houses:client:doorMenu', function(payload)
  local code = type(payload) == 'table' and (payload.code or payload[1]) or payload
  local ok, err = MZHouses.OpenDoorMenu(code)
  if not ok then MZHouses.Notify(friendlyDoorError(err), 'error') end
end)

RegisterNetEvent('mz_houses:client:doorStateChanged', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode)
  if code == '' then return end
  applyDoorContext(code, payload.state, nil, 0)
  CreateThread(function()
    MZHouses.RefreshVisibleHouses(true)
    local house = findVisibleHouse(code)
    if type(house) == 'table' then house.doorState = normalizeDoorState(payload.state) end
    TriggerEvent('mz_houses:client:doorVisibilityRefreshed', {
      houseCode = code,
      house = house or false
    })
  end)
end)

RegisterNetEvent('mz_houses:client:featurePolicyChanged', function(payload)
  payload = type(payload) == 'table' and payload or {}
  if CurrentHouse.inside ~= true or trim(CurrentHouse.code) ~= trim(payload.houseCode) then return end
  CreateThread(function()
    MZHouses.RefreshCurrentFeatureAccess()
  end)
end)

RegisterNetEvent('mz_houses:client:exitHouse', function()
  local ok, err = MZHouses.ExitHouse()
  if not ok then
    MZHouses.Notify(('Nao foi possivel sair: %s'):format(tostring(err or 'erro_desconhecido')), 'error')
  end
end)

RegisterNetEvent('mz_houses:client:forceExit', function(reason)
  if CurrentHouse.inside == true or currentInteriorHouseCode() ~= nil then
    MZHouses.Notify(('Acesso a propriedade atualizado: %s'):format(tostring(reason or 'alterado')), 'warning')
    cleanupHouse({ reason = reason or 'force_exit' })
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

exports('OpenPropertyTax', function(houseCode)
  if trim(houseCode) ~= '' then return MZHouses.OpenPropertyTax(houseCode) end
  return MZHouses.OpenPropertyTaxes()
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    cleanupHouse({
      force = CurrentHouse.inside == true,
      destroy = true,
      useCallback = false,
      reason = 'houses_resource_stop'
    })
    return
  end

  if resource == 'mz_interiors' and CurrentHouse.inside == true then
    cleanupHouse({ force = true, skipInterior = true, useCallback = false, reason = 'interiors_resource_stop' })
  end
end)

AddEventHandler('baseevents:onPlayerDied', function()
  if CurrentHouse.inside == true then MZHouses.ExitHouse() end
end)

AddEventHandler('baseevents:onPlayerKilled', function()
  if CurrentHouse.inside == true then MZHouses.ExitHouse() end
end)

CreateThread(function()
  local handledDeath = false
  while true do
    Wait(CurrentHouse.inside == true and 500 or 1500)
    if CurrentHouse.inside == true and IsEntityDead(PlayerPedId()) then
      if not handledDeath then
        handledDeath = true
        MZHouses.ExitHouse()
      end
    else
      handledDeath = false
    end
  end
end)

MZHouses.AsVector3 = asVector3
MZHouses.AsVector4 = asVector4

registerDebugCommands()
registerAdminEditCommands()
runStashMarkerLoop()
runWardrobeMarkerLoop()
runExitMarkerLoop()
runGarageMarkerLoop()
