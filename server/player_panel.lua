MZHousesPlayerPanel = MZHousesPlayerPanel or {}

local RateState = {}
local KeyLocks = {}
local RevokeTokens = {}
local TargetTokens = {}
local TokenSequence = 0

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function config()
  return type((MZHousesConfig or {}).PlayerPanel) == 'table' and MZHousesConfig.PlayerPanel or {}
end

local function enabled()
  return config().enabled ~= false
end

local function rateAllowed(source, action)
  source = tonumber(source)
  if not source or source <= 0 then return false end
  local delay = math.max(250, math.floor(tonumber(config().rateLimitMs) or 1000))
  local now = GetGameTimer()
  local key = ('%d:%s'):format(source, action)
  local previous = RateState[key]
  if previous and now >= previous and now - previous < delay then return false end
  RateState[key] = now
  return true
end

local function newToken(prefix, source)
  TokenSequence = (TokenSequence + 1) % 1000000
  return ('%s:%d:%d:%d:%06d'):format(
    prefix, tonumber(source) or 0, os.time(), GetGameTimer() % 1000000000, TokenSequence
  )
end

local function sourceValid(source)
  source = tonumber(source)
  return source and source > 0 and GetPlayerName(source) ~= nil
end

local function playerCitizenId(source)
  if not sourceValid(source) then return nil, 'invalid_source' end
  return MZHousesService.getPlayerCitizenId(source)
end

local function resolvedPolicyIsOwner(house)
  local policy = MZHousesAccessPolicy.resolve(house)
  return type(policy) == 'table' and policy.mode == 'owner'
end

local function personalProperty(house, ownerCitizenId)
  if type(house) ~= 'table' then return false, 'house_not_found' end
  local property = MZHousesRepository.normalizePropertyFields(house)
  local subtype = trim(property.subtype):lower()
  local status = trim(house.status):lower()
  if property.category ~= 'residential' or property.ownerType ~= 'player'
      or (subtype ~= 'house' and subtype ~= 'apartment' and subtype ~= 'apartment_unit') then
    return false, 'not_personal_residential_property'
  end
  if house.enabled ~= true or status ~= 'active' or status == 'archived' then
    return false, status == 'archived' and 'property_archived' or 'property_not_active'
  end
  if not resolvedPolicyIsOwner(house) then return false, 'property_policy_not_owner' end
  if ownerCitizenId and trim(house.owner_citizenid or house.owner) ~= ownerCitizenId then
    return false, 'not_owner'
  end
  return true, property
end

local function plainEntrance(value)
  if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
  local x, y, z = tonumber(value.x or value[1]), tonumber(value.y or value[2]), tonumber(value.z or value[3])
  if not x or not y or not z then return nil end
  return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function safeText(value, maximum)
  local text = trim(value)
  if text == '' then return nil end
  return text:sub(1, tonumber(maximum) or 160)
end

local function buildingContext(house, property)
  if property.subtype ~= 'apartment_unit' and property.subtype ~= 'apartment' then
    return nil, plainEntrance(house.entrance)
  end
  local parentCode = trim(property.parentCode)
  if parentCode == '' then return nil, nil end
  local building = MZHousesRepository.getHouseByCode(parentCode)
  if not building then return nil, nil end
  return {
    code = parentCode,
    label = safeText(building.label, 100) or parentCode
  }, plainEntrance(building.entrance)
end

