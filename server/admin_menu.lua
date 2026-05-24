local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
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
    furniture = features.furniture == true
  }
end

local function interiorPointFromPayload(payload, pointName)
  payload = type(payload) == 'table' and payload or {}
  local point = coordsFromPayload(payload.point, false)
  local spawn = coordsFromPayload(payload.spawnCoords, false)
  if not point or not spawn then
    return nil, 'invalid_interior_context'
  end

  local relative = vector3(point.x - spawn.x, point.y - spawn.y, point.z - spawn.z)
  local out = {
    enabled = true,
    coords = relative,
    relative = true
  }

  if pointName == 'exit' then
    out.label = 'Sair da casa'
    out.heading = tonumber((type(payload.point) == 'table' and (payload.point.heading or payload.point.w or payload.point.h)) or payload.heading) or 0.0
  elseif pointName == 'stash' then
    out.label = 'Bau da Casa'
    out.slots = tonumber((MZHousesConfig.Stash or {}).defaultSlots) or 50
    out.weight = tonumber((MZHousesConfig.Stash or {}).defaultWeight) or 100000
  elseif pointName == 'wardrobe' then
    out.label = 'Guarda-roupa'
  end

  return out
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

  if payload.inside ~= true or trim(payload.currentHouseCode) ~= code then
    return false, 'not_inside_property'
  end

  return true, code
end

lib.callback.register('mz_houses:server:admin:checkAccess', function(source)
  return {
    ok = isAdmin(source) == true and adminEnabled(),
    error = adminEnabled() and nil or 'admin_menu_disabled'
  }
end)

lib.callback.register('mz_houses:server:admin:setInternalPoint', function(source, payload)
  local valid, codeOrErr = validateInteriorEditContext(source, payload)
  if not valid then
    return { ok = false, error = codeOrErr }
  end

  payload = type(payload) == 'table' and payload or {}
  local code = codeOrErr
  local pointName = trim(payload.pointName)
  if pointName ~= 'exit' and pointName ~= 'stash' and pointName ~= 'wardrobe' then
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
  interior[pointName] = point

  local action = ('house.admin.internal.%s.set'):format(pointName)
  local response = adminUpdate(source, code, { interior = interior }, action, {
    point = pointName,
    shell = trim(payload.shell),
    coords = vector3Payload(point.coords),
    heading = point.heading
  }, ('Ponto interno atualizado: %s'):format(pointName))

  return response
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

lib.callback.register('mz_houses:server:admin:createProperty', function(source, payload)
  if not isAdmin(source) then
    return denied()
  end

  payload = type(payload) == 'table' and payload or {}
  payload.entrance = coordsFromPayload(payload.entrance or payload, true)

  local ok, result = MZHousesService.createAdminProperty(source, payload)
  if not ok then
    return { ok = false, error = result or 'create_failed' }
  end

  refreshVisibility('house_admin_menu_create')
  return okWithProperty(result.houseCode, source, 'Imovel criado.')
end)

lib.callback.register('mz_houses:server:admin:updateBasic', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code)
  local field = trim(payload.field)

  if field == 'label' then
    return adminUpdate(source, code, { label = trim(payload.label) }, 'house.admin.label.set', { label = trim(payload.label) }, 'Label atualizado.')
  end

  if field == 'enable' then
    return adminUpdate(source, code, { enabled = true, status = 'active' }, 'house.admin.enable', nil, 'Imovel ativado.')
  end

  if field == 'disable' then
    return adminUpdate(source, code, { enabled = false, status = 'disabled' }, 'house.admin.disable', nil, 'Imovel desativado.')
  end

  if field == 'archive' then
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
    if property and (property.category == 'org' or property.ownerType == 'org') then
      return { ok = false, error = 'org_property_not_listable' }
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
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.setHouseOwner(payload.code, payload.citizenid, source)
  if not ok then return { ok = false, error = result or 'owner_set_failed' } end
  refreshVisibility('admin_menu_owner_set')
  return okWithProperty(result.houseCode, source, 'Dono definido.')
end)

lib.callback.register('mz_houses:server:admin:clearOwner', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.clearHouseOwner(payload.code, source)
  if not ok then return { ok = false, error = result or 'owner_clear_failed' } end
  refreshVisibility('admin_menu_owner_clear')
  return okWithProperty(result.houseCode, source, 'Dono removido.')
end)

lib.callback.register('mz_houses:server:admin:giveKey', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.giveHouseKey(payload.code, payload.citizenid, source)
  if not ok then return { ok = false, error = result or 'key_give_failed' } end
  refreshVisibility('admin_menu_key_give')
  return okWithProperty(result.houseCode, source, 'Chave entregue.')
end)

lib.callback.register('mz_houses:server:admin:removeKey', function(source, payload)
  if not isAdmin(source) then return denied() end
  payload = type(payload) == 'table' and payload or {}
  local ok, result = MZHousesService.removeHouseKey(payload.code, payload.citizenid, source)
  if not ok then return { ok = false, error = result or 'key_remove_failed' } end
  refreshVisibility('admin_menu_key_remove')
  return okWithProperty(result.houseCode, source, 'Chave removida.')
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
