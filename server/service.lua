MZHousesService = MZHousesService or {}

local RuntimeAccess = {}
local RuntimeHouses = {}
local DatabaseActive = false
local publicHousePayload

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
  local interior = type(house.interior) == 'table' and house.interior or {}
  local override = type(interior[pointName]) == 'table' and interior[pointName] or house[pointName]
  local point = shallowMerge(defaults and defaults[pointName] or nil, override)
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

local function normalizeHouseProperty(house)
  if MZHousesRepository and type(MZHousesRepository.normalizePropertyFields) == 'function' then
    return MZHousesRepository.normalizePropertyFields(house)
  end

  local defaults = MZHousesConfig.PropertyDefaults or {}
  local features = type(defaults.features) == 'table' and defaults.features or {}

  return {
    category = tostring(defaults.category or 'residential'),
    subtype = tostring(defaults.subtype or 'house'),
    ownerType = tostring(defaults.ownerType or 'player'),
    parentCode = nil,
    unitNumber = nil,
    orgCode = defaults.orgCode,
    businessCode = defaults.businessCode,
    features = {
      stash = features.stash ~= false,
      wardrobe = features.wardrobe ~= false,
      garage = features.garage == true,
      furniture = features.furniture == true
    }
  }
end

local function houseWithPropertyFields(house)
  local out = shallowMerge(house, nil)
  local property = normalizeHouseProperty(out)

  out.category = property.category
  out.subtype = property.subtype
  out.ownerType = property.ownerType
  out.parentCode = property.parentCode
  out.parent_code = property.parentCode
  out.unitNumber = property.unitNumber
  out.unit_number = property.unitNumber
  out.orgCode = property.orgCode
  out.businessCode = property.businessCode
  out.features = property.features

  return out
end

local function isOrgProperty(house)
  local property = normalizeHouseProperty(house)
  return property.ownerType == 'org' or property.category == 'org'
end

local function getHouseAccessMode(house)
  local property = normalizeHouseProperty(house)
  if property.ownerType == 'org' or property.category == 'org' then
    return 'org'
  end

  if property.ownerType == 'business' or property.category == 'business' then
    return 'business'
  end

  if property.ownerType == 'player' then
    return 'player'
  end

  return 'player'
end

local function debugLog(message, data)
  if MZHousesConfig.Debug ~= true then return end
  local suffix = data ~= nil and (' | %s'):format(json.encode(data)) or ''
  print(('[mz_houses][service] %s%s'):format(tostring(message), suffix))
end

local function normalizeOrgCode(value)
  local orgCode = trim(value)
  if orgCode == '' then return nil end
  return orgCode
end

local function normalizeCapability(value)
  local capability = trim(value)
  if capability == '' then return nil end
  return capability
end

local function getHouseAccessConfig(code, house)
  local configuredHouse = code and (MZHousesConfig.Houses or {})[code] or nil

  if type(configuredHouse) == 'table' and type(configuredHouse.access) == 'table' then
    return configuredHouse.access
  end

  if type(house) == 'table' and type(house.access) == 'table' then
    return house.access
  end

  return {}
end