local function safePropertyPayload(house, keyRole)
  local property = MZHousesRepository.normalizePropertyFields(house)
  local commerce = MZHousesRepository.normalizeCommerce(house)
  local tax = MZHousesRepository.normalizeTax(house)
  local door = MZHousesRepository.normalizeDoor(house.door)
  local building, entrance = buildingContext(house, property)
  local keyCount = nil
  if keyRole == nil then keyCount = #MZHousesRepository.listKeys(house.code) end
  local listing = type(house.listing) == 'table' and house.listing or {}
  return {
    code = house.code,
    label = safeText(house.label, 100) or house.code,
    category = property.category,
    subtype = property.subtype,
    type = property.subtype,
    description = safeText(listing.description, 160),
    unitNumber = property.unitNumber,
    building = building,
    status = 'active',
    owner = keyRole and nil or 'Voce',
    doorState = door and door.state or 'locked',
    keyCount = keyCount,
    keyRole = keyRole and MZHousesRepository.normalizeKeyRole(keyRole) or nil,
    entrance = entrance,
    tax = {
      enabled = tax.taxEnabled,
      amount = tax.taxAmount,
      status = tax.taxStatus,
      dueAt = tax.taxDueAt,
      graceUntil = tax.taxGraceUntil,
      lastPaidAt = tax.taxLastPaidAt
    },
    commerce = {
      enabled = commerce.saleEnabled,
      mode = commerce.saleMode,
      price = commerce.salePrice,
      status = commerce.saleEnabled and ('for_sale_' .. commerce.saleMode) or 'not_for_sale'
    },
    features = {
      stash = property.features.stash == true,
      wardrobe = property.features.wardrobe == true,
      garage = property.features.garage == true
    }
  }
end

local function safeKeyedPropertyPayload(house, keyRole)
  local payload = safePropertyPayload(house, keyRole)
  payload.keyCount = nil
  payload.tax = nil
  payload.commerce = nil
  payload.features = nil
  payload.owner = nil
  return payload
end

local function freshOwnedProperty(source, code)
  local citizenid, citizenErr = playerCitizenId(source)
  if not citizenid then return nil, citizenErr or 'player_not_loaded' end
  code = trim(code)
  if code == '' then return nil, 'invalid_house' end
  local house = MZHousesRepository.getHouseByCode(code)
  local allowed, propertyOrErr = personalProperty(house, citizenid)
  if not allowed then return nil, propertyOrErr end
  return house, nil, citizenid, propertyOrErr
end

