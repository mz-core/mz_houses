MZHousesRepository = MZHousesRepository or {}

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

local function normalizeOptionalCode(value)
  local code = trim(value)
  if code == '' then return nil end
  return code
end

local function normalizeUnitNumber(value)
  local unit = tostring(value or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  unit = unit:gsub('[^%w_%-]', '_'):sub(1, 30)
  if unit == '' then return nil end
  return unit
end

local function normalizeCategory(value)
  local allowed = {
    residential = true,
    org = true,
    business = true,
    public = true,
    government = true,
    other = true
  }

  value = tostring(value or 'residential'):lower()
  return allowed[value] and value or 'residential'
end

local function normalizeSubtype(value)
  value = tostring(value or 'house'):lower()
  value = value:gsub('[^%w_%-]', '_'):sub(1, 40)
  if value == '' then value = 'house' end
  return value
end

local function normalizeOwnerType(value)
  local allowed = {
    player = true,
    org = true,
    business = true,
    none = true,
    server = true
  }

  value = tostring(value or 'player'):lower()
  return allowed[value] and value or 'player'
end

local function normalizeFeatureBool(value, fallback)
  if value == nil then
    value = fallback
  end

  if value == true then return true end
  if value == false or value == nil then return false end

  local numberValue = tonumber(value)
  if numberValue ~= nil then
    return numberValue == 1
  end

  local textValue = tostring(value):lower():gsub('^%s+', ''):gsub('%s+$', '')
  return textValue == '1' or textValue == 'true' or textValue == 'yes'
end

local function getPropertyDefaults()
  local defaults = MZHousesConfig and MZHousesConfig.PropertyDefaults or {}
  local features = type(defaults.features) == 'table' and defaults.features or {}

  return {
    category = defaults.category or 'residential',
    subtype = defaults.subtype or 'house',
    ownerType = defaults.ownerType or defaults.owner_type or 'player',
    orgCode = defaults.orgCode or defaults.org_code,
    businessCode = defaults.businessCode or defaults.business_code,
    features = {
      stash = features.stash ~= false,
      wardrobe = features.wardrobe ~= false,
      garage = features.garage == true,
      furniture = features.furniture == true
    }
  }
end

local function normalizeFeatures(features, defaults)
  features = type(features) == 'table' and features or {}
  defaults = type(defaults) == 'table' and defaults or {}

  return {
    stash = normalizeFeatureBool(features.stash, defaults.stash),
    wardrobe = normalizeFeatureBool(features.wardrobe, defaults.wardrobe),
    garage = normalizeFeatureBool(features.garage, defaults.garage),
    furniture = normalizeFeatureBool(features.furniture, defaults.furniture)
  }
end

local function normalizePropertyFields(data)
  data = type(data) == 'table' and data or {}
  local defaults = getPropertyDefaults()

  return {
    category = normalizeCategory(data.category or defaults.category),
    subtype = normalizeSubtype(data.subtype or defaults.subtype),
    ownerType = normalizeOwnerType(data.ownerType or data.owner_type or defaults.ownerType),
    parentCode = normalizeOptionalCode(data.parentCode or data.parent_code),
    unitNumber = normalizeUnitNumber(data.unitNumber or data.unit_number),
    orgCode = normalizeOptionalCode(data.orgCode or data.org_code or defaults.orgCode),
    businessCode = normalizeOptionalCode(data.businessCode or data.business_code or defaults.businessCode),
    features = normalizeFeatures(data.features, defaults.features)
  }
end

local function encodeJson(value)
  local ok, encoded = pcall(json.encode, value or {})
  if ok and encoded then return encoded end
  return '{}'
end

local function decodeJson(value, fallback)
  if type(value) ~= 'string' or value == '' then
    return fallback
  end

  local ok, decoded = pcall(json.decode, value)
  if ok and type(decoded) == 'table' then
    return decoded
  end

  return fallback
end

local function vectorToPlain(value)
  if type(value) == 'vector4' then
    return { x = value.x, y = value.y, z = value.z, w = value.w }
  end

  if type(value) == 'vector3' then
    return { x = value.x, y = value.y, z = value.z }
  end

  if type(value) == 'table' then
    return value
  end

  return nil
end

local function databaseBool(value)
  if value == true then return true end
  if value == false or value == nil then return false end

  local numberValue = tonumber(value)
  if numberValue ~= nil then
    return numberValue == 1
  end

  local textValue = tostring(value):lower():gsub('^%s+', ''):gsub('%s+$', '')
  return textValue == '1' or textValue == 'true'
end

local function normalizeVisibility(value)
  value = tostring(value or 'auto'):lower()
  if value == 'auto' or value == 'public' or value == 'restricted' or value == 'hidden' then
    return value
  end

  return 'auto'
end

local function normalizeListing(data)
  data = type(data) == 'table' and data or {}
  local sign = type(data.sign) == 'table' and data.sign or {}

  return {
    enabled = data.enabled == true,
    type = trim(data.type) ~= '' and trim(data.type) or 'sale',
    price = tonumber(data.price),
    label = trim(data.label) ~= '' and trim(data.label) or 'Imovel a venda',
    description = trim(data.description) ~= '' and trim(data.description) or nil,
    sign = {
      enabled = sign.enabled == true,
      coords = vectorToPlain(sign.coords),
      heading = tonumber(sign.heading) or 0.0
    }
  }
end

local function normalizeRealestate(data)
  data = type(data) == 'table' and data or {}

  return {
    enabled = data.enabled == true,
    canBeListed = data.canBeListed ~= false,
    defaultPrice = tonumber(data.defaultPrice),
    listingType = trim(data.listingType) ~= '' and trim(data.listingType) or 'sale'
  }
end

local function normalizeBuilding(data)
  data = type(data) == 'table' and data or {}

  return {
    floors = tonumber(data.floors),
    unitsPerFloor = tonumber(data.unitsPerFloor or data.units_per_floor),
    firstFloor = tonumber(data.firstFloor or data.first_floor) or 1,
    unitPattern = trim(data.unitPattern or data.unit_pattern) ~= '' and trim(data.unitPattern or data.unit_pattern) or nil,
    sharedEntrance = data.sharedEntrance ~= false,
    sharedGarage = data.sharedGarage == true,
    intercom = data.intercom ~= false,
    defaultUnitShell = trim(data.defaultUnitShell or data.default_unit_shell) ~= '' and trim(data.defaultUnitShell or data.default_unit_shell) or nil
  }
end

local function normalizeInteriorPoint(data, pointName)
  data = type(data) == 'table' and data or {}
  local coords = vectorToPlain(data.coords)
  if not coords and next(data) == nil then
    return nil
  end

  local point = {
    enabled = data.enabled ~= false,
    coords = coords,
    relative = data.relative ~= false
  }

  local label = trim(data.label)
  if label ~= '' then point.label = label end

  local heading = tonumber(data.heading or data.w)
  if heading ~= nil then point.heading = heading end

  if pointName == 'stash' then
    point.slots = tonumber(data.slots)
    point.weight = tonumber(data.weight)
  elseif pointName == 'wardrobe' then
    local shopId = trim(data.shopId or data.shop_id)
    if shopId ~= '' then point.shopId = shopId end
    local resource = trim(data.resource)
    if resource ~= '' then point.resource = resource end
  end

  return point
end

local function normalizeInterior(data)
  data = type(data) == 'table' and data or {}
  local interior = {}

  for _, pointName in ipairs({ 'exit', 'stash', 'wardrobe' }) do
    local point = normalizeInteriorPoint(data[pointName], pointName)
    if point then
      interior[pointName] = point
    end
  end

  return interior
end

local function rowToHouse(row)
  if type(row) ~= 'table' then return nil end

  row.entrance = decodeJson(row.entrance_json, nil)
  row.garage = decodeJson(row.garage_json, nil)
  row.interior = normalizeInterior(decodeJson(row.interior_json, nil))
  local property = normalizePropertyFields({
    category = row.category,
    subtype = row.subtype,
    ownerType = row.owner_type,
    parentCode = row.parent_code,
    unitNumber = row.unit_number,
    orgCode = row.org_code,
    businessCode = row.business_code,
    features = decodeJson(row.features_json, nil)
  })
  row.category = property.category
  row.subtype = property.subtype
  row.owner_type = property.ownerType
  row.ownerType = property.ownerType
  row.parent_code = property.parentCode
  row.parentCode = property.parentCode
  row.unit_number = property.unitNumber
  row.unitNumber = property.unitNumber
  row.org_code = property.orgCode
  row.orgCode = property.orgCode
  row.business_code = property.businessCode
  row.businessCode = property.businessCode
  row.features = property.features
  row.visibility = normalizeVisibility(row.visibility)
  row.listing = normalizeListing(decodeJson(row.listing_json, nil))
  row.realestate = normalizeRealestate(decodeJson(row.realestate_json, nil))
  row.building = normalizeBuilding(decodeJson(row.building_json, nil))
  row.enabled = databaseBool(row.enabled)
  row.public = databaseBool(row.public)
  return row
end

function MZHousesRepository.normalizePropertyFields(data)
  return normalizePropertyFields(data)
end

function MZHousesRepository.getHouseByCode(code)
  code = normalizeCode(code)
  if not code then return nil end

  local row = MySQL.single.await('SELECT * FROM mz_houses WHERE code = ? LIMIT 1', { code })
  return rowToHouse(row)
end

function MZHousesRepository.listHouses()
  local rows = MySQL.query.await('SELECT * FROM mz_houses ORDER BY code ASC', {}) or {}
  local houses = {}

  for _, row in ipairs(rows) do
    houses[#houses + 1] = rowToHouse(row)
  end

  return houses
end

function MZHousesRepository.upsertHouseFromConfig(code, data)
  code = normalizeCode(code)
  if not code or type(data) ~= 'table' then
    return false, 'invalid_house'
  end

  local existing = MZHousesRepository.getHouseByCode(code)
  local dbConfig = MZHousesConfig.Database or {}
  local access = type(data.access) == 'table' and data.access or {}
  local public = access.public == true and 1 or 0
  local owner = nil
  if dbConfig.configCanSetOwnerOnFirstInsert == true then
    owner = normalizeCitizenId(access.owner)
  end

  local label = trim(data.label)
  if label == '' then label = code end

  local houseType = trim(data.type)
  if houseType == '' then houseType = 'shell' end

  local shell = trim(data.shell)
  if shell == '' then shell = nil end

  local status = trim(data.status)
  if status == '' then status = 'active' end

  local enabled = data.enabled ~= false and 1 or 0
  local entranceJson = encodeJson(vectorToPlain(data.entrance))
  local garageJson = encodeJson(data.garage or {})
  local property = normalizePropertyFields(data)
  local featuresJson = encodeJson(property.features)
  local interiorJson = encodeJson(normalizeInterior(data.interior))
  local visibility = normalizeVisibility(data.visibility)
  local listingJson = encodeJson(normalizeListing(data.listing))
  local realestateJson = encodeJson(normalizeRealestate(data.realestate))
  local buildingJson = encodeJson(normalizeBuilding(data.building))

  if not existing then
    MySQL.insert.await([[
      INSERT INTO mz_houses (
        code, label, category, subtype, owner_type, parent_code, unit_number, org_code, business_code,
        building_json, type, shell, entrance_json, garage_json, features_json, interior_json, visibility, listing_json, realestate_json,
        status, enabled, public, owner_citizenid
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      code,
      label,
      property.category,
      property.subtype,
      property.ownerType,
      property.parentCode,
      property.unitNumber,
      property.orgCode,
      property.businessCode,
      buildingJson,
      houseType,
      shell,
      entranceJson,
      garageJson,
      featuresJson,
      interiorJson,
      visibility,
      listingJson,
      realestateJson,
      status,
      enabled,
      public,
      owner
    })

    return true, 'inserted'
  end

  local nextPublic = existing.public == true and 1 or 0
  if dbConfig.syncPublicFromConfig == true then
    nextPublic = public
  end
  local nextVisibility = normalizeVisibility(existing.visibility)
  local nextListingJson = encodeJson(normalizeListing(existing.listing))
  local nextRealestateJson = encodeJson(normalizeRealestate(existing.realestate))
  local nextInteriorJson = encodeJson(normalizeInterior(existing.interior))
  local nextBuildingJson = encodeJson(normalizeBuilding(existing.building))

  MySQL.update.await([[
    UPDATE mz_houses
    SET label = ?, category = ?, subtype = ?, owner_type = ?, parent_code = ?, unit_number = ?, org_code = ?, business_code = ?,
        building_json = ?, type = ?, shell = ?, entrance_json = ?, garage_json = ?, features_json = ?,
        interior_json = ?, visibility = ?, listing_json = ?, realestate_json = ?, status = ?, enabled = ?, public = ?
    WHERE code = ?
  ]], {
    label,
    property.category,
    property.subtype,
    property.ownerType,
    property.parentCode,
    property.unitNumber,
    property.orgCode,
    property.businessCode,
    nextBuildingJson,
    houseType,
    shell,
    entranceJson,
    garageJson,
    featuresJson,
    nextInteriorJson,
    nextVisibility,
    nextListingJson,
    nextRealestateJson,
    status,
    enabled,
    nextPublic,
    code
  })

  return true, 'updated'
end

function MZHousesRepository.createHouseFromAdmin(code, data)
  code = normalizeCode(code)
  if not code or type(data) ~= 'table' then
    return false, 'invalid_house'
  end

  if MZHousesRepository.getHouseByCode(code) then
    return false, 'house_exists'
  end

  local label = trim(data.label)
  if label == '' then label = code end

  local property = normalizePropertyFields(data)
  MySQL.insert.await([[
    INSERT INTO mz_houses (
      code, label, category, subtype, owner_type, parent_code, unit_number, org_code, business_code,
      building_json, type, shell, entrance_json, garage_json, features_json, interior_json, visibility,
      listing_json, realestate_json, status, enabled, public, owner_citizenid
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
  ]], {
    code,
    label,
    property.category,
    property.subtype,
    property.ownerType,
    property.parentCode,
    property.unitNumber,
    property.orgCode,
    property.businessCode,
    encodeJson(normalizeBuilding(data.building)),
    trim(data.type) ~= '' and trim(data.type) or 'shell',
    trim(data.shell) ~= '' and trim(data.shell) or nil,
    encodeJson(vectorToPlain(data.entrance)),
    encodeJson(data.garage or {}),
    encodeJson(property.features),
    encodeJson(normalizeInterior(data.interior)),
    normalizeVisibility(data.visibility),
    encodeJson(normalizeListing(data.listing)),
    encodeJson(normalizeRealestate(data.realestate)),
    trim(data.status) ~= '' and trim(data.status) or 'draft',
    data.enabled ~= false and 1 or 0,
    type(data.access) == 'table' and data.access.public == true and 1 or 0
  })

  return true, 'created'
end

function MZHousesRepository.updateHouseFromAdmin(code, data)
  code = normalizeCode(code)
  if not code or type(data) ~= 'table' then
    return false, 'invalid_house'
  end

  local existing = MZHousesRepository.getHouseByCode(code)
  if not existing then
    return false, 'house_not_found'
  end

  local label = trim(data.label)
  if label == '' then label = existing.label or code end

  local property = normalizePropertyFields(data)
  local affected = MySQL.update.await([[
    UPDATE mz_houses
    SET label = ?, category = ?, subtype = ?, owner_type = ?, parent_code = ?, unit_number = ?, org_code = ?, business_code = ?,
        building_json = ?, type = ?, shell = ?, entrance_json = ?, garage_json = ?, features_json = ?,
        interior_json = ?, visibility = ?, listing_json = ?, realestate_json = ?, status = ?, enabled = ?, public = ?
    WHERE code = ?
  ]], {
    label,
    property.category,
    property.subtype,
    property.ownerType,
    property.parentCode,
    property.unitNumber,
    property.orgCode,
    property.businessCode,
    encodeJson(normalizeBuilding(data.building)),
    trim(data.type) ~= '' and trim(data.type) or 'shell',
    trim(data.shell) ~= '' and trim(data.shell) or nil,
    encodeJson(vectorToPlain(data.entrance)),
    encodeJson(data.garage or {}),
    encodeJson(property.features),
    encodeJson(normalizeInterior(data.interior)),
    normalizeVisibility(data.visibility),
    encodeJson(normalizeListing(data.listing)),
    encodeJson(normalizeRealestate(data.realestate)),
    trim(data.status) ~= '' and trim(data.status) or 'active',
    data.enabled ~= false and 1 or 0,
    type(data.access) == 'table' and data.access.public == true and 1 or 0,
    code
  })

  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.setOwner(code, citizenid)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  if not code then return false, 'invalid_house' end
  if not citizenid then return false, 'invalid_citizenid' end

  local affected = MySQL.update.await(
    'UPDATE mz_houses SET owner_citizenid = ?, public = 0 WHERE code = ?',
    { citizenid, code }
  )

  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.clearOwner(code)
  code = normalizeCode(code)
  if not code then return false, 'invalid_house' end

  local affected = MySQL.update.await(
    'UPDATE mz_houses SET owner_citizenid = NULL WHERE code = ?',
    { code }
  )

  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.giveKey(code, citizenid, role)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  role = trim(role)
  if role == '' then role = 'key' end

  if not code then return false, 'invalid_house' end
  if not citizenid then return false, 'invalid_citizenid' end

  MySQL.insert.await([[
    INSERT INTO mz_house_keys (house_code, citizenid, role)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE role = VALUES(role)
  ]], { code, citizenid, role })

  MySQL.update.await('UPDATE mz_houses SET public = 0 WHERE code = ?', { code })
  return true
end

function MZHousesRepository.removeKey(code, citizenid)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  if not code then return false, 'invalid_house' end
  if not citizenid then return false, 'invalid_citizenid' end

  MySQL.query.await(
    'DELETE FROM mz_house_keys WHERE house_code = ? AND citizenid = ?',
    { code, citizenid }
  )

  return true
end

function MZHousesRepository.listKeys(code)
  code = normalizeCode(code)
  if not code then return {} end

  return MySQL.query.await([[
    SELECT house_code, citizenid, role, created_at
    FROM mz_house_keys
    WHERE house_code = ?
    ORDER BY citizenid ASC
  ]], { code }) or {}
end

function MZHousesRepository.hasKey(code, citizenid)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  if not code or not citizenid then return false end

  local row = MySQL.single.await([[
    SELECT id FROM mz_house_keys
    WHERE house_code = ? AND citizenid = ?
    LIMIT 1
  ]], { code, citizenid })

  return row ~= nil
end

function MZHousesRepository.insertLog(code, action, actorCitizenId, targetCitizenId, meta)
  code = normalizeCode(code)
  action = trim(action)
  if action == '' then return false, 'invalid_action' end

  MySQL.insert.await([[
    INSERT INTO mz_house_logs (house_code, action, actor_citizenid, target_citizenid, meta_json)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    code,
    action,
    normalizeCitizenId(actorCitizenId),
    normalizeCitizenId(targetCitizenId),
    encodeJson(meta or {})
  })

  return true
end
