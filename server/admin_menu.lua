if type(MZHousesCommerce) ~= 'table'
    or type(MZHousesCommerce.purchase) ~= 'function' then
  error('[mz_houses] MZHousesCommerce.purchase não foi carregado. Verifique commerce.lua e fxmanifest.')
end
if type(MZHousesCommerce.configureSale) ~= 'function' then
  error('[mz_houses] MZHousesCommerce.configureSale não foi carregado. Verifique o startup de commerce.lua.')
end
if type(MZHousesApartments) ~= 'table'
    or type(MZHousesApartments.previewBatch) ~= 'function'
    or type(MZHousesApartments.previewBulk) ~= 'function' then
  error('[mz_houses] API pública de MZHousesApartments incompleta. Verifique apartments.lua e fxmanifest.')
end
if type(MZHousesTax) ~= 'table'
    or type(MZHousesTax.configure) ~= 'function'
    or type(MZHousesTax.setStatus) ~= 'function'
    or type(MZHousesTax.setDueAt) ~= 'function'
    or type(MZHousesTax.getStatus) ~= 'function' then
  error('[mz_houses] API publica de MZHousesTax incompleta. Verifique tax.lua e fxmanifest.')
end
if type(MZHousesLegacyMigration) ~= 'table'
    or type(MZHousesLegacyMigration.preview) ~= 'function'
    or type(MZHousesLegacyMigration.apply) ~= 'function'
    or type(MZHousesLegacyMigration.audit) ~= 'function' then
  error('[mz_houses] API publica de MZHousesLegacyMigration incompleta. Verifique legacy_migration.lua e fxmanifest.')
end

local PreviewPlayers = {}
local MutationRate = {}

local function allowMutation(source)
  local now = os.time()
  local state = MutationRate[source]
  if not state or now - state.startedAt >= 10 then
    MutationRate[source] = { startedAt = now, count = 1 }
    return true
  end
  state.count = state.count + 1
  return state.count <= 25
end

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function clearPreviewSession(source)
  source = tonumber(source)
  if not source then return false end

  if not GetPlayerName(source) then
    PreviewPlayers[source] = nil
    return false
  end

  local player = Player(source)
  local state = player and player.state or nil
  local tracked = PreviewPlayers[source] == true or (state and trim(state.mzHousePreview) ~= '')
  if not tracked then return false end

  PreviewPlayers[source] = nil
  if state then state:set('mzHousePreview', nil, true) end

  -- Um cleanup atrasado de preview nao deve retirar o player de uma casa.
  if not state or trim(state.mzHouseCode) == '' then
    SetPlayerRoutingBucket(source, 0)
  end
  return true
end

