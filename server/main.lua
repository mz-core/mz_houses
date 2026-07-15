if type(MZHousesCommerce) ~= 'table'
    or type(MZHousesCommerce.purchase) ~= 'function' then
  error('[mz_houses] MZHousesCommerce.purchase não foi carregado. Verifique commerce.lua e fxmanifest.')
end
if type(MZHousesCommerce.configureSale) ~= 'function'
    or type(MZHousesCommerce.recoverInterruptedTransactions) ~= 'function' then
  error('[mz_houses] API pública de MZHousesCommerce incompleta. Verifique o startup de commerce.lua.')
end
if type(MZHousesApartments) ~= 'table'
    or type(MZHousesApartments.validateIntercomPurchaseContext) ~= 'function' then
  error('[mz_houses] API pública de MZHousesApartments incompleta. Verifique apartments.lua e fxmanifest.')
end
if type(MZHousesTax) ~= 'table'
    or type(MZHousesTax.pay) ~= 'function'
    or type(MZHousesTax.processBatch) ~= 'function'
    or type(MZHousesTax.getStatus) ~= 'function'
    or type(MZHousesTax.listForOwner) ~= 'function'
    or type(MZHousesTax.configure) ~= 'function'
    or type(MZHousesTax.recoverInterruptedPayments) ~= 'function'
    or type(MZHousesTax.notifyOwner) ~= 'function' then
  error('[mz_houses] API publica de MZHousesTax incompleta. Verifique tax.lua e fxmanifest.')
end

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

-- Instancias pertencem ao mz_houses: mz_interiors cria somente o shell local.
-- O bucket e compartilhado por todos os moradores da mesma propriedade e
-- diferente entre propriedades.
local HouseSessions = {}
local HouseBuckets = {}
local NextHouseBucket = 5000
local SensitiveRate = {}

local function allowSensitive(src, action, limit, windowSeconds)
  local key = ('%s:%s'):format(tonumber(src) or 0, action)
  local now = os.time()
  local state = SensitiveRate[key]
  if not state or now - state.startedAt >= windowSeconds then
    SensitiveRate[key] = { startedAt = now, count = 1 }
    return true
  end
  state.count = state.count + 1
  return state.count <= limit
end

local function houseBucket(code)
  if not HouseBuckets[code] then
    HouseBuckets[code] = NextHouseBucket
    NextHouseBucket = NextHouseBucket + 1
  end
  return HouseBuckets[code]
end

local function clearHouseSession(src)
  src = tonumber(src)
  if not src then return end
  HouseSessions[src] = nil
  if GetPlayerName(src) then
    local player = Player(src)
    local state = player and player.state or nil
    if state then state:set('mzHouseCode', nil, true) end

    -- Preview e casa sao mutuamente exclusivos. A guarda evita retirar um
    -- player de um preview valido caso um cleanup atrasado de casa seja recebido.
    if not state or trim(state.mzHousePreview) == '' then
      SetPlayerRoutingBucket(src, 0)
    end
  end
end

local function nearCoords(src, point, maxDistance)
  local ped = GetPlayerPed(src)
  if not ped or ped <= 0 or not point then return false end
  local coords = GetEntityCoords(ped)
  local dx, dy, dz = coords.x - point.x, coords.y - point.y, coords.z - point.z
  return (dx * dx + dy * dy + dz * dz) <= ((maxDistance or 6.0) ^ 2)
end

AddEventHandler('mz_houses:server:propertyAccessChanged', function(code, reason)
  code = trim(code)
  local preserveOccupants = reason == 'owner_key_revoked'
  for src, session in pairs(HouseSessions) do
    if session.code == code and preserveOccupants ~= true then
      local ace = trim(((MZHousesConfig or {}).Admin or {}).ace)
      local admin = ace ~= '' and IsPlayerAceAllowed(src, ace) == true
      local allowed = MZHousesService and MZHousesService.canEnterHouse(src, code, admin)
      if allowed ~= true or reason == 'house.admin.shell.set' or reason == 'house.admin.archive' or reason == 'house.admin.disable' then
        TriggerClientEvent('mz_houses:client:forceExit', src, reason or 'access_changed')
        clearHouseSession(src)
      end
    end
  end
end)

local function debugLog(message, data)
  if MZHousesConfig.Debug ~= true then
    return
  end

  local suffix = data ~= nil and (' | %s'):format(json.encode(data)) or ''
  print(('[mz_houses][server] %s%s'):format(tostring(message), suffix))
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

local function safeJson(value)
  local ok, encoded = pcall(json.encode, value)
  if ok then
    return encoded
  end

  return tostring(encoded)
end

