MZHousesApartments = MZHousesApartments or {}

if type(MZHousesCommerce) ~= 'table'
    or type(MZHousesCommerce.purchase) ~= 'function'
    or type(MZHousesCommerce.configureSale) ~= 'function'
    or type(MZHousesCommerce.isPurchaseLocked) ~= 'function' then
  error('[mz_houses] API da Fase 4 indisponivel para apartments.lua.')
end

local BuildingLocks = {}
local UnitMutationLocks = {}
local BatchPreviews = {}
local BulkPreviews = {}
local PreviewSequence = 0
local PREVIEW_TTL = 120
local MAX_BATCH_UNITS = 250
local MAX_BULK_UNITS = 200

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function copyTable(value, seen)
  if type(value) ~= 'table' then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, item in pairs(value) do out[copyTable(key, seen)] = copyTable(item, seen) end
  return out
end

local function nextToken(prefix, source)
  PreviewSequence = (PreviewSequence + 1) % 1000000
  return ('%s:%d:%d:%06d:%06d'):format(
    prefix, tonumber(source) or 0, os.time(), PreviewSequence, math.random(0, 999999)
  )
end

local function stableHash(text)
  local hash = 5381
  for index = 1, #text do hash = (hash * 33 + text:byte(index)) % 2147483647 end
  return tostring(hash)
end

local function propertyFields(house)
  return MZHousesRepository.normalizePropertyFields(type(house) == 'table' and house or {})
end

local function getBuilding(buildingCode)
  local code = trim(buildingCode)
  if code == '' then return nil, 'invalid_building' end
  local house = MZHousesRepository.getHouseByCode(code)
  if not house then return nil, 'building_not_found' end
  local property = propertyFields(house)
  if property.category ~= 'residential' or property.subtype ~= 'apartment_building'
      or property.ownerType ~= 'server' then
    return nil, 'not_apartment_building'
  end
  if trim(house.owner_citizenid or house.owner) ~= '' then return nil, 'building_must_not_have_owner' end
  return house, nil
end

local function normalizePrice(value)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then
    return nil, 'invalid_sale_price'
  end
  return math.min(9000000000000000, math.floor(value)), nil
end

local function normalizeMode(value)
  value = trim(value):lower()
  if value == 'none' or value == 'admin' or value == 'direct' then return value end
  return nil, 'invalid_sale_mode'
end

local function normalizeDefaults(raw, current)
  raw = type(raw) == 'table' and raw or {}
  current = type(current) == 'table' and current or {}
  local enabled = raw.saleEnabled
  if enabled == nil then enabled = current.saleEnabled == true end
  enabled = enabled == true or tonumber(enabled) == 1
  local mode, modeErr = normalizeMode(raw.saleMode ~= nil and raw.saleMode or current.saleMode or 'none')
  if not mode then return nil, modeErr end
  local price, priceErr = normalizePrice(raw.salePrice ~= nil and raw.salePrice or current.salePrice or 0)
  if price == nil then return nil, priceErr end
  if enabled and mode == 'none' then return nil, 'invalid_sale_mode' end
  if enabled and price <= 0 then return nil, 'invalid_sale_price' end
  if not enabled then mode = 'none' end
  local shell = trim(raw.shell ~= nil and raw.shell or current.shell)
  local shellOk, shellErr = MZHousesService.IsShellSelectable(shell)
  if not shellOk then return nil, shellErr or 'invalid_shell' end
  local currentTax = type(current.tax) == 'table' and current.tax or {}
  local rawTax = type(raw.tax) == 'table' and raw.tax or {}
  local taxEnabled = raw.taxEnabled
  if taxEnabled == nil then taxEnabled = rawTax.enabled end
  if taxEnabled == nil then taxEnabled = currentTax.enabled end
  local tax = MZHousesRepository.normalizeTax({
    taxEnabled = taxEnabled,
    taxAmount = raw.taxAmount ~= nil and raw.taxAmount
      or rawTax.amount ~= nil and rawTax.amount or currentTax.amount,
    taxIntervalDays = raw.taxIntervalDays ~= nil and raw.taxIntervalDays
      or rawTax.intervalDays ~= nil and rawTax.intervalDays or currentTax.intervalDays,
    taxGracePeriodDays = raw.taxGracePeriodDays ~= nil and raw.taxGracePeriodDays
      or rawTax.gracePeriodDays ~= nil and rawTax.gracePeriodDays or currentTax.gracePeriodDays
  })
  if tax.taxEnabled and tax.taxAmount <= 0 then return nil, 'invalid_tax_amount' end
  return {
    saleEnabled = enabled,
    saleMode = mode,
    salePrice = price,
    shell = shell,
    interior = copyTable(type(current.interior) == 'table' and current.interior or {}),
    features = copyTable(type(current.features) == 'table' and current.features or {
      stash = true, wardrobe = true, garage = false, furniture = false
    }),
    tax = {
      enabled = tax.taxEnabled,
      amount = tax.taxAmount,
      intervalDays = tax.taxIntervalDays,
      gracePeriodDays = tax.taxGracePeriodDays
    }
  }, nil
