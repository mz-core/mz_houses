MZHousesService = MZHousesService or {}

local RuntimeAccess = {}
local RuntimeHouses = {}
local DatabaseActive = false

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizeCode(value)
  local code = trim(value)
  if code == '' then return nil end
  return code
end

local function normalizeCitizenId(value)
  local citizenid = trim(value)
  if citizenid == '' then return nil end
  return citizenid
end

local function clampInteger(value, fallback, minValue, maxValue)
  value = tonumber(value) or tonumber(fallback) or 0
  value = math.floor(value)
  minValue = tonumber(minValue) or 1
  maxValue = tonumber(maxValue) or value

  if value < minValue then value = minValue end
  if value > maxValue then value = maxValue end

  return value
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

local function vector3Payload(value)
  local coords = asVector3(value)
  if not coords then return nil end

  return {
    x = coords.x + 0.0,
    y = coords.y + 0.0,
    z = coords.z + 0.0
  }
end

local function vector4Payload(value)
  local coords = asVector4(value)
  if not coords then return nil end

  return {
    x = coords.x + 0.0,
    y = coords.y + 0.0,
    z = coords.z + 0.0,
    w = coords.w + 0.0
  }
end

local function configuredDatabaseEnabled()
  return MZHousesConfig
    and MZHousesConfig.Database
    and MZHousesConfig.Database.enabled == true
end

local function databaseEnabled()
  return DatabaseActive == true
end

local function cloneKeys(keys)
  local out = {}
  if type(keys) ~= 'table' then return out end

  for key, value in pairs(keys) do
    if type(key) == 'number' then
      local citizenid = normalizeCitizenId(value)
      if citizenid then out[citizenid] = true end
    elseif value == true then
      local citizenid = normalizeCitizenId(key)
      if citizenid then out[citizenid] = true end
    end
  end

  return out
end

local function getConfigHouse(code)
  code = normalizeCode(code)
  if not code then return nil, 'invalid_house' end

  local house = (MZHousesConfig.Houses or {})[code]
  if type(house) ~= 'table' then
    return nil, 'house_not_found'
  end

  return house, nil, code
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

local function getHouseInteriorDefaults(house)
  if type(house) ~= 'table' then
    return nil
  end

  local shell = trim(house.shell)
  if shell == '' then
    return nil
  end

  return (MZHousesConfig.InteriorDefaults or {})[shell]
end

local function getEffectiveHousePoint(house, pointName)
  if type(house) ~= 'table' then
    return nil
  end

  local defaults = getHouseInteriorDefaults(house)
  local point = shallowMerge(defaults and defaults[pointName] or nil, house[pointName])
  if next(point) == nil then
    return nil
  end

  return point
end

local function accessFromConfigHouse(house)
  local access = type(house.access) == 'table' and house.access or {}
  return {
    public = access.public == true,
    owner = normalizeCitizenId(access.owner),
    keys = cloneKeys(access.keys),
    enabled = house.enabled ~= false,
    status = trim(house.status) ~= '' and trim(house.status) or 'active'
  }
end

local function debugLog(message, data)
  if MZHousesConfig.Debug ~= true then return end
  local suffix = data ~= nil and (' | %s'):format(json.encode(data)) or ''
  print(('[mz_houses][service] %s%s'):format(tostring(message), suffix))
end

function MZHousesService.getPlayerCitizenId(src)
  src = tonumber(src)
  if not src or src <= 0 then
    return nil, 'invalid_source'
  end

  if GetResourceState('mz_core') ~= 'started' then
    return nil, 'core_unavailable'
  end

  local ok, player = pcall(function()
    return exports['mz_core']:GetPlayer(src)
  end)

  if not ok or type(player) ~= 'table' then
    return nil, 'player_not_loaded'
  end

  local citizenid = normalizeCitizenId(player.citizenid)
  if not citizenid then
    return nil, 'citizenid_not_found'
  end

  return citizenid
end

local function loadFromConfig()
  RuntimeAccess = {}
  RuntimeHouses = {}

  for code, house in pairs(MZHousesConfig.Houses or {}) do
    RuntimeHouses[code] = house
    RuntimeAccess[code] = accessFromConfigHouse(house)
  end

  return true
end

local function syncConfigToDatabase()
  local dbConfig = MZHousesConfig.Database or {}
  if dbConfig.syncConfigOnStart ~= true then
    return true
  end

  for code, house in pairs(MZHousesConfig.Houses or {}) do
    local ok, err = MZHousesRepository.upsertHouseFromConfig(code, house)
    if not ok then
      return false, err
    end
  end

  return true
