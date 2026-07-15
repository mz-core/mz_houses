MZHousesLegacyMigration = MZHousesLegacyMigration or {}

local PreviewBySource = {}
local MigrationLocks = {}
local PREVIEW_TTL_SECONDS = 300
local MAX_AUDIT_SAMPLES = 50

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function clone(value, seen)
  if type(value) ~= 'table' then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
  return copy
end

local function normalizeCode(value)
  local code = trim(value)
  if code == '' or #code > 80 or not code:match('^[%w_%-]+$') then return nil end
  return code
end

local function normalizeUnitNumber(value)
  local unit = trim(value)
  if unit == '' or #unit > 30 or not unit:match('^[%w_%-]+$') then return nil end
  return unit
end

local function defaultFeaturePolicies(mode)
  local featureMode = mode == 'public' and 'disabled' or mode == 'admin' and 'admin' or 'inherit'
  return {
    stash = { mode = featureMode, match = 'any', rules = {} },
    wardrobe = { mode = featureMode, match = 'any', rules = {} },
    garage = { mode = featureMode, match = 'any', rules = {} }
  }
end

local function featurePolicies(house, mode)
  local current = type(house.accessPolicy) == 'table' and house.accessPolicy.features or nil
  if type(current) == 'table' then return clone(current) end
  return defaultFeaturePolicies(mode)
end

local function signature(house)
  if type(house) ~= 'table' then return nil end
  local snapshot = {
    code = house.code,
    category = house.category,
    subtype = house.subtype,
    ownerType = house.ownerType or house.owner_type,
    parentCode = house.parentCode or house.parent_code,
    unitNumber = house.unitNumber or house.unit_number,
    orgCode = house.orgCode or house.org_code,
    businessCode = house.businessCode or house.business_code,
    accessPolicy = house.accessPolicy,
    door = house.door,
    visibility = house.visibility,
    public = house.public,
    owner = house.owner_citizenid or house.owner,
    saleEnabled = house.saleEnabled or house.sale_enabled,
    saleMode = house.saleMode or house.sale_mode,
    salePrice = house.salePrice or house.sale_price,
    taxEnabled = house.taxEnabled or house.tax_enabled,
    taxStatus = house.taxStatus or house.tax_status,
    updatedAt = house.updated_at
  }
  return json.encode(snapshot)
end

local function isOwnerTemplate(template)
  return template == 'residence' or template == 'unit'
end

local function validateNoIndividualRelations(code, house, template)
  if isOwnerTemplate(template) then return true end
  if trim(house.owner_citizenid or house.owner) ~= '' then
    return false, 'legacy_owner_must_be_cleared'
  end
  local keys = MZHousesRepository.listKeys(code) or {}
  if #keys > 0 then return false, 'legacy_keys_must_be_cleared' end
  return true
end

local function baseMetadata(house, template, actorSource)
  local metadata = clone(type(house.metadata) == 'table' and house.metadata or {})
  metadata.legacyMigration = {
    version = 1,
    template = template,
    migratedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    actorSource = tonumber(actorSource) or 0,
    previousCategory = house.category,
    previousSubtype = house.subtype,
    previousOwnerType = house.ownerType or house.owner_type
  }
  return metadata
end

local function validateParent(parentCode, unitNumber, currentCode)
  parentCode = normalizeCode(parentCode)
  unitNumber = normalizeUnitNumber(unitNumber)
  if not parentCode then return nil, 'invalid_parent_code' end
  if not unitNumber then return nil, 'invalid_unit_number' end
  local parent = MZHousesRepository.getHouseByCode(parentCode)
  local property = parent and MZHousesRepository.normalizePropertyFields(parent) or nil
  if not property or property.subtype ~= 'apartment_building' then
    return nil, 'parent_building_not_found'
  end
  for _, candidate in ipairs(MZHousesRepository.listHouses()) do
    local candidateProperty = MZHousesRepository.normalizePropertyFields(candidate)
    if candidate.code ~= currentCode and candidateProperty.subtype == 'apartment_unit'
      and candidateProperty.parentCode == parentCode and candidateProperty.unitNumber == unitNumber then
      return nil, 'unit_number_already_exists'
    end
  end
  return { parentCode = parentCode, unitNumber = unitNumber }
