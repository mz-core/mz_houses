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

    local ok, result = MZHousesService.giveHouseKey(args and args[1], args and args[2], source)
    if not ok then
      return reply(source, ('Erro: %s'):format(tostring(result)))
    end

    refreshVisibilityTargets('key_given')
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
      #result.keys > 0 and table.concat(result.keys, ', ') or 'nenhuma',
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

    reply(source, ('Casa=%s accessMode=%s category=%s subtype=%s ownerType=%s orgCode=%s businessCode=%s features=%s enterAccess=%s featuresAccess=%s public=%s owner=%s key_count=%d currentAccess=%s reason=%s canBeListed=%s listReason=%s database=%s'):format(
      result.houseCode,
      tostring(result.accessMode or 'player'),
      tostring(result.category or 'residential'),
      tostring(result.subtype or 'house'),
      tostring(result.ownerType or 'player'),
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
    adminUpdate(source, args[1], { shell = shell, type = 'shell' }, 'house.admin.shell.set', { shell = shell }, 'Shell atualizado.')
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
      if property and (property.category == 'org' or property.ownerType == 'org') then
        return reply(source, 'Imovel org/base nao pode ser listable por padrao.')
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
    reply(source, ('Info casa=%s label=%s enabled=%s status=%s category=%s subtype=%s ownerType=%s orgCode=%s shell=%s visibility=%s public=%s canBeListed=%s reason=%s owner=%s garage=%s/%s/%s coords=%.2f,%.2f,%.2f'):format(
      code,
      tostring(property.label or 'nil'),
      tostring(property.enabled == true),
      tostring(property.status or 'nil'),
      tostring(property.category or 'nil'),
      tostring(property.subtype or 'nil'),
      tostring(property.ownerType or 'nil'),
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

exports('GivePropertyKey', function(code, citizenid, actorSource, reason, meta)
  local ok, result = MZHousesService.GivePropertyKey(code, citizenid, actorSource, reason, meta)
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

exports('GiveHouseKey', function(houseCode, citizenid, actorSource, reason, meta)
  local ok, result = MZHousesService.GivePropertyKey(houseCode, citizenid, actorSource, reason, meta)
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