function MZHousesPlayerPanel.GetPlayerOwnedProperties(source)
  local citizenid, citizenErr = playerCitizenId(source)
  if not citizenid then return nil, citizenErr or 'player_not_loaded' end
  local out = {}
  for _, house in ipairs(MZHousesRepository.listHousesByOwner(citizenid)) do
    if personalProperty(house, citizenid) == true then
      out[#out + 1] = safePropertyPayload(house)
    end
  end
  return out, nil
end

function MZHousesPlayerPanel.GetPlayerKeyedProperties(source)
  local citizenid, citizenErr = playerCitizenId(source)
  if not citizenid then return nil, citizenErr or 'player_not_loaded' end
  local out = {}
  for _, house in ipairs(MZHousesRepository.listHousesByKeyHolder(citizenid)) do
    local owner = trim(house.owner_citizenid or house.owner)
    if owner ~= citizenid and personalProperty(house) == true then
      out[#out + 1] = safeKeyedPropertyPayload(house, house.playerKeyRole)
    end
  end
  return out, nil
end

function MZHousesPlayerPanel.GetPlayerPropertyPanel(source, houseCode)
  local house, err = freshOwnedProperty(source, houseCode)
  if not house then return nil, err end
  return safePropertyPayload(house), nil
end

local function onlineIdentityByCitizenId(citizenid)
  if GetResourceState('mz_core') ~= 'started' then return nil, nil end
  local ok, player = pcall(function() return exports['mz_core']:GetPlayerByCitizenId(citizenid) end)
  if not ok or type(player) ~= 'table' then return nil, nil end
  local source = tonumber(player.source)
  local charinfo = type(player.charinfo) == 'table' and player.charinfo or {}
  local name = trim(('%s %s'):format(charinfo.firstname or '', charinfo.lastname or ''))
  if name == '' and source then name = GetPlayerName(source) or '' end
  return source, name ~= '' and name or nil
end

function MZHousesPlayerPanel.ListPropertyKeys(source, houseCode)
  local house, err, ownerCitizenId = freshOwnedProperty(source, houseCode)
  if not house then return nil, err end
  RevokeTokens[source] = {}
  local out = {}
  for _, row in ipairs(MZHousesRepository.listKeys(house.code)) do
    local citizenid = trim(row.citizenid)
    if citizenid ~= '' and citizenid ~= ownerCitizenId then
      local onlineSource, characterName = onlineIdentityByCitizenId(citizenid)
      local token = newToken('revoke', source)
      RevokeTokens[source][token] = {
        code = house.code, citizenid = citizenid, expiresAt = os.time() + 120
      }
      out[#out + 1] = {
        token = token,
        name = characterName or 'Jogador offline',
        role = MZHousesRepository.normalizeKeyRole(row.role),
        createdAt = row.created_at,
        online = onlineSource ~= nil
      }
    end
  end
  return out, nil
end

local function playerDistance(leftSource, rightSource)
  local leftPed, rightPed = GetPlayerPed(leftSource), GetPlayerPed(rightSource)
  if not leftPed or leftPed <= 0 or not rightPed or rightPed <= 0 then return nil end
  local left, right = GetEntityCoords(leftPed), GetEntityCoords(rightPed)
  local dx, dy, dz = left.x - right.x, left.y - right.y, left.z - right.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function MZHousesPlayerPanel.GetNearbyPlayersForPropertyKey(source, houseCode)
  local house, err, ownerCitizenId = freshOwnedProperty(source, houseCode)
  if not house then return nil, err end
  local maximum = math.max(0.5, tonumber(config().nearbyPlayerDistance) or 3.0)
  TargetTokens[source] = {}
  local out = {}
  for _, rawTarget in ipairs(GetPlayers()) do
    local target = tonumber(rawTarget)
    if target and target ~= tonumber(source) and GetPlayerName(target) then
      local distance = playerDistance(source, target)
      if distance and distance <= maximum then
        local citizenid = MZHousesService.getPlayerCitizenId(target)
        if citizenid and citizenid ~= ownerCitizenId then
          local player = exports['mz_core']:GetPlayer(target)
          local charinfo = type(player) == 'table' and type(player.charinfo) == 'table' and player.charinfo or {}
          local name = trim(('%s %s'):format(charinfo.firstname or '', charinfo.lastname or ''))
          if name == '' then name = GetPlayerName(target) or ('ID %d'):format(target) end
          local token = newToken('target', source)
          TargetTokens[source][token] = {
            code = house.code, targetSource = target, expiresAt = os.time() + 120
          }
          out[#out + 1] = {
            token = token, source = target, name = name,
            distance = math.floor(distance * 10 + 0.5) / 10
          }
        end
      end
    end
  end
  table.sort(out, function(left, right) return left.distance < right.distance end)
  return out, nil
end

local function withKeyLock(code, callback)
  code = trim(code)
  if code == '' then return false, 'invalid_house' end
  if KeyLocks[code] then return false, 'property_key_mutation_in_progress' end
  KeyLocks[code] = true
  local ok, result, extra = xpcall(callback, debug.traceback)
  KeyLocks[code] = nil
  if not ok then
    print(('[mz_houses][player_panel] key mutation failed house=%s error=%s'):format(code, tostring(result)))
    return false, 'property_key_mutation_failed'
  end
  return result, extra
end

local function mutationFailed(action, code, source, targetCitizenId, role, reason)
  MZHousesService.log(action, code, source, targetCitizenId, {
    role = role, result = 'failed', reason = reason
  })
  return false, reason
end

function MZHousesPlayerPanel.GrantPropertyKeyByOwner(source, houseCode, targetSource, role, targetToken)
  source, targetSource = tonumber(source), tonumber(targetSource)
  houseCode, role, targetToken = trim(houseCode), trim(role):lower(), trim(targetToken)
  if role ~= 'access' and role ~= 'control' then
    return mutationFailed('property.key.owner_grant_failed', houseCode, source, nil, role, 'invalid_key_role')
  end
  local token = type(TargetTokens[source]) == 'table' and TargetTokens[source][targetToken] or nil
  if not token or token.expiresAt < os.time() or token.code ~= houseCode or token.targetSource ~= targetSource then
    return mutationFailed('property.key.owner_grant_failed', houseCode, source, nil, role, 'invalid_target_token')
  end
  return withKeyLock(houseCode, function()
    local house, err, ownerCitizenId = freshOwnedProperty(source, houseCode)
    if not house then return mutationFailed('property.key.owner_grant_failed', houseCode, source, nil, role, err) end
    if not sourceValid(targetSource) then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, nil, role, 'target_not_online')
    end
    local targetCitizenId, targetErr = MZHousesService.getPlayerCitizenId(targetSource)
    if not targetCitizenId then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, nil, role, targetErr or 'invalid_target')
    end
    if targetCitizenId == ownerCitizenId then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, targetCitizenId, role, 'cannot_key_owner')
    end
    local maximumDistance = math.max(0.5, tonumber(config().nearbyPlayerDistance) or 3.0)
    local distance = playerDistance(source, targetSource)
    if not distance or distance > maximumDistance then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, targetCitizenId, role, 'target_too_far')
    end
    local keys = MZHousesRepository.listKeys(houseCode)
    local existing = false
    local previousRole = nil
    for _, row in ipairs(keys) do
      if trim(row.citizenid) == targetCitizenId then
        existing = true
        previousRole = MZHousesRepository.normalizeKeyRole(row.role)
        break
      end
    end
    local maximumKeys = math.max(1, math.floor(tonumber(config().maxKeysPerProperty) or 10))
    if not existing and #keys >= maximumKeys then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, targetCitizenId, role, 'key_limit_reached')
    end
    local granted, result = MZHousesRepository.giveKeyByOwner(
      houseCode, ownerCitizenId, targetCitizenId, role, maximumKeys
    )
    if not granted then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, targetCitizenId, role, result or 'key_save_failed')
    end
    local refreshed, refreshErr = MZHousesService.refreshProperty(houseCode)
    if not refreshed then
      return mutationFailed('property.key.owner_grant_failed', houseCode, source, targetCitizenId, role, refreshErr or 'house_refresh_failed')
    end
    local compatibilityAction = previousRole and previousRole ~= role and 'property.key.role.change'
      or role == 'control' and 'property.key.control.give'
      or 'property.key.access.give'
    MZHousesService.log(compatibilityAction, houseCode, source, targetCitizenId, {
      previousRole = previousRole, role = role, source = 'owner_panel'
    })
    TriggerEvent('mz_houses:server:propertyAccessChanged', houseCode, 'key_given')
    TargetTokens[source][targetToken] = nil
    MZHousesService.log('property.key.owner_granted', houseCode, source, targetCitizenId, {
      role = role, result = 'success', distance = distance, maximumKeys = maximumKeys
    })
    TriggerClientEvent('mz_houses:client:refreshVisibility', source, 'owner_key_granted')
    TriggerClientEvent('mz_houses:client:refreshVisibility', targetSource, 'owner_key_granted')
    TriggerClientEvent('mz_houses:client:playerPanelKeyNotice', targetSource, {
      action = 'granted', propertyLabel = safeText(house.label, 100) or houseCode, role = role
    })
    return true, { houseCode = houseCode, role = role }
  end)