local function featuresToText(features)
  features = type(features) == 'table' and features or {}
  local names = {}

  if features.stash == true then names[#names + 1] = 'stash' end
  if features.wardrobe == true then names[#names + 1] = 'wardrobe' end
  if features.garage == true then names[#names + 1] = 'garage' end
  if features.furniture == true then names[#names + 1] = 'furniture' end

  if #names == 0 then
    return 'none'
  end

  return table.concat(names, ',')
end

local function reply(source, message)
  message = tostring(message or '')
  if tonumber(source) == 0 then
    print(('[mz_houses] %s'):format(message))
    return
  end

  TriggerClientEvent('chat:addMessage', source, {
    color = { 120, 190, 255 },
    args = { 'mz_houses', message }
  })
end

local function refreshVisibilityTargets(reason)
  TriggerClientEvent('mz_houses:client:refreshVisibility', -1, reason or 'server_refresh')
end

local function parseBool(value)
  value = tostring(value or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if value == 'true' or value == '1' or value == 'yes' or value == 'sim' or value == 'on' then
    return true
  end

  if value == 'false' or value == '0' or value == 'no' or value == 'nao' or value == 'off' then
    return false
  end

  return nil
end

local function joinArgs(args, startIndex)
  args = type(args) == 'table' and args or {}
  startIndex = tonumber(startIndex) or 1
  local out = {}
  for index = startIndex, #args do
    out[#out + 1] = tostring(args[index])
  end
  return table.concat(out, ' ')
end

local isHouseAdmin

local function adminUpdate(source, code, patch, action, meta, successMessage)
  if not isHouseAdmin(source) then
    return reply(source, 'Voce nao tem permissao para usar este comando.')
  end

  local ok, result = MZHousesService.updateAdminProperty(source, code, patch, action, meta)
  if not ok then
    return reply(source, ('Erro: %s'):format(tostring(result)))
  end

  refreshVisibilityTargets(action or 'admin_update')
  reply(source, successMessage or ('Imovel atualizado: %s'):format(result.houseCode))
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

local function isAceAllowed(src, ace)
  local sourceId = tonumber(src)
  if not sourceId or sourceId <= 0 then return false end

  ace = trim(ace)
  if ace == '' then return false end

  local allowed = IsPlayerAceAllowed(sourceId, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function getAdminAce()
  local admin = MZHousesConfig.Admin or {}
  local ace = trim(admin.ace)
  if ace == '' then
    ace = 'group.mz_owner'
  end
  return ace
end

local function hasOwnerAce(source)
  local src = tonumber(source) or 0
  if src == 0 then return true end
  return isAceAllowed(src, getAdminAce())
end

isHouseAdmin = function(source)
  local src = tonumber(source) or 0
  if src == 0 then return true end

  local admin = MZHousesConfig.Admin or {}
  if admin.requireAce ~= true then
    return true
  end

  local allowed = hasOwnerAce(src)
  if not allowed then
    debugLog('admin_denied', {
      source = src,
      ace = getAdminAce(),
      allowed = allowed
    })
  end

  return allowed
end

local function canUseDebugCommand(source)
  local commands = MZHousesConfig.Commands or {}
  if commands.requireAce ~= true then
    return true
  end

  local ace = trim(commands.ace)
  if ace == '' then
    return false
  end

  return isAceAllowed(source, ace)
end

local function runAceCheck(source)
  local src = tonumber(source) or 0
  local ace = getAdminAce()
  local configuredAllowed = src == 0 or isAceAllowed(src, ace)
  local ownerAllowed = src == 0 or isAceAllowed(src, 'group.mz_owner')

  reply(src, ('ACE check src=%s ace=%s allowed=%s owner_allowed=%s'):format(
    tostring(src),
    ace,
    tostring(configuredAllowed),
    tostring(ownerAllowed)
  ))

  if src == 0 then
    reply(src, 'Console permitido automaticamente.')
    return
  end

  for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
    reply(src, ('identifier: %s'):format(identifier))
  end
end

local function runHouseGarageExportTest(source, houseCode)
  local src = tonumber(source) or 0
  if not isHouseAdmin(src) then
    return reply(src, 'Voce nao tem permissao para usar este comando.')
  end

  houseCode = trim(houseCode)
  if houseCode == '' then
    return reply(src, 'Uso: /mhouse_testgarage codigo_da_casa')
  end

  local garage, garageErr, code = MZHousesService.getHouseGarageConfig(houseCode)
  if not garage then
    print(('[mz_houses][testgarage] garage config failed house=%s error=%s'):format(
      tostring(houseCode),
      tostring(garageErr)
    ))
    return reply(src, ('Erro config garagem: %s'):format(tostring(garageErr)))
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
    action = 'open'
  }

  local printableDescriptor = {
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
    sessionSeconds = descriptor.sessionSeconds,
    action = descriptor.action
  }

  print(('[mz_houses][testgarage] resource_state mz_garagem=%s'):format(GetResourceState('mz_garagem')))
  print(('[mz_houses][testgarage] descriptor=%s'):format(safeJson(printableDescriptor)))

  local ok, result = pcall(function()
    return exports['mz_garagem']:OpenHouseGarage(src, descriptor)
  end)

  print(('[mz_houses][testgarage] pcall_ok=%s'):format(tostring(ok)))

  if not ok then
    print(('[mz_houses][testgarage] export exception: %s'):format(tostring(result)))
    return reply(src, ('Teste falhou: %s'):format(tostring(result)))
  end

  if type(result) == 'table' then
    print(('[mz_houses][testgarage] result=%s'):format(safeJson(result)))
    if result.ok == true then
      return reply(src, ('Teste OK: garageId=%s'):format(tostring(result.garageId or '')))
    end

    return reply(src, ('Teste retornou erro: %s %s'):format(
      tostring(result.error or 'garage_open_failed'),
      tostring(result.detail or '')
    ))
  end

  print(('[mz_houses][testgarage] result=%s'):format(tostring(result)))
  if result == true then
    return reply(src, 'Teste OK.')
  end

  return reply(src, ('Teste retornou erro: %s'):format(tostring(result)))
end

local function currentServerPoint(source)
  local src = tonumber(source) or 0
  if src <= 0 then
    return nil
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then
    return nil
  end

  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  return vector4(coords.x, coords.y, coords.z, heading)
end

local function createStructuredFromCommand(source, payload)
  if not isHouseAdmin(source) then
    return reply(source, 'Voce nao tem permissao para usar este comando.')
  end

  payload = type(payload) == 'table' and payload or {}
  payload.entrance = currentServerPoint(source)
  if not payload.entrance then
    return reply(source, 'Nao foi possivel ler sua posicao.')
  end

  local ok, result = MZHousesService.createStructuredProperty(source, payload)
  if not ok then
    return reply(source, ('Erro: %s'):format(tostring(result)))
  end

  refreshVisibilityTargets('structured_create_command')
  reply(source, ('Imovel criado: %s'):format(tostring(result.houseCode)))
end

local function registerAdminCommands()
  local admin = MZHousesConfig.Admin or {}

  RegisterCommand(tostring(admin.setOwner or 'mhouse_setowner'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.setHouseOwner(args and args[1], args and args[2], source)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    refreshVisibilityTargets('owner_set')
    reply(source, ('Dono definido: casa=%s owner=%s'):format(result.houseCode, result.owner))
  end, false)

  RegisterCommand(tostring(admin.clearOwner or 'mhouse_clearowner'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.clearHouseOwner(args and args[1], source)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    refreshVisibilityTargets('owner_cleared')
    reply(source, ('Dono removido: casa=%s'):format(result.houseCode))
  end, false)

  RegisterCommand(tostring(admin.giveKey or 'mhouse_givekey'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.giveHouseKey(args and args[1], args and args[2], source, args and args[3])
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    refreshVisibilityTargets('key_given')
    reply(source, ('Chave entregue: casa=%s citizenid=%s role=%s'):format(result.houseCode, result.citizenid, result.role))
  end, false)

  RegisterCommand(tostring(admin.removeKey or 'mhouse_removekey'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.removeHouseKey(args and args[1], args and args[2], source)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    refreshVisibilityTargets('key_removed')
    reply(source, ('Chave removida: casa=%s citizenid=%s'):format(result.houseCode, result.citizenid))
  end, false)

  RegisterCommand(tostring(admin.listKeys or 'mhouse_keys'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.listHouseKeys(args and args[1])
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    reply(source, ('Acesso casa=%s public=%s owner=%s keys=%s database=%s'):format(
      result.houseCode,
      tostring(result.public == true),
      tostring(result.owner or 'nil'),
      #result.keys > 0 and (function()
        local parts = {}; for _, key in ipairs(result.keys) do parts[#parts + 1] = ('%s:%s'):format(key.citizenid, key.role) end
        return table.concat(parts, ', ')
      end)() or 'nenhuma',
      tostring(result.database == true)
    ))
  end, false)

  RegisterCommand(tostring(admin.access or 'mhouse_access'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.listHouseKeys(args and args[1], source, isHouseAdmin(source))
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    reply(source, ('Casa=%s accessMode=%s category=%s subtype=%s ownerType=%s parentCode=%s unitNumber=%s orgCode=%s businessCode=%s features=%s enterAccess=%s featuresAccess=%s public=%s owner=%s key_count=%d currentAccess=%s reason=%s canBeListed=%s listReason=%s database=%s'):format(
      result.houseCode,
      tostring(result.accessMode or 'player'),
      tostring(result.category or 'residential'),
      tostring(result.subtype or 'house'),
      tostring(result.ownerType or 'player'),
      tostring(result.parentCode or 'nil'),
      tostring(result.unitNumber or 'nil'),
      tostring(result.orgCode or 'nil'),
      tostring(result.businessCode or 'nil'),
      featuresToText(result.features),
      tostring(result.enterAccess or 'member'),
      tostring(result.featuresAccess or 'none'),
      tostring(result.public == true),
      tostring(result.owner or 'nil'),
      #result.keys,
      result.currentAccess == nil and 'nil' or tostring(result.currentAccess == true),
      tostring(result.currentAccessReason or 'nil'),
      tostring(result.canBeListed == true),
      tostring(result.canBeListedReason or 'nil'),
      tostring(result.database == true)
    ))
  end, false)

  RegisterCommand(tostring(admin.aceCheck or 'mhouse_acecheck'), function(source)
    runAceCheck(source)
  end, false)

  RegisterCommand(tostring(admin.reload or 'mhouse_reload'), function(source)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, err = MZHousesService.reload()
    if not ok then
      return reply(source, ('Erro ao recarregar casas: %s'):format(tostring(err)))
    end

    refreshVisibilityTargets('reload')
    reply(source, ('Casas recarregadas. total=%d'):format(MZHousesService.countHouses()))
  end, false)

  RegisterCommand('mhouse_create_auto', function(source, args)
    local kind = trim(args and args[1])
    if kind == '' then
      return reply(source, 'Uso: /mhouse_create_auto house|org_base|business [label/subtype]')
    end

    createStructuredFromCommand(source, {
      kind = kind,
      label = joinArgs(args, 2),
      subtype = trim(args and args[2])
    })
  end, false)

  RegisterCommand('mhouse_create_building', function(source, args)
    createStructuredFromCommand(source, {
      kind = 'apartment_building',
      label = joinArgs(args, 4),
      floors = tonumber(args and args[1]) or 1,
      unitsPerFloor = tonumber(args and args[2]) or 1,
      shell = trim(args and args[3]) ~= '' and trim(args and args[3]) or 'apartment_low',
      createUnits = true
    })
  end, false)

  RegisterCommand('mhouse_create_unit', function(source, args)
    local buildingCode = trim(args and args[1])
    local unitNumber = trim(args and args[2])
    if buildingCode == '' or unitNumber == '' then
      return reply(source, 'Uso: /mhouse_create_unit apt_building_000001 305 [shell]')
    end

    createStructuredFromCommand(source, {
      kind = 'apartment_unit',
      parentCode = buildingCode,
      unitNumber = unitNumber,
      shell = trim(args and args[3]) ~= '' and trim(args and args[3]) or 'apartment_low'
    })
  end, false)

  RegisterCommand('mhouse_list_units', function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local buildingCode = trim(args and args[1])
    local result, err = MZHousesService.ListApartmentUnits(source, buildingCode, true)
    if not result then
      return reply(source, ('Erro: %s'):format(tostring(err)))
    end

    local names = {}
    for _, unit in ipairs(result.units or {}) do
      names[#names + 1] = ('%s(%s)'):format(tostring(unit.unitNumber or '?'), tostring(unit.code or '?'))
    end
    reply(source, ('Unidades %s: %s'):format(buildingCode, #names > 0 and table.concat(names, ', ') or 'nenhuma'))
  end, false)

  RegisterCommand('mhouse_building_info', function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local code = trim(args and args[1])
    local property = MZHousesService.getAdminPropertyInfo(code)
    if not property then
      return reply(source, 'Predio nao encontrado.')
    end

    local result = MZHousesService.ListApartmentUnits(source, code, true)
    reply(source, ('Predio=%s label=%s units=%d garage=%s'):format(
      tostring(property.code),
      tostring(property.label),
      type(result) == 'table' and type(result.units) == 'table' and #result.units or 0,
      tostring(type(property.garage) == 'table' and property.garage.enabled == true)
    ))
  end, false)

  RegisterCommand(tostring(admin.archive or 'mhouse_archive'), function(source, args)
    adminUpdate(source, args and args[1], { enabled = false, status = 'archived', visibility = 'hidden' }, 'house.admin.archive', nil, 'Imovel arquivado/desativado.')
  end, false)

  RegisterCommand(tostring(admin.enable or 'mhouse_enable'), function(source, args)
    adminUpdate(source, args and args[1], { enabled = true, status = 'active' }, 'house.admin.enable', nil, 'Imovel ativado.')
  end, false)

  RegisterCommand(tostring(admin.disable or 'mhouse_disable'), function(source, args)
    adminUpdate(source, args and args[1], { enabled = false, status = 'disabled' }, 'house.admin.disable', nil, 'Imovel desativado.')
  end, false)

  RegisterCommand(tostring(admin.setLabel or 'mhouse_setlabel'), function(source, args)
    local label = joinArgs(args, 2)
    if trim(args and args[1]) == '' or trim(label) == '' then
      return reply(source, 'Uso: /mhouse_setlabel codigo Label do Imovel')
    end
    adminUpdate(source, args[1], { label = label }, 'house.admin.label.set', { label = label }, 'Label atualizado.')
  end, false)

  RegisterCommand(tostring(admin.setShell or 'mhouse_setshell'), function(source, args)
    local shell = trim(args and args[2])
    if trim(args and args[1]) == '' or shell == '' then
      return reply(source, 'Uso: /mhouse_setshell codigo shellName')
    end
    adminUpdate(source, args[1], { shell = shell, type = 'shell', interior = {} }, 'house.admin.shell.set', {
      shell = shell,
      resetInteriorOverrides = true
    }, 'Shell atualizado. Overrides internos resetados.')
  end, false)

  RegisterCommand(tostring(admin.setCategory or 'mhouse_setcategory'), function(source, args)
    local code = trim(args and args[1])
    local category = trim(args and args[2])
    local subtype = trim(args and args[3])
    local ownerType = trim(args and args[4])
    if code == '' or category == '' or subtype == '' or ownerType == '' then
      return reply(source, 'Uso: /mhouse_setcategory codigo residential house player')
    end

    local patch = { category = category, subtype = subtype, ownerType = ownerType }
    if category == 'org' or ownerType == 'org' then
      patch.realestate = { enabled = false, canBeListed = false, defaultPrice = nil, listingType = 'sale' }
    end

    adminUpdate(source, code, patch, 'house.admin.category.set', patch, 'Categoria atualizada.')
    if category == 'org' or ownerType == 'org' then
      reply(source, 'Aviso: configure /mhouse_setorg codigo orgCode para acesso de org funcionar.')
    end
  end, false)

  RegisterCommand(tostring(admin.setOrg or 'mhouse_setorg'), function(source, args)
    local code = trim(args and args[1])
    local orgCode = trim(args and args[2])
    if code == '' or orgCode == '' then
      return reply(source, 'Uso: /mhouse_setorg codigo orgCode')
    end
    adminUpdate(source, code, { orgCode = orgCode }, 'house.admin.org.set', { orgCode = orgCode }, 'Org vinculada.')
  end, false)

  RegisterCommand(tostring(admin.setPublic or 'mhouse_setpublic'), function(source, args)
    local value = parseBool(args and args[2])
    if trim(args and args[1]) == '' or value == nil then
      return reply(source, 'Uso: /mhouse_setpublic codigo true|false')
    end
    adminUpdate(source, args[1], { public = value }, 'house.admin.public.set', { public = value }, 'Public atualizado.')
  end, false)

  RegisterCommand(tostring(admin.setListable or 'mhouse_setlistable'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local code = trim(args and args[1])
    local value = parseBool(args and args[2])
    if code == '' or value == nil then
      return reply(source, 'Uso: /mhouse_setlistable codigo true|false')
    end

    if value == true then
      local property = MZHousesService.getAdminPropertyInfo(code)
      if not property then
        return reply(source, 'Imovel nao encontrado.')
      end

      if property.category == 'org' or property.ownerType == 'org' then
        return reply(source, 'Imovel org/base nao pode ser listable por padrao.')
      end

      if property.category ~= 'residential' or property.ownerType ~= 'player' then
        return reply(source, 'Apenas propriedade residencial/player pode ser listable nesta fase.')
      end

      if property.subtype == 'apartment_building' then
        return reply(source, 'Predio nao e listable como unidade comum. Selecione uma unidade.')
      end
    end

    adminUpdate(source, code, {
      realestate = { enabled = false, canBeListed = value, defaultPrice = nil, listingType = 'sale' }
    }, 'house.admin.listable.set', { canBeListed = value }, 'Listable atualizado.')
  end, false)

  RegisterCommand(tostring(admin.setVisibility or 'mhouse_setvisibility'), function(source, args)
    local visibility = trim(args and args[2])
    if trim(args and args[1]) == '' or visibility == '' then
      return reply(source, 'Uso: /mhouse_setvisibility codigo auto|public|restricted|hidden')
    end
    adminUpdate(source, args[1], { visibility = visibility }, 'house.admin.visibility.set', { visibility = visibility }, 'Visibilidade atualizada.')
  end, false)

  RegisterCommand(tostring(admin.garageEnable or 'mhouse_garage_enable'), function(source, args)
    local code = trim(args and args[1])
    local value = parseBool(args and args[2])
    if code == '' or value == nil then
      return reply(source, 'Uso: /mhouse_garage_enable codigo true|false')
    end
    local property = MZHousesService.getAdminPropertyInfo(code)
    local garage = type(property) == 'table' and type(property.garage) == 'table' and property.garage or {}
    garage.enabled = value
    garage.label = garage.label or 'Garagem da Casa'
    garage.mode = garage.mode or 'private'
    garage.slots = tonumber(garage.slots) or tonumber((MZHousesConfig.Garage or {}).defaultSlots) or 2
    garage.storeRadius = tonumber(garage.storeRadius) or tonumber((MZHousesConfig.Garage or {}).storeRadius) or 4.0
    local features = type(property) == 'table' and type(property.features) == 'table' and property.features or {}
    features.garage = value
    adminUpdate(source, code, { garage = garage, features = features }, 'house.admin.garage.enable', { enabled = value }, 'Garagem atualizada.')
  end, false)

  RegisterCommand(tostring(admin.garageSlots or 'mhouse_garage_slots'), function(source, args)
    local code = trim(args and args[1])
    local slots = math.floor(tonumber(args and args[2]) or 0)
    local maxSlots = tonumber((MZHousesConfig.Garage or {}).maxSlots) or 20
    if code == '' or slots <= 0 then
      return reply(source, 'Uso: /mhouse_garage_slots codigo slots')
    end
    if slots > maxSlots then slots = maxSlots end
    local property = MZHousesService.getAdminPropertyInfo(code)
    local garage = type(property) == 'table' and type(property.garage) == 'table' and property.garage or {}
    garage.enabled = garage.enabled ~= false
    garage.slots = slots
    garage.mode = garage.mode or 'private'
    adminUpdate(source, code, { garage = garage }, 'house.admin.garage.slots.set', { slots = slots }, 'Slots da garagem atualizados.')
  end, false)

  RegisterCommand(tostring(admin.garageMode or 'mhouse_garage_mode'), function(source, args)
    local code = trim(args and args[1])
    local mode = trim(args and args[2])
    if code == '' or (mode ~= 'private' and mode ~= 'shared') then
      return reply(source, 'Uso: /mhouse_garage_mode codigo private|shared')
    end
    local property = MZHousesService.getAdminPropertyInfo(code)
    local garage = type(property) == 'table' and type(property.garage) == 'table' and property.garage or {}
    garage.enabled = garage.enabled ~= false
    garage.mode = mode
    adminUpdate(source, code, { garage = garage }, 'house.admin.garage.mode.set', { mode = mode }, 'Modo da garagem atualizado.')
  end, false)

  RegisterCommand(tostring(admin.info or 'mhouse_info'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local code = trim(args and args[1])
    if code == '' then
      return reply(source, 'Uso: /mhouse_info codigo')
    end

    local ok, access = MZHousesService.listHouseKeys(code, source, true)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(access)))
    end

    local property = MZHousesService.getAdminPropertyInfo(code) or {}
    local garage = type(property.garage) == 'table' and property.garage or {}
    local entrance = type(property.entrance) == 'table' and property.entrance or {}
    if property.subtype == 'apartment_building' then
      local result = MZHousesService.ListApartmentUnits(source, code, true)
      local unitCount = type(result) == 'table' and type(result.units) == 'table' and #result.units or 0
      return reply(source, ('Info predio=%s label=%s enabled=%s status=%s units=%d interfone=true garage=%s/%s/%s coords=%.2f,%.2f,%.2f use=/mhouse_list_units %s'):format(
        code,
        tostring(property.label or 'nil'),
        tostring(property.enabled == true),
        tostring(property.status or 'nil'),
        unitCount,
        tostring(garage.enabled == true),
        tostring(garage.mode or 'nil'),
        tostring(garage.slots or 'nil'),
        tonumber(entrance.x) or 0.0,
        tonumber(entrance.y) or 0.0,
        tonumber(entrance.z) or 0.0,
        code
      ))
    end

    reply(source, ('Info casa=%s label=%s enabled=%s status=%s category=%s subtype=%s ownerType=%s parentCode=%s unitNumber=%s orgCode=%s shell=%s visibility=%s public=%s canBeListed=%s reason=%s owner=%s garage=%s/%s/%s coords=%.2f,%.2f,%.2f'):format(
      code,
      tostring(property.label or 'nil'),
      tostring(property.enabled == true),
      tostring(property.status or 'nil'),
      tostring(property.category or 'nil'),
      tostring(property.subtype or 'nil'),
      tostring(property.ownerType or 'nil'),
      tostring(property.parentCode or 'nil'),
      tostring(property.unitNumber or 'nil'),
      tostring(access.orgCode or 'nil'),
      tostring(property.shell or 'nil'),
      tostring(property.visibility or 'auto'),
      tostring(property.public == true),
      tostring(property.canBeListed == true),
      tostring(property.canBeListedReason or 'nil'),
      access.owner and 'sim' or 'nao',
      tostring(garage.enabled == true),
      tostring(garage.mode or 'nil'),
      tostring(garage.slots or 'nil'),
      tonumber(entrance.x) or 0.0,
      tonumber(entrance.y) or 0.0,
      tonumber(entrance.z) or 0.0
    ))
  end, false)

  if MZHousesConfig.Debug == true then
    RegisterCommand('mhouse_testgarage', function(source, args)
      runHouseGarageExportTest(source, args and args[1])
    end, false)
  end
end

lib.callback.register('mz_houses:server:listVisibleHouses', function(source)
  local houses = MZHousesService.listVisibleHouses(source)
  return {
    ok = true,
    houses = houses,
    cacheSeconds = tonumber((MZHousesConfig.Visibility or {}).cacheSeconds) or 5
  }
end)

lib.callback.register('mz_houses:server:getPublicPropertyInfo', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local canSeeEntry = MZHousesService.CanSeeHouse(source, houseCode, 'entry')
  local canSeeGarage = MZHousesService.CanSeeHouse(source, houseCode, 'garage')
  if canSeeEntry ~= true and canSeeGarage ~= true then
    return { ok = false, error = 'not_visible' }
  end

  local property, err = MZHousesService.getPublicPropertyInfo(houseCode)
  if not property then
    return { ok = false, error = err or 'house_not_found' }
  end

  return { ok = true, property = property }
end)

lib.callback.register('mz_houses:server:listProperties', function(source, filters)
  filters = type(filters) == 'table' and filters or {}
  local visible = MZHousesService.listVisibleHouses(source)
  local properties = {}

  for _, visibleHouse in ipairs(visible) do
    local property = MZHousesService.getPublicPropertyInfo(visibleHouse.code)
    if property then
      local include = true

      if filters.category ~= nil and trim(filters.category) ~= '' then
        include = include and property.category == trim(filters.category)
      end

      if filters.subtype ~= nil and trim(filters.subtype) ~= '' then
        include = include and property.subtype == trim(filters.subtype)
      end

      if filters.ownerType ~= nil and trim(filters.ownerType) ~= '' then
        include = include and property.ownerType == trim(filters.ownerType)
      end

      if filters.canBeListed ~= nil then
        include = include and property.canBeListed == (filters.canBeListed == true)
      end

      if filters.enabled ~= nil then
        include = include and property.enabled == (filters.enabled == true)
      end

      if include then
        properties[#properties + 1] = property
      end
    end
  end

  return {
    ok = true,
    properties = properties
  }
end)

lib.callback.register('mz_houses:server:listApartmentUnits', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local buildingCode = trim(payload.buildingCode or payload.houseCode or payload.code)
  local contextType = trim(payload.context)
  if not allowSensitive(source, 'apartment_units', 10, 10) then
    return { ok = false, error = 'rate_limited' }
  end
  if contextType == 'intercom' then
    local contextOk, contextErr = MZHousesApartments.validateIntercomContext(
      source, buildingCode, isHouseAdmin(source)
    )
    if not contextOk then return { ok = false, error = contextErr or 'intercom_unavailable' } end
  end
  if not isHouseAdmin(source) then
    local canSeeEntry = MZHousesService.CanSeeHouse(source, buildingCode, 'entry')
    local canSeeGarage = MZHousesService.CanSeeHouse(source, buildingCode, 'garage')
    if canSeeEntry ~= true and canSeeGarage ~= true then
      return { ok = false, error = 'not_visible' }
    end
  end

  local result, err = MZHousesService.ListApartmentUnits(source, buildingCode, isHouseAdmin(source))
  if not result then
    return { ok = false, error = err or 'apartment_units_failed' }
  end

  MZHousesService.log('house.apartment.intercom.open', buildingCode, source, nil, {
    unitCount = type(result.units) == 'table' and #result.units or 0
  })

  return {
    ok = true,
    building = result.building,
    units = result.units
  }
end)

lib.callback.register('mz_houses:server:resolveEntryContext', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local houseCode = trim(payload.houseCode or payload.code)
  local result, err = MZHousesService.ResolveEntryContext(source, houseCode, isHouseAdmin(source))
  if not result then
    return { ok = false, error = err or 'entry_context_failed' }
  end

  return result
end)

lib.callback.register('mz_houses:server:canPlayerAccessProperty', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, result = MZHousesService.canEnterHouse(source, houseCode, isHouseAdmin(source))
  return {
    ok = true,
    allowed = ok == true,
    reason = ok == true and type(result) == 'table' and result.reason or result
  }
end)

lib.callback.register('mz_houses:server:canPlayerManageProperty', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, reason = MZHousesService.canPlayerManageProperty(source, houseCode, isHouseAdmin(source))
  return {
    ok = true,
    allowed = ok == true,
    reason = reason
  }
end)

lib.callback.register('mz_houses:server:canPropertyBeListed', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, reason = MZHousesService.CanPropertyBeListed(houseCode)
  MZHousesService.log('house.realestate.can_list', houseCode, source, nil, {
    allowed = ok == true,
    reason = reason
  })
  return {
    ok = true,
    allowed = ok == true,
    reason = reason
  }
end)

lib.callback.register('mz_houses:server:canEnterHouse', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, result = MZHousesService.canEnterHouse(source, houseCode, isHouseAdmin(source))
  if not ok then
    return {
      ok = false,
      error = result or 'no_house_access'
    }
  end

  MZHousesService.log('house.open', result and result.houseCode or trim(houseCode), source, nil, {
    reason = result and result.reason or 'allowed'
  })

  local openedCode = result and result.houseCode or trim(houseCode)
  local property = MZHousesService.getPublicPropertyInfo(openedCode)
  if property and property.subtype == 'apartment_unit' then
    MZHousesService.log('house.apartment.unit.enter', openedCode, source, nil, {
      buildingCode = property.parentCode,
      unitNumber = property.unitNumber,
      reason = result and result.reason or 'allowed'
    })
  end

  return {
    ok = true,
    reason = result and result.reason or 'allowed',
    houseCode = result and result.houseCode or trim(houseCode)
  }
end)

lib.callback.register('mz_houses:server:beginEnterHouse', function(source, payload)
  if not allowSensitive(source, 'enter', 5, 10) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode or payload.code)
  if HouseSessions[source] then return { ok = false, error = 'already_inside_house' } end
  local player = Player(source)
  local state = player and player.state or nil
  if state and trim(state.mzHousePreview) ~= '' then
    return { ok = false, error = 'preview_active' }
  end

  local allowed, access = MZHousesService.canEnterHouse(source, code, isHouseAdmin(source))
  if not allowed then return { ok = false, error = access or 'no_house_access' } end

  local context, contextErr = MZHousesService.ResolveEntryContext(source, code, isHouseAdmin(source))
  if not context or context.ok ~= true then
    return { ok = false, error = contextErr or (context and context.reason) or 'invalid_entry' }
  end
  if not nearCoords(source, context.entrance, 7.5) then
    MZHousesService.log('house.enter.denied', code, source, nil, { reason = 'too_far_from_entrance' })
    return { ok = false, error = 'too_far_from_entrance' }
  end

  local bucket = houseBucket(code)
  local entrySpawn, entrySpawnErr = MZHousesService.getEntrySpawnConfig(code)
  if not entrySpawn then return { ok = false, error = entrySpawnErr or 'invalid_entry_spawn' } end
  local accessReason = type(access) == 'table' and access.reason or access
  local isGuest = accessReason == 'public_unlocked'
  if isGuest then
    -- Uma porta aberta não transforma owner/chave/gang/job autorizados em
    -- guest. Guest é somente quem depende exclusivamente do unlocked.
    local inherited = MZHousesService.revalidateInheritedHouseAccess(source, code, isHouseAdmin(source))
    if inherited == true then isGuest = false end
  end
  HouseSessions[source] = {
    code = code, bucket = bucket, enteredAt = os.time(), confirmed = false,
    accessReason = accessReason, isGuest = isGuest
  }
  SetPlayerRoutingBucket(source, bucket)
  if player and player.state then player.state:set('mzHouseCode', code, true) end
  return {
    ok = true,
    houseCode = code,
    bucket = bucket,
    reason = accessReason,
    entrySpawn = entrySpawn
  }
end)

lib.callback.register('mz_houses:server:confirmEnterHouse', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local session = HouseSessions[source]
  if not session or session.code ~= trim(payload.houseCode or payload.code) then
    clearHouseSession(source)
    return { ok = false, error = 'invalid_house_session' }
  end
  session.confirmed = true
  session.confirmedAt = os.time()
  return { ok = true }
end)

CreateThread(function()
  while true do
    Wait(5000)
    local now = os.time()
    for src, session in pairs(HouseSessions) do
      if session.confirmed ~= true and now - (session.enteredAt or now) > 20 then
        clearHouseSession(src)
      end
    end
  end
end)

lib.callback.register('mz_houses:server:leaveHouse', function(source)
  clearHouseSession(source)
  return { ok = true }
end)

RegisterNetEvent('mz_houses:server:abortEnterHouse', function()
  clearHouseSession(source)
end)

AddEventHandler('playerDropped', function()
  HouseSessions[source] = nil
  local prefix = ('%s:'):format(tonumber(source) or 0)
  for key in pairs(SensitiveRate) do
    if key:sub(1, #prefix) == prefix then SensitiveRate[key] = nil end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() and resource ~= 'mz_interiors' then return end
  for src in pairs(HouseSessions) do clearHouseSession(src) end
end)

local function nearPropertyDoor(source, code)
  local session = HouseSessions[source]
  if session and session.code == code then return true end
  local context = MZHousesService.ResolveEntryContext(source, code, isHouseAdmin(source))
  return type(context) == 'table' and nearCoords(source, context.entrance, 7.5)
end

local function confirmedInteriorFeatureSession(source, houseCode)
  local code = trim(houseCode)
  local session = HouseSessions[source]
  if not session or session.code ~= code then return nil, 'not_inside_property' end
  if session.confirmed ~= true then return nil, 'house_session_not_confirmed' end
  return {
    code = code,
    confirmed = true,
    kind = 'interior',
    isGuest = session.isGuest == true
  }
end

local function garageFeatureSession(source, houseCode, action)
  local code = trim(houseCode)
  action = trim(action):lower()
  if action ~= 'open' and action ~= 'store' then return nil, 'invalid_garage_action' end

  local current = HouseSessions[source]
  if current then
    if current.code ~= code then return nil, 'wrong_property_session' end
    if current.confirmed ~= true then return nil, 'house_session_not_confirmed' end
    return {
      code = code,
      confirmed = true,
      kind = 'interior',
      isGuest = current.isGuest == true
    }
  end

  local player = Player(source)
  local state = player and player.state or nil
  if state and trim(state.mzHousePreview) ~= '' then return nil, 'preview_active' end

  local garage, garageErr = MZHousesService.getHouseGarageConfig(code)
  if not garage then return nil, garageErr or 'garage_disabled' end
  local point = action == 'store' and garage.store or garage.entry
  local radius = action == 'store' and garage.storeRadius or garage.entryRadius
  if not nearCoords(source, point, math.max(tonumber(radius) or 2.0, 2.0) + 1.5) then
    return nil, 'too_far_from_garage'
  end
  return {
    code = code,
    confirmed = true,
    kind = 'external_garage',
    isGuest = false
  }
end

lib.callback.register('mz_houses:server:getFeatureContext', function(source, payload)
  if not allowSensitive(source, 'feature_context', 20, 10) then return { ok = false, error = 'rate_limited' } end
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local session, sessionErr = confirmedInteriorFeatureSession(source, houseCode)
  if not session then return { ok = false, error = sessionErr } end
  session.silent = true

  local result = {}
  for _, featureName in ipairs({ 'stash', 'wardrobe', 'garage' }) do
    local allowed = MZHousesService.CanAccessPropertyFeature(
      source,
      session.code,
      featureName,
      session,
      isHouseAdmin(source)
    )
    result[featureName] = allowed == true
  end
  return { ok = true, houseCode = session.code, features = result }
end)

lib.callback.register('mz_houses:server:getDoorContext', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode or payload.code)
  if code == '' or not nearPropertyDoor(source, code) then return { ok = false, error = 'too_far_from_entrance' } end
  local door, doorErr = MZHousesService.getDoorState(code)
  if not door then return { ok = false, error = doorErr or 'house_not_found' } end
  local allowed, control = MZHousesService.canControlDoor(source, code, isHouseAdmin(source))
  return { ok = true, houseCode = code, state = door.state, canControl = allowed == true, controlReason = allowed and control.reason or nil }
end)

lib.callback.register('mz_houses:server:listMyPropertyTaxes', function(source)
  if not allowSensitive(source, 'tax_list', 10, 10) then return { ok = false, error = 'rate_limited' } end
  local taxes, err = MZHousesTax.listForOwner(source)
  if not taxes then return { ok = false, error = err or 'tax_list_failed' } end
  return { ok = true, taxes = taxes }
end)

lib.callback.register('mz_houses:server:getPropertyTaxStatus', function(source, payload)
  if not allowSensitive(source, 'tax_status', 10, 10) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local state, err = MZHousesTax.getStatus(source, payload.houseCode or payload.code, isHouseAdmin(source), true)
  if not state then return { ok = false, error = err or 'tax_status_failed' } end
  return { ok = true, tax = state }
end)

lib.callback.register('mz_houses:server:payPropertyTax', function(source, payload)
  if not allowSensitive(source, 'tax_pay', 3, 10) then return { ok = false, reason = 'rate_limited', message = 'Aguarde antes de tentar novamente.' } end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesTax.pay(source, payload.houseCode or payload.code)
  if not ok then
    local messages = {
      insufficient_funds = 'Saldo bancario insuficiente.',
      not_enough_money = 'Saldo bancario insuficiente.',
      tax_not_due_yet = 'O IPTU ainda nao esta dentro da janela de pagamento.',
      tax_payment_in_progress = 'Ja existe um pagamento em andamento.',
      tax_payment_manual_review = 'Existe um pagamento pendente de revisao administrativa.',
      tax_owner_required = 'Somente o proprietario pode pagar este IPTU.',
      tax_not_initialized = 'O IPTU ainda nao foi inicializado.',
      tax_blocked = 'O IPTU esta bloqueado administrativamente.',
      tax_state_changed = 'A situacao do IPTU mudou; o valor debitado foi devolvido.',
      financial_service_unavailable = 'O servico bancario esta indisponivel.',
      core_unavailable = 'O servico bancario esta indisponivel.',
      money_export_failed = 'Nao foi possivel consultar o servico bancario.',
      payment_failed = 'O banco recusou o pagamento.',
      tax_payment_internal_error = 'Ocorreu um erro interno ao processar o IPTU.'
    }
    return { ok = false, reason = result or 'tax_payment_failed', message = messages[result] or 'Nao foi possivel pagar o IPTU.' }
  end
  return {
    ok = true, houseCode = result.houseCode, paymentId = result.paymentId,
    amount = result.amount, status = result.status, nextDueAt = result.nextDueAt,
    message = 'IPTU pago pelo banco.'
  }
end)

RegisterNetEvent('mz_houses:server:taxPlayerReady', function()
  local src = source
  if allowSensitive(src, 'tax_notice', 2, 60) then MZHousesTax.notifyOwner(src) end
end)

lib.callback.register('mz_houses:server:setDoorState', function(source, payload)
  if not allowSensitive(source, 'door', 10, 10) then return { ok = false, error = 'rate_limited' } end
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode or payload.code)
  if code == '' or not nearPropertyDoor(source, code) then return { ok = false, error = 'too_far_from_entrance' } end
  local ok, result = MZHousesService.setDoorState(source, code, payload.state, isHouseAdmin(source))
  if not ok then return { ok = false, error = result or 'door_update_failed' } end
  return { ok = true, houseCode = result.houseCode, state = result.state }
end)

local PURCHASE_MESSAGES = {
  rate_limited = { 'rate_limited', 'Aguarde antes de tentar comprar novamente.' },
  invalid_house = { 'invalid_property', 'Propriedade inválida.' },
  must_purchase_at_entrance = { 'invalid_purchase_context', 'A compra deve ser feita na entrada da propriedade.' },
  preview_active = { 'invalid_purchase_context', 'Saia do preview antes de comprar.' },
  too_far_from_entrance = { 'too_far_from_property', 'Aproxime-se da entrada para comprar.' },
  not_enough_money = { 'insufficient_funds', 'Saldo bancário insuficiente.' },
  property_already_owned = { 'property_already_sold', 'Esta propriedade já possui proprietário.' },
  purchase_conflict = { 'property_already_sold', 'A propriedade foi comprada por outro jogador.' },
  property_not_for_sale = { 'sale_unavailable', 'Esta propriedade não está mais à venda.' },
  sale_mode_not_allowed = { 'sale_unavailable', 'A compra direta não está disponível.' },
  invalid_sale_price = { 'invalid_price', 'O preço da propriedade é inválido.' },
  invalid_sale_mode = { 'sale_unavailable', 'O modo de venda é inválido.' },
  property_not_active = { 'property_unavailable', 'A propriedade não está ativa.' },
  property_not_residential_sale = { 'property_unavailable', 'Esta propriedade não aceita venda residencial.' },
  property_not_individually_sellable = { 'property_unavailable', 'Esta propriedade não pode ser vendida individualmente.' },
  property_not_owner_policy = { 'property_unavailable', 'A política desta propriedade não permite venda residencial.' },
  purchase_in_progress = { 'purchase_in_progress', 'Já existe uma compra em andamento para esta propriedade.' },
  purchase_financial_state_pending = { 'financial_review_required', 'Existe uma transação pendente de revisão para esta propriedade.' },
  purchase_manual_review = { 'financial_review_required', 'Existe uma transação pendente de revisão para esta propriedade.' },
  player_not_loaded = { 'player_not_ready', 'Os dados do jogador ainda não estão disponíveis.' },
  core_unavailable = { 'financial_service_unavailable', 'O serviço bancário está indisponível.' },
  money_export_failed = { 'financial_service_unavailable', 'Não foi possível consultar o serviço bancário.' },
  payment_failed = { 'payment_failed', 'O banco recusou o pagamento.' },
  property_admin_mutation_in_progress = { 'property_busy', 'Esta unidade está em uma operação administrativa.' },
  purchase_unit_requires_intercom_context = { 'invalid_purchase_context', 'A compra desta unidade deve ser feita pelo interfone do prédio.' },
  too_far_from_intercom = { 'too_far_from_property', 'Aproxime-se do interfone para comprar.' },
  unit_not_in_building = { 'invalid_purchase_context', 'A unidade não pertence a este prédio.' },
  intercom_disabled = { 'intercom_unavailable', 'O interfone deste prédio está desativado.' },
  building_blocked = { 'intercom_unavailable', 'O acesso deste prédio está bloqueado.' },
  invalid_building = { 'invalid_purchase_context', 'Prédio inválido.' },
  building_not_found = { 'invalid_purchase_context', 'Prédio não encontrado.' },
  not_apartment_building = { 'invalid_purchase_context', 'O contexto informado não é um prédio de apartamentos.' },
  building_not_active = { 'property_unavailable', 'O prédio não está ativo.' },
  building_not_visible = { 'intercom_unavailable', 'O interfone não está disponível para este jogador.' },
  unit_not_found = { 'invalid_property', 'Unidade não encontrada.' },
  unit_not_active = { 'property_unavailable', 'A unidade não está ativa.' }
}

local function purchaseFailure(reason)
  reason = trim(reason)
  local mapped = PURCHASE_MESSAGES[reason]
  if mapped then return { ok = false, reason = mapped[1], message = mapped[2] } end
  return { ok = false, reason = 'purchase_internal_error', message = 'Não foi possível concluir a compra.' }
end

local function purchaseCallbackTraceback(err)
  if type(debug) == 'table' and type(debug.traceback) == 'function' then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

local function purchaseCallbackDebug(stage, source, code, detail)
  if MZHousesConfig.CommerceDebug ~= true and MZHousesConfig.Debug ~= true then return end
  print(('[mz_houses][purchase-callback] stage=%s source=%s house=%s detail=%s'):format(
    tostring(stage), tostring(tonumber(source) or 0), tostring(code or ''), tostring(detail or '-')
  ))
end

lib.callback.register('mz_houses:server:purchaseProperty', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode or payload.code)
  pcall(purchaseCallbackDebug, 'callback_received', source, code)

  local protected, response = xpcall(function()
    if not allowSensitive(source, 'purchase', 3, 10) then return purchaseFailure('rate_limited') end
    if code == '' then return purchaseFailure('invalid_house') end
    if HouseSessions[source] then return purchaseFailure('must_purchase_at_entrance') end
    local player = Player(source)
    if player and player.state and trim(player.state.mzHousePreview) ~= '' then
      return purchaseFailure('preview_active')
    end
    local targetHouse = MZHousesRepository.getHouseByCode(code)
    local targetProperty = MZHousesRepository.normalizePropertyFields(targetHouse or {})
    if targetProperty.subtype == 'apartment_unit' then
      return purchaseFailure('purchase_unit_requires_intercom_context')
    end
    if not nearPropertyDoor(source, code) then return purchaseFailure('too_far_from_entrance') end

    local purchased, result = MZHousesCommerce.purchase(source, code)
    if not purchased then return purchaseFailure(result or 'purchase_failed') end
    local refreshed = pcall(refreshVisibilityTargets, 'property_purchase_completed')
    if not refreshed then pcall(purchaseCallbackDebug, 'visibility_refresh_failed', source, code, result.transactionId) end
    return {
      ok = true,
      houseCode = result.houseCode,
      transactionId = result.transactionId,
      message = 'Compra concluída com sucesso.'
    }
  end, purchaseCallbackTraceback)

  if not protected then
    pcall(purchaseCallbackDebug, 'exception_captured', source, code, 'purchase_internal_error')
    pcall(function()
      MZHousesService.log('property.purchase.callback.exception', code, source, nil, { reason = 'purchase_internal_error' })
    end)
    print(('[mz_houses][purchase-callback] exception house=%s source=%s error=%s'):format(
      tostring(code), tostring(source), tostring(response)
    ))
    response = purchaseFailure('purchase_internal_error')
  end

  if type(response) ~= 'table' then response = purchaseFailure('purchase_internal_error') end
  pcall(purchaseCallbackDebug, 'response_sent', source, code, response.reason or response.transactionId)
  return response
end)

lib.callback.register('mz_houses:server:purchaseApartmentUnit', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local buildingCode = trim(payload.buildingCode)
  local unitCode = trim(payload.unitCode or payload.houseCode or payload.code)
  local protected, response = xpcall(function()
    if not allowSensitive(source, 'purchase_intercom', 3, 10) then return purchaseFailure('rate_limited') end
    if HouseSessions[source] then return purchaseFailure('must_purchase_at_entrance') end
    local player = Player(source)
    if player and player.state and trim(player.state.mzHousePreview) ~= '' then
      return purchaseFailure('preview_active')
    end
    local contextOk, context = MZHousesApartments.validateIntercomPurchaseContext(
      source, buildingCode, unitCode, isHouseAdmin(source)
    )
    if not contextOk then return purchaseFailure(context or 'invalid_purchase_context') end
    MZHousesService.log('building.unit.purchase.started', unitCode, source, nil, {
      buildingCode = buildingCode, unitNumber = context.unitNumber
    })
    local purchased, result = MZHousesCommerce.purchase(source, unitCode)
    if not purchased then
      MZHousesService.log('building.unit.purchase.failed', unitCode, source, nil, {
        buildingCode = buildingCode, reason = result
      })
      return purchaseFailure(result or 'purchase_failed')
    end
    pcall(refreshVisibilityTargets, 'building_unit_purchase_completed')
    MZHousesService.log('building.unit.purchase.completed', unitCode, source, nil, {
      buildingCode = buildingCode, transactionId = result.transactionId
    })
    return {
      ok = true,
      houseCode = result.houseCode,
      buildingCode = buildingCode,
      transactionId = result.transactionId,
      message = 'Compra da unidade concluída com sucesso.'
    }
  end, purchaseCallbackTraceback)
  if not protected then
    print(('[mz_houses][apartment-purchase] exception building=%s unit=%s source=%s error=%s'):format(
      buildingCode, unitCode, tostring(source), tostring(response)
    ))
    response = purchaseFailure('purchase_internal_error')
  end
  if type(response) ~= 'table' then response = purchaseFailure('purchase_internal_error') end
  return response
end)

lib.callback.register('mz_houses:server:openHouseStash', function(source, payload)
  if not allowSensitive(source, 'stash', 10, 10) then return { ok = false, error = 'rate_limited' } end
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local session, sessionErr = confirmedInteriorFeatureSession(source, houseCode)
  if not session then return { ok = false, error = sessionErr } end
  local ok, result, detail = MZHousesService.openHouseStash(source, houseCode, isHouseAdmin(source), session)
  if not ok then
    return {
      ok = false,
      error = result or 'stash_open_failed',
      detail = detail
    }
  end

  return {
    ok = true,
    houseCode = result.houseCode,
    stashId = result.stashId,
    label = result.label,
    slots = result.slots,
    weight = result.weight,
    inventoryTarget = result.inventoryTarget
  }
end)

lib.callback.register('mz_houses:server:openHouseWardrobe', function(source, payload)
  if not allowSensitive(source, 'wardrobe', 10, 10) then return { ok = false, error = 'rate_limited' } end
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local session, sessionErr = confirmedInteriorFeatureSession(source, houseCode)
  if not session then return { ok = false, error = sessionErr } end
  local ok, result, detail = MZHousesService.openHouseWardrobe(source, houseCode, isHouseAdmin(source), session)
  if not ok then
    return {
      ok = false,
      error = result or 'wardrobe_open_failed',
      detail = detail
    }
  end

  return {
    ok = true,
    houseCode = result.houseCode,
    label = result.label,
    resource = result.resource,
    shopId = result.shopId
  }
end)

lib.callback.register('mz_houses:server:openHouseGarage', function(source, payload)
  if not allowSensitive(source, 'garage', 10, 10) then return { ok = false, error = 'rate_limited' } end
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local action = type(payload) == 'table' and payload.action or 'open'
  local session, sessionErr = garageFeatureSession(source, houseCode, action)
  if not session then return { ok = false, error = sessionErr } end
  local ok, result, detail = MZHousesService.openHouseGarage(source, houseCode, action, isHouseAdmin(source), session)
  if not ok then
    return {
      ok = false,
      error = result or 'garage_open_failed',
      detail = detail
    }
  end

  return {
    ok = true,
    houseCode = result.houseCode,
    garageId = result.garageId,
    label = result.label,
    action = result.action
  }
end)

RegisterNetEvent('mz_houses:server:runCommand', function(action, args)
  local src = source

  if not canUseDebugCommand(src) then
    debugLog('command_denied', {
      source = src,
      action = action
    })
    TriggerClientEvent('mz_houses:client:commandDenied', src, 'sem_permissao')
    return
  end

  TriggerClientEvent('mz_houses:client:runCommand', src, trim(action), type(args) == 'table' and args or {})
end)

RegisterNetEvent('mz_houses:server:createAdminProperty', function(payload)
  local src = source
  if not isHouseAdmin(src) then
    return reply(src, 'Voce nao tem permissao para usar este comando.')
  end

  payload = type(payload) == 'table' and payload or {}
  payload.entrance = coordsFromPayload(payload.entrance or payload, true)

  local ok, result = MZHousesService.createAdminProperty(src, payload)
  if not ok then
    return reply(src, ('Erro: %s'):format(tostring(result)))
  end

  refreshVisibilityTargets('house_admin_create')
  reply(src, ('Imovel criado: %s - %s'):format(result.houseCode, result.label))
end)

RegisterNetEvent('mz_houses:server:setAdminEntrance', function(payload)
  local src = source
  local code = trim(type(payload) == 'table' and payload.code or '')
  local entrance = coordsFromPayload(type(payload) == 'table' and payload.entrance or nil, true)
  if code == '' or not entrance then
    return reply(src, 'Uso: /mhouse_setentrance codigo')
  end

  adminUpdate(src, code, { entrance = entrance }, 'house.admin.entrance.set', {
    entrance = vector4Payload(entrance)
  }, 'Entrada atualizada.')
end)

RegisterNetEvent('mz_houses:server:setAdminGaragePoint', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local kind = trim(payload.kind)
  if code == '' or (kind ~= 'entry' and kind ~= 'spawn' and kind ~= 'store') then
    return reply(src, 'Uso: /mhouse_garage_entry_here|spawn_here|store_here codigo')
  end

  local property = MZHousesService.getAdminPropertyInfo(code)
  local garage = type(property) == 'table' and type(property.garage) == 'table' and property.garage or {}
  garage.enabled = garage.enabled ~= false
  garage.label = garage.label or 'Garagem da Casa'
  garage.mode = garage.mode or 'private'
  garage.slots = tonumber(garage.slots) or tonumber((MZHousesConfig.Garage or {}).defaultSlots) or 2
  garage.storeRadius = tonumber(garage.storeRadius) or tonumber((MZHousesConfig.Garage or {}).storeRadius) or 4.0

  if kind == 'spawn' then
    local spawn = coordsFromPayload(payload.point, true)
    if not spawn then return reply(src, 'Coordenada invalida.') end
    garage.spawn = spawn
  else
    local point = coordsFromPayload(payload.point, false)
    if not point then return reply(src, 'Coordenada invalida.') end
    garage[kind] = point
  end

  local features = type(property) == 'table' and type(property.features) == 'table' and property.features or {}
  features.garage = true
  adminUpdate(src, code, { garage = garage, features = features }, ('house.admin.garage.%s.set'):format(kind), {
    kind = kind
  }, ('Ponto da garagem atualizado: %s'):format(kind))
end)

exports('CanEnterHouse', function(source, houseCode)
  return MZHousesService.canEnterHouse(source, houseCode, isHouseAdmin(source))
end)

exports('GetPropertyByCode', function(code)
  return MZHousesService.GetPropertyByCode(code)
end)

exports('GetPublicPropertyInfo', function(code)
  return MZHousesService.getPublicPropertyInfo(code)
end)

exports('ListProperties', function(filters)
  return MZHousesService.ListProperties(filters)
end)

exports('CanPlayerAccessProperty', function(source, code)
  return MZHousesService.canEnterHouse(source, code, isHouseAdmin(source))
end)

exports('CanPlayerManageProperty', function(source, code)
  return MZHousesService.canPlayerManageProperty(source, code, isHouseAdmin(source))
end)

exports('GetPropertyAccessPolicy', function(code)
  local property, err = MZHousesService.getAdminPropertyInfo(code)
  if not property then return nil, err end
  return property.accessPolicy
end)

exports('SetPropertyAccessPolicy', function(code, policy, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesService.updateAdminProperty(actorSource, code, { accessPolicy = policy }, 'property.access.policy.set', {
    mode = type(policy) == 'table' and policy.mode or nil
  })
end)

exports('GetPropertyDoorState', function(code)
  return MZHousesService.getDoorState(code)
end)

exports('CanControlPropertyDoor', function(source, code)
  return MZHousesService.CanControlDoor(source, code, isHouseAdmin(source))
end)

exports('CanControlDoor', function(source, code)
  return MZHousesService.CanControlDoor(source, code, isHouseAdmin(source))
end)

exports('SetPropertyDoorState', function(code, state, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesService.setDoorState(actorSource, code, state, true)
end)

exports('CanPropertyBeListed', function(code)
  return MZHousesService.CanPropertyBeListed(code)
end)

exports('SetPropertyOwner', function(code, citizenid, actorSource, reason, meta)
  local ok, result = MZHousesService.SetPropertyOwner(code, citizenid, actorSource, reason, meta)
  if ok then refreshVisibilityTargets('property_owner_set') end
  return ok, result
end)

exports('ClearPropertyOwner', function(code, actorSource, reason, meta)
  local ok, result = MZHousesService.ClearPropertyOwner(code, actorSource, reason, meta)
  if ok then refreshVisibilityTargets('property_owner_cleared') end
  return ok, result
end)

exports('GivePropertyKey', function(code, citizenid, actorSource, reason, meta, role)
  local ok, result = MZHousesService.GivePropertyKey(code, citizenid, actorSource, reason, meta, role)
  if ok then refreshVisibilityTargets('property_key_given') end
  return ok, result
end)

exports('RemovePropertyKey', function(code, citizenid, actorSource, reason, meta)
  local ok, result = MZHousesService.RemovePropertyKey(code, citizenid, actorSource, reason, meta)
  if ok then refreshVisibilityTargets('property_key_removed') end
  return ok, result
end)

exports('SetHouseOwner', function(houseCode, citizenid, actorSource, reason, meta)
  local ok, result = MZHousesService.SetPropertyOwner(houseCode, citizenid, actorSource, reason, meta)
  if ok then refreshVisibilityTargets('house_owner_set') end
  return ok, result
end)

exports('ClearHouseOwner', function(houseCode, actorSource, reason, meta)
  local ok, result = MZHousesService.ClearPropertyOwner(houseCode, actorSource, reason, meta)
  if ok then refreshVisibilityTargets('house_owner_cleared') end
  return ok, result
end)

exports('GiveHouseKey', function(houseCode, citizenid, actorSource, reason, meta, role)
  local ok, result = MZHousesService.GivePropertyKey(houseCode, citizenid, actorSource, reason, meta, role)
  if ok then refreshVisibilityTargets('house_key_given') end
  return ok, result
end)

exports('RemoveHouseKey', function(houseCode, citizenid, actorSource, reason, meta)
  local ok, result = MZHousesService.RemovePropertyKey(houseCode, citizenid, actorSource, reason, meta)
  if ok then refreshVisibilityTargets('house_key_removed') end
  return ok, result
end)

exports('GetHouseAccess', function(houseCode)
  return MZHousesService.getPublicPropertyInfo(houseCode)
end)

exports('OpenHouseStash', function(source, houseCode)
  local session, sessionErr = confirmedInteriorFeatureSession(source, houseCode)
  if not session then return false, sessionErr end
  return MZHousesService.openHouseStash(source, houseCode, isHouseAdmin(source), session)
end)

exports('OpenHouseWardrobe', function(source, houseCode)
  local session, sessionErr = confirmedInteriorFeatureSession(source, houseCode)
  if not session then return false, sessionErr end
  return MZHousesService.openHouseWardrobe(source, houseCode, isHouseAdmin(source), session)
end)

exports('OpenHouseGarage', function(source, houseCode, action)
  local session, sessionErr = garageFeatureSession(source, houseCode, action)
  if not session then return false, sessionErr end
  return MZHousesService.openHouseGarage(source, houseCode, action, isHouseAdmin(source), session)
end)

exports('CanAccessPropertyFeature', function(source, houseCode, featureName)
  local session, sessionErr
  if trim(featureName):lower() == 'garage' then
    session, sessionErr = garageFeatureSession(source, houseCode, 'open')
  else
    session, sessionErr = confirmedInteriorFeatureSession(source, houseCode)
  end
  if not session then return false, sessionErr end
  return MZHousesService.CanAccessPropertyFeature(source, houseCode, featureName, session, isHouseAdmin(source))
end)

-- API administrativa. Todos os exports mutaveis exigem um actorSource admin.
exports('CreateProperty', function(payload, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  local ok, result = MZHousesService.createAdminProperty(actorSource, payload)
  if ok then refreshVisibilityTargets('property_created') end
  return ok, result
end)

exports('UpdateProperty', function(code, patch, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  local ok, result = MZHousesService.updateAdminProperty(actorSource, code, patch, 'house.admin.export.update', patch)
  if ok then refreshVisibilityTargets('property_updated') end
  return ok, result
end)

exports('DeleteProperty', function(code, actorSource, confirmCode)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  if trim(code) == '' or trim(confirmCode) ~= trim(code) then return false, 'confirmation_mismatch' end
  local ok, result = MZHousesService.updateAdminProperty(actorSource, code, {
    enabled = false, status = 'archived', visibility = 'hidden'
  }, 'house.admin.archive', { softDelete = true })
  if ok then refreshVisibilityTargets('property_archived') end
  return ok, result
end)

exports('SetPropertyEntrance', function(code, entrance, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesService.updateAdminProperty(actorSource, code, { entrance = entrance }, 'house.admin.entrance.set')
end)

exports('SetPropertyInterior', function(code, shell, interior, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesService.updateAdminProperty(actorSource, code, { shell = shell, interior = interior }, 'house.admin.interior.set')
end)

exports('SetPropertyGarage', function(code, garage, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesService.updateAdminProperty(actorSource, code, { garage = garage }, 'house.admin.garage.set')
end)

exports('SetPropertyEnabled', function(code, enabled, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesService.updateAdminProperty(actorSource, code, {
    enabled = enabled == true, status = enabled == true and 'active' or 'disabled'
  }, 'house.admin.enabled.set')
end)

exports('ListPropertyKeys', function(code, actorSource)
  if not isHouseAdmin(actorSource) then return nil, 'admin_required' end
  return MZHousesService.listHouseKeys(code, actorSource, true)
end)

exports('SetPropertySale', function(code, commerce, actorSource)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  local ok, result = MZHousesCommerce.configureSale(actorSource, code, commerce)
  if ok then refreshVisibilityTargets('property_sale_configured') end
  return ok, result
end)

exports('PurchaseProperty', function(source, code)
  source = tonumber(source)
  if not source or HouseSessions[source] or not nearPropertyDoor(source, trim(code)) then
    return false, 'too_far_from_entrance'
  end
  local house = MZHousesRepository.getHouseByCode(code)
  local property = MZHousesRepository.normalizePropertyFields(house or {})
  if property.subtype == 'apartment_unit' then
    return false, 'purchase_unit_requires_intercom_context'
  end
  local ok, result = MZHousesCommerce.purchase(source, code)
  if ok then refreshVisibilityTargets('property_purchase_completed') end
  return ok, result
end)

exports('GetPropertyTaxStatus', function(code, source)
  source = tonumber(source)
  if not source or source <= 0 then return nil, 'source_required' end
  return MZHousesTax.getStatus(source, code, isHouseAdmin(source), true)
end)

exports('PayPropertyTax', function(source, code)
  return MZHousesTax.pay(source, code)
end)

exports('ConfigurePropertyTax', function(code, tax, actorSource, options)
  if not isHouseAdmin(actorSource) then return false, 'admin_required' end
  return MZHousesTax.configure(actorSource, code, tax, options)
end)

CreateThread(function()
  if MZHousesConfig.Debug == true then
    print('[mz_houses] house garage integration debug loaded')
  end

  local booted = MZHousesService.bootstrap()
  if booted == true then
    local recovered, recoverErr = pcall(MZHousesCommerce.recoverInterruptedTransactions)
    if not recovered then
      print(('[mz_houses][commerce] transaction recovery failed: %s'):format(tostring(recoverErr)))
    end
    local taxRecovered, taxRecoverErr = pcall(MZHousesTax.recoverInterruptedPayments)
    if not taxRecovered then
      print(('[mz_houses][tax] payment recovery failed: %s'):format(tostring(taxRecoverErr)))
    end
    local processed, processErr = pcall(MZHousesTax.processBatch)
    if not processed then
      print(('[mz_houses][tax] initial processing failed: %s'):format(tostring(processErr)))
    end
  end
  debugLog('started', {
    houses = MZHousesService.countHouses()
  })
end)


CreateThread(function()
  local seconds = math.max(300, math.floor(tonumber(((MZHousesConfig or {}).Tax or {}).processingIntervalSeconds) or 3600))
  while true do
    Wait(seconds * 1000)
    local ok, err = pcall(MZHousesTax.processBatch)
    if not ok then print(('[mz_houses][tax] batch processing failed: %s'):format(tostring(err))) end
  end
end)

registerAdminCommands()