end

local function loadFromDatabase()
  RuntimeAccess = {}
  RuntimeHouses = {}

  local houses = MZHousesRepository.listHouses()
  for _, row in ipairs(houses) do
    local code = normalizeCode(row.code)
    if code then
      RuntimeHouses[code] = row
      RuntimeAccess[code] = {
        public = row.public == true,
        owner = normalizeCitizenId(row.owner_citizenid),
        keys = {},
        enabled = row.enabled == true,
        status = trim(row.status) ~= '' and trim(row.status) or 'active'
      }

      local keys = MZHousesRepository.listKeys(code)
      for _, keyRow in ipairs(keys) do
        local citizenid = normalizeCitizenId(keyRow.citizenid)
        if citizenid then
          RuntimeAccess[code].keys[citizenid] = true
        end
      end
    end
  end

  return true
end

function MZHousesService.bootstrap()
  DatabaseActive = false

  if not configuredDatabaseEnabled() then
    debugLog('boot config runtime')
    return loadFromConfig()
  end

  local prepared, prepareErr = MZHousesPrepare.run()
  if not prepared then
    print(('[mz_houses] database prepare failed; using config runtime: %s'):format(tostring(prepareErr)))
    return loadFromConfig()
  end

  DatabaseActive = true

  local synced, syncErr = syncConfigToDatabase()
  if not synced then
    DatabaseActive = false
    print(('[mz_houses] database sync failed; using config runtime: %s'):format(tostring(syncErr)))
    return loadFromConfig()
  end

  loadFromDatabase()
  debugLog('boot database runtime', {
    houses = MZHousesService.countHouses()
  })
  return true
end

function MZHousesService.reload()
  if configuredDatabaseEnabled() then
    if not DatabaseActive then
      local prepared, prepareErr = MZHousesPrepare.run()
      if not prepared then
        return false, prepareErr
      end
      DatabaseActive = true
    end

    local synced, syncErr = syncConfigToDatabase()
    if not synced then
      return false, syncErr
    end
    return loadFromDatabase()
  end

  return loadFromConfig()
end

function MZHousesService.countHouses()
  local total = 0
  for _ in pairs(RuntimeHouses) do
    total = total + 1
  end
  return total
end

function MZHousesService.getAccessState(houseCode)
  local code = normalizeCode(houseCode)
  if not code then return nil, 'invalid_house' end

  local access = RuntimeAccess[code]
  if access then
    return access, nil, code, RuntimeHouses[code]
  end

  if not databaseEnabled() then
    local house, err = getConfigHouse(code)
    if not house then return nil, err end
    RuntimeHouses[code] = house
    RuntimeAccess[code] = accessFromConfigHouse(house)
    return RuntimeAccess[code], nil, code, house
  end

  local row = MZHousesRepository.getHouseByCode(code)
  if not row then return nil, 'house_not_found' end

  RuntimeHouses[code] = row
  RuntimeAccess[code] = {
    public = row.public == true,
    owner = normalizeCitizenId(row.owner_citizenid),
    keys = {},
    enabled = row.enabled == true,
    status = trim(row.status) ~= '' and trim(row.status) or 'active'
  }

  for _, keyRow in ipairs(MZHousesRepository.listKeys(code)) do
    local citizenid = normalizeCitizenId(keyRow.citizenid)
    if citizenid then
      RuntimeAccess[code].keys[citizenid] = true
    end
  end

  return RuntimeAccess[code], nil, code, row
end

function MZHousesService.canEnterHouse(source, houseCode, isAdmin)
  local access, err, code = MZHousesService.getAccessState(houseCode)
  if not access then
    return false, err or 'house_not_found'
  end

  if access.enabled == false then
    return false, 'house_disabled'
  end

  if access.status == 'inactive' or access.status == 'disabled' then
    return false, 'house_inactive'
  end

  if access.public == true then
    return true, { reason = 'public', houseCode = code }
  end

  if isAdmin == true then
    return true, { reason = 'admin', houseCode = code }
  end

  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then
    return false, citizenErr or 'player_not_loaded'
  end

  if access.owner and access.owner == citizenid then
    return true, { reason = 'owner', houseCode = code, citizenid = citizenid }
  end

  if access.keys and access.keys[citizenid] == true then
    return true, { reason = 'key', houseCode = code, citizenid = citizenid }
  end

  MZHousesService.log('house.enter.denied', code, source, citizenid, {
    reason = 'no_house_access'
  })

  return false, 'no_house_access'