end

function MZHousesPlayerPanel.RevokePropertyKeyByOwner(source, houseCode, revokeToken)
  source, houseCode, revokeToken = tonumber(source), trim(houseCode), trim(revokeToken)
  local token = type(RevokeTokens[source]) == 'table' and RevokeTokens[source][revokeToken] or nil
  if not token or token.expiresAt < os.time() or token.code ~= houseCode then
    return mutationFailed('property.key.owner_revoke_failed', houseCode, source, nil, nil, 'invalid_revoke_token')
  end
  return withKeyLock(houseCode, function()
    local house, err, ownerCitizenId = freshOwnedProperty(source, houseCode)
    if not house then return mutationFailed('property.key.owner_revoke_failed', houseCode, source, nil, nil, err) end
    if token.citizenid == ownerCitizenId then
      return mutationFailed('property.key.owner_revoke_failed', houseCode, source, token.citizenid, nil, 'cannot_revoke_owner')
    end
    local currentRole = nil
    for _, row in ipairs(MZHousesRepository.listKeys(houseCode)) do
      if trim(row.citizenid) == token.citizenid then
        currentRole = MZHousesRepository.normalizeKeyRole(row.role)
        break
      end
    end
    if not currentRole then
      return mutationFailed('property.key.owner_revoke_failed', houseCode, source, token.citizenid, nil, 'key_not_found')
    end
    local revoked, result = MZHousesRepository.removeKeyByOwner(
      houseCode, ownerCitizenId, token.citizenid
    )
    if not revoked then
      return mutationFailed('property.key.owner_revoke_failed', houseCode, source, token.citizenid, currentRole, result or 'key_remove_failed')
    end
    local refreshed, refreshErr = MZHousesService.refreshProperty(houseCode)
    if not refreshed then
      return mutationFailed('property.key.owner_revoke_failed', houseCode, source, token.citizenid, currentRole, refreshErr or 'house_refresh_failed')
    end
    MZHousesService.log('house.key.remove', houseCode, source, token.citizenid, {
      role = currentRole, source = 'owner_panel'
    })
    TriggerEvent('mz_houses:server:propertyAccessChanged', houseCode, 'owner_key_revoked')
    RevokeTokens[source][revokeToken] = nil
    MZHousesService.log('property.key.owner_revoked', houseCode, source, token.citizenid, {
      role = currentRole, result = 'success', occupantPreserved = true
    })
    local targetSource = onlineIdentityByCitizenId(token.citizenid)
    TriggerClientEvent('mz_houses:client:refreshVisibility', source, 'owner_key_revoked')
    if targetSource then
      TriggerClientEvent('mz_houses:client:refreshVisibility', targetSource, 'owner_key_revoked')
      TriggerClientEvent('mz_houses:client:playerPanelKeyNotice', targetSource, {
        action = 'revoked', propertyLabel = safeText(house.label, 100) or houseCode, role = currentRole
      })
    end
    return true, { houseCode = houseCode, role = currentRole }
  end)
