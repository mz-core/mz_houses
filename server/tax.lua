MZHousesTax = MZHousesTax or {}

if type(MZHousesMoney) ~= 'table'
    or type(MZHousesMoney.getBalance) ~= 'function'
    or type(MZHousesMoney.removeTaxBank) ~= 'function'
    or type(MZHousesMoney.refundTaxBank) ~= 'function' then
  error('[mz_houses] Adapter financeiro de IPTU nao foi carregado.')
end
if type(MZHousesAccessPolicy) ~= 'table'
    or type(MZHousesAccessPolicy.resolve) ~= 'function' then
  error('[mz_houses] Evaluator de acesso nao foi carregado antes do IPTU.')
end

local PaymentLocks = {}
local NoticeState = {}
local Sequence = 0

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function config()
  return type((MZHousesConfig or {}).Tax) == 'table' and MZHousesConfig.Tax or {}
end

local function debugLog(stage, code, detail)
  if config().debug ~= true then return end
  print(('[mz_houses][tax] stage=%s house=%s detail=%s'):format(
    tostring(stage), tostring(code or '-'), tostring(detail or '-')
  ))
end

local function codeOf(value)
  local code = trim(value)
  return code ~= '' and code or nil
end

local function normalizeDate(value)
  local date = trim(value):gsub('T', ' '):gsub('Z$', '')
  local y, m, d, h, i, s = date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$')
  if not y then
    y, m, d = date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    h, i, s = '00', '00', '00'
  end
  y, m, d, h, i, s = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(i), tonumber(s)
  if not y or y < 2020 or y > 2200 or m < 1 or m > 12 or d < 1 or d > 31
      or h < 0 or h > 23 or i < 0 or i > 59 or s < 0 or s > 59 then
    return nil
  end
  local monthDays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 then monthDays[2] = 29 end
  if d > monthDays[m] then return nil end
  return ('%04d-%02d-%02d %02d:%02d:%02d'):format(y, m, d, h, i, s)
end

local function eligible(house, requireOwner, allowInactive)
  if type(house) ~= 'table' then return false, 'house_not_found' end
  local property = MZHousesRepository.normalizePropertyFields(house)
  if property.category ~= 'residential' or property.ownerType ~= 'player'
      or (property.subtype ~= 'house' and property.subtype ~= 'apartment'
        and property.subtype ~= 'apartment_unit') then
    return false, 'tax_not_eligible'
  end
  local policy = MZHousesAccessPolicy.resolve(house)
  if type(policy) ~= 'table' or policy.mode ~= 'owner' then
    return false, 'tax_not_eligible'
  end
  local propertyStatus = trim(house.status):lower()
  if propertyStatus == 'archived' then return false, 'property_archived' end
  if allowInactive ~= true and (house.enabled ~= true or propertyStatus ~= 'active') then
    return false, 'property_not_active'
  end
  if requireOwner == true and trim(house.owner_citizenid or house.owner) == '' then
    return false, 'property_has_no_owner'
  end
  return true, property
end

local function statePayload(house, includeHistory, includeSensitiveHistory)
  local tax = MZHousesRepository.normalizeTax(house)
  local payload = {
    houseCode = house.code,
    label = house.label or house.code,
    enabled = tax.taxEnabled,
    amount = tax.taxAmount,
    intervalDays = tax.taxIntervalDays,
    gracePeriodDays = tax.taxGracePeriodDays,
    dueAt = tax.taxDueAt,
    graceUntil = tax.taxGraceUntil,
    status = tax.taxStatus,
    lastPaidAt = tax.taxLastPaidAt,
    initialized = tax.taxDueAt ~= nil and trim(tax.taxDueAt) ~= '',
    hasOwner = trim(house.owner_citizenid or house.owner) ~= ''
  }
  if includeHistory == true then
    local rows = MZHousesRepository.listTaxPayments(
      house.code, tonumber(config().historyLimit) or 20
    )
    if includeSensitiveHistory == true then
      payload.payments = rows
    else
      payload.payments = {}
      local currentOwner = trim(house.owner_citizenid or house.owner)
      for _, row in ipairs(rows) do
        if trim(row.owner_citizenid) == currentOwner then
          payload.payments[#payload.payments + 1] = {
            id = row.id, amount = row.amount, payment_method = row.payment_method,
            period_start = row.period_start, period_end = row.period_end,
            due_at = row.due_at, paid_at = row.paid_at, status = row.status,
            created_at = row.created_at, completed_at = row.completed_at
          }
        end
      end
    end
  end
  return payload