local function getAccessRuleText(rule, defaultRequireMember)
  if type(rule) ~= 'table' then
    return 'member'
  end

  local parts = {}
  local capability = normalizeCapability(rule.requiredCapability or rule.requiredPermission)
  local gradeLevel = tonumber(rule.requiredGradeLevel)

  if capability then parts[#parts + 1] = capability end
  if gradeLevel then parts[#parts + 1] = ('grade>=%d'):format(gradeLevel) end

  if #parts == 0 then
    local shouldRequireMember = rule.requireMember
    if shouldRequireMember == nil then
      shouldRequireMember = defaultRequireMember ~= false
    end

    return shouldRequireMember == false and 'allowed' or 'member'
  end

  return table.concat(parts, '+')
end

local function safeCoreExport(exportName, ...)
  if GetResourceState('mz_core') ~= 'started' then
    debugLog('org_access_core_unavailable', {
      export = exportName,
      resourceState = GetResourceState('mz_core')
    })
    return nil, 'org_access_unavailable'
  end

  local args = { ... }
  local ok, result, extra = pcall(function()
    local coreExports = exports['mz_core']
    return coreExports[exportName](coreExports, table.unpack(args))
  end)

  if not ok then
    debugLog('org_access_core_export_failed', {
      export = exportName,
      error = tostring(result)
    })
    return nil, 'org_access_unavailable'
  end

  return result, extra
end

local function getHouseOrgCode(house)
  local property = normalizeHouseProperty(house)
  return normalizeOrgCode(property.orgCode)
end

local function runtimeAccessFromDatabaseRow(row)
  if type(row) ~= 'table' then
    return nil
  end

  local code = normalizeCode(row.code)
  if not code then
    return nil
  end

  local access = {
    public = row.public == true,
    owner = normalizeCitizenId(row.owner_citizenid),
    keys = {},
    enabled = row.enabled == true,
    status = trim(row.status) ~= '' and trim(row.status) or 'active'
  }

  for _, keyRow in ipairs(MZHousesRepository.listKeys(code)) do
    local citizenid = normalizeCitizenId(keyRow.citizenid)
    if citizenid then
      access.keys[citizenid] = true
    end
  end

  return access, code
end

local function refreshRuntimeHouse(code)
  code = normalizeCode(code)
  if not code then
    return false, 'invalid_house'
  end

  if not databaseEnabled() then
    return false, 'database_disabled'
  end

  local row = MZHousesRepository.getHouseByCode(code)
  if not row then
    return false, 'house_not_found'
  end

  local access = runtimeAccessFromDatabaseRow(row)
  RuntimeHouses[code] = row
  RuntimeAccess[code] = access
  return true, row
end

local function playerOrgMatches(org, orgCode)
  if type(org) ~= 'table' then
    return false
  end

  local code = normalizeOrgCode(org.code or org.orgCode or org.org_code)
  return code ~= nil and code == orgCode
end

local function getPlayerOrgMembership(source, orgCode)
  local orgs, err = safeCoreExport('GetPlayerOrgContext', source)
  if orgs == nil then
    orgs, err = safeCoreExport('GetPlayerOrgs', source)
  end

  if orgs == nil then
    return nil, err or 'org_access_unavailable'
  end

  if type(orgs) ~= 'table' then
    return nil, 'org_access_unavailable'
  end

  for _, org in ipairs(orgs) do
    if playerOrgMatches(org, orgCode) then
      return org
    end
  end

  return nil, 'org_access_denied'
end

local function evaluateOrgRules(source, orgCode, rules, defaultRequireMember, successReason)
  rules = type(rules) == 'table' and rules or {}

  local requiredCapability = normalizeCapability(rules.requiredCapability or rules.requiredPermission)
  local requiredGradeLevel = tonumber(rules.requiredGradeLevel)
  local shouldRequireMember = rules.requireMember
  if shouldRequireMember == nil then
    shouldRequireMember = defaultRequireMember ~= false
  end

  if requiredCapability then
    local allowed, err = safeCoreExport('CanOrg', source, orgCode, requiredCapability)
    if allowed == nil then
      return false, err or 'org_access_unavailable'
    end

    if allowed ~= true then
      return false, 'feature_capability_denied'
    end
  end

  if requiredGradeLevel then
    local allowed, err = safeCoreExport('HasGradeOrAbove', source, orgCode, requiredGradeLevel)
    if allowed == nil then
      return false, err or 'org_access_unavailable'
    end

    if allowed ~= true then
      return false, 'feature_grade_denied'
    end
  end

  if requiredCapability or requiredGradeLevel then
    return true, successReason or 'org_rule'
  end

  if shouldRequireMember ~= false then
    local membership, membershipErr = getPlayerOrgMembership(source, orgCode)
    if not membership then
      return false, membershipErr or 'org_access_denied'
    end

    return true, successReason or 'org_member'
  end

  return true, successReason or 'org_allowed'
end

local function getOrgEnterRules(accessConfig)
  if type(accessConfig) ~= 'table' then
    return {}
  end

  if type(accessConfig.enter) == 'table' then
    return accessConfig.enter
  end

  return {
    requireMember = accessConfig.requireMember,
    requiredCapability = accessConfig.requiredCapability or accessConfig.requiredPermission,
    requiredGradeLevel = accessConfig.requiredGradeLevel
  }
end

local function getFeatureAccessRules(accessConfig, featureName)
  if type(accessConfig) ~= 'table' then
    return nil
  end

  local featureAccess = type(accessConfig.features) == 'table' and accessConfig.features or nil
  local rules = featureAccess and featureAccess[featureName] or nil
  if type(rules) ~= 'table' then
    return nil
  end

  return rules
end

local function buildFeatureAccessSummary(accessConfig)
  local features = { 'stash', 'wardrobe', 'garage' }
  local summary = {}

  for _, featureName in ipairs(features) do
    local rules = getFeatureAccessRules(accessConfig, featureName)
    summary[#summary + 1] = ('%s:%s'):format(
      featureName,
      rules and getAccessRuleText(rules, false) or 'member'
    )
  end

  return table.concat(summary, ' ')
end

local function getVisibilityConfig()
  return MZHousesConfig.Visibility or {}
end

local function visibilityEnabled()
  return getVisibilityConfig().enabled == true
end

local function normalizeVisibilityMode(value)
  value = tostring(value or 'auto'):lower()
  if value == 'public' or value == 'restricted' or value == 'hidden' then
    return value
  end

  return 'auto'
end

local function getConfiguredHouse(code)
  code = normalizeCode(code)
  if not code then return nil end

  local configured = (MZHousesConfig.Houses or {})[code]
  if type(configured) == 'table' then
    return configured
  end

  return nil
end

local function getHouseVisibilityMode(code, house)
  if databaseEnabled() and type(house) == 'table' and house.visibility ~= nil then
    return normalizeVisibilityMode(house.visibility)
  end

  local configured = getConfiguredHouse(code)
  if configured and configured.visibility ~= nil then
    return normalizeVisibilityMode(configured.visibility)
  end

  if type(house) == 'table' and house.visibility ~= nil then
    return normalizeVisibilityMode(house.visibility)
  end

  return 'auto'
end

local function getHouseListingConfig(code, house)
  if databaseEnabled() and type(house) == 'table' and type(house.listing) == 'table' then
    return house.listing
  end

  local configured = getConfiguredHouse(code)
  if configured and type(configured.listing) == 'table' then
    return configured.listing
  end

  if type(house) == 'table' and type(house.listing) == 'table' then
    return house.listing
  end

  return {}
end

local function getHouseRealestateConfig(code, house)
  if databaseEnabled() and type(house) == 'table' and type(house.realestate) == 'table' then
    return house.realestate
  end

  local configured = getConfiguredHouse(code)
  if configured and type(configured.realestate) == 'table' then
    return configured.realestate
  end

  if type(house) == 'table' and type(house.realestate) == 'table' then
    return house.realestate
  end

  return {}
end

local function isListingEnabled(code, house)
  return getHouseListingConfig(code, house).enabled == true
end

local function getAdminAce()
  local admin = MZHousesConfig.Admin or {}
  local ace = trim(admin.ace)
  if ace == '' then
    ace = 'group.mz_owner'
  end
  return ace
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

local function isVisibilityAdmin(source)
  local src = tonumber(source) or 0
  if src == 0 then return true end

  local visibility = getVisibilityConfig()
  if visibility.adminSeesAll ~= true then
    return false
  end

  local admin = MZHousesConfig.Admin or {}
  if admin.requireAce ~= true then
    return true
  end

  return isAceAllowed(src, getAdminAce())
end

local function isAdminActor(source)
  local src = tonumber(source) or 0
  if src <= 0 then return false end

  local admin = MZHousesConfig.Admin or {}
  if admin.requireAce ~= true then
    return true
  end

  return isAceAllowed(src, getAdminAce())
end

local function canAccessOrgProperty(source, code, house, citizenid, isAdmin)
  if isAdmin == true then
    return true, {
      reason = 'admin',
      houseCode = code,
      accessMode = 'org',
      citizenid = citizenid
    }
  end

  local orgCode = getHouseOrgCode(house)
  if not orgCode then
    return false, 'org_code_missing'
  end

  if GetResourceState('mz_org') ~= 'started' then
    debugLog('org_access_unavailable', {
      house = code,
      orgCode = orgCode,
      resourceState = GetResourceState('mz_org')
    })
    return false, 'org_access_unavailable'
  end

  local org, orgErr = safeCoreExport('GetOrgByCode', orgCode)
  if org == nil then
    return false, orgErr or 'org_access_denied'
  end

  local accessConfig = getHouseAccessConfig(code, house)
  local allowed, reason = evaluateOrgRules(source, orgCode, getOrgEnterRules(accessConfig), true)
  if not allowed then
    return false, reason == 'feature_capability_denied' and 'org_capability_denied'
      or reason == 'feature_grade_denied' and 'org_grade_denied'
      or reason
  end

  return true, {
    reason = reason,
    houseCode = code,
    accessMode = 'org',
    orgCode = orgCode,
    citizenid = citizenid
  }
end

local function canSeeResidentialByRelation(source, access)
  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then
    return false, citizenErr or 'player_not_loaded'
  end

  if access.owner and access.owner == citizenid then
    return true, 'owner'
  end

  if access.keys and access.keys[citizenid] == true then
    return true, 'key'
  end

  return false, 'not_owner_or_key'
end

local function canSeeOrgByMembership(source, code, house)
  local orgCode = getHouseOrgCode(house)
  if not orgCode then
    return false, 'org_code_missing'
  end

  if GetResourceState('mz_org') ~= 'started' then
    return false, 'org_access_unavailable'
  end

  local org = safeCoreExport('GetOrgByCode', orgCode)
  if org == nil then
    return false, 'org_access_denied'
  end

  local membership, membershipErr = getPlayerOrgMembership(source, orgCode)
  if not membership then
    return false, membershipErr or 'not_org_member'
  end

  return true, 'org_member'
end

local function canSeeApartmentBuildingByUnit(source, buildingCode)
  local citizenid = nil
  if tonumber(source) and tonumber(source) > 0 then
    citizenid = MZHousesService.getPlayerCitizenId(source)
  end

  if not citizenid then
    return false, 'no_unit_access'
  end

  for unitCode, unitHouse in pairs(RuntimeHouses or {}) do
    local unitProperty = normalizeHouseProperty(unitHouse)
    if unitProperty.subtype == 'apartment_unit' and unitProperty.parentCode == buildingCode then
      local unitAccess = RuntimeAccess[unitCode]
      if unitAccess and unitAccess.enabled ~= false then
        if unitAccess.owner == citizenid then
          return true, 'unit_owner'
        end

        if type(unitAccess.keys) == 'table' and unitAccess.keys[citizenid] == true then
          return true, 'unit_key'
        end
      end
    end
  end

  return false, 'no_unit_access'
end

function MZHousesService.CanSeeHouse(source, houseCode, context)
  local contextType = context
  if type(context) == 'table' then
    contextType = context.type or context.context
  end
  contextType = trim(contextType)
  if contextType == '' then contextType = 'entry' end

  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return false, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  if access.enabled == false then
    return false, 'house_disabled'
  end

  if access.status == 'inactive' or access.status == 'disabled' then
    return false, 'house_inactive'
  end

  if not visibilityEnabled() then
    return true, 'visibility_disabled'
  end

  if isVisibilityAdmin(source) then
    return true, 'admin'
  end

  local mode = getHouseVisibilityMode(code, house)
  if mode == 'hidden' then
    return false, 'hidden'
  end

  if mode == 'public' then
    return true, 'public'
  end

  if contextType == 'listing' then
    return false, isListingEnabled(code, house) and 'listing_passive' or 'unlisted'
  end

  local property = normalizeHouseProperty(house)

  if property.subtype == 'apartment_building' then
    local unitVisible, unitReason = canSeeApartmentBuildingByUnit(source, code)
    if unitVisible then
      return true, unitReason
    end

    if access.public == true and getVisibilityConfig().showPublicResidential == true then
      return true, 'public_building'
    end

    if mode == 'restricted' then
      return false, unitReason
    end
  end

  if mode == 'restricted' then
    if property.ownerType == 'org' or property.category == 'org' then
      return canSeeOrgByMembership(source, code, house)
    end

    if property.ownerType == 'business' or property.category == 'business' then
      return false, 'business_restricted'
    end

    return canSeeResidentialByRelation(source, access)
  end

  if property.ownerType == 'org' or property.category == 'org' then
    if getVisibilityConfig().showOrgPropertiesToNonMembers == true then
      return true, 'org_visible_public'
    end

    return canSeeOrgByMembership(source, code, house)
  end

  if property.ownerType == 'business' or property.category == 'business' then
    if getVisibilityConfig().showBusinessPropertiesToPublic == true then
      return true, 'business_public'
    end

    return false, 'business_hidden'
  end

  if access.public == true and getVisibilityConfig().showPublicResidential == true then
    return true, 'public_residential'
  end

  local relationAllowed, relationReason = canSeeResidentialByRelation(source, access)
  if relationAllowed then
    return true, relationReason
  end

  if access.owner and getVisibilityConfig().showOwnedResidentialToEveryone == true then
    return true, 'owned_residential_public'
  end

  if not access.owner and not isListingEnabled(code, house)
    and getVisibilityConfig().showUnlistedAvailableResidential == true then
    return true, 'unlisted_available_residential'
  end

  if not access.owner and not isListingEnabled(code, house) then
    return false, 'unlisted'
  end

  if isListingEnabled(code, house) then
    return false, 'listing_only'
  end

  return false, relationReason or 'unlisted'
end

local function canAccessHouseFeature(source, houseCode, featureName, isAdmin)
  local accessAllowed, accessResult = MZHousesService.canEnterHouse(source, houseCode, isAdmin)
  if not accessAllowed then
    return false, accessResult or 'no_house_access'
  end

  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return false, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  if not isOrgProperty(house) then
    return true, type(accessResult) == 'table' and accessResult.reason or 'allowed'
  end

  if isAdmin == true then
    return true, 'admin'
  end

  local orgCode = getHouseOrgCode(house)
  if not orgCode then
    return false, 'org_code_missing'
  end

  local rules = getFeatureAccessRules(getHouseAccessConfig(code, house), featureName)
  if not rules then
    return true, type(accessResult) == 'table' and accessResult.reason or 'org_member'
  end

  local allowed, reason = evaluateOrgRules(source, orgCode, rules, false, 'feature_allowed')
  if not allowed then
    return false, reason or 'feature_access_denied'
  end

  return true, reason or 'feature_allowed'
end

local function rejectBuildingOwnershipMutation(houseCode)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return false, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  local property = normalizeHouseProperty(house)
  if property.subtype == 'apartment_building' then
    return false, 'predio_nao_recebe_dono_use_unidade'
  end

  return true, nil, code, house
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
    RuntimeHouses[code] = houseWithPropertyFields(house)
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
    RuntimeHouses[code] = houseWithPropertyFields(house)
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
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
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

  house = RuntimeHouses[code] or house or {}
  if isOrgProperty(house) then
    local citizenid = nil
    if tonumber(source) and tonumber(source) > 0 then
      citizenid = MZHousesService.getPlayerCitizenId(source)
    end

    local orgAllowed, orgResult = canAccessOrgProperty(source, code, house, citizenid, false)
    if orgAllowed then
      return true, orgResult
    end

    MZHousesService.log('house.enter.denied', code, source, citizenid, {
      reason = orgResult or 'org_access_denied',
      accessMode = 'org',
      orgCode = getHouseOrgCode(house)
    })

    return false, orgResult or 'org_access_denied'
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

function MZHousesService.ResolveEntryContext(source, houseCode, isAdmin)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return nil, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  local property = normalizeHouseProperty(house)

  if property.subtype == 'apartment_building' then
    return {
      ok = false,
      kind = 'apartment_building',
      property = publicHousePayload(code, house, { entryVisible = true, garageVisible = true }),
      entrance = vector4Payload(house.entrance),
      reason = 'building_has_no_shell_use_intercom'
    }
  end

  if property.subtype == 'apartment_unit' then
    local parentCode = normalizeCode(property.parentCode)
    if not parentCode then
      return nil, 'invalid_parent_building'
    end

    local parentAccess, parentErr, resolvedParentCode, parentHouse = MZHousesService.getAccessState(parentCode)
    if not parentAccess then
      return nil, parentErr or 'invalid_parent_building'
    end

    parentHouse = RuntimeHouses[resolvedParentCode] or parentHouse or {}
    local parentProperty = normalizeHouseProperty(parentHouse)
    if parentProperty.subtype ~= 'apartment_building' then
      return nil, 'invalid_parent_building'
    end

    local parentEntrance = asVector4(parentHouse.entrance)
    if not parentEntrance then
      MZHousesService.log('house.apartment.invalid_entrance', code, source, nil, {
        buildingCode = resolvedParentCode,
        reason = 'invalid_building_entrance'
      })
      return nil, 'invalid_building_entrance'
    end

    local allowed, accessResult = MZHousesService.canEnterHouse(source, code, isAdmin == true)
    if not allowed then
      MZHousesService.log('house.apartment.unit.denied', code, source, nil, {
        buildingCode = resolvedParentCode,
        unitNumber = property.unitNumber,
        reason = accessResult or 'no_house_access'
      })
      return nil, accessResult or 'no_house_access'
    end

    return {
      ok = true,
      kind = 'apartment_unit',
      property = publicHousePayload(code, house, { entryVisible = true, garageVisible = true }),
      building = publicHousePayload(resolvedParentCode, parentHouse, { entryVisible = true, garageVisible = true }),
      entrance = vector4Payload(parentEntrance),
      reason = type(accessResult) == 'table' and accessResult.reason or accessResult or 'allowed'
    }
  end

  local entrance = asVector4(house.entrance)
  if not entrance then
    return nil, 'invalid_entrance'
  end

  return {
    ok = true,
    kind = 'house',
    property = publicHousePayload(code, house, { entryVisible = true, garageVisible = true }),
    entrance = vector4Payload(entrance),
    reason = 'own_entrance'
  }
end

function MZHousesService.getHouseStashConfig(houseCode)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return nil, err or 'house_not_found'
  end

  local configuredHouse = RuntimeHouses[code] or house or getConfiguredHouse(code)
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

  local accessAllowed, accessResult = canAccessHouseFeature(
    source,
    houseCode,
    'stash',
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
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return nil, err or 'house_not_found'
  end

  local configuredHouse = RuntimeHouses[code] or house or getConfiguredHouse(code)
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

  local accessAllowed, accessResult = canAccessHouseFeature(
    source,
    houseCode,
    'wardrobe',
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
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return nil, err or 'house_not_found'
  end

  local configuredHouse = RuntimeHouses[code] or house or getConfiguredHouse(code)
  if type(configuredHouse) ~= 'table' then
    return nil, 'house_not_found'
  end
  local property = normalizeHouseProperty(configuredHouse)
  local garageHouse = configuredHouse

  if property.subtype == 'apartment_unit' and property.parentCode then
    local parentAccess, parentErr, parentCode, parentHouse = MZHousesService.getAccessState(property.parentCode)
    if not parentAccess then
      return nil, parentErr or 'parent_not_found'
    end

    parentHouse = RuntimeHouses[parentCode] or parentHouse
    if type(parentHouse) ~= 'table' then
      return nil, 'parent_not_found'
    end

    garageHouse = parentHouse
  end

  local garageConfig = MZHousesConfig.Garage or {}
  if garageConfig.enabled ~= true then
    return nil, 'garage_disabled'
  end

  local houseGarage = type(garageHouse.garage) == 'table' and garageHouse.garage or {}
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
    label = property.subtype == 'apartment_unit'
      and ('Garagem Apt %s'):format(tostring(property.unitNumber or code))
      or trim(houseGarage.label) ~= '' and trim(houseGarage.label)
      or ('Garagem - ' .. tostring(configuredHouse.label or code)),
    garageId = property.subtype == 'apartment_unit' and property.parentCode
      and ('apt:%s:%s'):format(property.parentCode, tostring(property.unitNumber or code))
      or trim(houseGarage.garageId or houseGarage.garage_id) ~= '' and trim(houseGarage.garageId or houseGarage.garage_id)
      or ('house:' .. code),
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

  local accessAllowed, accessResult = canAccessHouseFeature(
    source,
    houseCode,
    'garage',
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

  local _, _, _, openedHouse = MZHousesService.getAccessState(code)
  local openedProperty = normalizeHouseProperty(openedHouse or {})
  if openedProperty.subtype == 'apartment_unit' then
    MZHousesService.log('house.apartment.garage.open', code, source, actorCitizenId, {
      buildingCode = openedProperty.parentCode,
      unitNumber = openedProperty.unitNumber,
      garageId = result and result.garageId or nil,
      action = action
    })
  end

  return true, {
    houseCode = code,
    garageId = result and result.garageId or nil,
    label = garage.label,
    action = action == 'store' and 'store' or 'open'
  }
end

function MZHousesService.setHouseOwner(houseCode, citizenid, actorSource)
  local mutationAllowed, mutationErr = rejectBuildingOwnershipMutation(houseCode)
  if not mutationAllowed then return false, mutationErr end

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
  local mutationAllowed, mutationErr = rejectBuildingOwnershipMutation(houseCode)
  if not mutationAllowed then return false, mutationErr end

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
  local mutationAllowed, mutationErr = rejectBuildingOwnershipMutation(houseCode)
  if not mutationAllowed then return false, mutationErr end

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
  local mutationAllowed, mutationErr = rejectBuildingOwnershipMutation(houseCode)
  if not mutationAllowed then return false, mutationErr end

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

function MZHousesService.canPlayerManageProperty(source, houseCode, isAdmin)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then return false, err or 'house_not_found' end

  if isAdmin == true or isAdminActor(source) then
    return true, 'admin'
  end

  if access.enabled == false then
    return false, 'house_disabled'
  end

  house = RuntimeHouses[code] or house or {}
  local property = normalizeHouseProperty(house)
  if property.ownerType ~= 'player' or property.category == 'org' then
    return false, 'not_player_property'
  end

  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then
    return false, citizenErr or 'player_not_loaded'
  end

  if access.owner and access.owner == citizenid then
    return true, 'owner'
  end

  return false, 'not_owner'
end

function MZHousesService.CanPropertyBeListed(houseCode)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return false, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  if access.enabled == false then
    return false, 'disabled'
  end

  local status = trim(access.status)
  if status == 'archived' then
    return false, 'archived'
  end

  if status == 'inactive' or status == 'disabled' then
    return false, 'disabled'
  end

  if getHouseVisibilityMode(code, house) == 'hidden' then
    return false, 'hidden'
  end

  local property = normalizeHouseProperty(house)
  if property.ownerType == 'org' or property.category == 'org' then
    return false, 'org_property'
  end

  if property.category ~= 'residential' then
    return false, 'not_residential'
  end

  if property.ownerType ~= 'player' then
    return false, 'not_player_property'
  end

  local realestate = getHouseRealestateConfig(code, house)
  if realestate.canBeListed == false then
    return false, 'not_listable'
  end

  return true, 'listable'
end

local function isValidAdminCode(code)
  code = normalizeCode(code)
  return code ~= nil and code:match('^[%w_%-]+$') ~= nil and #code <= 80
end

local function getDefaultAdminShell()
  local shell = trim(MZHousesConfig.DefaultShell)
  if shell == '' then
    shell = 'shell_test'
  end
  return shell
end

function MZHousesService.ListAvailableShells()
  local out = {}
  local seen = {}

  if GetResourceState('mz_interiors') == 'started' then
    local ok, shells = pcall(function()
      return exports['mz_interiors']:GetShells()
    end)

    if ok and type(shells) == 'table' then
      for name, shell in pairs(shells) do
        local shellName = nil
        local label = nil
        local enabled = false
        local reason = nil

        if type(shell) == 'table' and shell.name ~= nil then
          shellName = trim(shell.name)
          label = trim(shell.label) ~= '' and trim(shell.label) or shellName
          enabled = shell.enabled ~= false and shell.selectable ~= false
          reason = shell.disabledReason
        elseif type(shell) == 'table' then
          shellName = trim(name)
          label = trim(shell.label) ~= '' and trim(shell.label) or shellName
          enabled = shell.enabled ~= false and shell.exit ~= nil and trim(shell.model) ~= ''
          reason = shell.disabledReason
        end

        if shellName ~= '' and not seen[shellName] then
          seen[shellName] = true
          out[#out + 1] = {
            name = shellName,
            label = label,
            enabled = enabled == true,
            selectable = enabled == true,
            disabledReason = enabled == true and nil or (reason or 'shell_disabled')
          }
        end
      end
    end
  end

  if #out == 0 then
    for shellName, defaults in pairs(MZHousesConfig.InteriorDefaults or {}) do
      local normalizedShellName = trim(shellName)
      if normalizedShellName ~= '' and not seen[normalizedShellName] then
        seen[normalizedShellName] = true
        out[#out + 1] = {
          name = normalizedShellName,
          label = trim(defaults and defaults.label) ~= '' and trim(defaults.label) or normalizedShellName,
          enabled = true,
          selectable = true
        }
      end
    end
  end

  table.sort(out, function(left, right)
    return tostring(left.label or left.name or '') < tostring(right.label or right.name or '')
  end)

  return out
end

function MZHousesService.IsShellSelectable(shellName)
  shellName = trim(shellName)
  if shellName == '' then
    return false, 'invalid_shell'
  end

  for _, shell in ipairs(MZHousesService.ListAvailableShells() or {}) do
    if trim(shell.name) == shellName then
      if shell.enabled == true and shell.selectable ~= false then
        return true, 'ok'
      end

      return false, shell.disabledReason or 'shell_disabled'
    end
  end

  return false, 'shell_not_found'
end

local function slug(value, fallback)
  local text = trim(value):lower()
  text = text:gsub('[%z\1-\127\194-\244][\128-\191]*', function(char)
    local map = {
      ['á'] = 'a', ['à'] = 'a', ['ã'] = 'a', ['â'] = 'a', ['ä'] = 'a',
      ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
      ['í'] = 'i', ['ì'] = 'i', ['î'] = 'i', ['ï'] = 'i',
      ['ó'] = 'o', ['ò'] = 'o', ['õ'] = 'o', ['ô'] = 'o', ['ö'] = 'o',
      ['ú'] = 'u', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u',
      ['ç'] = 'c'
    }
    return map[char] or char
  end)
  text = text:gsub('[^a-z0-9]+', '_'):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
  if text == '' then text = fallback or 'item' end
  return text
end

local function codeExists(code)
  code = normalizeCode(code)
  if not code then return false end
  if RuntimeHouses[code] ~= nil then return true end
  if databaseEnabled() and MZHousesRepository.getHouseByCode(code) ~= nil then return true end
  return false
end

function MZHousesService.getNextSequence(prefix)
  prefix = slug(prefix, 'property')
  local highest = 0
  local pattern = '^' .. prefix:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1') .. '_(%d%d%d%d%d%d)$'

  local function scan(code)
    local numberText = tostring(code or ''):match(pattern)
    local numberValue = tonumber(numberText)
    if numberValue and numberValue > highest then
      highest = numberValue
    end
  end

  for code in pairs(RuntimeHouses or {}) do
    scan(code)
  end

  if databaseEnabled() then
    for _, row in ipairs(MZHousesRepository.listHouses() or {}) do
      scan(row.code)
    end
  end

  return highest + 1
end

local function sequenceCode(prefix)
  prefix = slug(prefix, 'property')
  local sequence = MZHousesService.getNextSequence(prefix)
  local code = nil
  repeat
    code = ('%s_%06d'):format(prefix, sequence)
    sequence = sequence + 1
  until not codeExists(code)

  return code
end

local function buildingNumberFromCode(code)
  local numberText = tostring(code or ''):match('^apt_building_(%d%d%d%d%d%d)$')
  return numberText or tostring(code or ''):gsub('^apt_building_', ''):gsub('[^%w]', '')
end

local function unitCode(buildingCode, unitNumber)
  return ('apt_%s_%s'):format(buildingNumberFromCode(buildingCode), slug(unitNumber, 'unit'))
end

local function defaultAdminFeatures()
  return {
    stash = true,
    wardrobe = true,
    garage = false,
    furniture = false
  }
end

local function defaultAdminListing()
  return {
    enabled = false,
    type = 'sale',
    price = nil,
    label = 'Imovel a venda',
    description = nil,
    sign = {
      enabled = false,
      coords = nil,
      heading = 0.0
    }
  }
end

local function defaultAdminRealestate(canBeListed)
  return {
    enabled = false,
    canBeListed = canBeListed ~= false,
    defaultPrice = nil,
    listingType = 'sale'
  }
end

local function defaultAdminGarage()
  return {
    enabled = false,
    label = 'Garagem da Casa',
    mode = 'private',
    slots = tonumber((MZHousesConfig.Garage or {}).defaultSlots) or 2,
    entry = nil,
    spawn = nil,
    store = nil,
    storeRadius = tonumber((MZHousesConfig.Garage or {}).storeRadius) or 4.0,
    vehicleTypes = { 'car', 'bike' }
  }
end

local function defaultAdminInterior()
  return {}
end

local function getPersistableHouseData(code, patch)
  patch = type(patch) == 'table' and patch or {}
  local access = RuntimeAccess[code] or {}
  local house = RuntimeHouses[code] or {}
  local currentPublic = access.public == true
  local nextPublic = currentPublic
  if patch.public ~= nil then
    nextPublic = patch.public == true
  end

  local nextEnabled = access.enabled == true
  if patch.enabled ~= nil then
    nextEnabled = patch.enabled == true
  end

  return {
    code = code,
    label = patch.label ~= nil and patch.label or house.label or code,
    category = patch.category ~= nil and patch.category or house.category or 'residential',
    subtype = patch.subtype ~= nil and patch.subtype or house.subtype or 'house',
    ownerType = patch.ownerType ~= nil and patch.ownerType or house.ownerType or house.owner_type or 'player',
    parentCode = patch.parentCode ~= nil and patch.parentCode or house.parentCode or house.parent_code,
    unitNumber = patch.unitNumber ~= nil and patch.unitNumber or house.unitNumber or house.unit_number,
    orgCode = patch.orgCode ~= nil and patch.orgCode or house.orgCode or house.org_code,
    businessCode = patch.businessCode ~= nil and patch.businessCode or house.businessCode or house.business_code,
    building = patch.building ~= nil and patch.building or house.building,
    type = patch.type ~= nil and patch.type or house.type or 'shell',
    shell = patch.shell ~= nil and patch.shell or house.shell or getDefaultAdminShell(),
    entrance = patch.entrance ~= nil and patch.entrance or house.entrance,
    garage = patch.garage ~= nil and patch.garage or house.garage or defaultAdminGarage(),
    interior = patch.interior ~= nil and patch.interior or house.interior or defaultAdminInterior(),
    features = patch.features ~= nil and patch.features or house.features or defaultAdminFeatures(),
    visibility = patch.visibility ~= nil and patch.visibility or house.visibility or 'restricted',
    listing = patch.listing ~= nil and patch.listing or house.listing or defaultAdminListing(),
    realestate = patch.realestate ~= nil and patch.realestate or house.realestate or defaultAdminRealestate(true),
    status = patch.status ~= nil and patch.status or access.status or house.status or 'active',
    enabled = nextEnabled,
    access = {
      public = nextPublic
    }
  }
end

local function refreshAfterAdminUpdate(code, action, actorSource, meta)
  local refreshed = refreshRuntimeHouse(code)
  MZHousesService.log(action, code, actorSource, nil, meta or {})
  return refreshed
end

function MZHousesService.createAdminProperty(actorSource, payload)
  payload = type(payload) == 'table' and payload or {}
  local code = normalizeCode(payload.code)
  if not isValidAdminCode(code) then
    return false, 'invalid_code'
  end

  if not databaseEnabled() then
    return false, 'database_disabled'
  end

  if MZHousesRepository.getHouseByCode(code) then
    return false, 'house_exists'
  end

  local label = trim(payload.label)
  if label == '' then
    return false, 'invalid_label'
  end

  local entrance = asVector4(payload.entrance)
  if not entrance then
    return false, 'invalid_entrance'
  end

  local shellName = trim(payload.shell) ~= '' and trim(payload.shell) or getDefaultAdminShell()
  local shellOk, shellErr = MZHousesService.IsShellSelectable(shellName)
  if not shellOk then
    return false, shellErr or 'invalid_shell'
  end

  local data = {
    label = label,
    category = 'residential',
    subtype = 'house',
    ownerType = 'player',
    orgCode = nil,
    businessCode = nil,
    type = 'shell',
    shell = shellName,
    entrance = entrance,
    status = 'draft',
    enabled = true,
    visibility = 'restricted',
    features = defaultAdminFeatures(),
    access = { public = false },
    listing = defaultAdminListing(),
    realestate = defaultAdminRealestate(true),
    garage = defaultAdminGarage(),
    interior = defaultAdminInterior()
  }

  local ok, err = MZHousesRepository.createHouseFromAdmin(code, data)
  if not ok then
    return false, err or 'create_failed'
  end

  refreshRuntimeHouse(code)
  MZHousesService.log('house.admin.create', code, actorSource, nil, {
    label = label,
    entrance = vector4Payload(entrance),
    shell = data.shell
  })

  return true, { houseCode = code, label = label }
end

function MZHousesService.generatePropertyCode(kind, data)
  kind = slug(kind, 'house')
  data = type(data) == 'table' and data or {}

  if kind == 'house' or kind == 'residential_house' then
    return sequenceCode('house')
  end

  if kind == 'apartment_building' or kind == 'apt_building' then
    return sequenceCode('apt_building')
  end

  if kind == 'apartment_unit' or kind == 'apt_unit' then
    local parentCode = normalizeCode(data.parentCode or data.parent_code)
    local unitNumber = slug(data.unitNumber or data.unit_number, 'unit')
    if not parentCode then return nil, 'invalid_parent' end
    local code = unitCode(parentCode, unitNumber)
    if codeExists(code) then
      return nil, 'unit_exists'
    end
    return code
  end

  if kind == 'org_base' or kind == 'gang_base' or kind == 'fac_base' then
    local orgCode = slug(data.orgCode or data.org_code, 'org')
    return sequenceCode(('org_base_%s'):format(orgCode))
  end

  if kind == 'business' or kind == 'government' then
    local subtype = slug(data.subtype, kind == 'government' and 'office' or 'office')
    local prefix = kind == 'government' and ('gov_%s'):format(subtype) or ('business_%s'):format(subtype)
    return sequenceCode(prefix)
  end

  return sequenceCode(kind)
end

local function defaultStructuredLabel(code, label, prefix)
  label = trim(label)
  if label ~= '' then return label end
  local numberText = tostring(code or ''):match('(%d%d%d%d%d%d)$') or tostring(code or '')
  return ('%s %s'):format(prefix or 'Imovel', numberText)
end

local function insertAdminHouse(actorSource, code, data, action, meta)
  local ok, err = MZHousesRepository.createHouseFromAdmin(code, data)
  if not ok then
    return false, err or 'create_failed'
  end

  refreshRuntimeHouse(code)
  MZHousesService.log(action or 'house.admin.structured.create', code, actorSource, nil, meta or {
    code = code,
    label = data.label
  })

  return true, { houseCode = code, label = data.label }
end

function MZHousesService.createStructuredProperty(actorSource, payload)
  payload = type(payload) == 'table' and payload or {}
  if not databaseEnabled() then
    return false, 'database_disabled'
  end

  local kind = slug(payload.kind or payload.type or 'house', 'house')
  local entrance = asVector4(payload.entrance)
  if not entrance then
    return false, 'invalid_entrance'
  end

  local shellName = trim(payload.shell) ~= '' and trim(payload.shell) or getDefaultAdminShell()
  local garageEnabled = payload.garageEnabled == true
  local garage = defaultAdminGarage()
  garage.enabled = garageEnabled
  local features = defaultAdminFeatures()
  features.garage = garageEnabled

  if kind == 'house' or kind == 'residential_house' then
    local shellOk, shellErr = MZHousesService.IsShellSelectable(shellName)
    if not shellOk then return false, shellErr or 'invalid_shell' end
    local code = MZHousesService.generatePropertyCode('house', payload)
    local data = {
      label = defaultStructuredLabel(code, payload.label, 'Casa'),
      category = 'residential',
      subtype = 'house',
      ownerType = 'player',
      type = 'shell',
      shell = shellName,
      entrance = entrance,
      status = 'draft',
      enabled = true,
      visibility = trim(payload.visibility) ~= '' and trim(payload.visibility) or 'restricted',
      features = features,
      access = { public = false },
      listing = defaultAdminListing(),
      realestate = defaultAdminRealestate(payload.canBeListed ~= false),
      garage = garage,
      interior = defaultAdminInterior()
    }
    return insertAdminHouse(actorSource, code, data, 'house.admin.structured.create', { kind = 'house', code = code })
  end

  if kind == 'apartment_building' or kind == 'apt_building' then
    local floors = clampInteger(payload.floors, 1, 1, 100)
    local unitsPerFloor = clampInteger(payload.unitsPerFloor, 1, 1, 50)
    local firstFloor = clampInteger(payload.firstFloor, 1, 0, 999)
    local createUnits = payload.createUnits == true
    local shellOk, shellErr = MZHousesService.IsShellSelectable(shellName)
    if createUnits and not shellOk then return false, shellErr or 'invalid_shell' end

    local code = MZHousesService.generatePropertyCode('apartment_building', payload)
    local building = {
      floors = floors,
      unitsPerFloor = unitsPerFloor,
      firstFloor = firstFloor,
      unitPattern = 'floor_number',
      sharedEntrance = true,
      sharedGarage = garageEnabled,
      intercom = true,
      defaultUnitShell = shellName
    }
    local data = {
      label = defaultStructuredLabel(code, payload.label, 'Edificio'),
      category = 'residential',
      subtype = 'apartment_building',
      ownerType = 'server',
      type = 'building',
      shell = nil,
      entrance = entrance,
      status = 'draft',
      enabled = true,
      visibility = 'public',
      features = { stash = false, wardrobe = false, garage = garageEnabled, furniture = false },
      access = { public = false },
      listing = defaultAdminListing(),
      realestate = defaultAdminRealestate(false),
      garage = garage,
      interior = defaultAdminInterior(),
      building = building
    }

    local ok, result = insertAdminHouse(actorSource, code, data, 'house.admin.apartment_building.create', {
      kind = 'apartment_building',
      floors = floors,
      unitsPerFloor = unitsPerFloor,
      createUnits = createUnits
    })
    if not ok then return false, result end

    local createdUnits = {}
    if createUnits then
      for floor = firstFloor, firstFloor + floors - 1 do
        for index = 1, unitsPerFloor do
          local unitNumber = ('%d%02d'):format(floor, index)
          local unitCodeValue = unitCode(code, unitNumber)
          local unitData = {
            label = ('Apartamento %s'):format(unitNumber),
            category = 'residential',
            subtype = 'apartment_unit',
            ownerType = 'player',
            parentCode = code,
            unitNumber = unitNumber,
            type = 'shell',
            shell = shellName,
            entrance = nil,
            status = 'draft',
            enabled = true,
            visibility = 'restricted',
            features = { stash = true, wardrobe = true, garage = garageEnabled, furniture = false },
            access = { public = false },
            listing = defaultAdminListing(),
            realestate = defaultAdminRealestate(true),
            garage = { enabled = garageEnabled, label = ('Garagem Apt %s'):format(unitNumber), mode = 'private', slots = garage.slots, storeRadius = garage.storeRadius, vehicleTypes = garage.vehicleTypes },
            interior = defaultAdminInterior()
          }
          local unitOk, unitErr = insertAdminHouse(actorSource, unitCodeValue, unitData, 'house.admin.apartment_unit.create', {
            buildingCode = code,
            unitNumber = unitNumber
          })
          if not unitOk then return false, unitErr end
          createdUnits[#createdUnits + 1] = unitCodeValue
        end
      end
    end

    return true, { houseCode = code, label = data.label, units = createdUnits }
  end

  if kind == 'apartment_unit' or kind == 'apt_unit' then
    local parentCode = normalizeCode(payload.parentCode or payload.parent_code)
    local rawUnitNumber = trim(payload.unitNumber or payload.unit_number)
    if not parentCode then return false, 'invalid_parent' end
    if rawUnitNumber == '' then return false, 'invalid_unit_number' end
    local unitNumber = slug(rawUnitNumber, 'unit')
    local parent = RuntimeHouses[parentCode] or (databaseEnabled() and MZHousesRepository.getHouseByCode(parentCode) or nil)
    if type(parent) ~= 'table' or parent.subtype ~= 'apartment_building' then
      return false, 'parent_not_building'
    end
    local shellOk, shellErr = MZHousesService.IsShellSelectable(shellName)
    if not shellOk then return false, shellErr or 'invalid_shell' end
    local code, codeErr = MZHousesService.generatePropertyCode('apartment_unit', { parentCode = parentCode, unitNumber = unitNumber })
    if not code then return false, codeErr or 'unit_exists' end
    local parentGarage = type(parent.garage) == 'table' and parent.garage or {}
    local unitGarageEnabled = parentGarage.enabled == true or garageEnabled
    local data = {
      label = trim(payload.label) ~= '' and trim(payload.label) or ('Apartamento %s'):format(unitNumber),
      category = 'residential',
      subtype = 'apartment_unit',
      ownerType = 'player',
      parentCode = parentCode,
      unitNumber = unitNumber,
      type = 'shell',
      shell = shellName,
      entrance = nil,
      status = 'draft',
      enabled = true,
      visibility = 'restricted',
      features = { stash = true, wardrobe = true, garage = unitGarageEnabled, furniture = false },
      access = { public = false },
      listing = defaultAdminListing(),
      realestate = defaultAdminRealestate(true),
      garage = { enabled = unitGarageEnabled, label = ('Garagem Apt %s'):format(unitNumber), mode = 'private', slots = tonumber(parentGarage.slots) or garage.slots, storeRadius = tonumber(parentGarage.storeRadius) or garage.storeRadius, vehicleTypes = parentGarage.vehicleTypes or garage.vehicleTypes },
      interior = defaultAdminInterior()
    }
    return insertAdminHouse(actorSource, code, data, 'house.admin.unit.create', { buildingCode = parentCode, unitNumber = unitNumber })
  end

  if kind == 'org_base' or kind == 'gang_base' or kind == 'fac_base' then
    local orgCode = slug(payload.orgCode or payload.org_code, '')
    if orgCode == '' then return false, 'invalid_org' end
    local shellOk, shellErr = MZHousesService.IsShellSelectable(shellName)
    if not shellOk then return false, shellErr or 'invalid_shell' end
    local subtype = kind == 'fac_base' and 'fac_base' or kind == 'org_base' and 'org_base' or 'gang_base'
    local code = MZHousesService.generatePropertyCode('org_base', { orgCode = orgCode })
    local data = {
      label = trim(payload.label) ~= '' and trim(payload.label) or ('Base %s'):format(orgCode),
      category = 'org',
      subtype = subtype,
      ownerType = 'org',
      orgCode = orgCode,
      type = 'shell',
      shell = shellName,
      entrance = entrance,
      status = 'draft',
      enabled = true,
      visibility = 'restricted',
      features = features,
      access = { public = false },
      listing = defaultAdminListing(),
      realestate = defaultAdminRealestate(false),
      garage = garage,
      interior = defaultAdminInterior()
    }
    return insertAdminHouse(actorSource, code, data, 'house.admin.org_base.create', { orgCode = orgCode, subtype = subtype })
  end

  if kind == 'business' or kind == 'government' then
    local subtype = slug(payload.subtype, 'office')
    local shellOk, shellErr = MZHousesService.IsShellSelectable(shellName)
    if not shellOk then return false, shellErr or 'invalid_shell' end
    local code = MZHousesService.generatePropertyCode(kind, { subtype = subtype })
    local category = kind == 'government' and 'government' or 'business'
    local data = {
      label = trim(payload.label) ~= '' and trim(payload.label) or (category == 'government' and 'Governo' or 'Business'),
      category = category,
      subtype = subtype,
      ownerType = category == 'government' and 'server' or 'business',
      businessCode = trim(payload.businessCode or payload.business_code) ~= '' and trim(payload.businessCode or payload.business_code) or nil,
      type = 'shell',
      shell = shellName,
      entrance = entrance,
      status = 'draft',
      enabled = true,
      visibility = 'restricted',
      features = features,
      access = { public = false },
      listing = defaultAdminListing(),
      realestate = defaultAdminRealestate(false),
      garage = garage,
      interior = defaultAdminInterior()
    }
    return insertAdminHouse(actorSource, code, data, 'house.admin.business.create', { category = category, subtype = subtype })
  end

  return false, 'unsupported_kind'
end

function MZHousesService.updateAdminProperty(actorSource, houseCode, patch, action, meta)
  local code = normalizeCode(houseCode)
  if not code then
    return false, 'invalid_house'
  end

  if not databaseEnabled() then
    return false, 'database_disabled'
  end

  patch = type(patch) == 'table' and patch or {}
  if patch.shell ~= nil then
    local shellOk, shellErr = MZHousesService.IsShellSelectable(patch.shell)
    if not shellOk then
      return false, shellErr or 'invalid_shell'
    end
  end

  local access = MZHousesService.getAccessState(code)
  if not access then
    return false, 'house_not_found'
  end

  local data = getPersistableHouseData(code, patch)
  local ok, err = MZHousesRepository.updateHouseFromAdmin(code, data)
  if not ok then
    return false, err or 'update_failed'
  end

  refreshAfterAdminUpdate(code, action or 'house.admin.update', actorSource, meta or patch)
  return true, { houseCode = code }
end

function MZHousesService.listHouseKeys(houseCode, source, isAdmin)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then return false, err end

  local keys = {}
  for citizenid, enabled in pairs(access.keys or {}) do
    if enabled == true then keys[#keys + 1] = citizenid end
  end
  table.sort(keys)

  house = RuntimeHouses[code] or house or {}
  local property = normalizeHouseProperty(house)
  local currentAccess = nil
  local currentAccessReason = nil
  local accessConfig = getHouseAccessConfig(code, house)

  if source ~= nil then
    local allowed, accessResult = MZHousesService.canEnterHouse(source, code, isAdmin)
    currentAccess = allowed == true
    if allowed == true and type(accessResult) == 'table' then
      currentAccessReason = accessResult.reason or 'allowed'
    else
      currentAccessReason = accessResult or 'no_house_access'
    end
  end

  local canBeListed, canBeListedReason = MZHousesService.CanPropertyBeListed(code)

  return true, {
    houseCode = code,
    public = access.public == true,
    owner = access.owner,
    keys = keys,
    category = property.category,
    subtype = property.subtype,
    ownerType = property.ownerType,
    parentCode = property.parentCode,
    unitNumber = property.unitNumber,
    orgCode = property.orgCode,
    businessCode = property.businessCode,
    features = property.features,
    accessMode = getHouseAccessMode(house),
    enterAccess = isOrgProperty(house) and getAccessRuleText(getOrgEnterRules(accessConfig)) or 'residential',
    featuresAccess = isOrgProperty(house) and buildFeatureAccessSummary(accessConfig) or 'residential',
    currentAccess = currentAccess,
    currentAccessReason = currentAccessReason,
    canBeListed = canBeListed == true,
    canBeListedReason = canBeListedReason,
    database = databaseEnabled()
  }
end

local function publicListingPayload(code, house)
  local listing = getHouseListingConfig(code, house)
  if type(listing) ~= 'table' or listing.enabled ~= true then
    return nil
  end

  local sign = type(listing.sign) == 'table' and listing.sign or {}

  return {
    enabled = true,
    type = trim(listing.type) ~= '' and trim(listing.type) or 'sale',
    price = tonumber(listing.price),
    label = trim(listing.label) ~= '' and trim(listing.label) or 'Imovel a venda',
    description = trim(listing.description) ~= '' and trim(listing.description) or nil,
    sign = {
      enabled = sign.enabled == true,
      coords = vector3Payload(sign.coords),
      heading = tonumber(sign.heading) or 0.0
    }
  }
end

local function publicRealestatePayload(code, house, canBeListed)
  local realestate = getHouseRealestateConfig(code, house)
  local listing = getHouseListingConfig(code, house)

  return {
    enabled = realestate.enabled == true,
    canBeListed = canBeListed == true,
    defaultPrice = tonumber(realestate.defaultPrice),
    listingType = trim(realestate.listingType) ~= '' and trim(realestate.listingType)
      or trim(listing.type) ~= '' and trim(listing.type)
      or 'sale'
  }
end

local function publicGaragePayload(garage, includeDisabled)
  if type(garage) ~= 'table' or (includeDisabled ~= true and garage.enabled ~= true) then
    return nil
  end

  return {
    enabled = garage.enabled == true,
    label = trim(garage.label) ~= '' and trim(garage.label) or nil,
    mode = trim(garage.mode) ~= '' and trim(garage.mode) or nil,
    slots = tonumber(garage.slots),
    entry = vector3Payload(garage.entry),
    spawn = vector4Payload(garage.spawn),
    store = vector3Payload(garage.store),
    storeRadius = tonumber(garage.storeRadius),
    vehicleTypes = type(garage.vehicleTypes) == 'table' and garage.vehicleTypes or nil
  }
end

local function publicInteriorPointPayload(point, pointName)
  if type(point) ~= 'table' then
    return nil
  end

  local payload = {
    enabled = point.enabled ~= false,
    coords = vector3Payload(point.coords),
    relative = point.relative ~= false
  }

  local label = trim(point.label)
  if label ~= '' then payload.label = label end

  local heading = tonumber(point.heading or point.w)
  if heading ~= nil then payload.heading = heading end

  if pointName == 'stash' then
    payload.slots = tonumber(point.slots)
    payload.weight = tonumber(point.weight)
  elseif pointName == 'wardrobe' then
    local shopId = trim(point.shopId or point.shop_id)
    if shopId ~= '' then payload.shopId = shopId end
    local resource = trim(point.resource)
    if resource ~= '' then payload.resource = resource end
  end

  return payload
end

local function publicInteriorPayload(house)
  local interior = type(house) == 'table' and type(house.interior) == 'table' and house.interior or {}
  local payload = {}

  for _, pointName in ipairs({ 'exit', 'stash', 'wardrobe' }) do
    local point = publicInteriorPointPayload(interior[pointName], pointName)
    if point then
      payload[pointName] = point
    end
  end

  if next(payload) == nil then
    return nil
  end

  return payload
end

local function internalPointStatus(house, pointName)
  local interior = type(house) == 'table' and type(house.interior) == 'table' and house.interior or {}
  local defaults = getHouseInteriorDefaults(house)
  local override = type(interior[pointName]) == 'table' or type(house and house[pointName]) == 'table'
  local default = type(defaults) == 'table' and type(defaults[pointName]) == 'table'
  local effective = getEffectiveHousePoint(house, pointName)

  if type(effective) ~= 'table' then
    return { state = 'ausente', source = 'none', enabled = false }
  end

  local source = override and 'override' or (default and 'default' or 'none')
  if effective.enabled == false then
    return { state = 'desativado', source = source, enabled = false }
  end

  return {
    state = effective.coords ~= nil and 'definido' or 'sem_coords',
    source = source,
    enabled = true
  }
end

local function adminInternalSummaryPayload(house)
  house = type(house) == 'table' and house or {}
  return {
    shell = trim(house.shell),
    exit = internalPointStatus(house, 'exit'),
    stash = internalPointStatus(house, 'stash'),
    wardrobe = internalPointStatus(house, 'wardrobe')
  }
end

publicHousePayload = function(code, house, flags)
  flags = type(flags) == 'table' and flags or {}
  house = type(house) == 'table' and house or {}

  local configured = getConfiguredHouse(code) or {}
  local property = normalizeHouseProperty(house)
  local payload = {
    code = code,
    label = house.label or configured.label or code,
    category = property.category,
    subtype = property.subtype,
    ownerType = property.ownerType,
    parentCode = property.parentCode,
    unitNumber = property.unitNumber,
    type = house.type or configured.type or 'shell',
    shell = house.shell or configured.shell,
    entrance = vector4Payload(house.entrance or configured.entrance),
    features = property.features,
    interior = publicInteriorPayload(house),
    entryVisible = flags.entryVisible == true,
    garageVisible = flags.garageVisible == true,
    listingVisible = flags.listingVisible == true
  }

  if flags.garageVisible == true then
    payload.garage = publicGaragePayload(house.garage or configured.garage)
  end

  if flags.listingVisible == true then
    payload.listing = publicListingPayload(code, house)
  end

  if MZHousesConfig.Debug == true then
    payload.visibilityReason = {
      entry = flags.entryReason,
      garage = flags.garageReason,
      listing = flags.listingReason
    }
  end

  return payload
end

function MZHousesService.getPublicPropertyInfo(houseCode)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return nil, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  local configured = getConfiguredHouse(code) or {}
  local property = normalizeHouseProperty(house)
  local canBeListed, canBeListedReason = MZHousesService.CanPropertyBeListed(code)

  local payload = {
    code = code,
    label = house.label or configured.label or code,
    category = property.category,
    subtype = property.subtype,
    ownerType = property.ownerType,
    parentCode = property.parentCode,
    unitNumber = property.unitNumber,
    type = house.type or configured.type or 'shell',
    shell = house.shell or configured.shell,
    entrance = vector4Payload(house.entrance or configured.entrance),
    features = property.features,
    interior = publicInteriorPayload(house),
    garage = publicGaragePayload(house.garage or configured.garage),
    visibility = getHouseVisibilityMode(code, house),
    status = access.status,
    enabled = access.enabled == true,
    public = access.public == true,
    building = type(house.building) == 'table' and house.building or nil,
    listing = publicListingPayload(code, house),
    realestate = publicRealestatePayload(code, house, canBeListed),
    canBeListed = canBeListed == true,
    canBeListedReason = canBeListedReason
  }

  return payload, nil
end

function MZHousesService.getAdminPropertyInfo(houseCode)
  local access, err, code, house = MZHousesService.getAccessState(houseCode)
  if not access then
    return nil, err or 'house_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  local configured = getConfiguredHouse(code) or {}
  local property = normalizeHouseProperty(house)
  local canBeListed, canBeListedReason = MZHousesService.CanPropertyBeListed(code)
  local keys = {}
  for citizenid, enabled in pairs(access.keys or {}) do
    if enabled == true then
      keys[#keys + 1] = citizenid
    end
  end
  table.sort(keys)

  return {
    code = code,
    label = house.label or configured.label or code,
    category = property.category,
    subtype = property.subtype,
    ownerType = property.ownerType,
    parentCode = property.parentCode,
    unitNumber = property.unitNumber,
    orgCode = property.orgCode,
    businessCode = property.businessCode,
    type = house.type or configured.type or 'shell',
    shell = house.shell or configured.shell,
    entrance = vector4Payload(house.entrance or configured.entrance),
    features = property.features,
    interior = publicInteriorPayload(house),
    internalPoints = adminInternalSummaryPayload(house),
    garage = publicGaragePayload(house.garage or configured.garage, true),
    visibility = getHouseVisibilityMode(code, house),
    status = access.status,
    enabled = access.enabled == true,
    public = access.public == true,
    building = type(house.building) == 'table' and house.building or nil,
    listing = publicListingPayload(code, house),
    realestate = publicRealestatePayload(code, house, canBeListed),
    canBeListed = canBeListed == true,
    canBeListedReason = canBeListedReason,
    owner = access.owner,
    keys = keys,
    keyCount = #keys,
    database = databaseEnabled()
  }, nil
end

function MZHousesService.GetPropertyByCode(houseCode)
  return MZHousesService.getPublicPropertyInfo(houseCode)
end

function MZHousesService.ListProperties(filters)
  filters = type(filters) == 'table' and filters or {}
  local out = {}

  for code in pairs(RuntimeHouses or {}) do
    local property = MZHousesService.getPublicPropertyInfo(code)
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
        out[#out + 1] = property
      end
    end
  end

  table.sort(out, function(left, right)
    return tostring(left.code or '') < tostring(right.code or '')
  end)

  return out
end

local function requireAdminMutationActor(actorSource)
  local src = tonumber(actorSource) or 0
  if src <= 0 then
    return false, 'actor_required'
  end

  if not isAdminActor(src) then
    return false, 'admin_required'
  end

  return true
end

function MZHousesService.SetPropertyOwner(houseCode, citizenid, actorSource, reason, meta)
  local allowed, allowedErr = requireAdminMutationActor(actorSource)
  if not allowed then
    return false, allowedErr
  end

  local ok, result = MZHousesService.setHouseOwner(houseCode, citizenid, actorSource)
  if ok then
    MZHousesService.log('property.owner.set.authorized', result.houseCode, actorSource, citizenid, {
      reason = trim(reason) ~= '' and trim(reason) or 'admin_export',
      meta = type(meta) == 'table' and meta or nil
    })
  end

  return ok, result
end

function MZHousesService.ClearPropertyOwner(houseCode, actorSource, reason, meta)
  local allowed, allowedErr = requireAdminMutationActor(actorSource)
  if not allowed then
    return false, allowedErr
  end

  local ok, result = MZHousesService.clearHouseOwner(houseCode, actorSource)
  if ok then
    MZHousesService.log('property.owner.clear.authorized', result.houseCode, actorSource, nil, {
      reason = trim(reason) ~= '' and trim(reason) or 'admin_export',
      meta = type(meta) == 'table' and meta or nil
    })
  end

  return ok, result
end

function MZHousesService.GivePropertyKey(houseCode, citizenid, actorSource, reason, meta)
  local allowed, allowedErr = requireAdminMutationActor(actorSource)
  if not allowed then
    return false, allowedErr
  end

  local ok, result = MZHousesService.giveHouseKey(houseCode, citizenid, actorSource)
  if ok then
    MZHousesService.log('property.key.give.authorized', result.houseCode, actorSource, citizenid, {
      reason = trim(reason) ~= '' and trim(reason) or 'admin_export',
      meta = type(meta) == 'table' and meta or nil
    })
  end

  return ok, result
end

function MZHousesService.RemovePropertyKey(houseCode, citizenid, actorSource, reason, meta)
  local allowed, allowedErr = requireAdminMutationActor(actorSource)
  if not allowed then
    return false, allowedErr
  end

  local ok, result = MZHousesService.removeHouseKey(houseCode, citizenid, actorSource)
  if ok then
    MZHousesService.log('property.key.remove.authorized', result.houseCode, actorSource, citizenid, {
      reason = trim(reason) ~= '' and trim(reason) or 'admin_export',
      meta = type(meta) == 'table' and meta or nil
    })
  end

  return ok, result
end

function MZHousesService.ListApartmentUnits(source, buildingCode, isAdmin)
  local access, err, code, house = MZHousesService.getAccessState(buildingCode)
  if not access then
    return nil, err or 'building_not_found'
  end

  house = RuntimeHouses[code] or house or {}
  local buildingProperty = normalizeHouseProperty(house)
  if buildingProperty.subtype ~= 'apartment_building' then
    return nil, 'not_apartment_building'
  end

  local units = {}
  for unitCodeValue, unitHouse in pairs(RuntimeHouses or {}) do
    local unitProperty = normalizeHouseProperty(unitHouse)
    if unitProperty.subtype == 'apartment_unit' and unitProperty.parentCode == code then
      local allowed = false
      local result = 'no_house_access'
      local unitAccess = RuntimeAccess[unitCodeValue]

      if isAdmin == true then
        allowed = true
        result = 'admin'
      elseif unitAccess and unitAccess.enabled == false then
        result = 'house_disabled'
      elseif unitAccess and unitAccess.public == true then
        allowed = true
        result = 'public'
      else
        local citizenid = MZHousesService.getPlayerCitizenId(source)
        if citizenid and unitAccess and unitAccess.owner == citizenid then
          allowed = true
          result = 'owner'
        elseif citizenid and unitAccess and type(unitAccess.keys) == 'table' and unitAccess.keys[citizenid] == true then
          allowed = true
          result = 'key'
        end
      end

      local unitPayload = publicHousePayload(unitCodeValue, unitHouse, {
        entryVisible = allowed == true,
        garageVisible = allowed == true,
        listingVisible = false,
        entryReason = result,
        garageReason = result
      })
      unitPayload.allowed = allowed == true
      unitPayload.reason = result
      units[#units + 1] = unitPayload
    end
  end

  table.sort(units, function(left, right)
    local leftUnit = tostring(left.unitNumber or '')
    local rightUnit = tostring(right.unitNumber or '')
    if leftUnit ~= rightUnit then
      return leftUnit < rightUnit
    end
    return tostring(left.code or '') < tostring(right.code or '')
  end)

  return {
    building = publicHousePayload(code, house, { entryVisible = true, garageVisible = true }),
    units = units
  }, nil
end

function MZHousesService.listVisibleHouses(source)
  local houses = {}

  for code, house in pairs(RuntimeHouses or {}) do
    local entryVisible, entryReason = MZHousesService.CanSeeHouse(source, code, 'entry')
    local garageVisible, garageReason = MZHousesService.CanSeeHouse(source, code, 'garage')
    local listingVisible, listingReason = MZHousesService.CanSeeHouse(source, code, 'listing')

    if entryVisible == true or garageVisible == true or listingVisible == true then
      houses[#houses + 1] = publicHousePayload(code, house, {
        entryVisible = entryVisible == true,
        garageVisible = garageVisible == true,
        listingVisible = listingVisible == true,
        entryReason = entryReason,
        garageReason = garageReason,
        listingReason = listingReason
      })
    elseif MZHousesConfig.Debug == true then
      debugLog('visibility_hidden', {
        source = source,
        house = code,
        entry = entryReason,
        garage = garageReason,
        listing = listingReason
      })
    end
  end

  table.sort(houses, function(left, right)
    return tostring(left.code or '') < tostring(right.code or '')
  end)

  if MZHousesConfig.Debug == true then
    debugLog('visible_houses', {
      source = source,
      count = #houses
    })
  end

  return houses
end

function MZHousesService.getHouseAccessMode(houseCode)
  local house = houseCode
  if type(houseCode) ~= 'table' then
    local code = normalizeCode(houseCode)
    house = code and RuntimeHouses[code] or nil
  end

  return getHouseAccessMode(house)
end

local HOUSE_LOG_ACTIONS = {
  ['house.enter.denied'] = 'house.access.denied',
  ['house.stash.open.denied'] = 'house.stash.open.failed',
  ['house.wardrobe.open.denied'] = 'house.wardrobe.open.failed',
  ['house.garage.open.denied'] = 'house.garage.open.failed',
  ['property.owner.set.authorized'] = 'house.owner.set',
  ['property.owner.clear.authorized'] = 'house.owner.clear',
  ['property.key.give.authorized'] = 'house.key.give',
  ['property.key.remove.authorized'] = 'house.key.remove'
}

local LOG_SENSITIVE_KEYS = {
  token = true,
  tokens = true,
  password = true,
  secret = true,
  inventory = true,
  money = true
}

local function getLoggingConfig()
  return MZHousesConfig.Logging or {}
end

local function normalizeLogMode()
  local logging = getLoggingConfig()
  if logging.enabled == false then
    return 'none'
  end

  local mode = tostring(logging.mode or 'central'):lower()
  if mode == 'central' or mode == 'local' or mode == 'both' or mode == 'none' then
    return mode
  end

  return 'central'
end

local function normalizeHouseLogAction(action)
  action = trim(action)
  if action == '' then
    return 'house.unknown'
  end

  return HOUSE_LOG_ACTIONS[action] or action
end

local function sanitizeLogValue(value)
  local valueType = type(value)
  if valueType == 'table' then
    local out = {}
    for key, child in pairs(value) do
      local normalizedKey = tostring(key or ''):lower()
      if LOG_SENSITIVE_KEYS[normalizedKey] ~= true then
        out[key] = sanitizeLogValue(child)
      end
    end
    return out
  end

  if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
    return value
  end

  return nil
end

local function encodeLogJson(value)
  local ok, encoded = pcall(json.encode, sanitizeLogValue(value) or {})
  if ok and encoded then
    return encoded
  end

  return '{}'
end

local function writeCentralHouseLog(action, houseCode, actorSource, actorCitizenId, targetCitizenId, meta)
  local code = normalizeCode(houseCode)
  local src = tonumber(actorSource) or 0
  local actorId = actorCitizenId or (src > 0 and ('source:%s'):format(src) or 'system')
  local targetId = code and ('house:%s'):format(code) or 'house:unknown'

  local payload = {
    actor = {
      type = src > 0 and 'player' or 'system',
      id = actorId,
      citizenid = actorCitizenId,
      source = src > 0 and src or nil
    },
    target = {
      type = 'house',
      id = targetId,
      house_code = code
    },
    context = {
      resource = 'mz_houses',
      house_code = code
    },
    before = {},
    after = {},
    meta = sanitizeLogValue(meta or {})
  }

  if targetCitizenId then
    payload.meta.target_citizenid = targetCitizenId
  end

  local ok, err = pcall(function()
    MySQL.insert.await([[
      INSERT INTO mz_logs (scope, action, actor, target, data_json)
      VALUES (?, ?, ?, ?, ?)
    ]], {
      'house',
      action,
      actorId,
      targetId,
      encodeLogJson(payload)
    })
  end)

  if not ok and getLoggingConfig().debug == true then
    print(('[mz_houses][logging] central log failed action=%s house=%s err=%s'):format(
      tostring(action),
      tostring(code),
      tostring(err)
    ))
  end

  return ok
end

local function writeLocalHouseLog(action, houseCode, actorCitizenId, targetCitizenId, meta)
  if not databaseEnabled() or not MZHousesRepository or not MZHousesRepository.insertLog then
    return false
  end

  local ok, err = pcall(function()
    MZHousesRepository.insertLog(houseCode, action, actorCitizenId, targetCitizenId, meta)
  end)

  if not ok and getLoggingConfig().debug == true then
    print(('[mz_houses][logging] local log failed action=%s house=%s err=%s'):format(
      tostring(action),
      tostring(houseCode),
      tostring(err)
    ))
  end

  return ok
end

function MZHousesService.log(action, houseCode, actorSource, targetCitizenId, meta)
  local mode = normalizeLogMode()
  if mode == 'none' then
    return false
  end

  action = normalizeHouseLogAction(action)

  local actorCitizenId = nil
  if tonumber(actorSource) and tonumber(actorSource) > 0 then
    actorCitizenId = MZHousesService.getPlayerCitizenId(actorSource)
  end

  local centralOk = false
  local localOk = false

  if mode == 'central' or mode == 'both' then
    centralOk = writeCentralHouseLog(action, houseCode, actorSource, actorCitizenId, targetCitizenId, meta)
  end

  if mode == 'local' or mode == 'both' or (mode == 'central' and centralOk ~= true and getLoggingConfig().localFallback == true) then
    localOk = writeLocalHouseLog(action, houseCode, actorCitizenId, targetCitizenId, meta)
  end

  return centralOk == true or localOk == true
end
