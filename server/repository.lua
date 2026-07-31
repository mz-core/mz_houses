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
    organization = true,
    org = true,
    business = true,
    public = true,
    administrative = true,
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

local function normalizePolicyRules(rawRules, includeDoorControl)
  local rules = {}
  for index, raw in ipairs(type(rawRules) == 'table' and rawRules or {}) do
    if index > 16 then break end
    if type(raw) == 'table' then
      local ruleType = trim(raw.type):lower()
      local name = trim(raw.name):sub(1, 64)
      if (ruleType == 'gang' or ruleType == 'job') and name ~= '' then
        local minimumGrade = math.floor(tonumber(raw.minimumGrade) or 0)
        if minimumGrade < 0 then minimumGrade = 0 end
        if minimumGrade > 1000 then minimumGrade = 1000 end
        local rule = {
          type = ruleType,
          name = name,
          minimumGrade = minimumGrade,
          requireDuty = ruleType == 'job' and raw.requireDuty == true or false
        }
        if includeDoorControl == true then
          rule.canControlDoorFromGrade = raw.canControlDoorFromGrade ~= nil
            and math.max(0, math.min(1000, math.floor(tonumber(raw.canControlDoorFromGrade) or 0))) or nil
        end
        rules[#rules + 1] = rule
      end
    end
  end
  return rules
end

local function normalizeFeaturePolicy(raw)
  raw = type(raw) == 'table' and raw or {}
  local mode = trim(raw.mode):lower()
  if mode == '' and raw.inherit == true then mode = 'inherit' end
  if mode == 'none' then mode = 'admin' end
  local allowed = { inherit = true, disabled = true, owner = true, keys = true, rules = true, public = true, admin = true }
  if not allowed[mode] then mode = 'inherit' end
  return {
    mode = mode,
    match = 'any',
    rules = mode == 'rules' and normalizePolicyRules(raw.rules, false) or {}
  }
end

local function normalizeAccessPolicy(data)
  if type(data) ~= 'table' then return nil end
  local allowedModes = { owner = true, rules = true, public = true, admin = true, none = true }
  local mode = trim(data.mode):lower()
  if not allowedModes[mode] then return nil end

  local rules = normalizePolicyRules(data.rules, true)

  local features = {}
  for _, name in ipairs({ 'stash', 'wardrobe', 'garage', 'furniture' }) do
    features[name] = normalizeFeaturePolicy(type(data.features) == 'table' and data.features[name] or nil)
  end

  return { version = 1, mode = mode, match = 'any', rules = rules, features = features }
end

local function normalizeKeyRole(value)
  value = trim(value):lower()
  if value == 'control' then return 'control' end
  return 'access'
end

local function normalizeDoor(data)
  if type(data) ~= 'table' then return nil end
  local state = trim(data.state):lower()
  if state ~= 'locked' and state ~= 'unlocked' and state ~= 'blocked' then return nil end
  local defaultState = trim(data.defaultState):lower()
  if defaultState ~= 'locked' and defaultState ~= 'unlocked' and defaultState ~= 'blocked' then defaultState = state end
  return {
    version = 1,
    state = state,
    defaultState = defaultState,
    autoLock = false,
    autoLockSeconds = 0,
    control = { mode = 'policy', minimumGrade = nil }
  }
end

local function normalizeSaleMode(value)
  value = trim(value):lower()
  if value == 'admin' or value == 'direct' then return value end
  return 'none'
end

local function normalizeSalePrice(value)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then return 0 end
  return math.min(9000000000000000, math.floor(value))
end

local function normalizeCommerce(data)
  data = type(data) == 'table' and data or {}
  local mode = normalizeSaleMode(data.saleMode or data.sale_mode)
  local price = normalizeSalePrice(data.salePrice or data.sale_price)
  local enabled = data.saleEnabled == true or data.sale_enabled == true
    or tonumber(data.saleEnabled or data.sale_enabled) == 1
  if not enabled or mode == 'none' or price <= 0 then
    enabled = false
    mode = 'none'
  end
  return { saleEnabled = enabled, saleMode = mode, salePrice = price }
end

local function boundedInteger(value, fallback, minimum, maximum)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback end
  value = math.floor(tonumber(value) or fallback or 0)
  return math.max(minimum, math.min(maximum, value))
end

local function normalizeTax(data)
  data = type(data) == 'table' and data or {}
  local enabled = data.taxEnabled == true or data.tax_enabled == true
    or tonumber(data.taxEnabled or data.tax_enabled) == 1
  local amount = normalizeSalePrice(data.taxAmount or data.tax_amount)
  local interval = boundedInteger(
    data.taxIntervalDays or data.tax_interval_days or data.billingIntervalDays or data.billing_interval_days,
    ((MZHousesConfig or {}).Tax or {}).defaultIntervalDays or 7, 1, 3650
  )
  local grace = boundedInteger(
    data.taxGracePeriodDays or data.tax_grace_period_days or data.gracePeriodDays or data.grace_period_days,
    ((MZHousesConfig or {}).Tax or {}).defaultGracePeriodDays or 3, 0, 365
  )
  local status = trim(data.taxStatus or data.tax_status):lower()
  local allowedStatus = { disabled = true, paid = true, due = true, overdue = true, blocked = true }
  if not allowedStatus[status] then status = 'disabled' end
  if not enabled or amount <= 0 then status = 'disabled' end
  return {
    taxEnabled = enabled,
    taxAmount = amount,
    taxIntervalDays = interval,
    taxGracePeriodDays = grace,
    taxDueAt = data.taxDueAt or data.tax_due_at,
    taxGraceUntil = data.taxGraceUntil or data.tax_grace_until,
    taxStatus = status,
    taxLastPaidAt = data.taxLastPaidAt or data.tax_last_paid_at
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
  local rawDefaults = type(data.unitDefaults) == 'table' and data.unitDefaults
    or type(data.unit_defaults) == 'table' and data.unit_defaults or {}
  local defaultEnabled = rawDefaults.saleEnabled
  if defaultEnabled == nil then defaultEnabled = data.defaultUnitSaleEnabled end
  local defaultMode = rawDefaults.saleMode
  if defaultMode == nil then defaultMode = data.defaultUnitSaleMode end
  local defaultPrice = rawDefaults.salePrice
  if defaultPrice == nil then defaultPrice = data.defaultUnitSalePrice end
  local defaultCommerce = normalizeCommerce({
    saleEnabled = defaultEnabled,
    saleMode = defaultMode,
    salePrice = defaultPrice
  })
  local defaultShell = trim(rawDefaults.shell or data.defaultUnitShell or data.default_unit_shell)
  local defaultFeatures = normalizeFeatures(rawDefaults.features, {
    stash = true,
    wardrobe = true,
    garage = data.sharedGarage == true,
    furniture = true
  })
  local rawTax = type(rawDefaults.tax) == 'table' and rawDefaults.tax or {
    taxEnabled = data.defaultUnitTaxEnabled,
    taxAmount = data.defaultUnitTaxAmount,
    taxIntervalDays = data.defaultUnitTaxIntervalDays,
    taxGracePeriodDays = data.defaultUnitTaxGracePeriodDays
  }
  local defaultTax = normalizeTax({
    taxEnabled = rawTax.taxEnabled ~= nil and rawTax.taxEnabled or rawTax.enabled,
    taxAmount = rawTax.taxAmount ~= nil and rawTax.taxAmount or rawTax.amount,
    taxIntervalDays = rawTax.taxIntervalDays ~= nil and rawTax.taxIntervalDays or rawTax.intervalDays,
    taxGracePeriodDays = rawTax.taxGracePeriodDays ~= nil and rawTax.taxGracePeriodDays or rawTax.gracePeriodDays
  })

  return {
    floors = tonumber(data.floors),
    unitsPerFloor = tonumber(data.unitsPerFloor or data.units_per_floor),
    firstFloor = tonumber(data.firstFloor or data.first_floor) or 1,
    unitPattern = trim(data.unitPattern or data.unit_pattern) ~= '' and trim(data.unitPattern or data.unit_pattern) or nil,
    sharedEntrance = data.sharedEntrance ~= false,
    sharedGarage = data.sharedGarage == true,
    intercom = data.intercom ~= false,
    defaultUnitShell = defaultShell ~= '' and defaultShell or nil,
    unitDefaults = {
      saleEnabled = defaultCommerce.saleEnabled,
      saleMode = defaultCommerce.saleMode,
      salePrice = defaultCommerce.salePrice,
      shell = defaultShell ~= '' and defaultShell or nil,
      interior = type(rawDefaults.interior) == 'table' and rawDefaults.interior or {},
      features = defaultFeatures,
      tax = {
        enabled = defaultTax.taxEnabled,
        amount = defaultTax.taxAmount,
        intervalDays = defaultTax.taxIntervalDays,
        gracePeriodDays = defaultTax.taxGracePeriodDays
      }
    }
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

  local rawEntrySpawn = type(data.entrySpawn) == 'table' and data.entrySpawn
    or type(data.entry_spawn) == 'table' and data.entry_spawn
    or nil
  if rawEntrySpawn then
    local mode = trim(rawEntrySpawn.mode):lower()
    if mode ~= 'custom' then mode = 'default' end
    local coords = vectorToPlain(rawEntrySpawn.coords or rawEntrySpawn)
    interior.entrySpawn = {
      mode = mode,
      coords = mode == 'custom' and coords or nil,
      heading = mode == 'custom' and tonumber(rawEntrySpawn.heading or rawEntrySpawn.h or rawEntrySpawn.w) or nil,
      relative = true
    }
  end

  return interior
end

local function rowToHouse(row)
  if type(row) ~= 'table' then return nil end

  row.entrance = decodeJson(row.entrance_json, nil)
  row.garage = decodeJson(row.garage_json, nil)
  row.interior = normalizeInterior(decodeJson(row.interior_json, nil))
  row.metadata = decodeJson(row.metadata_json, {})
  row.accessPolicy = normalizeAccessPolicy(decodeJson(row.access_json, nil))
  row.accessPolicyPersisted = row.accessPolicy ~= nil
  row.door = normalizeDoor(decodeJson(row.door_json, nil))
  row.doorPersisted = row.door ~= nil
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
  local commerce = normalizeCommerce(row)
  row.sale_enabled = commerce.saleEnabled
  row.saleEnabled = commerce.saleEnabled
  row.sale_mode = commerce.saleMode
  row.saleMode = commerce.saleMode
  row.sale_price = commerce.salePrice
  row.salePrice = commerce.salePrice
  local tax = normalizeTax(row)
  row.tax_enabled = tax.taxEnabled
  row.taxEnabled = tax.taxEnabled
  row.tax_amount = tax.taxAmount
  row.taxAmount = tax.taxAmount
  row.tax_interval_days = tax.taxIntervalDays
  row.taxIntervalDays = tax.taxIntervalDays
  row.tax_grace_period_days = tax.taxGracePeriodDays
  row.taxGracePeriodDays = tax.taxGracePeriodDays
  row.tax_due_at = tax.taxDueAt
  row.taxDueAt = tax.taxDueAt
  row.tax_grace_until = tax.taxGraceUntil
  row.taxGraceUntil = tax.taxGraceUntil
  row.tax_status = tax.taxStatus
  row.taxStatus = tax.taxStatus
  row.tax_last_paid_at = tax.taxLastPaidAt
  row.taxLastPaidAt = tax.taxLastPaidAt
  return row
end

function MZHousesRepository.normalizePropertyFields(data)
  return normalizePropertyFields(data)
end

function MZHousesRepository.normalizeAccessPolicy(data)
  return normalizeAccessPolicy(data)
end

function MZHousesRepository.normalizeFeaturePolicy(data)
  return normalizeFeaturePolicy(data)
end

function MZHousesRepository.normalizeDoor(data) return normalizeDoor(data) end
function MZHousesRepository.normalizeKeyRole(value) return normalizeKeyRole(value) end
function MZHousesRepository.normalizeCommerce(data) return normalizeCommerce(data) end
function MZHousesRepository.normalizeTax(data) return normalizeTax(data) end
function MZHousesRepository.normalizeBuilding(data) return normalizeBuilding(data) end

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

function MZHousesRepository.listHousesByOwner(citizenid)
  citizenid = normalizeCitizenId(citizenid)
  if not citizenid then return {} end

  local rows = MySQL.query.await([[
    SELECT * FROM mz_houses
    WHERE owner_citizenid = ?
    ORDER BY label ASC, code ASC
  ]], { citizenid }) or {}
  local houses = {}
  for _, row in ipairs(rows) do
    houses[#houses + 1] = rowToHouse(row)
  end
  return houses
end

function MZHousesRepository.listHousesByKeyHolder(citizenid)
  citizenid = normalizeCitizenId(citizenid)
  if not citizenid then return {} end

  local rows = MySQL.query.await([[
    SELECT h.*, k.role AS player_key_role, k.created_at AS player_key_created_at
    FROM mz_house_keys k
    INNER JOIN mz_houses h ON h.code = k.house_code
    WHERE k.citizenid = ?
    ORDER BY h.label ASC, h.code ASC
  ]], { citizenid }) or {}
  local houses = {}
  for _, row in ipairs(rows) do
    local house = rowToHouse(row)
    if house then
      house.playerKeyRole = normalizeKeyRole(row.player_key_role)
      house.playerKeyCreatedAt = row.player_key_created_at
      houses[#houses + 1] = house
    end
  end
  return houses
end

function MZHousesRepository.getHousesByCodes(codes)
  local normalized, seen = {}, {}
  for _, raw in ipairs(type(codes) == 'table' and codes or {}) do
    local code = normalizeCode(raw)
    if code and not seen[code] then
      seen[code] = true
      normalized[#normalized + 1] = code
    end
  end
  if #normalized == 0 then return {} end
  local placeholders = {}
  for index = 1, #normalized do placeholders[index] = '?' end
  local rows = MySQL.query.await((
    'SELECT * FROM mz_houses WHERE code IN (%s)'
  ):format(table.concat(placeholders, ', ')), normalized) or {}
  local out = {}
  for _, row in ipairs(rows) do
    local house = rowToHouse(row)
    if house and house.code then out[house.code] = house end
  end
  return out
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
  local accessJson = data.accessPolicy and encodeJson(normalizeAccessPolicy(data.accessPolicy)) or nil
  local doorJson = data.door and encodeJson(normalizeDoor(data.door)) or nil

  if not existing then
    MySQL.insert.await([[
      INSERT INTO mz_houses (
        code, label, category, subtype, owner_type, parent_code, unit_number, org_code, business_code,
        building_json, type, shell, entrance_json, garage_json, features_json, interior_json, access_json, door_json, visibility, listing_json, realestate_json,
        status, enabled, public, owner_citizenid
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      accessJson,
      doorJson,
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
  local nextAccessJson = existing.accessPolicy and encodeJson(existing.accessPolicy) or nil
  local nextDoorJson = existing.door and encodeJson(existing.door) or nil

  MySQL.update.await([[
    UPDATE mz_houses
    SET label = ?, category = ?, subtype = ?, owner_type = ?, parent_code = ?, unit_number = ?, org_code = ?, business_code = ?,
        building_json = ?, type = ?, shell = ?, entrance_json = ?, garage_json = ?, features_json = ?,
        interior_json = ?, access_json = ?, door_json = ?, visibility = ?, listing_json = ?, realestate_json = ?, status = ?, enabled = ?, public = ?
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
    nextAccessJson,
    nextDoorJson,
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
  local commerce = normalizeCommerce(data)
  local tax = normalizeTax(data)
  MySQL.insert.await([[
    INSERT INTO mz_houses (
      code, label, category, subtype, owner_type, parent_code, unit_number, org_code, business_code,
      building_json, type, shell, entrance_json, garage_json, features_json, interior_json, access_json, door_json, visibility,
      listing_json, realestate_json, metadata_json, status, enabled, public,
      sale_enabled, sale_mode, sale_price,
      tax_enabled, tax_amount, tax_interval_days, tax_grace_period_days,
      tax_due_at, tax_grace_until, tax_status, tax_last_paid_at, owner_citizenid
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 'disabled', NULL, NULL)
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
    data.accessPolicy and encodeJson(normalizeAccessPolicy(data.accessPolicy)) or nil,
    data.door and encodeJson(normalizeDoor(data.door)) or nil,
    normalizeVisibility(data.visibility),
    encodeJson(normalizeListing(data.listing)),
    encodeJson(normalizeRealestate(data.realestate)),
    encodeJson(type(data.metadata) == 'table' and data.metadata or {}),
    trim(data.status) ~= '' and trim(data.status) or 'draft',
    data.enabled ~= false and 1 or 0,
    type(data.access) == 'table' and data.access.public == true and 1 or 0,
    commerce.saleEnabled and 1 or 0,
    commerce.saleMode,
    commerce.salePrice,
    tax.taxEnabled and 1 or 0,
    tax.taxAmount,
    tax.taxIntervalDays,
    tax.taxGracePeriodDays
  })

  return true, 'created'
end

function MZHousesRepository.createApartmentUnitsBatch(rows)
  rows = type(rows) == 'table' and rows or {}
  if #rows == 0 then return false, 'empty_unit_batch' end
  local statements, seen = {}, {}
  for _, row in ipairs(rows) do
    local code = normalizeCode(type(row) == 'table' and row.code or nil)
    local data = type(row) == 'table' and row.data or nil
    if not code or type(data) ~= 'table' or seen[code] then
      return false, seen[code] and 'duplicate_unit_code' or 'invalid_unit_batch'
    end
    seen[code] = true
    local property = normalizePropertyFields(data)
    local commerce = normalizeCommerce(data)
    local tax = normalizeTax(data)
    if property.subtype ~= 'apartment_unit' or not property.parentCode or not property.unitNumber then
      return false, 'invalid_apartment_unit'
    end
    statements[#statements + 1] = {
      query = [[
        INSERT INTO mz_houses (
          code, label, category, subtype, owner_type, parent_code, unit_number, org_code, business_code,
          building_json, type, shell, entrance_json, garage_json, features_json, interior_json, access_json, door_json, visibility,
          listing_json, realestate_json, metadata_json, status, enabled, public,
          sale_enabled, sale_mode, sale_price,
          tax_enabled, tax_amount, tax_interval_days, tax_grace_period_days,
          tax_due_at, tax_grace_until, tax_status, tax_last_paid_at, owner_citizenid
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 'disabled', NULL, NULL)
      ]],
      parameters = {
        code,
        trim(data.label) ~= '' and trim(data.label) or code,
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
        data.accessPolicy and encodeJson(normalizeAccessPolicy(data.accessPolicy)) or nil,
        data.door and encodeJson(normalizeDoor(data.door)) or nil,
        normalizeVisibility(data.visibility),
        encodeJson(normalizeListing(data.listing)),
        encodeJson(normalizeRealestate(data.realestate)),
        encodeJson(type(data.metadata) == 'table' and data.metadata or {}),
        trim(data.status) ~= '' and trim(data.status) or 'draft',
        data.enabled ~= false and 1 or 0,
        type(data.access) == 'table' and data.access.public == true and 1 or 0,
        commerce.saleEnabled and 1 or 0,
        commerce.saleMode,
        commerce.salePrice,
        tax.taxEnabled and 1 or 0,
        tax.taxAmount,
        tax.taxIntervalDays,
        tax.taxGracePeriodDays
      }
    }
  end
  local ok, result = pcall(function() return MySQL.transaction.await(statements) end)
  if not ok or result ~= true then
    return false, ok and 'unit_batch_transaction_failed' or tostring(result)
  end
  return true, #rows
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
        interior_json = ?, access_json = ?, door_json = ?, visibility = ?, listing_json = ?, realestate_json = ?, metadata_json = ?, status = ?, enabled = ?, public = ?
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
    data.accessPolicy and encodeJson(normalizeAccessPolicy(data.accessPolicy)) or nil,
    data.door and encodeJson(normalizeDoor(data.door)) or nil,
    normalizeVisibility(data.visibility),
    encodeJson(normalizeListing(data.listing)),
    encodeJson(normalizeRealestate(data.realestate)),
    encodeJson(type(data.metadata) == 'table' and data.metadata or existing.metadata or {}),
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

  local affected = MySQL.update.await([[
    UPDATE mz_houses SET
      tax_due_at = CASE WHEN owner_citizenid IS NULL OR owner_citizenid <> ? THEN NULL ELSE tax_due_at END,
      tax_grace_until = CASE WHEN owner_citizenid IS NULL OR owner_citizenid <> ? THEN NULL ELSE tax_grace_until END,
      tax_status = CASE WHEN owner_citizenid IS NULL OR owner_citizenid <> ? THEN 'disabled' ELSE tax_status END,
      tax_last_paid_at = CASE WHEN owner_citizenid IS NULL OR owner_citizenid <> ? THEN NULL ELSE tax_last_paid_at END,
      owner_citizenid = ?, public = 0, sale_enabled = 0, sale_mode = 'none'
    WHERE code = ?
  ]], { citizenid, citizenid, citizenid, citizenid, citizenid, code })

  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.updateCommerce(code, commerce)
  code = normalizeCode(code)
  if not code then return false, 'invalid_house' end
  commerce = normalizeCommerce(commerce)
  local affected = MySQL.update.await([[
    UPDATE mz_houses
    SET sale_enabled = ?, sale_mode = ?, sale_price = ?
    WHERE code = ?
  ]], { commerce.saleEnabled and 1 or 0, commerce.saleMode, commerce.salePrice, code })
  return (tonumber(affected) or 0) > 0, commerce
end

function MZHousesRepository.claimPurchase(code, citizenid, expectedPrice, expectedMode)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  expectedPrice = normalizeSalePrice(expectedPrice)
  expectedMode = normalizeSaleMode(expectedMode)
  if not code then return false, 'invalid_house' end
  if not citizenid then return false, 'invalid_citizenid' end
  if expectedPrice <= 0 or (expectedMode ~= 'direct' and expectedMode ~= 'admin') then return false, 'invalid_sale' end
  local affected = MySQL.update.await([[
    UPDATE mz_houses
    SET tax_due_at = NULL, tax_grace_until = NULL, tax_status = 'disabled',
      tax_last_paid_at = NULL, owner_citizenid = ?, public = 0,
      sale_enabled = 0, sale_mode = 'none'
    WHERE code = ? AND owner_citizenid IS NULL AND sale_enabled = 1
      AND sale_price = ? AND sale_mode = ? AND enabled = 1 AND status = 'active'
  ]], { citizenid, code, expectedPrice, expectedMode })
  return (tonumber(affected) or 0) == 1
end

function MZHousesRepository.rollbackPurchaseClaim(code, citizenid, price, mode)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  price = normalizeSalePrice(price)
  mode = normalizeSaleMode(mode)
  if not code or not citizenid or price <= 0 or mode == 'none' then return false end
  local affected = MySQL.update.await([[
    UPDATE mz_houses
    SET owner_citizenid = NULL, sale_enabled = 1, sale_mode = ?
    WHERE code = ? AND owner_citizenid = ? AND sale_enabled = 0 AND sale_mode = 'none' AND sale_price = ?
  ]], { mode, code, citizenid, price })
  return (tonumber(affected) or 0) == 1
end

function MZHousesRepository.createTransaction(data)
  data = type(data) == 'table' and data or {}
  local transactionKey = trim(data.transactionKey or data.transaction_key):sub(1, 96)
  local code = normalizeCode(data.houseCode or data.house_code)
  local buyer = normalizeCitizenId(data.buyerCitizenId or data.buyer_citizenid)
  local actor = normalizeCitizenId(data.actorCitizenId or data.actor_citizenid)
  local amount = normalizeSalePrice(data.amount)
  local mode = normalizeSaleMode(data.mode)
  if transactionKey == '' or not code or not buyer or amount <= 0 or mode == 'none' then
    return nil, 'invalid_transaction'
  end
  local id = MySQL.insert.await([[
    INSERT INTO mz_house_transactions (
      transaction_key, house_code, buyer_citizenid, actor_citizenid, seller_type,
      amount, payment_method, mode, transaction_type, status, meta_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    transactionKey, code, buyer, actor, trim(data.sellerType) ~= '' and trim(data.sellerType) or 'server',
    amount, 'bank', mode, trim(data.transactionType) ~= '' and trim(data.transactionType) or 'purchase',
    trim(data.status) ~= '' and trim(data.status) or 'initiated', encodeJson(data.meta or {})
  })
  return tonumber(id), tonumber(id) and nil or 'transaction_insert_failed'
end

function MZHousesRepository.updateTransaction(id, status, meta, completed)
  id = math.floor(tonumber(id) or 0)
  status = trim(status):lower()
  local fromByStatus = {
    payment_pending = { 'initiated' },
    money_removed = { 'payment_pending' },
    completed = { 'money_removed' },
    failed = { 'initiated', 'payment_pending' },
    refunded = { 'payment_pending', 'money_removed' },
    manual_review = { 'payment_pending', 'money_removed' }
  }
  local from = fromByStatus[status]
  if id <= 0 or not from then return false, 'invalid_transaction_status' end
  local placeholders = {}
  local params = { status, encodeJson(meta or {}), completed == true and 1 or 0, id }
  for _, previous in ipairs(from) do
    placeholders[#placeholders + 1] = '?'
    params[#params + 1] = previous
  end
  local affected = MySQL.update.await(([=[
    UPDATE mz_house_transactions
    SET status = ?, meta_json = ?, completed_at = CASE WHEN ? = 1 THEN CURRENT_TIMESTAMP ELSE completed_at END
    WHERE id = ? AND status IN (%s)
  ]=]):format(table.concat(placeholders, ', ')), params)
  if (tonumber(affected) or 0) <= 0 then return false, 'invalid_transaction_transition' end
  return true
end

function MZHousesRepository.recoverInterruptedTransactions()
  MySQL.update.await([[
    UPDATE mz_house_transactions SET status = 'failed', completed_at = CURRENT_TIMESTAMP
    WHERE status = 'initiated'
  ]], {})
  MySQL.update.await([[
    UPDATE mz_house_transactions SET status = 'manual_review'
    WHERE status IN ('payment_pending', 'money_removed')
  ]], {})
  return true
end

function MZHousesRepository.getBlockingPurchaseTransaction(code)
  code = normalizeCode(code)
  if not code then return nil end
  local row = MySQL.single.await([[
    SELECT id, status, transaction_key, created_at, updated_at
    FROM mz_house_transactions
    WHERE house_code = ? AND status IN ('payment_pending', 'money_removed', 'manual_review')
    ORDER BY id DESC LIMIT 1
  ]], { code })
  return row
end

function MZHousesRepository.hasManualReviewTransaction(code)
  local row = MZHousesRepository.getBlockingPurchaseTransaction(code)
  return row ~= nil and row.status == 'manual_review'
end

function MZHousesRepository.listTransactions(code, limit)
  code = normalizeCode(code)
  if not code then return {} end
  limit = math.max(1, math.min(100, math.floor(tonumber(limit) or 20)))
  return MySQL.query.await(([=[
    SELECT id, transaction_key, house_code, buyer_citizenid, actor_citizenid,
      seller_type, amount, payment_method, mode, transaction_type, status,
      meta_json, created_at, updated_at, completed_at
    FROM mz_house_transactions WHERE house_code = ? ORDER BY id DESC LIMIT %d
  ]=]):format(limit), { code }) or {}
end

function MZHousesRepository.updateTaxConfiguration(code, config)
  code = normalizeCode(code)
  config = normalizeTax(config)
  if not code then return false, 'invalid_house' end
  local affected = MySQL.update.await([[
    UPDATE mz_houses
    SET tax_enabled = ?, tax_amount = ?, tax_interval_days = ?, tax_grace_period_days = ?,
      tax_due_at = CASE WHEN ? = 1 THEN tax_due_at ELSE NULL END,
      tax_grace_until = CASE
        WHEN ? = 1 AND tax_due_at IS NOT NULL THEN DATE_ADD(tax_due_at, INTERVAL ? DAY)
        ELSE NULL END,
      tax_status = CASE WHEN ? = 1 AND owner_citizenid IS NOT NULL THEN tax_status ELSE 'disabled' END
    WHERE code = ?
  ]], {
    config.taxEnabled and 1 or 0, config.taxAmount, config.taxIntervalDays, config.taxGracePeriodDays,
    config.taxEnabled and 1 or 0, config.taxEnabled and 1 or 0, config.taxGracePeriodDays,
    config.taxEnabled and 1 or 0, code
  })
  return (tonumber(affected) or 0) > 0, config
end

function MZHousesRepository.initializeTaxForOwner(code, citizenid, dueAt)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  dueAt = trim(dueAt)
  if not code then return false, 'invalid_house' end
  if not citizenid then return false, 'invalid_citizenid' end
  local affected
  if dueAt ~= '' then
    affected = MySQL.update.await([[
      UPDATE mz_houses
      SET tax_due_at = ?, tax_grace_until = DATE_ADD(?, INTERVAL tax_grace_period_days DAY),
        tax_status = 'paid', tax_last_paid_at = NULL
      WHERE code = ? AND owner_citizenid = ? AND tax_enabled = 1 AND tax_amount > 0
        AND category = 'residential' AND owner_type = 'player'
        AND subtype IN ('house', 'apartment', 'apartment_unit')
        AND enabled = 1 AND status = 'active' AND tax_due_at IS NULL
    ]], { dueAt, dueAt, code, citizenid })
  else
    affected = MySQL.update.await([[
      UPDATE mz_houses
      SET tax_due_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL tax_interval_days DAY),
        tax_grace_until = DATE_ADD(DATE_ADD(UTC_TIMESTAMP(), INTERVAL tax_interval_days DAY), INTERVAL tax_grace_period_days DAY),
        tax_status = 'paid', tax_last_paid_at = NULL
      WHERE code = ? AND owner_citizenid = ? AND tax_enabled = 1 AND tax_amount > 0
        AND category = 'residential' AND owner_type = 'player'
        AND subtype IN ('house', 'apartment', 'apartment_unit')
        AND enabled = 1 AND status = 'active' AND tax_due_at IS NULL
    ]], { code, citizenid })
  end
  if (tonumber(affected) or 0) == 1 then return true, 'initialized' end
  local current = MZHousesRepository.getHouseByCode(code)
  local tax = current and normalizeTax(current) or nil
  if current and normalizeCitizenId(current.owner_citizenid or current.owner) == citizenid
      and tax and tax.taxEnabled and tax.taxAmount > 0 and trim(tax.taxDueAt) ~= '' then
    return true, 'already_initialized'
  end
  return false, 'tax_initialize_failed'
end

function MZHousesRepository.suspendTax(code, citizenid)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  if not code then return false, 'invalid_house' end
  local sql = [[
    UPDATE mz_houses SET tax_due_at = NULL, tax_grace_until = NULL, tax_status = 'disabled'
    WHERE code = ?
  ]]
  local params = { code }
  if citizenid then
    sql = sql .. ' AND owner_citizenid = ?'
    params[#params + 1] = citizenid
  end
  local affected = MySQL.update.await(sql, params)
  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.setTaxDueAt(code, dueAt)
  code = normalizeCode(code)
  dueAt = trim(dueAt)
  if not code or dueAt == '' then return false, 'invalid_tax_due_at' end
  local affected = MySQL.update.await([[
    UPDATE mz_houses
    SET tax_due_at = ?, tax_grace_until = DATE_ADD(?, INTERVAL tax_grace_period_days DAY),
      tax_status = CASE
        WHEN tax_status = 'blocked' THEN 'blocked'
        WHEN UTC_TIMESTAMP() < ? THEN 'paid'
        WHEN UTC_TIMESTAMP() <= DATE_ADD(?, INTERVAL tax_grace_period_days DAY) THEN 'due'
        ELSE 'overdue' END
    WHERE code = ? AND tax_enabled = 1 AND owner_citizenid IS NOT NULL
  ]], { dueAt, dueAt, dueAt, dueAt, code })
  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.setTaxStatus(code, status)
  code = normalizeCode(code)
  status = trim(status):lower()
  if not code then return false, 'invalid_house' end
  if status ~= 'paid' and status ~= 'due' and status ~= 'overdue' and status ~= 'blocked' then
    return false, 'invalid_tax_status'
  end
  local affected = MySQL.update.await([[
    UPDATE mz_houses SET tax_status = ?
    WHERE code = ? AND tax_enabled = 1 AND tax_amount > 0
      AND owner_citizenid IS NOT NULL AND tax_due_at IS NOT NULL
  ]], { status, code })
  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.refreshTaxStatus(code)
  code = normalizeCode(code)
  if not code then return false, 'invalid_house' end
  MySQL.update.await([[
    UPDATE mz_houses SET tax_status = CASE
      WHEN tax_enabled = 0 OR tax_amount <= 0 OR owner_citizenid IS NULL
        OR category <> 'residential' OR owner_type <> 'player'
        OR subtype NOT IN ('house', 'apartment', 'apartment_unit')
        OR enabled <> 1 OR status <> 'active' OR tax_due_at IS NULL THEN 'disabled'
      WHEN tax_status = 'blocked' THEN 'blocked'
      WHEN UTC_TIMESTAMP() < tax_due_at THEN 'paid'
      WHEN tax_grace_until IS NULL OR UTC_TIMESTAMP() <= tax_grace_until THEN 'due'
      ELSE 'overdue' END
    WHERE code = ?
  ]], { code })
  return MZHousesRepository.getHouseByCode(code)
end

function MZHousesRepository.listTaxTransitionCandidates(afterCode, limit)
  afterCode = trim(afterCode)
  limit = math.max(1, math.min(500, math.floor(tonumber(limit) or 100)))
  return MySQL.query.await(([=[
    SELECT code FROM mz_houses
    WHERE code > ? AND tax_enabled = 1 AND tax_amount > 0 AND owner_citizenid IS NOT NULL
      AND category = 'residential' AND owner_type = 'player'
      AND subtype IN ('house', 'apartment', 'apartment_unit')
      AND enabled = 1 AND status = 'active' AND tax_due_at IS NOT NULL
      AND tax_status <> 'blocked'
      AND ((tax_status = 'paid' AND tax_due_at <= UTC_TIMESTAMP())
        OR (tax_status = 'due' AND tax_grace_until IS NOT NULL AND tax_grace_until < UTC_TIMESTAMP()))
    ORDER BY code ASC LIMIT %d
  ]=]):format(limit), { afterCode }) or {}
end

function MZHousesRepository.listTaxesByOwner(citizenid)
  citizenid = normalizeCitizenId(citizenid)
  if not citizenid then return {} end
  local rows = MySQL.query.await([[
    SELECT * FROM mz_houses WHERE owner_citizenid = ? ORDER BY code ASC
  ]], { citizenid }) or {}
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = rowToHouse(row) end
  return out
end

function MZHousesRepository.createTaxPayment(data)
  data = type(data) == 'table' and data or {}
  local key = trim(data.transactionKey):sub(1, 96)
  local code = normalizeCode(data.houseCode)
  local owner = normalizeCitizenId(data.ownerCitizenId)
  local amount = normalizeSalePrice(data.amount)
  if key == '' or not code or not owner or amount <= 0 or trim(data.dueAt) == '' then
    return nil, 'invalid_tax_payment'
  end
  local id = MySQL.insert.await([[
    INSERT INTO mz_house_tax_payments (
      transaction_key, house_code, owner_citizenid, amount, payment_method,
      period_start, period_end, due_at, status, transaction_reference, metadata_json
    ) VALUES (?, ?, ?, ?, 'bank', ?, ?, ?, 'initiated', ?, ?)
  ]], {
    key, code, owner, amount, data.periodStart, data.periodEnd, data.dueAt,
    key, encodeJson(type(data.metadata) == 'table' and data.metadata or {})
  })
  return tonumber(id), tonumber(id) and nil or 'tax_payment_insert_failed'
end

function MZHousesRepository.updateTaxPayment(id, status, metadata, completed)
  id = math.floor(tonumber(id) or 0)
  status = trim(status):lower()
  local fromByStatus = {
    payment_pending = { 'initiated' }, money_removed = { 'payment_pending' },
    completed = { 'money_removed' }, failed = { 'initiated', 'payment_pending' },
    refunded = { 'payment_pending', 'money_removed' },
    manual_review = { 'payment_pending', 'money_removed' }
  }
  local from = fromByStatus[status]
  if id <= 0 or not from then return false, 'invalid_tax_payment_status' end
  local placeholders, params = {}, { status, encodeJson(metadata or {}), completed == true and 1 or 0, completed == true and 1 or 0, id }
  for _, previous in ipairs(from) do placeholders[#placeholders + 1] = '?'; params[#params + 1] = previous end
  local affected = MySQL.update.await(([=[
    UPDATE mz_house_tax_payments
    SET status = ?, metadata_json = ?,
      paid_at = CASE WHEN ? = 1 THEN UTC_TIMESTAMP() ELSE paid_at END,
      completed_at = CASE WHEN ? = 1 THEN UTC_TIMESTAMP() ELSE completed_at END
    WHERE id = ? AND status IN (%s)
  ]=]):format(table.concat(placeholders, ', ')), params)
  return (tonumber(affected) or 0) == 1
end

function MZHousesRepository.getBlockingTaxPayment(code, ownerCitizenId)
  code = normalizeCode(code)
  if not code then return nil end
  ownerCitizenId = normalizeCitizenId(ownerCitizenId)
  local sql = [[
    SELECT id, transaction_key, status, created_at, updated_at
    FROM mz_house_tax_payments
    WHERE house_code = ? AND status IN ('payment_pending', 'money_removed', 'manual_review')
  ]]
  local params = { code }
  if ownerCitizenId then
    sql = sql .. ' AND owner_citizenid = ?'
    params[#params + 1] = ownerCitizenId
  end
  return MySQL.single.await(sql .. ' ORDER BY id DESC LIMIT 1', params)
end

function MZHousesRepository.getTaxPaymentById(id)
  id = math.floor(tonumber(id) or 0)
  if id <= 0 then return nil end
  return MySQL.single.await([[
    SELECT id, transaction_key, house_code, owner_citizenid, amount,
      payment_method, period_start, period_end, due_at, paid_at, status,
      transaction_reference, metadata_json, created_at, updated_at, completed_at
    FROM mz_house_tax_payments WHERE id = ? LIMIT 1
  ]], { id })
end

function MZHousesRepository.getTaxTiming(code)
  code = normalizeCode(code)
  if not code then return nil end
  return MySQL.single.await([[
    SELECT TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), tax_due_at) AS seconds_until_due,
      TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), tax_grace_until) AS seconds_until_grace
    FROM mz_houses WHERE code = ? LIMIT 1
  ]], { code })
end

function MZHousesRepository.completeTaxPayment(id, code, citizenid, expectedAmount, expectedDueAt, metadata)
  id = math.floor(tonumber(id) or 0)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  expectedAmount = normalizeSalePrice(expectedAmount)
  expectedDueAt = trim(expectedDueAt)
  if id <= 0 or not code or not citizenid or expectedAmount <= 0 or expectedDueAt == '' then return false end
  local affected = MySQL.update.await([[
    UPDATE mz_houses AS h
    INNER JOIN mz_house_tax_payments AS p
      ON p.id = ? AND p.house_code = h.code AND p.owner_citizenid = ?
    SET h.tax_grace_until = DATE_ADD(
        DATE_ADD(GREATEST(UTC_TIMESTAMP(), h.tax_due_at), INTERVAL h.tax_interval_days DAY),
        INTERVAL h.tax_grace_period_days DAY
      ),
      h.tax_due_at = DATE_ADD(GREATEST(UTC_TIMESTAMP(), h.tax_due_at), INTERVAL h.tax_interval_days DAY),
      h.tax_last_paid_at = UTC_TIMESTAMP(), h.tax_status = 'paid',
      p.status = 'completed', p.metadata_json = ?, p.paid_at = UTC_TIMESTAMP(),
      p.completed_at = UTC_TIMESTAMP()
    WHERE h.code = ? AND h.owner_citizenid = ? AND h.tax_enabled = 1 AND h.tax_amount = ?
      AND h.tax_due_at = ? AND h.tax_status IN ('paid', 'due', 'overdue')
      AND p.status = 'money_removed'
  ]], {
    id, citizenid, encodeJson(metadata or {}),
    code, citizenid, expectedAmount, expectedDueAt
  })
  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.listTaxPayments(code, limit)
  code = normalizeCode(code)
  if not code then return {} end
  limit = math.max(1, math.min(100, math.floor(tonumber(limit) or 20)))
  return MySQL.query.await(([=[
    SELECT id, transaction_key, house_code, owner_citizenid, amount, payment_method,
      period_start, period_end, due_at, paid_at, status, transaction_reference,
      metadata_json, created_at, updated_at, completed_at
    FROM mz_house_tax_payments WHERE house_code = ? ORDER BY id DESC LIMIT %d
  ]=]):format(limit), { code }) or {}
end

function MZHousesRepository.recoverInterruptedTaxPayments()
  local failed = MySQL.update.await([[
    UPDATE mz_house_tax_payments SET status = 'failed', completed_at = UTC_TIMESTAMP()
    WHERE status = 'initiated'
  ]], {})
  local manualReview = MySQL.update.await([[
    UPDATE mz_house_tax_payments SET status = 'manual_review'
    WHERE status IN ('payment_pending', 'money_removed')
  ]], {})
  return true, {
    failed = tonumber(failed) or 0,
    manualReview = tonumber(manualReview) or 0
  }
end

function MZHousesRepository.clearOwner(code)
  code = normalizeCode(code)
  if not code then return false, 'invalid_house' end

  local affected = MySQL.update.await([[
    UPDATE mz_houses SET owner_citizenid = NULL, tax_due_at = NULL,
      tax_grace_until = NULL, tax_status = 'disabled', tax_last_paid_at = NULL
    WHERE code = ?
  ]], { code })

  return (tonumber(affected) or 0) > 0
end

function MZHousesRepository.giveKey(code, citizenid, role)
  code = normalizeCode(code)
  citizenid = normalizeCitizenId(citizenid)
  role = normalizeKeyRole(role)

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

function MZHousesRepository.giveKeyByOwner(code, ownerCitizenId, citizenid, role, maximumKeys)
  code = normalizeCode(code)
  ownerCitizenId = normalizeCitizenId(ownerCitizenId)
  citizenid = normalizeCitizenId(citizenid)
  role = normalizeKeyRole(role)
  maximumKeys = math.max(1, math.floor(tonumber(maximumKeys) or 10))
  if not code then return false, 'invalid_house' end
  if not ownerCitizenId or not citizenid then return false, 'invalid_citizenid' end

  local ok, err = pcall(function()
    MySQL.insert.await([[
      INSERT INTO mz_house_keys (house_code, citizenid, role)
      SELECT h.code, ?, ?
      FROM mz_houses h
      WHERE h.code = ? AND h.owner_citizenid = ? AND h.owner_type = 'player'
        AND h.category = 'residential' AND h.subtype IN ('house', 'apartment', 'apartment_unit')
        AND h.enabled = 1 AND h.status = 'active'
        AND (
          EXISTS (
            SELECT 1 FROM mz_house_keys existing_key
            WHERE existing_key.house_code = h.code AND existing_key.citizenid = ?
          )
          OR (
            SELECT COUNT(*) FROM mz_house_keys counted_key
            WHERE counted_key.house_code = h.code
          ) < ?
        )
      ON DUPLICATE KEY UPDATE role = VALUES(role)
    ]], { citizenid, role, code, ownerCitizenId, citizenid, maximumKeys })
  end)
  if not ok then return false, 'key_save_failed' end

  local house = MZHousesRepository.getHouseByCode(code)
  if not house or normalizeCitizenId(house.owner_citizenid or house.owner) ~= ownerCitizenId then
    return false, 'not_owner'
  end
  local keys = MZHousesRepository.listKeys(code)
  for _, row in ipairs(keys) do
    if normalizeCitizenId(row.citizenid) == citizenid and normalizeKeyRole(row.role) == role then
      MySQL.update.await(
        'UPDATE mz_houses SET public = 0 WHERE code = ? AND owner_citizenid = ?',
        { code, ownerCitizenId }
      )
      return true
    end
  end
  return false, #keys >= maximumKeys and 'key_limit_reached' or 'key_save_failed'
end

function MZHousesRepository.updateDoor(code, door)
  code = normalizeCode(code)
  door = normalizeDoor(door)
  if not code then return false, 'invalid_house' end
  if not door then return false, 'invalid_door' end
  local affected = MySQL.update.await('UPDATE mz_houses SET door_json = ? WHERE code = ?', { encodeJson(door), code })
  return (tonumber(affected) or 0) > 0
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

function MZHousesRepository.removeKeyByOwner(code, ownerCitizenId, citizenid)
  code = normalizeCode(code)
  ownerCitizenId = normalizeCitizenId(ownerCitizenId)
  citizenid = normalizeCitizenId(citizenid)
  if not code then return false, 'invalid_house' end
  if not ownerCitizenId or not citizenid then return false, 'invalid_citizenid' end
  local affected = MySQL.update.await([[
    DELETE property_key
    FROM mz_house_keys property_key
    INNER JOIN mz_houses property_house ON property_house.code = property_key.house_code
    WHERE property_house.code = ? AND property_house.owner_citizenid = ?
      AND property_house.owner_type = 'player' AND property_house.category = 'residential'
      AND property_house.subtype IN ('house', 'apartment', 'apartment_unit')
      AND property_house.enabled = 1 AND property_house.status = 'active'
      AND property_key.citizenid = ?
  ]], { code, ownerCitizenId, citizenid })
  if (tonumber(affected) or 0) > 0 then return true end
  local house = MZHousesRepository.getHouseByCode(code)
  if not house or normalizeCitizenId(house.owner_citizenid or house.owner) ~= ownerCitizenId then
    return false, 'not_owner'
  end
  return false, 'key_not_found'
end

function MZHousesRepository.clearKeys(code)
  code = normalizeCode(code)
  if not code then return false, 'invalid_house' end
  MySQL.update.await('DELETE FROM mz_house_keys WHERE house_code = ?', { code })
  return true
end

function MZHousesRepository.restoreKeys(code, snapshot)
  code = normalizeCode(code)
  if not code or type(snapshot) ~= 'table' then return false, 'invalid_key_snapshot' end
  local statements = {
    { query = 'DELETE FROM mz_house_keys WHERE house_code = ?', parameters = { code } }
  }
  for _, row in ipairs(snapshot) do
    local citizenid = normalizeCitizenId(row.citizenid)
    local role = trim(row.role):lower()
    if role ~= 'key' and role ~= 'access' and role ~= 'control' then role = 'access' end
    if not citizenid then return false, 'invalid_key_snapshot' end
    if row.created_at ~= nil then
      statements[#statements + 1] = {
        query = 'INSERT INTO mz_house_keys (house_code, citizenid, role, created_at) VALUES (?, ?, ?, ?)',
        parameters = { code, citizenid, role, row.created_at }
      }
    else
      statements[#statements + 1] = {
        query = 'INSERT INTO mz_house_keys (house_code, citizenid, role) VALUES (?, ?, ?)',
        parameters = { code, citizenid, role }
      }
    end
  end
  local ok, result = pcall(function() return MySQL.transaction.await(statements) end)
  if not ok or result ~= true then return false, ok and 'key_restore_failed' or tostring(result) end
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

function MZHousesRepository.listLogs(code, limit)
  code = normalizeCode(code)
  if not code then return {} end
  limit = math.max(1, math.min(100, math.floor(tonumber(limit) or 20)))
  return MySQL.query.await(([=[
    SELECT action, actor_citizenid, target_citizenid, meta_json, created_at
    FROM mz_house_logs WHERE house_code = ? ORDER BY id DESC LIMIT %d
  ]=]):format(limit), { code }) or {}
end