end

local function refreshWithAudit(code, actorSource)
  local before = MZHousesRepository.getHouseByCode(code)
  local previous = before and MZHousesRepository.normalizeTax(before).taxStatus or nil
  local current = MZHousesRepository.refreshTaxStatus(code)
  local status = current and MZHousesRepository.normalizeTax(current).taxStatus or nil
  if current and previous and status ~= previous then
    MZHousesService.log('property.tax.status.changed', code, actorSource, current.owner_citizenid, {
      before = previous, after = status,
      dueAt = current.taxDueAt, graceUntil = current.taxGraceUntil,
      automatic = actorSource == nil
    })
    if status == 'overdue' then
      MZHousesService.log('property.tax.overdue', code, actorSource, current.owner_citizenid, {
        dueAt = current.taxDueAt, graceUntil = current.taxGraceUntil
      })
    end
  end
  return current, previous, status
end

local function inspectCompletion(recovery, code)
  local payment = MZHousesRepository.getTaxPaymentById(recovery.id)
  local house = MZHousesRepository.getHouseByCode(code)
  if not payment or not house then return 'ambiguous' end
  local paymentStatus = trim(payment.status):lower()
  local currentOwner = trim(house.owner_citizenid or house.owner)
  local currentTax = MZHousesRepository.normalizeTax(house)
  if paymentStatus == 'completed' and currentOwner == recovery.owner
      and trim(currentTax.taxDueAt) ~= trim(recovery.cycleDueAt) then
    return 'completed', house
  end
  if paymentStatus == 'money_removed' and currentOwner == recovery.owner
      and trim(currentTax.taxDueAt) == trim(recovery.cycleDueAt) then
    return 'safe_refund', house
  end
  if paymentStatus == 'refunded' then return 'refunded', house end
  return 'ambiguous', house
end

local function transactionKey(code)
  Sequence = (Sequence + 1) % 1000000
  return ('tax:%s:%d:%d:%06d:%06d'):format(
    code, os.time(), GetGameTimer() % 1000000000, Sequence, math.random(0, 999999)
  ):sub(1, 96)
end

local function markFailed(id, reason, code, source, owner, amount)
  if id then
    MZHousesRepository.updateTaxPayment(id, 'failed', { reason = reason }, true)
    MZHousesService.log('property.tax.payment.failed', code, source, owner, {
      paymentId = id, reason = reason, amount = amount
    })
  end
  return false, reason
end

local function markManualReview(id, code, source, reason)
  MZHousesRepository.updateTaxPayment(id, 'manual_review', { reason = reason }, false)
  MZHousesService.log('property.tax.manual_review', code, source, nil, {
    paymentId = id, reason = reason
  })
  return false, 'tax_payment_manual_review'
end

local function refund(source, id, key, code, owner, amount, reason, recovery)
  recovery = type(recovery) == 'table' and recovery or {}
  if recovery.refundAttempted == true then
    pcall(MZHousesRepository.updateTaxPayment, id, 'manual_review', {
      reason = reason, refundError = 'refund_already_attempted'
    }, false)
    return false, 'tax_payment_manual_review'
  end
  recovery.refundAttempted = true
  recovery.refundReason = reason
  local refunded, refundErr = MZHousesMoney.refundTaxBank(source, amount, {
    houseCode = code, ownerCitizenId = owner, transactionKey = key,
    paymentId = id, cycleDueAt = recovery.cycleDueAt, reason = reason
  })
  if refunded == true then
    recovery.refundSucceeded = true
    recovery.charged = false
    local recorded = MZHousesRepository.updateTaxPayment(id, 'refunded', { reason = reason }, true)
    if recorded ~= true then
      pcall(MZHousesRepository.updateTaxPayment, id, 'manual_review', {
        reason = reason, refundError = 'refund_state_not_recorded'
      }, false)
      MZHousesService.log('property.tax.manual_review', code, source, nil, {
        paymentId = id, reason = reason, refundError = 'refund_state_not_recorded'
      })
      return false, 'tax_payment_manual_review'
    end
    recovery.refundRecorded = true
    MZHousesService.log('property.tax.refunded', code, source, nil, {
      paymentId = id, amount = amount, reason = reason
    })
    return false, reason
  end
  MZHousesRepository.updateTaxPayment(id, 'manual_review', {
    reason = reason, refundError = refundErr
  }, false)
  MZHousesService.log('property.tax.manual_review', code, source, nil, {
    paymentId = id, reason = reason, refundError = refundErr
  })
  return false, 'tax_payment_manual_review'