end

local function buildPatch(source, house, raw)
  raw = type(raw) == 'table' and raw or {}
  local template = trim(raw.template):lower()
  local allowed = {
    residence = true, building = true, unit = true, gang = true,
    job = true, public = true, administrative = true
  }
  if not allowed[template] then return nil, 'invalid_migration_template' end

  local code = normalizeCode(house.code)
  if not code then return nil, 'invalid_house' end
  local relationOk, relationErr = validateNoIndividualRelations(code, house, template)
  if not relationOk then return nil, relationErr end

  local mode = (template == 'gang' or template == 'job') and 'rules'
    or template == 'public' and 'public'
    or template == 'administrative' and 'admin'
    or template == 'building' and 'public'
    or 'owner'
  local policy = { version = 1, mode = mode, match = 'any', rules = {}, features = featurePolicies(house, mode) }
  local patch = {
    metadata = baseMetadata(house, template, source),
    accessPolicy = policy,
    orgCode = '',
    businessCode = '',
    parentCode = '',
    unitNumber = '',
    public = false,
    visibility = 'restricted'
  }
  local doorState = 'locked'
  local summary = {}
  local warnings = {
    'listing_json e realestate_json serao preservados sem efeito no runtime.',
    'Shell, entrada, interior, pontos, garagem, features, owner e chaves permitidos pelo template nao serao regravados.'
  }

  if template == 'residence' then
    patch.category, patch.subtype, patch.ownerType = 'residential', 'house', 'player'
    summary[#summary + 1] = 'Residencia individual: policy owner, visibilidade restrita e porta locked.'
  elseif template == 'building' then
    patch.category, patch.subtype, patch.ownerType = 'residential', 'apartment_building', 'server'
    patch.public, patch.visibility, doorState = true, 'public', 'unlocked'
    summary[#summary + 1] = 'Predio agrupador: sem owner individual, policy public e porta unlocked.'
  elseif template == 'unit' then
    local parent, parentErr = validateParent(raw.parentCode, raw.unitNumber, code)
    if not parent then return nil, parentErr end
    patch.category, patch.subtype, patch.ownerType = 'residential', 'apartment_unit', 'player'
    patch.parentCode, patch.unitNumber = parent.parentCode, parent.unitNumber
    summary[#summary + 1] = ('Unidade %s vinculada ao predio %s.'):format(parent.unitNumber, parent.parentCode)
  elseif template == 'gang' or template == 'job' then
    local groupType = template
    local groupCode = trim(raw.groupCode):lower()
    local group = groupCode ~= '' and MZHousesGroups.get(groupType, groupCode) or nil
    if not group then return nil, 'group_not_found' end
    local minimumGrade = math.floor(tonumber(raw.minimumGrade) or -1)
    local controlGrade = math.floor(tonumber(raw.controlGrade) or -1)
    if minimumGrade < 0 or minimumGrade > 1000 then return nil, 'invalid_minimum_grade' end
    if controlGrade < minimumGrade or controlGrade > 1000 then return nil, 'invalid_control_grade' end
    local rule = {
      type = groupType,
      name = groupCode,
      minimumGrade = minimumGrade,
      canControlDoorFromGrade = controlGrade
    }
    if groupType == 'job' then rule.requireDuty = raw.requireDuty == true end
    policy.rules = { rule }
    patch.category, patch.subtype, patch.ownerType = 'organization', 'interior', 'server'
    patch.orgCode = groupCode
    patch.public = raw.visible == true
    patch.visibility = raw.visible == true and 'public' or 'restricted'
    summary[#summary + 1] = ('Sede %s %s: grade %d, controle %d%s.'):format(
      groupType, groupCode, minimumGrade, controlGrade,
      groupType == 'job' and (rule.requireDuty and ', duty obrigatorio' or ', duty livre') or '')
  elseif template == 'public' then
    patch.category, patch.subtype, patch.ownerType = 'public', 'interior', 'server'
    patch.public, patch.visibility, doorState = true, 'public', 'unlocked'
    summary[#summary + 1] = 'Interior publico: policy public, porta unlocked e recursos disabled por default quando ainda sem policy.'
  else
    patch.category, patch.subtype, patch.ownerType = 'administrative', 'interior', 'server'
    patch.visibility, doorState = 'hidden', 'blocked'
    summary[#summary + 1] = 'Interior administrativo: policy admin, visibilidade hidden e porta blocked.'
  end

  patch.door = { version = 1, state = doorState, defaultState = doorState, autoLock = false, autoLockSeconds = 0,
    control = { mode = 'policy', minimumGrade = nil } }
  local policyOk, policyOrErr = MZHousesAccessPolicy.validate(policy)
  if not policyOk then return nil, policyOrErr or 'invalid_access_policy' end
  patch.accessPolicy = policyOrErr

  if type(house.accessPolicy) == 'table' then
    warnings[#warnings + 1] = 'A propriedade ja possui access_json; a policy principal sera substituida pelo template escolhido.'
  end
  if house.saleEnabled == true or tonumber(house.sale_enabled) == 1 then
    warnings[#warnings + 1] = 'Campos comerciais legados serao preservados; templates nao residenciais permanecem inelegiveis para venda no servidor.'
  end
  if house.taxEnabled == true or tonumber(house.tax_enabled) == 1 then
    warnings[#warnings + 1] = 'Ao tornar o tipo inelegivel, o ciclo fiscal sera suspenso pelo fluxo administrativo existente; o historico sera preservado.'
  end
  return patch, nil, summary, warnings, template
end

local function tokenFor(source)
  return ('legacy:%d:%d:%06d'):format(tonumber(source) or 0, os.time(), math.random(0, 999999))
end

function MZHousesLegacyMigration.preview(source, raw)
  raw = type(raw) == 'table' and raw or {}
  local code = normalizeCode(raw.code)
  if not code then return false, 'invalid_house' end
  local house = MZHousesRepository.getHouseByCode(code)
  if not house then return false, 'house_not_found' end
  local patch, err, summary, warnings, template = buildPatch(source, house, raw)
  if not patch then return false, err end
  local token = tokenFor(source)
  PreviewBySource[tonumber(source) or 0] = {
    token = token,
    code = code,
    template = template,
    patch = patch,
    signature = signature(house),
    expiresAt = os.time() + PREVIEW_TTL_SECONDS
  }
  return true, {
    token = token,
    houseCode = code,
    template = template,
    expiresIn = PREVIEW_TTL_SECONDS,
    before = {
      category = house.category,
      subtype = house.subtype,
      ownerType = house.ownerType or house.owner_type,
      accessMode = type(house.accessPolicy) == 'table' and house.accessPolicy.mode or 'legacy/null',
      doorState = type(house.door) == 'table' and house.door.state or 'fallback'
    },
    after = {
      category = patch.category,
      subtype = patch.subtype,
      ownerType = patch.ownerType,
      accessMode = patch.accessPolicy.mode,
      doorState = patch.door.state,
      visibility = patch.visibility
    },
    summary = summary,
    warnings = warnings
  }
end

local function persistentFinancialBarrier(code, house)
  if type(MZHousesCommerce) == 'table' and MZHousesCommerce.isPurchaseLocked(code) then
    return 'purchase_in_progress'
  end
  if type(MZHousesTax) == 'table' and MZHousesTax.isPaymentLocked(code) then
    return 'tax_payment_in_progress'
  end
  if type(MZHousesApartments) == 'table' and MZHousesApartments.isUnitMutationLocked(code) then
    return 'unit_mutation_in_progress'
  end
  if MZHousesRepository.getBlockingPurchaseTransaction(code) then
    return 'purchase_manual_review_or_pending'
  end
  local owner = trim(house.owner_citizenid or house.owner)
  if owner ~= '' and MZHousesRepository.getBlockingTaxPayment(code, owner) then
    return 'tax_manual_review_or_pending'
  end
  return nil
end

function MZHousesLegacyMigration.apply(source, token, confirmCode)
  source = tonumber(source) or 0
  local preview = PreviewBySource[source]
  if not preview or trim(token) == '' or preview.token ~= trim(token) then return false, 'migration_preview_not_found' end
  if preview.expiresAt < os.time() then PreviewBySource[source] = nil return false, 'migration_preview_expired' end
  if normalizeCode(confirmCode) ~= preview.code then return false, 'confirmation_mismatch' end
  if MigrationLocks[preview.code] then return false, 'migration_in_progress' end
  MigrationLocks[preview.code] = true
  local callOk, ok, result = pcall(function()
    local current = MZHousesRepository.getHouseByCode(preview.code)
    if not current then return false, 'house_not_found' end
    if signature(current) ~= preview.signature then return false, 'property_changed_since_preview' end
    local barrier = persistentFinancialBarrier(preview.code, current)
    if barrier then return false, barrier end
    return MZHousesService.updateAdminProperty(source, preview.code, preview.patch,
      'property.legacy.migration.completed', { template = preview.template, preview = true })
  end)
  MigrationLocks[preview.code] = nil
  if not callOk then
    MZHousesService.log('property.legacy.migration.failed', preview.code, source, nil, { reason = 'migration_internal_error' })
    return false, 'migration_internal_error'
  end
  if ok ~= true then return false, result or 'migration_failed' end
  PreviewBySource[source] = nil
  return true, { houseCode = preview.code, template = preview.template }
end

local function inspectJson(raw)
  raw = trim(raw)
  if raw == '' or raw == 'null' then return 'empty' end
  local ok, decoded = pcall(json.decode, raw)
  if not ok then return 'invalid' end
  if type(decoded) ~= 'table' or next(decoded) == nil then return 'empty' end
  return decoded.enabled == true and 'enabled' or 'preserved'
end

function MZHousesLegacyMigration.audit()
  local rows = MySQL.query.await([[
    SELECT code, category, subtype, owner_type, access_json, listing_json, realestate_json
    FROM mz_houses ORDER BY code ASC
  ]], {}) or {}
  local counts = {
    total = #rows, legacyTypes = 0, missingAccessPolicy = 0,
    listing = { empty = 0, preserved = 0, enabled = 0, invalid = 0 },
    realestate = { empty = 0, preserved = 0, enabled = 0, invalid = 0 }
  }
  local samples = {}
  for _, row in ipairs(rows) do
    local category = trim(row.category):lower()
    local ownerType = trim(row.owner_type):lower()
    local legacy = category == 'org' or category == 'business' or category == 'government'
      or ownerType == 'org' or ownerType == 'business'
    if legacy then counts.legacyTypes = counts.legacyTypes + 1 end
    local accessState = inspectJson(row.access_json)
    if accessState == 'empty' or accessState == 'invalid' then counts.missingAccessPolicy = counts.missingAccessPolicy + 1 end
    local listingState = inspectJson(row.listing_json)
    local realestateState = inspectJson(row.realestate_json)
    counts.listing[listingState] = counts.listing[listingState] + 1
    counts.realestate[realestateState] = counts.realestate[realestateState] + 1
    if #samples < MAX_AUDIT_SAMPLES and (legacy or accessState == 'invalid' or listingState ~= 'empty' or realestateState ~= 'empty') then
      samples[#samples + 1] = {
        code = row.code, category = row.category, subtype = row.subtype,
        ownerType = row.owner_type, access = accessState,
        listing = listingState, realestate = realestateState
      }
    end
  end
  return { counts = counts, samples = samples, sampleLimit = MAX_AUDIT_SAMPLES, destructiveActions = 0 }
end

AddEventHandler('playerDropped', function() PreviewBySource[source] = nil end)
AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  PreviewBySource = {}
  MigrationLocks = {}
end)