end

function MZHousesService.getHouseStashConfig(houseCode)
  local code = normalizeCode(houseCode)
  if not code then return nil, 'invalid_house' end

  local configuredHouse = (MZHousesConfig.Houses or {})[code]
  if type(configuredHouse) ~= 'table' then
    return nil, 'house_not_found'
  end

  local stashConfig = MZHousesConfig.Stash or {}
  if stashConfig.enabled ~= true then
    return nil, 'stash_disabled'
  end

  local houseStash = getEffectiveHousePoint(configuredHouse, 'stash') or {}
  if houseStash.enabled ~= true then
    return nil, 'stash_disabled'
  end

  local prefix = trim(stashConfig.idPrefix)
  if prefix == '' then prefix = 'house:' end
  local slots = clampInteger(houseStash.slots, stashConfig.defaultSlots or 50, 1, stashConfig.maxSlots or 200)
  local weight = clampInteger(houseStash.weight, stashConfig.defaultWeight or 100000, 1, stashConfig.maxWeight or 1000000)

  return {
    id = ('%s%s'):format(prefix, code),
    label = trim(houseStash.label) ~= '' and trim(houseStash.label) or ('Bau - ' .. code),
    slots = slots,
    weight = weight
  }, nil, code
end

function MZHousesService.openHouseStash(source, houseCode, isAdmin)
  local stashConfig = MZHousesConfig.Stash or {}
  if stashConfig.enabled ~= true then
    return false, 'stash_disabled'
  end

  local actorCitizenId = nil
  if tonumber(source) and tonumber(source) > 0 then
    actorCitizenId = MZHousesService.getPlayerCitizenId(source)
  end

  local accessAllowed, accessResult = MZHousesService.canEnterHouse(
    source,
    houseCode,
    stashConfig.allowAdminDebug == true and isAdmin == true
  )

  if not accessAllowed then
    MZHousesService.log('house.stash.open.denied', houseCode, source, actorCitizenId, {
      reason = accessResult or 'no_house_access'
    })
    return false, accessResult or 'no_house_access'
  end

  local stash, stashErr, code = MZHousesService.getHouseStashConfig(houseCode)
  if not stash then
    MZHousesService.log('house.stash.open.failed', houseCode, source, nil, {
      reason = stashErr or 'stash_disabled'
    })
    return false, stashErr or 'stash_disabled'
  end

  if GetResourceState('mz_inventory') ~= 'started' or GetResourceState('mz_core') ~= 'started' then
    MZHousesService.log('house.stash.open.failed', code, source, nil, {
      stashId = stash.id,
      reason = 'inventory_resource_unavailable'
    })
    return false, 'inventory_stash_not_available'
  end

  local grantCallOk, grantResultOk, grantResult = pcall(function()
    return exports['mz_core']:CreateHouseStashAccessGrant(source, {
      houseCode = code,
      stashId = stash.id,
      label = stash.label,
      slots = stash.slots,
      weight = stash.weight
    })
  end)

  if not grantCallOk then
    MZHousesService.log('house.stash.open.failed', code, source, nil, {
      stashId = stash.id,
      reason = 'inventory_grant_failed',
      detail = tostring(grantResultOk)
    })
    return false, 'stash_open_failed'
  end

  if grantResultOk ~= true or type(grantResult) ~= 'table' then
    MZHousesService.log('house.stash.open.failed', code, source, nil, {
      stashId = stash.id,
      reason = tostring(grantResult or 'inventory_grant_denied')
    })
    return false, grantResult or 'stash_open_failed'
  end

  MZHousesService.log('house.stash.open', code, source, nil, {
    stashId = stash.id
  })

  return true, {
    houseCode = code,
    stashId = stash.id,
    label = stash.label,
    slots = stash.slots,
    weight = stash.weight,
    inventoryTarget = grantResult
  }
end