end

function MZHousesTax.normalizeConfig(raw)
  raw = type(raw) == 'table' and raw or {}
  local normalized = MZHousesRepository.normalizeTax(raw)
  if normalized.taxEnabled and normalized.taxAmount <= 0 then return nil, 'invalid_tax_amount' end
  return normalized, nil
end

function MZHousesTax.isEligible(house, requireOwner)
  return eligible(house, requireOwner)
end

function MZHousesTax.isPaymentLocked(code)
  return PaymentLocks[trim(code)] == true
end

function MZHousesTax.refreshStatus(code)
  local raw = MZHousesRepository.getHouseByCode(code)
  local allowed, allowedErr = eligible(raw, false)
  if not allowed then return nil, allowedErr end
  local house = refreshWithAudit(code)
  if not house then return nil, 'house_not_found' end
  MZHousesService.refreshProperty(house.code)
  return statePayload(house, false)
end

function MZHousesTax.getStatus(source, code, isAdmin, includeHistory)
  source = tonumber(source)
  code = codeOf(code)
  if not source or source <= 0 or not code then return nil, 'invalid_tax_request' end
  local raw = MZHousesRepository.getHouseByCode(code)
  local ok, err = eligible(raw, false, isAdmin == true)
  if not ok then return nil, err end
  local house = refreshWithAudit(code, isAdmin == true and source or nil)
  local citizenid = MZHousesService.getPlayerCitizenId(source)
  if isAdmin ~= true and (not citizenid or trim(house.owner_citizenid) ~= citizenid) then
    return nil, 'tax_owner_required'
  end
  MZHousesService.refreshProperty(code)
  return statePayload(house, includeHistory == true, isAdmin == true), nil
end