end

function MZHousesApartments.getUnitDefaults(buildingCode)
  local buildingHouse, err = getBuilding(buildingCode)
  if not buildingHouse then return nil, err end
  return MZHousesService.getApartmentUnitDefaults(buildingHouse), nil, buildingHouse
end

function MZHousesApartments.updateUnitDefaults(actorSource, buildingCode, raw)
  local buildingHouse, err = getBuilding(buildingCode)
  if not buildingHouse then return false, err end
  local current = MZHousesService.getApartmentUnitDefaults(buildingHouse)
  local defaults, defaultsErr = normalizeDefaults(raw, current)
  if not defaults then return false, defaultsErr end
  local building = MZHousesRepository.normalizeBuilding(buildingHouse.building)
  building.defaultUnitShell = defaults.shell
  building.unitDefaults = defaults
  local ok, result = MZHousesService.updateAdminProperty(
    actorSource,
    buildingHouse.code,
    { building = building },
    'building.unit.default.updated',
    {
      saleEnabled = defaults.saleEnabled,
      saleMode = defaults.saleMode,
      salePrice = defaults.salePrice,
      shell = defaults.shell,
      taxEnabled = defaults.tax.enabled,
      taxAmount = defaults.tax.amount,
      taxIntervalDays = defaults.tax.intervalDays,
      taxGracePeriodDays = defaults.tax.gracePeriodDays
    }
  )
  if not ok then return false, result end
  return true, { houseCode = buildingHouse.code, defaults = defaults }
end

function MZHousesApartments.copyUnitTemplate(actorSource, buildingCode, unitCode)
  local buildingHouse, buildingErr = getBuilding(buildingCode)
  if not buildingHouse then return false, buildingErr end
  local unit = MZHousesRepository.getHouseByCode(unitCode)
  if not unit then return false, 'unit_not_found' end
  local unitProperty = propertyFields(unit)
  if unitProperty.subtype ~= 'apartment_unit' or unitProperty.parentCode ~= buildingHouse.code then
    return false, 'unit_not_in_building'
  end
  local shell = trim(unit.shell)
  local shellOk, shellErr = MZHousesService.IsShellSelectable(shell)
  if not shellOk then return false, shellErr or 'invalid_shell' end
  local building = MZHousesRepository.normalizeBuilding(buildingHouse.building)
  local defaults = MZHousesService.getApartmentUnitDefaults(buildingHouse)
  defaults.shell = shell
  defaults.interior = copyTable(type(unit.interior) == 'table' and unit.interior or {})
  defaults.features = copyTable(unitProperty.features)
  building.defaultUnitShell = shell
  building.unitDefaults = defaults
  local ok, result = MZHousesService.updateAdminProperty(
    actorSource, buildingHouse.code, { building = building },
    'building.unit.default.updated',
    { templateUnitCode = unit.code, shell = shell, copiedInterior = true, copiedFeatures = true }
  )
  if not ok then return false, result end
  return true, { houseCode = buildingHouse.code, defaults = defaults, templateUnitCode = unit.code }