function MZHousesService.getHouseWardrobeConfig(houseCode)
  local code = normalizeCode(houseCode)
  if not code then return nil, 'invalid_house' end

  local configuredHouse = (MZHousesConfig.Houses or {})[code]
  if type(configuredHouse) ~= 'table' then
    return nil, 'house_not_found'
  end

  local wardrobeConfig = MZHousesConfig.Wardrobe or {}
  if wardrobeConfig.enabled ~= true then
    return nil, 'wardrobe_disabled'
  end

  local houseWardrobe = getEffectiveHousePoint(configuredHouse, 'wardrobe') or {}
  if houseWardrobe.enabled ~= true then
    return nil, 'wardrobe_disabled'
  end

  return {
    label = trim(houseWardrobe.label) ~= '' and trim(houseWardrobe.label) or 'Guarda-roupa',
    shopId = trim(houseWardrobe.shopId) ~= '' and trim(houseWardrobe.shopId) or trim(wardrobeConfig.shopId),
    resource = trim(wardrobeConfig.resource) ~= '' and trim(wardrobeConfig.resource) or 'mz_clothing'
  }, nil, code
end

local function openHouseWardrobeForPlayer(source, houseCode, wardrobe)
  local resource = trim(wardrobe and wardrobe.resource)
  if resource == '' then
    resource = 'mz_clothing'
  end

  if resource ~= 'mz_clothing' then
    return false, 'wardrobe_not_available'
  end

  if GetResourceState('mz_clothing') ~= 'started' then
    return false, 'wardrobe_not_available'
  end

  local shopId = trim(wardrobe and wardrobe.shopId)
  if shopId == '' then
    shopId = 'clothing_1'
  end

  TriggerClientEvent('mz_clothing:client:openShop', source, shopId)
  return true, {
    resource = resource,
    shopId = shopId,
    houseCode = houseCode
  }
end

function MZHousesService.openHouseWardrobe(source, houseCode, isAdmin)
  local wardrobeConfig = MZHousesConfig.Wardrobe or {}
  if wardrobeConfig.enabled ~= true then
    return false, 'wardrobe_disabled'
  end

  local actorCitizenId = nil
  if tonumber(source) and tonumber(source) > 0 then
    actorCitizenId = MZHousesService.getPlayerCitizenId(source)
  end

  local accessAllowed, accessResult = MZHousesService.canEnterHouse(
    source,
    houseCode,
    wardrobeConfig.allowAdminDebug == true and isAdmin == true
  )

  if not accessAllowed then
    MZHousesService.log('house.wardrobe.open.denied', houseCode, source, actorCitizenId, {
      reason = accessResult or 'no_house_access'
    })
    return false, accessResult or 'no_house_access'
  end

  local wardrobe, wardrobeErr, code = MZHousesService.getHouseWardrobeConfig(houseCode)
  if not wardrobe then
    MZHousesService.log('house.wardrobe.open.failed', houseCode, source, actorCitizenId, {
      reason = wardrobeErr or 'wardrobe_disabled'
    })
    return false, wardrobeErr or 'wardrobe_disabled'
  end

  local opened, result = openHouseWardrobeForPlayer(source, code, wardrobe)
  if not opened then
    MZHousesService.log('house.wardrobe.open.failed', code, source, actorCitizenId, {
      reason = result or 'wardrobe_open_failed'
    })
    return false, result or 'wardrobe_open_failed'
  end

  MZHousesService.log('house.wardrobe.open', code, source, actorCitizenId, {
    resource = result.resource,
    shopId = result.shopId
  })

  return true, {
    houseCode = code,
    label = wardrobe.label,
    resource = result.resource,
    shopId = result.shopId
  }
end

function MZHousesService.getHouseGarageConfig(houseCode)
  local code = normalizeCode(houseCode)
  if not code then return nil, 'invalid_house' end

  local configuredHouse = (MZHousesConfig.Houses or {})[code]
  if type(configuredHouse) ~= 'table' then
    return nil, 'house_not_found'
  end

  local garageConfig = MZHousesConfig.Garage or {}
  if garageConfig.enabled ~= true then
    return nil, 'garage_disabled'
  end

  local houseGarage = type(configuredHouse.garage) == 'table' and configuredHouse.garage or {}
  if houseGarage.enabled ~= true then
    return nil, 'garage_disabled'
  end

  local entry = asVector3(houseGarage.entry)
  local spawn = asVector4(houseGarage.spawn)
  local store = asVector3(houseGarage.store)

  if not entry then return nil, 'invalid_garage_entry' end
  if not spawn then return nil, 'invalid_garage_spawn' end
  if not store then return nil, 'invalid_garage_store' end

  return {
    houseCode = code,
    label = trim(houseGarage.label) ~= '' and trim(houseGarage.label) or ('Garagem - ' .. tostring(configuredHouse.label or code)),
    garageId = trim(houseGarage.garageId or houseGarage.garage_id) ~= '' and trim(houseGarage.garageId or houseGarage.garage_id) or ('house:' .. code),
    garageMode = trim(houseGarage.mode or garageConfig.defaultMode) == 'shared' and 'shared' or 'private',
    slots = clampInteger(houseGarage.slots, garageConfig.defaultSlots or 2, 1, garageConfig.maxSlots or 20),
    entry = entry,
    spawn = spawn,
    store = store,
    storeRadius = tonumber(houseGarage.storeRadius or garageConfig.storeRadius) or 4.0,
    entryRadius = tonumber(houseGarage.entryRadius or garageConfig.interactionDistance) or 2.0,
    vehicleTypes = type(houseGarage.vehicleTypes) == 'table' and houseGarage.vehicleTypes or { 'car', 'bike' },
    sessionSeconds = tonumber(garageConfig.sessionSeconds) or 300
  }, nil, code
