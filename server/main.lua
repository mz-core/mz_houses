local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

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

local function isHouseAdmin(source)
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

    reply(source, ('Dono removido: casa=%s'):format(result.houseCode))
  end, false)

  RegisterCommand(tostring(admin.giveKey or 'mhouse_givekey'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.giveHouseKey(args and args[1], args and args[2], source)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    reply(source, ('Chave entregue: casa=%s citizenid=%s'):format(result.houseCode, result.citizenid))
  end, false)

  RegisterCommand(tostring(admin.removeKey or 'mhouse_removekey'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.removeHouseKey(args and args[1], args and args[2], source)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

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
      #result.keys > 0 and table.concat(result.keys, ', ') or 'nenhuma',
      tostring(result.database == true)
    ))
  end, false)

  RegisterCommand(tostring(admin.access or 'mhouse_access'), function(source, args)
    if not isHouseAdmin(source) then
      return reply(source, 'Voce nao tem permissao para usar este comando.')
    end

    local ok, result = MZHousesService.listHouseKeys(args and args[1])
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    reply(source, ('Casa=%s public=%s owner=%s key_count=%d database=%s'):format(
      result.houseCode,
      tostring(result.public == true),
      tostring(result.owner or 'nil'),
      #result.keys,
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

    reply(source, ('Casas recarregadas. total=%d'):format(MZHousesService.countHouses()))
  end, false)

  if MZHousesConfig.Debug == true then
    RegisterCommand('mhouse_testgarage', function(source, args)
      runHouseGarageExportTest(source, args and args[1])
    end, false)
  end
end

lib.callback.register('mz_houses:server:canEnterHouse', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, result = MZHousesService.canEnterHouse(source, houseCode, isHouseAdmin(source))
  if not ok then
    return {
      ok = false,
      error = result or 'no_house_access'
    }
  end

  return {
    ok = true,
    reason = result and result.reason or 'allowed',
    houseCode = result and result.houseCode or trim(houseCode)
  }
end)

lib.callback.register('mz_houses:server:openHouseStash', function(source, payload)
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, result, detail = MZHousesService.openHouseStash(source, houseCode, isHouseAdmin(source))
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
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local ok, result, detail = MZHousesService.openHouseWardrobe(source, houseCode, isHouseAdmin(source))
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
  local houseCode = type(payload) == 'table' and payload.houseCode or payload
  local action = type(payload) == 'table' and payload.action or 'open'
  local ok, result, detail = MZHousesService.openHouseGarage(source, houseCode, action, isHouseAdmin(source))
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

exports('CanEnterHouse', function(source, houseCode)
  return MZHousesService.canEnterHouse(source, houseCode, isHouseAdmin(source))
end)

exports('SetHouseOwner', function(houseCode, citizenid)
  return MZHousesService.setHouseOwner(houseCode, citizenid, 0)
end)

exports('ClearHouseOwner', function(houseCode)
  return MZHousesService.clearHouseOwner(houseCode, 0)
end)

exports('GiveHouseKey', function(houseCode, citizenid)
  return MZHousesService.giveHouseKey(houseCode, citizenid, 0)
end)

exports('RemoveHouseKey', function(houseCode, citizenid)
  return MZHousesService.removeHouseKey(houseCode, citizenid, 0)
end)

exports('GetHouseAccess', function(houseCode)
  return MZHousesService.listHouseKeys(houseCode)
end)

exports('OpenHouseStash', function(source, houseCode)
  return MZHousesService.openHouseStash(source, houseCode, isHouseAdmin(source))
end)

exports('OpenHouseWardrobe', function(source, houseCode)
  return MZHousesService.openHouseWardrobe(source, houseCode, isHouseAdmin(source))
end)

exports('OpenHouseGarage', function(source, houseCode, action)
  return MZHousesService.openHouseGarage(source, houseCode, action, isHouseAdmin(source))
end)

CreateThread(function()
  if MZHousesConfig.Debug == true then
    print('[mz_houses] house garage integration debug loaded')
  end

  MZHousesService.bootstrap()
  debugLog('started', {
    houses = MZHousesService.countHouses()
  })
end)

registerAdminCommands()