end

local function callbackError(reason)
  return { ok = false, error = reason or 'player_panel_failed' }
end

lib.callback.register('mz_houses:server:playerPanel:open', function(source)
  if not enabled() then return callbackError('player_panel_disabled') end
  if not rateAllowed(source, 'open') or not rateAllowed(source, 'property_list') then return callbackError('rate_limited') end
  local owned, ownedErr = MZHousesPlayerPanel.GetPlayerOwnedProperties(source)
  if not owned then return callbackError(ownedErr) end
  local keyed, keyedErr = MZHousesPlayerPanel.GetPlayerKeyedProperties(source)
  if not keyed then return callbackError(keyedErr) end
  MZHousesService.log('property.player_panel.opened', nil, source, nil, {
    ownedCount = #owned, keyedCount = #keyed, result = 'success'
  })
  return { ok = true, owned = owned, keyed = keyed }
end)

lib.callback.register('mz_houses:server:playerPanel:getProperty', function(source, payload)
  if not enabled() or not rateAllowed(source, 'property_detail') then return callbackError('rate_limited') end
  payload = type(payload) == 'table' and payload or {}
  local property, err = MZHousesPlayerPanel.GetPlayerPropertyPanel(source, payload.houseCode or payload.code)
  if not property then return callbackError(err) end
  return { ok = true, property = property }
end)