function MZHousesTax.listForOwner(source)
  source = tonumber(source)
  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then return nil, citizenErr or 'player_not_loaded' end
  local out = {}
  for _, raw in ipairs(MZHousesRepository.listTaxesByOwner(citizenid)) do
    local allowed = eligible(raw, true)
    if allowed then
      local house = refreshWithAudit(raw.code) or raw
      local state = statePayload(house, false)
      if state.enabled == true then out[#out + 1] = state end
    end
  end
  return out, nil
end

function MZHousesTax.configure(actorSource, code, raw, options)
  code = codeOf(code)
  options = type(options) == 'table' and options or {}
  if not code then return false, 'invalid_house' end
  local house = MZHousesRepository.getHouseByCode(code)
  local allowed, allowedErr = eligible(house, false, true)
  if not allowed then return false, allowedErr end
  local owner = trim(house.owner_citizenid or house.owner)
  if PaymentLocks[code] or MZHousesRepository.getBlockingTaxPayment(code, owner ~= '' and owner or nil) then
    return false, 'tax_payment_in_progress'
  end
  local normalized, normalizedErr = MZHousesTax.normalizeConfig(raw)
  if not normalized then return false, normalizedErr end
  local beforeTax = MZHousesRepository.normalizeTax(house)
  if options.initialize == true and normalized.taxEnabled then
    if owner == '' then return false, 'property_has_no_owner' end
    local initializable, initializableErr = eligible(house, true, false)
    if not initializable then return false, initializableErr end
  end
  local requestedDueAt = nil
  if options.initialize == true and options.dueAt ~= nil then
    requestedDueAt = normalizeDate(options.dueAt)
    if not requestedDueAt then return false, 'invalid_tax_due_at' end
  end
  local saved, saveErr = MZHousesRepository.updateTaxConfiguration(code, normalized)
  if not saved then return false, saveErr or 'tax_config_save_failed' end
  if normalized.taxEnabled and owner ~= '' and options.initialize == true then
    local initialized = MZHousesRepository.initializeTaxForOwner(code, owner, requestedDueAt)
    if not initialized then return false, 'tax_initialize_failed' end
  elseif not normalized.taxEnabled then
    MZHousesRepository.suspendTax(code)
  end
  MZHousesService.refreshProperty(code)
  local current = refreshWithAudit(code, actorSource) or MZHousesRepository.getHouseByCode(code)
  MZHousesService.refreshProperty(code)
  MZHousesService.log('property.tax.configure', code, actorSource, owner ~= '' and owner or nil, {
    before = {
      enabled = beforeTax.taxEnabled, amount = beforeTax.taxAmount,
      intervalDays = beforeTax.taxIntervalDays,
      gracePeriodDays = beforeTax.taxGracePeriodDays,
      dueAt = beforeTax.taxDueAt, status = beforeTax.taxStatus
    },
    after = {
      enabled = normalized.taxEnabled, amount = normalized.taxAmount,
      intervalDays = normalized.taxIntervalDays,
      gracePeriodDays = normalized.taxGracePeriodDays,
      dueAt = current and current.taxDueAt or nil,
      status = current and current.taxStatus or nil
    },
    initialized = options.initialize == true
  })
  return true, statePayload(current, false)
end

function MZHousesTax.initializeForOwner(code, citizenid, reason, dueAt)
  code = codeOf(code)
  citizenid = trim(citizenid)
  if not code or citizenid == '' then return false, 'invalid_tax_owner' end
  local house = MZHousesRepository.getHouseByCode(code)
  local allowed, allowedErr = eligible(house, true)
  if not allowed then return false, allowedErr end
  if trim(house.owner_citizenid or house.owner) ~= citizenid then return false, 'tax_owner_mismatch' end
  if PaymentLocks[code] or MZHousesRepository.getBlockingTaxPayment(code, citizenid) then
    return false, 'tax_payment_manual_review'
  end
  local tax = MZHousesRepository.normalizeTax(house)
  if not tax.taxEnabled or tax.taxAmount <= 0 then
    MZHousesRepository.suspendTax(code, citizenid)
    MZHousesService.refreshProperty(code)
    return true, { houseCode = code, initialized = false, status = 'disabled' }
  end
  local normalizedDue = dueAt ~= nil and normalizeDate(dueAt) or nil
  if dueAt ~= nil and not normalizedDue then return false, 'invalid_tax_due_at' end
  local initialized, initializeState = MZHousesRepository.initializeTaxForOwner(code, citizenid, normalizedDue)
  if not initialized then return false, initializeState or 'tax_initialize_failed' end
  local refreshed = refreshWithAudit(code)
  MZHousesService.refreshProperty(code)
  MZHousesService.log('property.tax.initialized', code, nil, citizenid, {
    reason = trim(reason) ~= '' and trim(reason) or 'owner_initialized',
    dueAt = refreshed and refreshed.taxDueAt or nil,
    idempotent = initializeState == 'already_initialized'
  })
  local payload = statePayload(refreshed, false)
  payload.idempotent = initializeState == 'already_initialized'
  return true, payload
end

function MZHousesTax.suspendForOwnerRemoval(code, citizenid, actorSource)
  code = codeOf(code)
  if not code then return false, 'invalid_house' end
  local suspended = MZHousesRepository.suspendTax(code, citizenid)
  if suspended then
    MZHousesService.log('property.tax.suspended', code, actorSource, citizenid, {
      reason = 'owner_removed', historyPreserved = true
    })
  end
  return suspended
end

function MZHousesTax.suspendIfIneligible(code, actorSource, reason)
  code = codeOf(code)
  if not code then return false, 'invalid_house' end
  local house = MZHousesRepository.getHouseByCode(code)
  if not house then return false, 'house_not_found' end
  local allowed = eligible(house, false)
  if allowed then return true, { suspended = false } end
  local tax = MZHousesRepository.normalizeTax(house)
  if tax.taxStatus == 'disabled' and trim(tax.taxDueAt) == '' then
    return true, { suspended = false }
  end
  local owner = trim(house.owner_citizenid or house.owner)
  local suspended = MZHousesRepository.suspendTax(code, owner ~= '' and owner or nil)
  if not suspended then return false, 'tax_suspend_failed' end
  MZHousesService.refreshProperty(code)
  MZHousesService.log('property.tax.suspended', code, actorSource, owner ~= '' and owner or nil, {
    reason = trim(reason) ~= '' and trim(reason) or 'property_no_longer_tax_eligible',
    historyPreserved = true
  })
  return true, { suspended = true }
end

function MZHousesTax.setDueAt(actorSource, code, dueAt)
  code = codeOf(code)
  dueAt = normalizeDate(dueAt)
  if not code or not dueAt then return false, 'invalid_tax_due_at' end
  local house = MZHousesRepository.getHouseByCode(code)
  local allowed, allowedErr = eligible(house, true, true)
  if not allowed then return false, allowedErr end
  local owner = trim(house.owner_citizenid or house.owner)
  if PaymentLocks[code] or MZHousesRepository.getBlockingTaxPayment(code, owner) then return false, 'tax_payment_in_progress' end
  local beforeTax = MZHousesRepository.normalizeTax(house)
  local saved = MZHousesRepository.setTaxDueAt(code, dueAt)
  if not saved then return false, 'tax_due_update_failed' end
  local refreshed = MZHousesRepository.getHouseByCode(code)
  MZHousesService.refreshProperty(code)
  MZHousesService.log('property.tax.adjusted', code, actorSource, owner, {
    field = 'dueAt', before = beforeTax.taxDueAt, after = dueAt
  })
  return true, statePayload(refreshed, false)
end

function MZHousesTax.setStatus(actorSource, code, status)
  code = codeOf(code)
  status = trim(status):lower()
  if not code then return false, 'invalid_house' end
  local before = MZHousesRepository.getHouseByCode(code)
  local allowed, allowedErr = eligible(before, true, true)
  if not allowed then return false, allowedErr end
  local owner = trim(before.owner_citizenid or before.owner)
  if PaymentLocks[code] or MZHousesRepository.getBlockingTaxPayment(code, owner) then return false, 'tax_payment_in_progress' end
  local previousStatus = MZHousesRepository.normalizeTax(before).taxStatus
  local saved, saveErr = MZHousesRepository.setTaxStatus(code, status)
  if not saved then return false, saveErr or 'tax_status_update_failed' end
  local house = MZHousesRepository.getHouseByCode(code)
  MZHousesService.refreshProperty(code)
  MZHousesService.log(status == 'blocked' and 'property.tax.blocked' or 'property.tax.adjusted', code, actorSource, owner, {
    field = 'status', before = previousStatus, after = status,
    doorStateUnchanged = true
  })
  return true, statePayload(house, false)
end

function MZHousesTax.pay(source, code)
  source = tonumber(source)
  code = codeOf(code)
  if not source or source <= 0 or not GetPlayerName(source) then return false, 'player_not_loaded' end
  if not code then return false, 'invalid_house' end
  if PaymentLocks[code] then return false, 'tax_payment_in_progress' end
  PaymentLocks[code] = true
  local recovery = { charged = false, advanced = false, completed = false }
  local ok, success, result = xpcall(function()
    local owner, ownerErr = MZHousesService.getPlayerCitizenId(source)
    if not owner then return false, ownerErr or 'player_not_loaded' end
    local house = MZHousesRepository.getHouseByCode(code)
    local allowed, allowedErr = eligible(house, true)
    if not allowed then return false, allowedErr end
    if trim(house.owner_citizenid or house.owner) ~= owner then return false, 'tax_owner_required' end
    house = refreshWithAudit(code)
    allowed, allowedErr = eligible(house, true)
    if not allowed then return false, allowedErr end
    local tax = MZHousesRepository.normalizeTax(house)
    if not tax.taxEnabled or tax.taxAmount <= 0 or trim(tax.taxDueAt) == '' then return false, 'tax_not_initialized' end
    if tax.taxStatus == 'blocked' then return false, 'tax_blocked' end
    local timing = MZHousesRepository.getTaxTiming(code) or {}
    local payAheadSeconds = math.max(0, math.floor(tonumber(config().payAheadDays) or 3)) * 86400
    if tax.taxStatus == 'paid' and (tonumber(timing.seconds_until_due) or math.huge) > payAheadSeconds then
      return false, 'tax_not_due_yet'
    end
    if MZHousesRepository.getBlockingTaxPayment(code, owner) then return false, 'tax_payment_manual_review' end
    local key = transactionKey(code)
    local id, idErr = MZHousesRepository.createTaxPayment({
      transactionKey = key, houseCode = code, ownerCitizenId = owner,
      amount = tax.taxAmount, periodStart = tax.taxLastPaidAt,
      periodEnd = tax.taxDueAt, dueAt = tax.taxDueAt,
      metadata = { status = tax.taxStatus }
    })
    if not id then return false, idErr or 'tax_payment_insert_failed' end
    recovery.id, recovery.key, recovery.amount = id, key, tax.taxAmount
    recovery.owner, recovery.cycleDueAt = owner, tax.taxDueAt
    MZHousesService.log('property.tax.payment.started', code, source, owner, {
      paymentId = id, amount = tax.taxAmount, dueAt = tax.taxDueAt
    })
    debugLog('payment_started', code, id)
    local balance, balanceErr = MZHousesMoney.getBalance(source)
    if not balance then return markFailed(id, balanceErr or 'financial_service_unavailable', code, source, owner, tax.taxAmount) end
    if balance < tax.taxAmount then return markFailed(id, 'insufficient_funds', code, source, owner, tax.taxAmount) end
    if not MZHousesRepository.updateTaxPayment(id, 'payment_pending', { amount = tax.taxAmount }, false) then
      return markFailed(id, 'tax_payment_state_failed', code, source, owner, tax.taxAmount)
    end
    local removed, removeErr = MZHousesMoney.removeTaxBank(source, tax.taxAmount, {
      houseCode = code, ownerCitizenId = owner, transactionKey = key,
      paymentId = id, cycleDueAt = tax.taxDueAt
    })
    if not removed then
      if removeErr == 'money_export_failed' then return markManualReview(id, code, source, 'debit_result_ambiguous') end
      return markFailed(id, removeErr or 'payment_failed', code, source, owner, tax.taxAmount)
    end
    recovery.charged = true
    if not MZHousesRepository.updateTaxPayment(id, 'money_removed', { amount = tax.taxAmount }, false) then
      return refund(source, id, key, code, owner, tax.taxAmount, 'tax_payment_state_failed', recovery)
    end
    recovery.completionAttempted = true
    local completed = MZHousesRepository.completeTaxPayment(id, code, owner, tax.taxAmount, tax.taxDueAt, {
      amount = tax.taxAmount, previousDueAt = tax.taxDueAt
    })
    if not completed then
      local completionState, completionHouse = inspectCompletion(recovery, code)
      if completionState == 'completed' then
        recovery.advanced, recovery.completed, recovery.charged = true, true, false
        return true, {
          houseCode = code, paymentId = id, amount = tax.taxAmount,
          status = completionHouse.taxStatus or 'paid', nextDueAt = completionHouse.taxDueAt,
          responseRecovered = true
        }
      end
      if completionState == 'safe_refund' then
        return refund(source, id, key, code, owner, tax.taxAmount, 'tax_state_changed', recovery)
      end
      return markManualReview(id, code, source, 'tax_completion_result_ambiguous')
    end
    recovery.advanced = true
    recovery.completed = true
    recovery.charged = false
    local refreshed = MZHousesRepository.getHouseByCode(code)
    MZHousesService.refreshProperty(code)
    MZHousesService.log('property.tax.paid', code, source, owner, {
      amount = tax.taxAmount, paymentId = id,
      previousDueAt = tax.taxDueAt, nextDueAt = refreshed and refreshed.taxDueAt or nil
    })
    return true, {
      houseCode = code, paymentId = id, amount = tax.taxAmount,
      status = refreshed and refreshed.taxStatus or 'paid',
      nextDueAt = refreshed and refreshed.taxDueAt or nil
    }
  end, function(err) return debug.traceback(tostring(err), 2) end)
  PaymentLocks[code] = nil
  if not ok then
    print(('[mz_houses][tax] payment exception house=%s error=%s'):format(code, tostring(success)))
    if recovery.completed then
      local readOk, current = pcall(MZHousesRepository.getHouseByCode, code)
      return true, {
        houseCode = code, paymentId = recovery.id, amount = recovery.amount,
        status = readOk and current and current.taxStatus or 'paid',
        nextDueAt = readOk and current and current.taxDueAt or nil,
        responseRecovered = true
      }
    end
    if recovery.refundAttempted then
      if recovery.refundSucceeded and recovery.refundRecorded then
        return false, recovery.refundReason or 'tax_payment_failed'
      end
      pcall(markManualReview, recovery.id, code, source,
        recovery.refundSucceeded and 'exception_after_tax_refund' or 'refund_result_ambiguous')
      return false, 'tax_payment_manual_review'
    end
    if recovery.charged and recovery.completionAttempted then
      local inspectOk, completionState, completionHouse = pcall(inspectCompletion, recovery, code)
      if inspectOk and completionState == 'completed' then
        recovery.completed, recovery.charged = true, false
        return true, {
          houseCode = code, paymentId = recovery.id, amount = recovery.amount,
          status = completionHouse and completionHouse.taxStatus or 'paid',
          nextDueAt = completionHouse and completionHouse.taxDueAt or nil,
          responseRecovered = true
        }
      end
      if inspectOk and completionState == 'safe_refund' then
        local refundCallOk, refundOk, refundReason = pcall(
          refund, source, recovery.id, recovery.key, code, recovery.owner,
          recovery.amount, 'tax_payment_internal_error', recovery
        )
        if refundCallOk then return refundOk, refundReason end
      end
      pcall(markManualReview, recovery.id, code, source, 'tax_completion_result_ambiguous')
      return false, 'tax_payment_manual_review'
    end
    if recovery.charged and recovery.id then
      if recovery.advanced then
        pcall(markManualReview, recovery.id, code, source, 'exception_after_tax_advance')
      else
        pcall(refund, source, recovery.id, recovery.key, code, recovery.owner, recovery.amount,
          'tax_payment_internal_error', recovery)
      end
      return false, 'tax_payment_manual_review'
    end
    return false, 'tax_payment_internal_error'
  end
  return success, result
end

function MZHousesTax.processBatch()
  local batchSize = math.max(1, math.min(500, math.floor(tonumber(config().batchSize) or 100)))
  local afterCode, changed = '', 0
  while true do
    local rows = MZHousesRepository.listTaxTransitionCandidates(afterCode, batchSize)
    if #rows == 0 then break end
    for _, row in ipairs(rows) do
      afterCode = trim(row.code)
      local before = MZHousesRepository.getHouseByCode(row.code)
      local allowed = eligible(before, true)
      if allowed then
        local current, previous, status = refreshWithAudit(row.code)
        if current and status ~= previous then
          changed = changed + 1
          MZHousesService.refreshProperty(row.code)
        end
      elseif before and MZHousesRepository.normalizeTax(before).taxStatus ~= 'disabled' then
        MZHousesRepository.suspendTax(row.code, before.owner_citizenid)
        MZHousesService.refreshProperty(row.code)
        MZHousesService.log('property.tax.suspended', row.code, nil, before.owner_citizenid, {
          reason = 'property_no_longer_tax_eligible', historyPreserved = true
        })
      end
    end
    if #rows < batchSize then break end
  end
  return true, { changed = changed }
end

function MZHousesTax.recoverInterruptedPayments()
  local ok, result = MZHousesRepository.recoverInterruptedTaxPayments()
  if ok then
    MZHousesService.log('property.tax.recovery', nil, nil, nil, result)
    debugLog('recovery', nil, ('failed=%s manualReview=%s'):format(
      tostring(result and result.failed or 0), tostring(result and result.manualReview or 0)
    ))
  end
  return ok, result
end

function MZHousesTax.notifyOwner(source)
  source = tonumber(source)
  if not source or source <= 0 or not GetPlayerName(source) then return false end
  local taxes = MZHousesTax.listForOwner(source)
  if type(taxes) ~= 'table' then return false end
  local now, cooldown = os.time(), math.max(60, tonumber(config().noticeCooldownSeconds) or 600)
  NoticeState[source] = NoticeState[source] or {}
  for _, tax in ipairs(taxes) do
    local timing = MZHousesRepository.getTaxTiming(tax.houseCode) or {}
    local seconds = tonumber(timing.seconds_until_due)
    local near = tax.status == 'paid' and seconds and seconds >= 0
      and seconds <= (math.max(0, tonumber(config().payAheadDays) or 3) * 86400)
    if near or tax.status == 'due' or tax.status == 'overdue' or tax.status == 'blocked' then
      local key = ('%s:%s'):format(tax.houseCode, tax.status)
      if now - (NoticeState[source][key] or 0) >= cooldown then
        NoticeState[source][key] = now
        TriggerClientEvent('mz_houses:client:taxNotice', source, {
          houseCode = tax.houseCode, label = tax.label, status = tax.status,
          amount = tax.amount, dueAt = tax.dueAt, graceUntil = tax.graceUntil,
          nearDue = near == true
        })
        MZHousesService.log('property.tax.notice.sent', tax.houseCode, source, nil, {
          status = tax.status, nearDue = near == true
        })
      end
    end
  end
  return true
end

AddEventHandler('playerDropped', function()
  NoticeState[source] = nil
end)