end

function MZHousesService.openHouseGarage(source, houseCode, action, isAdmin)
  local garageConfig = MZHousesConfig.Garage or {}
  if garageConfig.enabled ~= true then
    return false, 'garage_disabled'
  end

  local actorCitizenId = nil
  if tonumber(source) and tonumber(source) > 0 then
    actorCitizenId = MZHousesService.getPlayerCitizenId(source)
  end

  local accessAllowed, accessResult = MZHousesService.canEnterHouse(
    source,
    houseCode,
    garageConfig.allowAdminDebug == true and isAdmin == true
  )

  if not accessAllowed then
    MZHousesService.log('house.garage.open.denied', houseCode, source, actorCitizenId, {
      reason = accessResult or 'no_house_access',
      action = action
    })
    return false, accessResult or 'no_house_access'
  end

  local garage, garageErr, code = MZHousesService.getHouseGarageConfig(houseCode)
  if not garage then
    MZHousesService.log('house.garage.open.failed', houseCode, source, actorCitizenId, {
      reason = garageErr or 'garage_disabled',
      action = action
    })
    return false, garageErr or 'garage_disabled'
  end

  if GetResourceState('mz_garagem') ~= 'started' then
    MZHousesService.log('house.garage.open.failed', code, source, actorCitizenId, {
      reason = 'garage_resource_unavailable',
      action = action
    })
    return false, 'garage_unavailable'
  end

  local descriptor = {
    houseCode = code,
    label = garage.label,
    garageId = garage.garageId,
    garageMode = garage.garageMode,
    slots = garage.slots,
    entry = garage.entry,
    spawn = garage.spawn,
    store = garage.store,
    storeRadius = garage.storeRadius,
    entryRadius = garage.entryRadius,
    vehicleTypes = garage.vehicleTypes,
    sessionSeconds = garage.sessionSeconds,
    action = action == 'store' and 'store' or 'open'
  }

  if MZHousesConfig.Debug == true then
    print(('[mz_houses][house_garage] opening house=%s src=%s descriptor=%s'):format(
      tostring(code),
      tostring(source),
      json.encode({
        houseCode = descriptor.houseCode,
        label = descriptor.label,
        garageId = descriptor.garageId,
        garageMode = descriptor.garageMode,
        slots = descriptor.slots,
        entry = vector3Payload(descriptor.entry),
        spawn = vector4Payload(descriptor.spawn),
        store = vector3Payload(descriptor.store),
        storeRadius = descriptor.storeRadius,
        entryRadius = descriptor.entryRadius,
        vehicleTypes = descriptor.vehicleTypes,
        action = descriptor.action
      })
    ))
  end

  local exportOk, opened, result = pcall(function()
    return exports['mz_garagem']:OpenHouseGarage(source, descriptor)
  end)

  if not exportOk then
    print(('[mz_houses][house_garage] export failed | house=%s | error=%s'):format(
      tostring(code),
      tostring(opened)
    ))

    MZHousesService.log('house.garage.open.failed', code, source, actorCitizenId, {
      reason = 'garage_export_failed',
      detail = tostring(opened),
      action = action
    })
    return false, ('house_garage_export_exception:%s'):format(tostring(opened)), tostring(opened)
  end

  if type(opened) == 'table' then
    if opened.ok ~= true then
      local errorMessage = tostring(opened.error or 'garage_open_failed')
      if opened.detail ~= nil and tostring(opened.detail) ~= '' then
        errorMessage = ('%s:%s'):format(errorMessage, tostring(opened.detail))
      end

      MZHousesService.log('house.garage.open.failed', code, source, actorCitizenId, {
        reason = tostring(opened.error or 'garage_open_failed'),
        detail = opened.detail,
        action = action
      })
      return false, errorMessage, opened.detail
    end

    result = opened
    opened = true
  end

  if opened ~= true then
    local errorMessage = tostring(result or 'garage_open_failed')
    MZHousesService.log('house.garage.open.failed', code, source, actorCitizenId, {
      reason = errorMessage,
      action = action
    })
    return false, errorMessage
  end

  MZHousesService.log('house.garage.open', code, source, actorCitizenId, {
    garageId = result and result.garageId or nil,
    action = action
  })

  return true, {
    houseCode = code,
    garageId = result and result.garageId or nil,
    label = garage.label,
    action = action == 'store' and 'store' or 'open'
  }