lib.callback.register('mz_houses:server:playerPanel:listKeys', function(source, payload)
  if not enabled() or not rateAllowed(source, 'key_list') then return callbackError('rate_limited') end
  payload = type(payload) == 'table' and payload or {}
  local keys, err = MZHousesPlayerPanel.ListPropertyKeys(source, payload.houseCode or payload.code)
  if not keys then return callbackError(err) end
  return { ok = true, keys = keys }
end)

lib.callback.register('mz_houses:server:playerPanel:nearbyPlayers', function(source, payload)
  if not enabled() or not rateAllowed(source, 'nearby_players') then return callbackError('rate_limited') end
  payload = type(payload) == 'table' and payload or {}
  local players, err = MZHousesPlayerPanel.GetNearbyPlayersForPropertyKey(source, payload.houseCode or payload.code)
  if not players then return callbackError(err) end
  return { ok = true, players = players }
end)

lib.callback.register('mz_houses:server:playerPanel:grantKey', function(source, payload)
  if not enabled() then return callbackError('player_panel_disabled') end
  payload = type(payload) == 'table' and payload or {}
  if not rateAllowed(source, 'grant_key') then
    mutationFailed(
      'property.key.owner_grant_failed', trim(payload.houseCode or payload.code),
      source, nil, trim(payload.role):lower(), 'rate_limited'
    )
    return callbackError('rate_limited')
  end
  local ok, result = MZHousesPlayerPanel.GrantPropertyKeyByOwner(
    source, payload.houseCode or payload.code, payload.targetSource, payload.role, payload.targetToken
  )
  if not ok then return callbackError(result) end
  return { ok = true, result = result }
end)

lib.callback.register('mz_houses:server:playerPanel:revokeKey', function(source, payload)
  if not enabled() then return callbackError('player_panel_disabled') end
  payload = type(payload) == 'table' and payload or {}
  if not rateAllowed(source, 'revoke_key') then
    mutationFailed(
      'property.key.owner_revoke_failed', trim(payload.houseCode or payload.code),
      source, nil, nil, 'rate_limited'
    )
    return callbackError('rate_limited')
  end
  local ok, result = MZHousesPlayerPanel.RevokePropertyKeyByOwner(
    source, payload.houseCode or payload.code, payload.revokeToken
  )
  if not ok then return callbackError(result) end
  return { ok = true, result = result }
end)

lib.callback.register('mz_houses:server:playerPanel:getTaxStatus', function(source, payload)
  if not enabled() or not rateAllowed(source, 'tax_history') then return callbackError('rate_limited') end
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode or payload.code)
  local house, ownerErr = freshOwnedProperty(source, code)
  if not house then return callbackError(ownerErr) end
  local tax, taxErr = MZHousesTax.getStatus(source, code, false, true)
  if not tax then return callbackError(taxErr or 'tax_status_failed') end
  MZHousesService.log('property.owner_tax_viewed', code, source, nil, {
    status = tax.status, result = 'success'
  })
  return { ok = true, tax = tax }
end)

exports('GetPlayerOwnedProperties', MZHousesPlayerPanel.GetPlayerOwnedProperties)
exports('GetPlayerKeyedProperties', MZHousesPlayerPanel.GetPlayerKeyedProperties)
exports('GetPlayerPropertyPanel', MZHousesPlayerPanel.GetPlayerPropertyPanel)
exports('GrantPropertyKeyByOwner', MZHousesPlayerPanel.GrantPropertyKeyByOwner)
exports('RevokePropertyKeyByOwner', MZHousesPlayerPanel.RevokePropertyKeyByOwner)
exports('GetNearbyPlayersForPropertyKey', MZHousesPlayerPanel.GetNearbyPlayersForPropertyKey)

AddEventHandler('playerDropped', function()
  local source = source
  RevokeTokens[source] = nil
  TargetTokens[source] = nil
  local prefix = ('%d:'):format(tonumber(source) or 0)
  for key in pairs(RateState) do
    if key:sub(1, #prefix) == prefix then RateState[key] = nil end
  end
end)