end

local function normalizeUnitNumbers(values)
  local out, seen = {}, {}
  for _, raw in ipairs(type(values) == 'table' and values or {}) do
    local unit = MZHousesService.normalizeApartmentUnitNumber(raw)
    if not unit then return nil, 'invalid_unit_number' end
    if seen[unit] then return nil, 'duplicate_unit_number' end
    seen[unit] = true
    out[#out + 1] = unit
    if #out > MAX_BATCH_UNITS then return nil, 'unit_batch_too_large' end
  end
  if #out == 0 then return nil, 'empty_unit_batch' end
  table.sort(out)
  return out, nil
end

local function batchOperationKey(buildingCode, units, defaults)
  return ('unit-batch:%s:%s'):format(buildingCode, stableHash(table.concat({
    table.concat(units, ','),
    defaults.saleEnabled and '1' or '0',
    defaults.saleMode,
    tostring(defaults.salePrice),
    defaults.shell,
    defaults.tax.enabled and '1' or '0',
    tostring(defaults.tax.amount),
    tostring(defaults.tax.intervalDays),
    tostring(defaults.tax.gracePeriodDays)
  }, '|')))
end

local function buildBatchPlan(buildingCode, spec)
  local buildingHouse, buildingErr = getBuilding(buildingCode)
  if not buildingHouse then return nil, buildingErr end
  local units, unitsErr = normalizeUnitNumbers(type(spec) == 'table' and spec.unitNumbers or nil)
  if not units then return nil, unitsErr end
  local defaults, defaultsErr = normalizeDefaults(
    MZHousesService.getApartmentUnitDefaults(buildingHouse),
    MZHousesService.getApartmentUnitDefaults(buildingHouse)
  )
  if not defaults then return nil, defaultsErr end

  local codes, byUnit = {}, {}
  for _, unitNumber in ipairs(units) do
    local code, codeErr = MZHousesService.getApartmentUnitCode(buildingHouse.code, unitNumber)
    if not code then return nil, codeErr end
    if byUnit[code] then return nil, 'duplicate_unit_code' end
    byUnit[code] = unitNumber
    codes[#codes + 1] = code
  end
  local existing = MZHousesRepository.getHousesByCodes(codes)
  local existingCount, conflicts = 0, {}
  for _, code in ipairs(codes) do
    local row = existing[code]
    if row then
      local property = propertyFields(row)
      if property.subtype == 'apartment_unit' and property.parentCode == buildingHouse.code
          and property.unitNumber == byUnit[code] then
        existingCount = existingCount + 1
      else
        conflicts[#conflicts + 1] = code
      end
    end
  end
  if #conflicts > 0 then return nil, 'unit_code_conflict' end
  if existingCount > 0 and existingCount < #codes then return nil, 'batch_contains_existing_units' end

  local rows, preview = {}, {}
  if existingCount == 0 then
    for _, code in ipairs(codes) do
      local unitNumber = byUnit[code]
      local data, dataErr = MZHousesService.buildApartmentUnitData(buildingHouse, unitNumber, {})
      if not data then return nil, dataErr end
      rows[#rows + 1] = { code = code, data = data }
      preview[#preview + 1] = {
        code = code,
        unitNumber = unitNumber,
        label = data.label,
        shell = data.shell,
        saleEnabled = data.saleEnabled,
        saleMode = data.saleMode,
        salePrice = data.salePrice,
        taxEnabled = data.taxEnabled,
        taxAmount = data.taxAmount,
        taxIntervalDays = data.taxIntervalDays,
        taxGracePeriodDays = data.taxGracePeriodDays
      }
    end
  end
  return {
    buildingCode = buildingHouse.code,
    unitNumbers = units,
    rows = rows,
    preview = preview,
    defaults = defaults,
    existingCount = existingCount,
    alreadyExists = existingCount == #codes,
    operationKey = batchOperationKey(buildingHouse.code, units, defaults)
  }, nil
end

function MZHousesApartments.previewBatch(source, buildingCode, spec)
  local plan, err = buildBatchPlan(buildingCode, spec)
  if not plan then
    MZHousesService.log('building.unit.batch.failed', buildingCode, source, nil, { stage = 'preview', reason = err })
    return false, err
  end
  local token = nextToken('unit-batch', source)
  BatchPreviews[token] = {
    source = tonumber(source),
    expiresAt = os.time() + PREVIEW_TTL,
    buildingCode = plan.buildingCode,
    unitNumbers = copyTable(plan.unitNumbers),
    operationKey = plan.operationKey
  }
  MZHousesService.log('building.unit.batch.preview', plan.buildingCode, source, nil, {
    operationKey = plan.operationKey,
    total = #plan.unitNumbers,
    alreadyExists = plan.alreadyExists
  })
  return true, {
    previewToken = token,
    operationKey = plan.operationKey,
    buildingCode = plan.buildingCode,
    total = #plan.unitNumbers,
    existingCount = plan.existingCount,
    alreadyExists = plan.alreadyExists,
    units = plan.preview,
    defaults = plan.defaults
  }
end

local function executeBatch(source, buildingCode, spec)
  buildingCode = trim(buildingCode)
  if BuildingLocks[buildingCode] then return false, 'building_batch_in_progress' end
  BuildingLocks[buildingCode] = true
  local ok, success, result = xpcall(function()
    local plan, planErr = buildBatchPlan(buildingCode, spec)
    if not plan then return false, planErr end
    if plan.alreadyExists then
      return true, { buildingCode = plan.buildingCode, operationKey = plan.operationKey, created = 0, createdCodes = {}, alreadyExists = true }
    end
    local saved, saveResult = MZHousesRepository.createApartmentUnitsBatch(plan.rows)
    if not saved then return false, saveResult or 'unit_batch_transaction_failed' end
    local createdCodes, refreshFailed = {}, false
    for _, row in ipairs(plan.rows) do
      createdCodes[#createdCodes + 1] = row.code
      local refreshed = MZHousesService.refreshProperty(row.code)
      if refreshed ~= true then refreshFailed = true end
    end
    if refreshFailed then pcall(MZHousesService.bootstrap) end
    MZHousesService.log('building.unit.batch.created', plan.buildingCode, source, nil, {
      operationKey = plan.operationKey,
      created = #createdCodes,
      cacheReloaded = refreshFailed
    })
    return true, {
      buildingCode = plan.buildingCode,
      operationKey = plan.operationKey,
      created = #createdCodes,
      createdCodes = createdCodes,
      alreadyExists = false
    }
  end, function(err) return tostring(err) end)
  BuildingLocks[buildingCode] = nil
  if not ok then
    MZHousesService.log('building.unit.batch.failed', buildingCode, source, nil, { stage = 'persist', reason = 'unexpected_error' })
    return false, 'unit_batch_internal_error'
  end
  if not success then
    MZHousesService.log('building.unit.batch.failed', buildingCode, source, nil, { stage = 'persist', reason = result })
  end
  return success, result
end

function MZHousesApartments.createBatch(source, previewToken)
  local preview = BatchPreviews[trim(previewToken)]
  BatchPreviews[trim(previewToken)] = nil
  if not preview or preview.source ~= tonumber(source) then return false, 'invalid_batch_preview' end
  if preview.expiresAt < os.time() then return false, 'batch_preview_expired' end
  local fresh, err = buildBatchPlan(preview.buildingCode, { unitNumbers = preview.unitNumbers })
  if not fresh then return false, err end
  if fresh.operationKey ~= preview.operationKey then return false, 'batch_preview_stale' end
  return executeBatch(source, preview.buildingCode, { unitNumbers = preview.unitNumbers })
end

function MZHousesApartments.createBatchImmediate(source, buildingCode, spec)
  return executeBatch(source, buildingCode, spec)
end

function MZHousesApartments.isUnitMutationLocked(unitCode)
  return UnitMutationLocks[trim(unitCode)] == true
end

local function unitBulkProtected(house)
  local metadata = type(house) == 'table' and type(house.metadata) == 'table' and house.metadata or {}
  return metadata.bulkCommerceProtected == true
end

local function bulkTarget(house, spec)
  local current = MZHousesRepository.normalizeCommerce(house)
  local operation = trim(type(spec) == 'table' and spec.operation or ''):lower()
  if operation == 'disable' then
    return { saleEnabled = false, saleMode = 'none', salePrice = current.salePrice }
  end
  if operation == 'price' then
    local price, err = normalizePrice(spec.salePrice)
    if price == nil then return nil, err end
    if current.saleEnabled and price <= 0 then return nil, 'invalid_sale_price' end
    return { saleEnabled = current.saleEnabled, saleMode = current.saleMode, salePrice = price }
  end
  if operation == 'mode' then
    if not current.saleEnabled then return nil, 'sale_not_enabled' end
    local mode, err = normalizeMode(spec.saleMode)
    if not mode or mode == 'none' then return nil, err or 'invalid_sale_mode' end
    return { saleEnabled = true, saleMode = mode, salePrice = current.salePrice }
  end
  if operation == 'enable' then
    local mode, modeErr = normalizeMode(spec.saleMode)
    local price, priceErr = normalizePrice(spec.salePrice)
    if not mode or mode == 'none' then return nil, modeErr or 'invalid_sale_mode' end
    if price == nil or price <= 0 then return nil, priceErr or 'invalid_sale_price' end
    return { saleEnabled = true, saleMode = mode, salePrice = price }
  end
  return nil, 'invalid_bulk_operation'
end

local function normalizeSelectedCodes(values)
  local out, seen = {}, {}
  for _, raw in ipairs(type(values) == 'table' and values or {}) do
    local code = trim(raw)
    if code == '' or #code > 80 or not code:match('^[%w_%-]+$') then return nil, 'invalid_unit_code' end
    if not seen[code] then
      seen[code] = true
      out[#out + 1] = code
      if #out > MAX_BULK_UNITS then return nil, 'bulk_too_large' end
    end
  end
  if #out == 0 then return nil, 'empty_bulk_selection' end
  table.sort(out)
  return out
end

local function evaluateBulkUnit(buildingCode, code, house, spec, ownsMutationLock)
  if not house then return nil, 'unit_not_found' end
  local property = propertyFields(house)
  if property.subtype ~= 'apartment_unit' or property.parentCode ~= buildingCode then return nil, 'unit_not_in_building' end
  if house.enabled ~= true or trim(house.status):lower() ~= 'active' then return nil, 'unit_not_active' end
  if trim(house.owner_citizenid or house.owner) ~= '' then return nil, 'unit_has_owner' end
  if unitBulkProtected(house) then return nil, 'unit_bulk_protected' end
  if UnitMutationLocks[code] and ownsMutationLock ~= true then return nil, 'unit_mutation_in_progress' end
  if MZHousesCommerce.isPurchaseLocked(code) then return nil, 'purchase_in_progress' end
  if MZHousesRepository.getBlockingPurchaseTransaction(code) then return nil, 'purchase_financial_state_pending' end
  local target, targetErr = bulkTarget(house, spec)
  if not target then return nil, targetErr end
  return {
    code = code,
    unitNumber = property.unitNumber,
    previous = MZHousesRepository.normalizeCommerce(house),
    next = target
  }, nil
end

local function buildBulkPlan(buildingCode, spec)
  local buildingHouse, buildingErr = getBuilding(buildingCode)
  if not buildingHouse then return nil, buildingErr end
  local selected, selectedErr = normalizeSelectedCodes(type(spec) == 'table' and spec.unitCodes or nil)
  if not selected then return nil, selectedErr end
  local houses = MZHousesRepository.getHousesByCodes(selected)
  local eligible, skipped = {}, {}
  for _, code in ipairs(selected) do
    local item, reason = evaluateBulkUnit(buildingHouse.code, code, houses[code], spec)
    if item then eligible[#eligible + 1] = item else skipped[#skipped + 1] = { code = code, reason = reason } end
  end
  local signature = { buildingHouse.code, trim(spec.operation), tostring(spec.saleMode), tostring(spec.salePrice), table.concat(selected, ',') }
  return {
    buildingCode = buildingHouse.code,
    selected = selected,
    eligible = eligible,
    skipped = skipped,
    spec = { operation = trim(spec.operation), saleMode = spec.saleMode, salePrice = spec.salePrice },
    operationKey = ('unit-bulk:%s:%s'):format(buildingHouse.code, stableHash(table.concat(signature, '|')))
  }
end

function MZHousesApartments.previewBulk(source, buildingCode, spec)
  local plan, err = buildBulkPlan(buildingCode, spec)
  if not plan then return false, err end
  local token = nextToken('unit-bulk', source)
  BulkPreviews[token] = {
    source = tonumber(source), expiresAt = os.time() + PREVIEW_TTL,
    buildingCode = plan.buildingCode, selected = copyTable(plan.selected),
    spec = copyTable(plan.spec), operationKey = plan.operationKey
  }
  MZHousesService.log('building.unit.bulk.started', plan.buildingCode, source, nil, {
    stage = 'preview', operationKey = plan.operationKey,
    selected = #plan.selected, eligible = #plan.eligible, skipped = #plan.skipped
  })
  return true, {
    previewToken = token, operationKey = plan.operationKey,
    buildingCode = plan.buildingCode, selected = #plan.selected,
    eligible = plan.eligible, skipped = plan.skipped
  }
end

function MZHousesApartments.applyBulk(source, previewToken)
  local preview = BulkPreviews[trim(previewToken)]
  BulkPreviews[trim(previewToken)] = nil
  if not preview or preview.source ~= tonumber(source) then return false, 'invalid_bulk_preview' end
  if preview.expiresAt < os.time() then return false, 'bulk_preview_expired' end
  local plan, planErr = buildBulkPlan(preview.buildingCode, {
    unitCodes = preview.selected,
    operation = preview.spec.operation,
    saleMode = preview.spec.saleMode,
    salePrice = preview.spec.salePrice
  })
  if not plan then return false, planErr end
  if plan.operationKey ~= preview.operationKey then return false, 'bulk_preview_stale' end

  local updated, skipped = {}, copyTable(plan.skipped)
  for _, previewItem in ipairs(plan.eligible) do
    local code = previewItem.code
    if UnitMutationLocks[code] or MZHousesCommerce.isPurchaseLocked(code) then
      skipped[#skipped + 1] = { code = code, reason = 'unit_locked_after_preview' }
      MZHousesService.log('building.unit.bulk.item.skipped', code, source, nil, {
        buildingCode = plan.buildingCode,
        operationKey = plan.operationKey,
        reason = 'unit_locked_after_preview'
      })
    else
      UnitMutationLocks[code] = true
      local protected, itemOk, itemResult = xpcall(function()
        local current = MZHousesRepository.getHouseByCode(code)
        local fresh, freshErr = evaluateBulkUnit(plan.buildingCode, code, current, preview.spec, true)
        if not fresh then return false, freshErr end
        local saved, saveResult = MZHousesCommerce.configureSale(source, code, fresh.next)
        if not saved then return false, saveResult end
        return true, fresh
      end, function(err) return tostring(err) end)
      UnitMutationLocks[code] = nil
      if protected and itemOk then
        updated[#updated + 1] = itemResult
        MZHousesService.log('building.unit.bulk.item.updated', code, source, nil, {
          buildingCode = plan.buildingCode, operationKey = plan.operationKey,
          previous = itemResult.previous, next = itemResult.next
        })
      else
        local reason = protected and itemResult or 'bulk_item_internal_error'
        skipped[#skipped + 1] = { code = code, reason = reason }
        MZHousesService.log('building.unit.bulk.item.skipped', code, source, nil, {
          buildingCode = plan.buildingCode, operationKey = plan.operationKey, reason = reason
        })
      end
    end
  end
  MZHousesService.log('building.unit.bulk.completed', plan.buildingCode, source, nil, {
    operationKey = plan.operationKey, updated = #updated, skipped = #skipped
  })
  return true, {
    buildingCode = plan.buildingCode,
    operationKey = plan.operationKey,
    updated = updated,
    skipped = skipped
  }
end

function MZHousesApartments.setBulkProtection(actorSource, unitCode, protected)
  local house = MZHousesRepository.getHouseByCode(unitCode)
  if not house then return false, 'unit_not_found' end
  local property = propertyFields(house)
  if property.subtype ~= 'apartment_unit' then return false, 'not_apartment_unit' end
  local metadata = copyTable(type(house.metadata) == 'table' and house.metadata or {})
  metadata.bulkCommerceProtected = protected == true
  return MZHousesService.updateAdminProperty(
    actorSource, house.code, { metadata = metadata },
    'building.unit.bulk.protection.updated', { protected = protected == true }
  )
end

local function nearEntrance(source, entrance, distance)
  local ped = GetPlayerPed(source)
  if not ped or ped <= 0 or type(entrance) ~= 'table' then return false end
  local coords = GetEntityCoords(ped)
  local x, y, z = tonumber(entrance.x), tonumber(entrance.y), tonumber(entrance.z)
  if not x or not y or not z then return false end
  local dx, dy, dz = coords.x - x, coords.y - y, coords.z - z
  return dx * dx + dy * dy + dz * dz <= ((tonumber(distance) or 7.5) ^ 2)
end

function MZHousesApartments.validateIntercomContext(source, buildingCode, isAdmin)
  local buildingHouse, buildingErr = getBuilding(buildingCode)
  if not buildingHouse then return false, buildingErr end
  local building = MZHousesRepository.normalizeBuilding(buildingHouse.building)
  if building.intercom ~= true then return false, 'intercom_disabled' end
  if buildingHouse.enabled ~= true or trim(buildingHouse.status):lower() ~= 'active' then return false, 'building_not_active' end
  local visible = MZHousesService.CanSeeHouse(source, buildingHouse.code, 'entry')
  if visible ~= true then return false, 'building_not_visible' end
  local door = MZHousesDoorService.resolve(buildingHouse)
  if door.state == 'blocked' and isAdmin ~= true then return false, 'building_blocked' end
  if not nearEntrance(source, buildingHouse.entrance, 7.5) then return false, 'too_far_from_intercom' end

  return true, {
    buildingCode = buildingHouse.code,
    label = buildingHouse.label or buildingHouse.code,
    doorState = door.state
  }, buildingHouse
end

function MZHousesApartments.validateIntercomPurchaseContext(source, buildingCode, unitCode, isAdmin)
  local contextOk, context, buildingHouse = MZHousesApartments.validateIntercomContext(
    source, buildingCode, isAdmin
  )
  if not contextOk then return false, context end

  local unit = MZHousesRepository.getHouseByCode(unitCode)
  if not unit then return false, 'unit_not_found' end
  local property = propertyFields(unit)
  if property.subtype ~= 'apartment_unit' or property.parentCode ~= buildingHouse.code then
    return false, 'unit_not_in_building'
  end
  if unit.enabled ~= true or trim(unit.status):lower() ~= 'active' then return false, 'unit_not_active' end
  if trim(unit.owner_citizenid or unit.owner) ~= '' then return false, 'property_already_owned' end
  local commerce = MZHousesRepository.normalizeCommerce(unit)
  if commerce.saleEnabled ~= true or commerce.saleMode ~= 'direct' or commerce.salePrice <= 0 then
    return false, 'property_not_for_sale'
  end
  if MZHousesRepository.getBlockingPurchaseTransaction(unit.code) then
    return false, 'purchase_financial_state_pending'
  end
  return true, {
    buildingCode = buildingHouse.code,
    unitCode = unit.code,
    unitNumber = property.unitNumber,
    label = unit.label or unit.code,
    saleEnabled = true,
    saleMode = 'direct',
    salePrice = commerce.salePrice
  }
end