end

function MZHousesService.setHouseOwner(houseCode, citizenid, actorSource)
  local access, err, code = MZHousesService.getAccessState(houseCode)
  if not access then return false, err end

  citizenid = normalizeCitizenId(citizenid)
  if not citizenid then return false, 'invalid_citizenid' end

  if databaseEnabled() then
    local ok, dbErr = MZHousesRepository.setOwner(code, citizenid)
    if not ok then return false, dbErr or 'house_not_found' end
  end

  access.owner = citizenid
  access.public = false
  access.keys = access.keys or {}

  MZHousesService.log('house.owner.set', code, actorSource, citizenid)
  return true, { houseCode = code, owner = citizenid }
end

function MZHousesService.clearHouseOwner(houseCode, actorSource)
  local access, err, code = MZHousesService.getAccessState(houseCode)
  if not access then return false, err end

  if databaseEnabled() then
    local ok, dbErr = MZHousesRepository.clearOwner(code)
    if not ok then return false, dbErr or 'house_not_found' end
  end

  local previousOwner = access.owner
  access.owner = nil

  MZHousesService.log('house.owner.clear', code, actorSource, previousOwner)
  return true, { houseCode = code }
end

function MZHousesService.giveHouseKey(houseCode, citizenid, actorSource, role)
  local access, err, code = MZHousesService.getAccessState(houseCode)
  if not access then return false, err end

  citizenid = normalizeCitizenId(citizenid)
  if not citizenid then return false, 'invalid_citizenid' end

  if databaseEnabled() then
    local ok, dbErr = MZHousesRepository.giveKey(code, citizenid, role or 'key')
    if not ok then return false, dbErr or 'key_save_failed' end
  end

  access.keys = access.keys or {}
  access.keys[citizenid] = true
  access.public = false

  MZHousesService.log('house.key.give', code, actorSource, citizenid)
  return true, { houseCode = code, citizenid = citizenid }
end

function MZHousesService.removeHouseKey(houseCode, citizenid, actorSource)
  local access, err, code = MZHousesService.getAccessState(houseCode)
  if not access then return false, err end

  citizenid = normalizeCitizenId(citizenid)
  if not citizenid then return false, 'invalid_citizenid' end

  if databaseEnabled() then
    MZHousesRepository.removeKey(code, citizenid)
  end

  access.keys = access.keys or {}
  access.keys[citizenid] = nil

  MZHousesService.log('house.key.remove', code, actorSource, citizenid)
  return true, { houseCode = code, citizenid = citizenid }
end

function MZHousesService.listHouseKeys(houseCode)
  local access, err, code = MZHousesService.getAccessState(houseCode)
  if not access then return false, err end

  local keys = {}
  for citizenid, enabled in pairs(access.keys or {}) do
    if enabled == true then keys[#keys + 1] = citizenid end
  end
  table.sort(keys)

  return true, {
    houseCode = code,
    public = access.public == true,
    owner = access.owner,
    keys = keys,
    database = databaseEnabled()
  }
end

function MZHousesService.log(action, houseCode, actorSource, targetCitizenId, meta)
  if not databaseEnabled() or not MZHousesRepository or not MZHousesRepository.insertLog then
    return false
  end

  local actorCitizenId = nil
  if tonumber(actorSource) and tonumber(actorSource) > 0 then
    actorCitizenId = MZHousesService.getPlayerCitizenId(actorSource)
  end

  local ok = pcall(function()
    MZHousesRepository.insertLog(houseCode, action, actorCitizenId, targetCitizenId, meta)
  end)

  return ok
end