local function parseBool(value)
  if type(value) == 'boolean' then
    return value
  end

  value = tostring(value or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if value == 'true' or value == '1' or value == 'yes' or value == 'sim' or value == 'on' then
    return true
  end

  if value == 'false' or value == '0' or value == 'no' or value == 'nao' or value == 'off' then
    return false
  end

  return nil
end

local function vector3Payload(value)
  if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then
    return nil
  end

  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  if not x or not y or not z then
    return nil
  end

  return {
    x = x + 0.0,
    y = y + 0.0,
    z = z + 0.0
  }
end

local function vector4Payload(value)
  if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then
    return nil
  end

  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  local w = tonumber(value.w or value.h or value.heading or value[4]) or 0.0
  if not x or not y or not z then
    return nil
  end

  return {
    x = x + 0.0,
    y = y + 0.0,
    z = z + 0.0,
    w = w + 0.0
  }
end

local function coordsFromPayload(payload, includeHeading)
  payload = type(payload) == 'table' and payload or {}
  local coords = type(payload.coords) == 'table' and payload.coords or payload
  local x = tonumber(coords.x or coords[1])
  local y = tonumber(coords.y or coords[2])
  local z = tonumber(coords.z or coords[3])
  if not x or not y or not z then
    return nil
  end

  if includeHeading == true then
    local h = tonumber(payload.heading or coords.w or coords.h or coords[4]) or 0.0
    return vector4(x, y, z, h)
  end

  return vector3(x, y, z)
end

local function getAdminAce()
  local menu = MZHousesConfig.AdminMenu or {}
  local ace = trim(menu.ace)
  if ace == '' then
    ace = trim((MZHousesConfig.Admin or {}).ace)
  end
  if ace == '' then
    ace = 'group.mz_owner'
  end
  return ace
end

local function isAceAllowed(src, ace)
  local sourceId = tonumber(src)
  if not sourceId or sourceId <= 0 then
    return false
  end

  ace = trim(ace)
  if ace == '' then
    return false
  end

  local allowed = IsPlayerAceAllowed(sourceId, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function isAdmin(source)
  if (MZHousesConfig.AdminMenu or {}).enabled == false then
    return false
  end

  local src = tonumber(source) or 0
  if src == 0 then
    return true
  end

  -- Usa exatamente o mesmo validador dos comandos admin quando ele ja estiver carregado.
  -- Isso evita divergencia entre /mhouse_* funcionando e /mhouse_admin negando permissao.
  if type(isHouseAdmin) == 'function' then
    local ok, allowed = pcall(isHouseAdmin, src)
    if ok then
      return allowed == true
    end
  end

  -- Fallback robusto: alguns ambientes retornam 1/'1' em vez de boolean true.
  local admin = MZHousesConfig.Admin or {}
  if admin.requireAce ~= true then
    return true
  end

  return isAceAllowed(src, getAdminAce())
end

local function adminEnabled()
  return (MZHousesConfig.AdminMenu or {}).enabled ~= false
end

local function refreshVisibility(reason)
  TriggerClientEvent('mz_houses:client:refreshVisibility', -1, reason or 'admin_menu')
end

local function denied()
  return { ok = false, error = 'admin_required' }
end

local function adminPropertyInfo(code, source)
  local property, err = MZHousesService.getAdminPropertyInfo(code)
  if not property then
    return nil, err or 'house_not_found'
  end

  local keysOk, access = MZHousesService.listHouseKeys(code, source, true)
  if keysOk and type(access) == 'table' then
    property.owner = access.owner
    property.keyCount = type(access.keys) == 'table' and #access.keys or 0
    property.keys = access.keys or {}
    property.accessMode = access.accessMode
    property.enterAccess = access.enterAccess
    property.featuresAccess = access.featuresAccess
    property.orgCode = access.orgCode
    property.businessCode = access.businessCode
    property.currentAccess = access.currentAccess
    property.currentAccessReason = access.currentAccessReason
    property.database = access.database == true
  end

  return property, nil
end

local function okWithProperty(code, source, message)
  local property = adminPropertyInfo(code, source) or MZHousesService.getPublicPropertyInfo(code)
  return {
    ok = true,
    message = message,
    property = property
  }
end

local function adminUpdate(source, code, patch, action, meta, message)
  if not isAdmin(source) then
    return denied()
  end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end

  code = trim(code)
  if code == '' then
    return { ok = false, error = 'invalid_house' }
  end

  local ok, result = MZHousesService.updateAdminProperty(source, code, patch, action, meta)
  if not ok then
    return { ok = false, error = result or 'update_failed' }
  end

  refreshVisibility(action or 'admin_menu_update')
  return okWithProperty(result.houseCode or code, source, message or 'Imovel atualizado.')
end

local function currentGarage(code)
  local property = MZHousesService.getAdminPropertyInfo(code)
  local garage = type(property) == 'table' and type(property.garage) == 'table' and property.garage or {}
  garage.label = trim(garage.label) ~= '' and garage.label or 'Garagem da Casa'
  garage.mode = trim(garage.mode) == 'shared' and 'shared' or 'private'
  garage.slots = tonumber(garage.slots) or tonumber((MZHousesConfig.Garage or {}).defaultSlots) or 2
  garage.storeRadius = tonumber(garage.storeRadius) or tonumber((MZHousesConfig.Garage or {}).storeRadius) or 4.0
  return garage, property
end

local function defaultFeatures(property)
  local features = type(property) == 'table' and type(property.features) == 'table' and property.features or {}
  return {
    stash = features.stash == true,
    wardrobe = features.wardrobe == true,
    garage = features.garage == true,
    furniture = features.furniture == true,
    activities = features.activities == true
  }
end

local function interiorPointFromPayload(payload, pointName)
  payload = type(payload) == 'table' and payload or {}
  local relative = coordsFromPayload(payload.relativePoint, false)
  if not relative then
    local point = coordsFromPayload(payload.point, false)
    local spawn = coordsFromPayload(payload.spawnCoords, false)
    if point and spawn then relative = vector3(point.x - spawn.x, point.y - spawn.y, point.z - spawn.z) end
  end
  if not relative then
    return nil, 'invalid_interior_context'
  end
  local x, y, z = tonumber(relative.x), tonumber(relative.y), tonumber(relative.z)
  if not x or not y or not z or x ~= x or y ~= y or z ~= z
    or x == math.huge or y == math.huge or z == math.huge
    or x == -math.huge or y == -math.huge or z == -math.huge then
    return nil, 'invalid_interior_offset'
  end
  local maxOffset = tonumber((MZHousesConfig.Admin or {}).MaxInteriorPointOffset) or 100.0
  if math.sqrt(x*x + y*y + z*z) > maxOffset then return nil, 'interior_offset_too_far' end
  local out = {
    enabled = true,
    coords = vector3(x, y, z),
    relative = true
  }

  if pointName == 'entrySpawn' then
    local heading = tonumber(payload.relativeHeading)
    if not heading or heading ~= heading or heading == math.huge or heading == -math.huge then return nil, 'invalid_heading' end
    out.mode = 'custom'
    out.heading = heading % 360.0
  elseif pointName == 'exit' then
    out.label = 'Sair da casa'
    out.heading = (tonumber(payload.relativeHeading) or tonumber((type(payload.point) == 'table' and (payload.point.heading or payload.point.w or payload.point.h)) or payload.heading) or 0.0) % 360.0
  elseif pointName == 'stash' then
    out.label = 'Bau da Casa'
    out.slots = tonumber((MZHousesConfig.Stash or {}).defaultSlots) or 50
    out.weight = tonumber((MZHousesConfig.Stash or {}).defaultWeight) or 100000
  elseif pointName == 'wardrobe' then
    out.label = 'Guarda-roupa'
  end

  return out
end

local function validStoredInteriorPoint(point)
  if type(point) ~= 'table' or type(point.coords) ~= 'table' then return false end
  local x, y, z = tonumber(point.coords.x), tonumber(point.coords.y), tonumber(point.coords.z)
  local h = tonumber(point.heading) or 0.0
  if not x or not y or not z or x ~= x or y ~= y or z ~= z or h ~= h then return false end
  local maxOffset = tonumber((MZHousesConfig.Admin or {}).MaxInteriorPointOffset) or 100.0
  return math.sqrt(x*x + y*y + z*z) <= maxOffset
end

local function validateInteriorEditContext(source, payload)
  if not isAdmin(source) then
    return false, 'admin_required'
  end

  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  if code == '' then
    return false, 'invalid_house'
  end

  local property = MZHousesService.getAdminPropertyInfo(code)
  if not property then return false, 'house_not_found' end
  local player = Player(source)
  local state = player and player.state or nil
  local houseSession = state and trim(state.mzHouseCode) == code
  local previewShell = state and trim(state.mzHousePreview) or ''
  local previewSession = payload.preview == true and previewShell ~= '' and previewShell == trim(property.shell)
  if not houseSession and not previewSession then return false, 'not_inside_property_or_matching_preview' end
  if trim(payload.shell) ~= trim(property.shell) then return false, 'wrong_interior_shell' end

  return true, code
end

lib.callback.register('mz_houses:server:admin:checkAccess', function(source)
  return {
    ok = isAdmin(source) == true and adminEnabled(),
    error = adminEnabled() and nil or 'admin_menu_disabled'
  }
end)

lib.callback.register('mz_houses:server:admin:previewLegacyMigration', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  local callOk, ok, result = pcall(MZHousesLegacyMigration.preview, source, payload)
  if not callOk then
    MZHousesService.log('property.legacy.migration.preview.failed', trim(type(payload) == 'table' and payload.code or ''), source, nil, {
      reason = 'migration_preview_internal_error'
    })
    return { ok = false, error = 'migration_preview_internal_error' }
  end
  if ok ~= true then return { ok = false, error = result or 'migration_preview_failed' } end
  return { ok = true, preview = result }
end)

lib.callback.register('mz_houses:server:admin:applyLegacyMigration', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local callOk, ok, result = pcall(MZHousesLegacyMigration.apply, source, payload.token, payload.confirmCode)
  if not callOk then return { ok = false, error = 'migration_internal_error' } end
  if ok ~= true then return { ok = false, error = result or 'migration_failed' } end
  refreshVisibility('property_legacy_migrated')
  return okWithProperty(result.houseCode, source, 'Migracao legada aplicada apos preview e revalidacao.')
end)

lib.callback.register('mz_houses:server:admin:auditLegacyData', function(source)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  local callOk, report = pcall(MZHousesLegacyMigration.audit)
  if not callOk then return { ok = false, error = 'legacy_audit_internal_error' } end
  MZHousesService.log('property.legacy.audit.completed', nil, source, nil, {
    total = report.counts and report.counts.total or 0,
    samples = type(report.samples) == 'table' and #report.samples or 0,
    destructiveActions = 0
  })
  return { ok = true, report = report }
end)

lib.callback.register('mz_houses:server:admin:listGroups', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local groups, err = MZHousesGroups.list(trim(payload.type):lower())
  if not groups then return { ok = false, error = err or 'group_provider_failed' } end
  return { ok = true, groups = groups }
end)

lib.callback.register('mz_houses:server:admin:setAccessPolicy', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  if code == '' or type(payload.accessPolicy) ~= 'table' then
    return { ok = false, error = 'invalid_access_policy' }
  end
  local property = MZHousesService.getAdminPropertyInfo(code)
  if not property then return { ok = false, error = 'house_not_found' } end
  local requested = payload.accessPolicy
  if type(requested.features) ~= 'table' then
    local current = MZHousesAccessPolicy.resolve(property)
    requested.features = type(current) == 'table' and current.features or nil
  end
  return adminUpdate(source, code, { accessPolicy = requested }, 'property.access.policy.set', {
    requestedMode = requested.mode,
    requestedRuleCount = type(requested.rules) == 'table' and #requested.rules or 0
  }, 'Politica de acesso atualizada.')
end)

lib.callback.register('mz_houses:server:admin:setFeaturePolicy', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local featureName = trim(payload.featureName):lower()
  if code == '' then return { ok = false, error = 'invalid_house' } end

  local featureOk, featureOrErr = MZHousesAccessPolicy.validateFeaturePolicy(featureName, payload.featurePolicy)
  if not featureOk then return { ok = false, error = featureOrErr or 'invalid_feature_policy' } end
  local property = MZHousesService.getAdminPropertyInfo(code)
  if not property then return { ok = false, error = 'house_not_found' } end

  local currentPolicy = MZHousesAccessPolicy.resolve(property)
  if type(currentPolicy) ~= 'table' then return { ok = false, error = 'legacy_property_type_retired' } end
  local policy = MZHousesRepository.normalizeAccessPolicy(currentPolicy)
  policy.features[featureName] = featureOrErr
  local features = defaultFeatures(property)
  features[featureName] = featureOrErr.mode ~= 'disabled'

  local response = adminUpdate(source, code, {
    accessPolicy = policy,
    features = features
  }, 'property.feature.policy.set', {
    feature = featureName,
    mode = featureOrErr.mode,
    ruleCount = #featureOrErr.rules
  }, 'Permissao do recurso atualizada.')
  if response.ok == true then
    TriggerClientEvent('mz_houses:client:featurePolicyChanged', -1, {
      houseCode = code,
      feature = featureName,
      enabled = featureOrErr.mode ~= 'disabled'
    })
  end
  return response
end)

lib.callback.register('mz_houses:server:admin:setDoorState', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.setDoorState(source, payload.code, payload.state, true)
  if not ok then return { ok = false, error = result or 'door_update_failed' } end
  refreshVisibility('property_door_state_changed')
  return okWithProperty(result.houseCode, source, 'Estado da porta atualizado.')
end)

lib.callback.register('mz_houses:server:admin:beginPreview', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local shell = trim(payload.shell)
  local valid, reason = MZHousesService.IsShellSelectable(shell)
  if valid ~= true then return { ok = false, error = reason or 'invalid_shell' } end
  local player = Player(source)
  local state = player and player.state or nil
  if PreviewPlayers[source] or (state and trim(state.mzHousePreview) ~= '') then
    return { ok = false, error = 'preview_already_active' }
  end
  if state and trim(state.mzHouseCode) ~= '' then
    return { ok = false, error = 'house_session_active' }
  end
  local bucket = 100000 + tonumber(source)
  PreviewPlayers[source] = true
  SetPlayerRoutingBucket(source, bucket)
  if player and player.state then player.state:set('mzHousePreview', shell, true) end
  return { ok = true, bucket = bucket, shell = shell }
end)

lib.callback.register('mz_houses:server:admin:endPreview', function(source)
  -- Encerrar a propria sessao e sempre permitido para que perda de ACE durante
  -- o preview nao prenda bucket/state bag.
  clearPreviewSession(source)
  return { ok = true }
end)

RegisterNetEvent('mz_houses:server:adminPreviewStopped', function()
  clearPreviewSession(source)
end)

AddEventHandler('playerDropped', function() PreviewPlayers[source] = nil end)
AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() and resource ~= 'mz_interiors' then return end
  for src in pairs(PreviewPlayers) do clearPreviewSession(src) end
end)

lib.callback.register('mz_houses:server:admin:setInternalPoint', function(source, payload)
  local valid, codeOrErr = validateInteriorEditContext(source, payload)
  if not valid then
    return { ok = false, error = codeOrErr }
  end

  payload = type(payload) == 'table' and payload or {}
  local code = codeOrErr
  local pointName = trim(payload.pointName)
  if pointName ~= 'entrySpawn' and pointName ~= 'exit' and pointName ~= 'stash' and pointName ~= 'wardrobe' then
    return { ok = false, error = 'invalid_internal_point' }
  end

  local property = MZHousesService.getAdminPropertyInfo(code)
  if not property then
    return { ok = false, error = 'house_not_found' }
  end

  local point, err = interiorPointFromPayload(payload, pointName)
  if not point then
    return { ok = false, error = err or 'invalid_interior_point' }
  end

  local interior = type(property.interior) == 'table' and property.interior or {}
  local previous = interior[pointName]
  interior[pointName] = point

  local action = ('house.admin.internal.%s.set'):format(pointName)
  local response = adminUpdate(source, code, { interior = interior }, action, {
    point = pointName,
    shell = trim(payload.shell),
    coords = vector3Payload(point.coords),
    heading = point.heading,
    previous = previous,
    next = point
  }, ('Ponto interno atualizado: %s'):format(pointName))

  return response
end)

lib.callback.register('mz_houses:server:admin:setEntrySpawnDefault', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local property = MZHousesService.getAdminPropertyInfo(payload.code)
  if not property then return { ok = false, error = 'house_not_found' } end
  local interior = type(property.interior) == 'table' and property.interior or {}
  local previous = interior.entrySpawn
  interior.entrySpawn = { mode = 'default', relative = true }
  return adminUpdate(source, payload.code, { interior = interior }, 'house.admin.entry_spawn.default', {
    previous = previous, next = interior.entrySpawn
  }, 'Spawn de entrada restaurado para o padrao do shell.')
end)

lib.callback.register('mz_houses:server:admin:copyInteriorPoint', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local property = MZHousesService.getAdminPropertyInfo(payload.code)
  if not property then return { ok = false, error = 'house_not_found' } end
  local interior = type(property.interior) == 'table' and property.interior or {}
  local direction = trim(payload.direction)
  if direction == 'entry_to_exit' then
    local entry = type(interior.entrySpawn) == 'table' and interior.entrySpawn or nil
    if not entry or entry.mode ~= 'custom' or not validStoredInteriorPoint(entry) then return { ok = false, error = 'custom_entry_spawn_required' } end
    interior.exit = { enabled = true, label = 'Sair da casa', coords = entry.coords, heading = (tonumber(entry.heading) or 0.0) % 360.0, relative = true }
  elseif direction == 'exit_to_entry' then
    local exit = type(interior.exit) == 'table' and interior.exit or property.effectiveExit
    if not validStoredInteriorPoint(exit) then return { ok = false, error = 'valid_exit_required' } end
    interior.entrySpawn = { mode = 'custom', coords = exit.coords, heading = (tonumber(exit.heading) or 0.0) % 360.0, relative = true }
  else
    return { ok = false, error = 'invalid_copy_direction' }
  end
  return adminUpdate(source, payload.code, { interior = interior }, 'house.admin.internal.copy', { direction = direction }, 'Ponto interno copiado.')
end)

lib.callback.register('mz_houses:server:admin:resetInternalPoints', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end

  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  if code == '' then
    return { ok = false, error = 'invalid_house' }
  end

  return adminUpdate(source, code, { interior = {} }, 'house.admin.internal.reset', nil, 'Pontos internos resetados para defaults do shell.')
end)

lib.callback.register('mz_houses:server:admin:listNearbyProperties', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end

  payload = type(payload) == 'table' and payload or {}
  local origin = coordsFromPayload(payload.coords, false)
  if not origin then
    return { ok = false, error = 'invalid_coords' }
  end

  local menu = MZHousesConfig.AdminMenu or {}
  local radius = tonumber(payload.radius) or tonumber(menu.nearPropertyRadius) or 25.0
  local maxResults = math.floor(tonumber(payload.maxResults) or tonumber(menu.maxNearbyResults) or 10)
  if maxResults < 1 then maxResults = 1 end

  local out = {}
  for _, property in ipairs(MZHousesService.ListProperties({}) or {}) do
    local entrance = coordsFromPayload(property.entrance, false)
    if entrance then
      local distance = #(origin - entrance)
      if distance <= radius then
        out[#out + 1] = {
          code = property.code,
          label = property.label or property.code,
          category = property.category,
          subtype = property.subtype,
          ownerType = property.ownerType,
          distance = distance,
          enabled = property.enabled == true,
          status = property.status
        }
      end
    end
  end

  table.sort(out, function(left, right)
    return (tonumber(left.distance) or 999999.0) < (tonumber(right.distance) or 999999.0)
  end)

  while #out > maxResults do
    out[#out] = nil
  end

  return { ok = true, properties = out }
end)

lib.callback.register('mz_houses:server:admin:searchProperties', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local query = trim(payload.query):lower()
  local out = {}
  for _, item in ipairs(MZHousesService.ListProperties({}) or {}) do
    local property = MZHousesService.getAdminPropertyInfo(item.code)
    if property then
      local haystack = table.concat({
        tostring(property.code or ''), tostring(property.label or ''),
        tostring(property.owner or ''), tostring(property.category or ''),
        tostring(property.subtype or ''), tostring(property.status or '')
      }, ' '):lower()
      if query == '' or haystack:find(query, 1, true) then
        out[#out + 1] = property
        if #out >= 100 then break end
      end
    end
  end
  table.sort(out, function(a, b) return tostring(a.code) < tostring(b.code) end)
  return { ok = true, properties = out }
end)

lib.callback.register('mz_houses:server:admin:getPropertyInfo', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end

  local code = trim(type(payload) == 'table' and payload.code or payload)
  local property, err = adminPropertyInfo(code, source)
  if not property then
    return { ok = false, error = err or 'house_not_found' }
  end

  return { ok = true, property = property }
end)

lib.callback.register('mz_houses:server:admin:getPropertyLogs', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  return { ok = true, logs = MZHousesRepository.listLogs(payload.code, 20) }
end)

lib.callback.register('mz_houses:server:admin:createProperty', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end

  payload = type(payload) == 'table' and payload or {}
  payload.entrance = coordsFromPayload(payload.entrance or payload, true)

  local ok, result = MZHousesService.createAdminProperty(source, payload)
  if not ok then
    return { ok = false, error = result or 'create_failed' }
  end

  refreshVisibility('house_admin_menu_create')
  return okWithProperty(result.houseCode, source, 'Imovel criado.')
end)

lib.callback.register('mz_houses:server:admin:createStructuredProperty', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end

  payload = type(payload) == 'table' and payload or {}
  payload.entrance = coordsFromPayload(payload.entrance or payload, true)

  local ok, result = MZHousesService.createStructuredProperty(source, payload)
  if not ok then
    return { ok = false, error = result or 'create_failed' }
  end

  refreshVisibility('house_admin_structured_create')
  local response = okWithProperty(result.houseCode, source,
    result.unitBatchError and 'Predio criado; o lote de unidades falhou e nenhuma unidade parcial foi mantida.'
      or 'Imovel criado com code automatico.')
  response.units = result.units
  response.unitBatchError = result.unitBatchError
  return response
end)

lib.callback.register('mz_houses:server:admin:listApartmentBuildings', function(source)
  if not isAdmin(source) then
    return denied()
  end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end

  local out = {}
  for _, property in ipairs(MZHousesService.ListProperties({ category = 'residential', subtype = 'apartment_building' }) or {}) do
    out[#out + 1] = {
      code = property.code,
      label = property.label or property.code,
      status = property.status,
      enabled = property.enabled == true
    }
  end

  return { ok = true, buildings = out }
end)

lib.callback.register('mz_houses:server:admin:listBuildingUnits', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end

  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code or payload.buildingCode)
  local result, err = MZHousesService.ListApartmentUnits(source, code, true)
  if not result then
    return { ok = false, error = err or 'units_failed' }
  end

  local units = {}
  for _, unit in ipairs(result.units or {}) do
    local adminInfo = MZHousesService.getAdminPropertyInfo(unit.code) or unit
    units[#units + 1] = {
      code = adminInfo.code or unit.code,
      label = adminInfo.label or unit.label,
      unitNumber = adminInfo.unitNumber or unit.unitNumber,
      shell = adminInfo.shell or unit.shell,
      owner = adminInfo.owner,
      keyCount = tonumber(adminInfo.keyCount) or 0,
      enabled = adminInfo.enabled == true,
      status = adminInfo.status,
      saleEnabled = adminInfo.saleEnabled == true,
      saleMode = adminInfo.saleMode,
      salePrice = adminInfo.salePrice,
      tax = adminInfo.tax,
      bulkCommerceProtected = type(adminInfo.metadata) == 'table'
        and adminInfo.metadata.bulkCommerceProtected == true
    }
  end

  return { ok = true, building = result.building, units = units }
end)

lib.callback.register('mz_houses:server:admin:getBuildingUnitDefaults', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local defaults, err = MZHousesApartments.getUnitDefaults(payload.code or payload.buildingCode)
  if not defaults then return { ok = false, error = err or 'unit_defaults_failed' } end
  return { ok = true, defaults = defaults }
end)

lib.callback.register('mz_houses:server:admin:updateBuildingUnitDefaults', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.updateUnitDefaults(source, payload.code or payload.buildingCode, {
    saleEnabled = payload.saleEnabled == true,
    saleMode = payload.saleMode,
    salePrice = payload.salePrice,
    shell = payload.shell,
    taxEnabled = payload.taxEnabled == true,
    taxAmount = payload.taxAmount,
    taxIntervalDays = payload.taxIntervalDays,
    taxGracePeriodDays = payload.taxGracePeriodDays
  })
  if not ok then return { ok = false, error = result or 'unit_defaults_update_failed' } end
  return okWithProperty(result.houseCode, source, 'Defaults de novas unidades atualizados; unidades existentes nao foram alteradas.')
end)

lib.callback.register('mz_houses:server:admin:copyBuildingUnitTemplate', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.copyUnitTemplate(
    source, payload.code or payload.buildingCode, payload.unitCode
  )
  if not ok then return { ok = false, error = result or 'unit_template_copy_failed' } end
  return okWithProperty(result.houseCode, source,
    'Shell, interior e features copiados para o modelo de novas unidades; unidades existentes nao mudaram.')
end)

lib.callback.register('mz_houses:server:admin:previewApartmentBatch', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.previewBatch(source, payload.buildingCode or payload.code, {
    unitNumbers = payload.unitNumbers
  })
  if not ok then return { ok = false, error = result or 'unit_batch_preview_failed' } end
  result.ok = true
  return result
end)

lib.callback.register('mz_houses:server:admin:createApartmentBatch', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.createBatch(source, payload.previewToken)
  if not ok then return { ok = false, error = result or 'unit_batch_create_failed' } end
  refreshVisibility('building_unit_batch_created')
  result.ok = true
  result.message = result.alreadyExists and 'Este lote ja existe; nenhuma duplicata foi criada.'
    or ('%d unidades criadas de forma transacional.'):format(tonumber(result.created) or 0)
  return result
end)

lib.callback.register('mz_houses:server:admin:previewApartmentBulk', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.previewBulk(source, payload.buildingCode or payload.code, {
    unitCodes = payload.unitCodes,
    operation = payload.operation,
    saleMode = payload.saleMode,
    salePrice = payload.salePrice
  })
  if not ok then return { ok = false, error = result or 'unit_bulk_preview_failed' } end
  result.ok = true
  return result
end)

lib.callback.register('mz_houses:server:admin:applyApartmentBulk', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.applyBulk(source, payload.previewToken)
  if not ok then return { ok = false, error = result or 'unit_bulk_apply_failed' } end
  refreshVisibility('building_unit_bulk_updated')
  result.ok = true
  result.message = ('Lote concluido: %d atualizadas, %d ignoradas.'):format(
    #(result.updated or {}), #(result.skipped or {})
  )
  return result
end)

lib.callback.register('mz_houses:server:admin:setUnitBulkProtection', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesApartments.setBulkProtection(source, payload.code, payload.protected == true)
  if not ok then return { ok = false, error = result or 'unit_protection_failed' } end
  return okWithProperty(result.houseCode, source, payload.protected == true
    and 'Unidade protegida contra operacoes comerciais em lote.'
    or 'Protecao comercial em lote removida.')
end)

lib.callback.register('mz_houses:server:admin:updateBasic', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local field = trim(payload.field)

  if field == 'label' then
    return adminUpdate(source, code, { label = trim(payload.label) }, 'house.admin.label.set', { label = trim(payload.label) }, 'Label atualizado.')
  end

  if field == 'metadata' then
    local price = tonumber(payload.price)
    if price and (price < 0 or price > 1000000000000) then
      return { ok = false, error = 'invalid_metadata_price' }
    end
    local notes = trim(payload.notes)
    if #notes > 1000 then return { ok = false, error = 'metadata_notes_too_long' } end
    return adminUpdate(source, code, { metadata = {
      administrativePrice = price,
      notes = notes ~= '' and notes or nil
    } }, 'house.admin.metadata.set', nil, 'Metadata administrativa atualizada.')
  end

  if field == 'enable' then
    return adminUpdate(source, code, { enabled = true, status = 'active' }, 'house.admin.enable', nil, 'Imovel ativado.')
  end

  if field == 'disable' then
    return adminUpdate(source, code, { enabled = false, status = 'disabled' }, 'house.admin.disable', nil, 'Imovel desativado.')
  end

  if field == 'archive' then
    if trim(payload.confirmCode) ~= code then
      return { ok = false, error = 'confirmation_mismatch' }
    end
    return adminUpdate(source, code, { enabled = false, status = 'archived', visibility = 'hidden' }, 'house.admin.archive', nil, 'Imovel arquivado.')
  end

  return { ok = false, error = 'invalid_basic_action' }
end)

lib.callback.register('mz_houses:server:admin:setEntrance', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local entrance = coordsFromPayload(payload.entrance or payload, true)
  if not entrance then
    return { ok = false, error = 'invalid_entrance' }
  end

  return adminUpdate(source, payload.code, { entrance = entrance }, 'house.admin.entrance.set', {
    entrance = vector4Payload(entrance)
  }, 'Entrada atualizada.')
end)

lib.callback.register('mz_houses:server:admin:setShell', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local shell = trim(payload.shell)
  if shell == '' then
    return { ok = false, error = 'invalid_shell' }
  end

  return adminUpdate(source, payload.code, { shell = shell, type = 'shell', interior = {} }, 'house.admin.shell.set', {
    shell = shell,
    resetInteriorOverrides = true
  }, 'Shell atualizado. Overrides internos resetados.')
end)

lib.callback.register('mz_houses:server:admin:setCategory', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local category = trim(payload.category)
  local subtype = trim(payload.subtype)
  local ownerType = trim(payload.ownerType)
  if category == '' or subtype == '' or ownerType == '' then
    return { ok = false, error = 'invalid_category' }
  end
  if category == 'org' or category == 'business' or category == 'government'
    or ownerType == 'org' or ownerType == 'business' then
    return { ok = false, error = 'unsupported_administrative_property_type' }
  end

  local patch = { category = category, subtype = subtype, ownerType = ownerType }
  if category == 'org' or ownerType == 'org' then
    patch.realestate = { enabled = false, canBeListed = false, defaultPrice = nil, listingType = 'sale' }
  end

  return adminUpdate(source, payload.code, patch, 'house.admin.category.set', patch, 'Categoria atualizada.')
end)

lib.callback.register('mz_houses:server:admin:setOrg', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local orgCode = trim(payload.orgCode)
  if orgCode == '' then
    return { ok = false, error = 'invalid_org' }
  end

  return adminUpdate(source, payload.code, { orgCode = orgCode }, 'house.admin.org.set', { orgCode = orgCode }, 'Org vinculada.')
end)

lib.callback.register('mz_houses:server:admin:setPublic', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local value = parseBool(payload.value)
  if value == nil then
    return { ok = false, error = 'invalid_bool' }
  end

  return adminUpdate(source, payload.code, { public = value }, 'house.admin.public.set', { public = value }, 'Public atualizado.')
end)

lib.callback.register('mz_houses:server:admin:setListable', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end

  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local value = parseBool(payload.value)
  if code == '' or value == nil then
    return { ok = false, error = 'invalid_listable' }
  end

  if value == true then
    local property = MZHousesService.getPublicPropertyInfo(code)
    if not property then
      return { ok = false, error = 'house_not_found' }
    end

    if property.category == 'org' or property.ownerType == 'org' then
      return { ok = false, error = 'org_property_not_listable' }
    end

    if property.category ~= 'residential' or property.ownerType ~= 'player' then
      return { ok = false, error = 'not_residential_player_property' }
    end

    if property.subtype == 'apartment_building' then
      return { ok = false, error = 'building_not_listable_use_unit' }
    end
  end

  return adminUpdate(source, code, {
    realestate = { enabled = false, canBeListed = value, defaultPrice = nil, listingType = 'sale' }
  }, 'house.admin.listable.set', { canBeListed = value }, 'Listable atualizado.')
end)

lib.callback.register('mz_houses:server:admin:setVisibility', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local visibility = trim(payload.visibility)
  if visibility ~= 'auto' and visibility ~= 'public' and visibility ~= 'restricted' and visibility ~= 'hidden' then
    return { ok = false, error = 'invalid_visibility' }
  end

  return adminUpdate(source, payload.code, { visibility = visibility }, 'house.admin.visibility.set', { visibility = visibility }, 'Visibilidade atualizada.')
end)

lib.callback.register('mz_houses:server:admin:setGarageEnabled', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local value = parseBool(payload.value)
  if code == '' or value == nil then
    return { ok = false, error = 'invalid_garage_enabled' }
  end

  local garage, property = currentGarage(code)
  garage.enabled = value
  local features = defaultFeatures(property)
  features.garage = value

  return adminUpdate(source, code, { garage = garage, features = features }, 'house.admin.garage.enable', { enabled = value }, 'Garagem atualizada.')
end)

lib.callback.register('mz_houses:server:admin:setGaragePoint', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local kind = trim(payload.kind)
  if code == '' or (kind ~= 'entry' and kind ~= 'spawn' and kind ~= 'store') then
    return { ok = false, error = 'invalid_garage_point' }
  end

  local garage, property = currentGarage(code)
  garage.enabled = true

  if kind == 'spawn' then
    local spawn = coordsFromPayload(payload.point, true)
    if not spawn then return { ok = false, error = 'invalid_coords' } end
    garage.spawn = spawn
  else
    local point = coordsFromPayload(payload.point, false)
    if not point then return { ok = false, error = 'invalid_coords' } end
    garage[kind] = point
  end

  local features = defaultFeatures(property)
  features.garage = true

  return adminUpdate(source, code, { garage = garage, features = features }, ('house.admin.garage.%s.set'):format(kind), {
    kind = kind,
    point = kind == 'spawn' and vector4Payload(garage.spawn) or vector3Payload(garage[kind])
  }, ('Ponto da garagem atualizado: %s'):format(kind))
end)

lib.callback.register('mz_houses:server:admin:setGarageSlots', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local slots = math.floor(tonumber(payload.slots) or 0)
  local maxSlots = tonumber((MZHousesConfig.Garage or {}).maxSlots) or 20
  if code == '' or slots <= 0 then
    return { ok = false, error = 'invalid_slots' }
  end
  if slots > maxSlots then slots = maxSlots end

  local garage = currentGarage(code)
  garage.enabled = garage.enabled ~= false
  garage.slots = slots

  return adminUpdate(source, code, { garage = garage }, 'house.admin.garage.slots.set', { slots = slots }, 'Slots atualizados.')
end)

lib.callback.register('mz_houses:server:admin:setGarageMode', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local mode = trim(payload.mode)
  if code == '' or (mode ~= 'private' and mode ~= 'shared') then
    return { ok = false, error = 'invalid_mode' }
  end

  local garage = currentGarage(code)
  garage.enabled = garage.enabled ~= false
  garage.mode = mode

  return adminUpdate(source, code, { garage = garage }, 'house.admin.garage.mode.set', { mode = mode }, 'Modo atualizado.')
end)

lib.callback.register('mz_houses:server:admin:setOwner', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.setHouseOwner(payload.code, payload.citizenid, source, {
    initializeTax = payload.initializeTax == true,
    taxDueAt = payload.taxDueAt
  })
  if not ok then return { ok = false, error = result or 'owner_set_failed' } end
  refreshVisibility('admin_menu_owner_set')
  return okWithProperty(result.houseCode, source, result.taxError
    and ('Dono definido; IPTU nao inicializado: ' .. tostring(result.taxError))
    or result.taxInitialized and 'Dono definido e IPTU inicializado.' or 'Dono definido; IPTU nao inicializado por padrao seguro.')
end)

lib.callback.register('mz_houses:server:admin:getTaxStatus', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local state, err = MZHousesTax.getStatus(source, payload.code, true, true)
  if not state then return { ok = false, error = err or 'tax_status_failed' } end
  return { ok = true, tax = state }
end)

lib.callback.register('mz_houses:server:admin:configureTax', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesTax.configure(source, payload.code, {
    taxEnabled = payload.enabled == true,
    taxAmount = payload.amount,
    taxIntervalDays = payload.intervalDays,
    taxGracePeriodDays = payload.gracePeriodDays
  }, { initialize = payload.initialize == true, dueAt = payload.dueAt })
  if not ok then return { ok = false, error = result or 'tax_config_failed' } end
  return { ok = true, tax = result, message = 'Configuracao de IPTU atualizada.' }
end)

lib.callback.register('mz_houses:server:admin:setTaxDueAt', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesTax.setDueAt(source, payload.code, payload.dueAt)
  if not ok then return { ok = false, error = result or 'tax_due_update_failed' } end
  return { ok = true, tax = result, message = 'Vencimento do IPTU ajustado em UTC.' }
end)

lib.callback.register('mz_houses:server:admin:setTaxStatus', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesTax.setStatus(source, payload.code, payload.status)
  if not ok then return { ok = false, error = result or 'tax_status_update_failed' } end
  return { ok = true, tax = result, message = 'Status administrativo do IPTU atualizado; porta inalterada.' }
end)

lib.callback.register('mz_houses:server:admin:configureSale', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesCommerce.configureSale(source, payload.code, {
    saleEnabled = payload.saleEnabled == true,
    saleMode = payload.saleMode,
    salePrice = payload.salePrice
  })
  if not ok then return { ok = false, error = result or 'sale_update_failed' } end
  refreshVisibility('property_sale_configured')
  return okWithProperty(result.houseCode, source, result.commerce.saleEnabled and 'Venda ativada.' or 'Venda desativada.')
end)

lib.callback.register('mz_houses:server:admin:listSaleTargets', function(source)
  if not isAdmin(source) then return denied() end
  local players = {}
  for _, rawSource in ipairs(GetPlayers()) do
    local target = tonumber(rawSource)
    local citizenid = target and MZHousesService.getPlayerCitizenId(target) or nil
    if target and citizenid then
      players[#players + 1] = {
        source = target,
        citizenid = citizenid,
        name = GetPlayerName(target) or ('ID %d'):format(target)
      }
    end
  end
  table.sort(players, function(left, right) return left.source < right.source end)
  return { ok = true, players = players }
end)

lib.callback.register('mz_houses:server:admin:sellProperty', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local target = math.floor(tonumber(payload.targetSource) or 0)
  if target <= 0 or not GetPlayerName(target) then return { ok = false, error = 'buyer_not_online' } end
  local ok, result = MZHousesCommerce.purchase(target, payload.code, {
    adminSale = true,
    actorSource = source
  })
  if not ok then return { ok = false, error = result or 'admin_sale_failed' } end
  refreshVisibility('property_admin_sale_completed')
  return okWithProperty(result.houseCode, source, 'Venda administrativa concluida e cobrada no banco.')
end)

lib.callback.register('mz_houses:server:admin:getTransactions', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  return { ok = true, transactions = MZHousesRepository.listTransactions(payload.code, 30) }
end)

lib.callback.register('mz_houses:server:admin:setOwnerBySource', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local target = math.floor(tonumber(payload.targetSource) or 0)
  if target <= 0 or not GetPlayerName(target) then return { ok = false, error = 'player_not_online' } end
  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(target)
  if not citizenid then return { ok = false, error = citizenErr or 'citizenid_unavailable' } end
  local ok, result = MZHousesService.setHouseOwner(payload.code, citizenid, source, {
    initializeTax = payload.initializeTax == true,
    taxDueAt = payload.taxDueAt
  })
  if not ok then return { ok = false, error = result or 'owner_set_failed' } end
  refreshVisibility('admin_menu_owner_set_source')
  return okWithProperty(result.houseCode, source, result.taxError
    and ('Dono definido; IPTU nao inicializado: ' .. tostring(result.taxError))
    or result.taxInitialized and 'Dono online definido e IPTU inicializado.' or 'Dono online definido; IPTU nao inicializado por padrao seguro.')
end)

lib.callback.register('mz_houses:server:admin:clearOwner', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.clearHouseOwner(payload.code, source)
  if not ok then return { ok = false, error = result or 'owner_clear_failed' } end
  refreshVisibility('admin_menu_owner_clear')
  return okWithProperty(result.houseCode, source, 'Dono removido.')
end)

lib.callback.register('mz_houses:server:admin:giveKey', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.giveHouseKey(payload.code, payload.citizenid, source, payload.role)
  if not ok then return { ok = false, error = result or 'key_give_failed' } end
  refreshVisibility('admin_menu_key_give')
  return okWithProperty(result.houseCode, source, 'Chave entregue.')
end)

lib.callback.register('mz_houses:server:admin:removeKey', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.removeHouseKey(payload.code, payload.citizenid, source)
  if not ok then return { ok = false, error = result or 'key_remove_failed' } end
  refreshVisibility('admin_menu_key_remove')
  return okWithProperty(result.houseCode, source, 'Chave removida.')
end)

lib.callback.register('mz_houses:server:admin:clearKeys', function(source, payload)
  if not isAdmin(source) then return denied() end
  if not allowMutation(source) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  if trim(payload.confirmCode) ~= trim(payload.code) then return { ok = false, error = 'confirmation_mismatch' } end
  local ok, result = MZHousesService.clearHouseKeys(payload.code, source)
  if not ok then return { ok = false, error = result or 'keys_clear_failed' } end
  refreshVisibility('admin_menu_keys_clear')
  return okWithProperty(result.houseCode, source, 'Todas as chaves foram removidas.')
end)

lib.callback.register('mz_houses:server:admin:reload', function(source)
  if not isAdmin(source) then return denied() end
  local ok, err = MZHousesService.reload()
  if not ok then
    return { ok = false, error = err or 'reload_failed' }
  end

  refreshVisibility('admin_menu_reload')
  return {
    ok = true,
    message = ('Casas recarregadas. total=%d'):format(MZHousesService.countHouses())
  }
end)
