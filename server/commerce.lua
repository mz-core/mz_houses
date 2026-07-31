MZHousesCommerce = MZHousesCommerce or {}

local PurchaseLocks = {}
local TransactionSequence = 0

local function safeTraceback(err)
  if type(debug) == 'table' and type(debug.traceback) == 'function' then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

local function debugStage(stage, code, source, data)
  if not MZHousesConfig or (MZHousesConfig.CommerceDebug ~= true and MZHousesConfig.Debug ~= true) then return end
  data = type(data) == 'table' and data or {}
  local safe = {
    stage = tostring(stage or 'unknown'),
    houseCode = tostring(code or ''),
    source = tonumber(source) or 0,
    transactionId = tonumber(data.transactionId),
    status = data.status and tostring(data.status) or nil,
    reason = data.reason and tostring(data.reason) or nil
  }
  local ok, encoded = pcall(json.encode, safe)
  print(('[mz_houses][commerce] %s'):format(ok and encoded or safe.stage))
end

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function codeOf(value)
  local code = trim(value)
  return code ~= '' and code or nil
end

local function transactionKey(code)
  TransactionSequence = (TransactionSequence + 1) % 1000000
  return ('house:%s:%d:%06d:%06d'):format(
    tostring(code or ''):sub(1, 40), os.time(), TransactionSequence, math.random(0, 999999)
  )
end

local function propertyPolicy(house)
  local policy = type(house) == 'table' and house.accessPolicy or nil
  if policy then return policy end
  return MZHousesAccessPolicy.resolve(house)
end

local function validateResidentialType(house)
  if type(house) ~= 'table' then return false, 'house_not_found' end
  local property = MZHousesRepository.normalizePropertyFields(house)
  if property.category ~= 'residential' or property.ownerType ~= 'player' then
    return false, 'property_not_residential_sale'
  end
  if property.subtype ~= 'house' and property.subtype ~= 'apartment_unit' and property.subtype ~= 'apartment' then
    return false, 'property_not_individually_sellable'
  end
  local policy = propertyPolicy(house)
  if type(policy) ~= 'table' or policy.mode ~= 'owner' then return false, 'property_not_owner_policy' end
  return true, property
end

local function validateAvailable(house, requiredMode)
  local eligible, propertyOrErr = validateResidentialType(house)
  if not eligible then return false, propertyOrErr end
  if house.enabled ~= true or trim(house.status):lower() ~= 'active' then return false, 'property_not_active' end
  if trim(house.owner_citizenid or house.owner) ~= '' then return false, 'property_already_owned' end
  local commerce = MZHousesRepository.normalizeCommerce(house)
  if commerce.saleEnabled ~= true then return false, 'property_not_for_sale' end
  if commerce.salePrice <= 0 then return false, 'invalid_sale_price' end
  if commerce.saleMode ~= 'direct' and commerce.saleMode ~= 'admin' then return false, 'invalid_sale_mode' end
  if requiredMode and commerce.saleMode ~= requiredMode then return false, 'sale_mode_not_allowed' end
  local blocking = MZHousesRepository.getBlockingPurchaseTransaction(house.code)
  if blocking then return false, 'purchase_financial_state_pending' end
  return true, { property = propertyOrErr, commerce = commerce }
end

local function actorCitizenId(source)
  if tonumber(source) and tonumber(source) > 0 then return MZHousesService.getPlayerCitizenId(source) end
  return nil
end

local function failTransaction(id, code, source, buyer, reason, meta)
  if id then MZHousesRepository.updateTransaction(id, 'failed', meta or { reason = reason }, true) end
  MZHousesService.log('property.purchase.failed', code, source, buyer, {
    reason = reason,
    transactionId = id
  })
  return false, reason
end

local function manualReviewTransaction(id, code, source, buyer, reason, meta)
  local detail = type(meta) == 'table' and meta or {}
  detail.reason = reason
  MZHousesRepository.updateTransaction(id, 'manual_review', detail, false)
  pcall(MZHousesService.log, 'property.purchase.manual_review', code, source, buyer, {
    reason = reason,
    transactionId = id
  })
  return false, 'purchase_manual_review'
end

local function refundAfterFailure(source, id, key, code, buyer, amount, reason, recovery, extra)
  recovery = type(recovery) == 'table' and recovery or {}
  if recovery.refundAttempted == true then
    MZHousesRepository.updateTransaction(id, 'manual_review', {
      reason = 'refund_already_attempted', originalReason = reason
    }, false)
    return false, 'purchase_manual_review'
  end
  recovery.refundAttempted = true
  MZHousesService.log('property.purchase.failed', code, source, buyer, {
    amount = amount, reason = reason, transactionId = id
  })
  local refunded, refundErr = MZHousesMoney.refundBank(source, amount, {
    houseCode = code,
    transactionKey = key,
    transactionId = id,
    failureReason = reason
  })
  local status = refunded and 'refunded' or 'manual_review'
  if refunded then
    recovery.refunded = true
    recovery.charged = false
  end
  MZHousesRepository.updateTransaction(id, status, {
    reason = reason,
    refundError = refundErr,
    extra = extra
  }, refunded)
  MZHousesService.log(refunded and 'property.purchase.refunded' or 'property.purchase.manual_review', code, source, buyer, {
    amount = amount,
    reason = reason,
    refundError = refundErr,
    transactionId = id
  })
  return false, refunded and reason or 'purchase_manual_review'
end

function MZHousesCommerce.getSaleState(houseCode)
  local code = codeOf(houseCode)
  if not code then return nil, 'invalid_house' end
  local house = MZHousesRepository.getHouseByCode(code)
  if not house then return nil, 'house_not_found' end
  local eligible, propertyOrErr = validateResidentialType(house)
  local commerce = MZHousesRepository.normalizeCommerce(house)
  return {
    houseCode = code,
    eligible = eligible == true,
    eligibilityReason = eligible and nil or propertyOrErr,
    saleEnabled = commerce.saleEnabled,
    saleMode = commerce.saleMode,
    salePrice = commerce.salePrice,
    hasOwner = trim(house.owner_citizenid) ~= '',
    status = commerce.saleEnabled and commerce.saleMode == 'direct' and 'available_direct'
      or commerce.saleEnabled and commerce.saleMode == 'admin' and 'available_admin' or 'not_for_sale'
  }
end

function MZHousesCommerce.configureSale(actorSource, houseCode, raw)
  local code = codeOf(houseCode)
  if not code then return false, 'invalid_house' end
  local house = MZHousesRepository.getHouseByCode(code)
  local eligible, propertyOrErr = validateResidentialType(house)
  if not eligible then return false, propertyOrErr end
  local commerce = MZHousesRepository.normalizeCommerce(raw)
  if raw and raw.saleEnabled == true then
    if commerce.saleMode == 'none' then return false, 'invalid_sale_mode' end
    if commerce.salePrice <= 0 then return false, 'invalid_sale_price' end
    if house.enabled ~= true or trim(house.status):lower() ~= 'active' then return false, 'property_not_active' end
    if trim(house.owner_citizenid) ~= '' then return false, 'property_already_owned' end
    if MZHousesRepository.getBlockingPurchaseTransaction(code) then return false, 'purchase_financial_state_pending' end
    commerce.saleEnabled = true
  else
    commerce.saleEnabled = false
    commerce.saleMode = 'none'
  end
  local ok, result = MZHousesRepository.updateCommerce(code, commerce)
  if not ok then return false, result or 'sale_update_failed' end
  local refreshed, refreshErr = MZHousesService.refreshProperty(code)
  if not refreshed then return false, refreshErr or 'sale_refresh_failed' end
  local action = commerce.saleEnabled and 'property.sale.enabled' or 'property.sale.disabled'
  MZHousesService.log(action, code, actorSource, nil, {
    saleMode = commerce.saleMode,
    salePrice = commerce.salePrice
  })
  MZHousesService.log('property.sale.configure', code, actorSource, nil, commerce)
  return true, { houseCode = code, commerce = commerce }
end

function MZHousesCommerce.isPurchaseLocked(houseCode)
  local code = codeOf(houseCode)
  return code ~= nil and PurchaseLocks[code] == true
end

function MZHousesCommerce.purchase(source, houseCode, options)
  source = tonumber(source)
  options = type(options) == 'table' and options or {}
  local code = codeOf(houseCode)
  if not source or source <= 0 or not GetPlayerName(source) then return false, 'player_not_loaded' end
  if not code then return false, 'invalid_house' end
  if type(MZHousesApartments) == 'table'
      and type(MZHousesApartments.isUnitMutationLocked) == 'function'
      and MZHousesApartments.isUnitMutationLocked(code) then
    return false, 'property_admin_mutation_in_progress'
  end
  if PurchaseLocks[code] then return false, 'purchase_in_progress' end
  PurchaseLocks[code] = true
  local recovery = { charged = false, claimed = false, completed = false }

  local ok, success, result = xpcall(function()
    local buyer, buyerErr = MZHousesService.getPlayerCitizenId(source)
    if not buyer then return false, buyerErr or 'player_not_loaded' end
    recovery.buyer = buyer
    local house = MZHousesRepository.getHouseByCode(code)
    debugStage('property_reread', code, source, { status = house and house.status or 'missing' })
    local requiredMode = options.adminSale == true and nil or 'direct'
    local available, stateOrErr = validateAvailable(house, requiredMode)
    if not available then return false, stateOrErr end
    local commerce = stateOrErr.commerce
    local mode = commerce.saleMode
    local amount = commerce.salePrice
    local key = transactionKey(code)
    local actor = options.adminSale == true and actorCitizenId(options.actorSource) or buyer
    local transactionType = options.adminSale == true and 'admin_sale' or 'purchase'
    local id, txErr = MZHousesRepository.createTransaction({
      transactionKey = key,
      houseCode = code,
      buyerCitizenId = buyer,
      actorCitizenId = actor,
      sellerType = 'server',
      amount = amount,
      mode = mode,
      transactionType = transactionType,
      status = 'initiated',
      meta = { source = source, actorSource = options.actorSource }
    })
    if not id then
      debugStage('transaction_create_failed', code, source, { reason = txErr or 'transaction_insert_failed' })
      return false, txErr or 'transaction_insert_failed'
    end
    recovery.id, recovery.key, recovery.amount, recovery.mode = id, key, amount, mode
    debugStage('transaction_created', code, source, { transactionId = id, status = 'initiated' })

    MZHousesService.log('property.purchase.started', code, options.actorSource or source, buyer, {
      amount = amount, mode = mode, transactionId = id, transactionType = transactionType
    })
    local balance, balanceErr = MZHousesMoney.getBalance(source)
    if not balance then
      debugStage('balance_checked', code, source, { transactionId = id, status = 'error', reason = balanceErr })
      return failTransaction(id, code, options.actorSource or source, buyer, balanceErr, { reason = balanceErr })
    end
    debugStage('balance_checked', code, source, { transactionId = id, status = balance >= amount and 'sufficient' or 'insufficient' })
    if balance < amount then return failTransaction(id, code, options.actorSource or source, buyer, 'not_enough_money', { reason = 'not_enough_money', amount = amount }) end

    local paymentPending = MZHousesRepository.updateTransaction(id, 'payment_pending', {
      amount = amount, mode = mode
    }, false)
    if not paymentPending then return failTransaction(id, code, options.actorSource or source, buyer, 'transaction_state_failed') end

    debugStage('debit_started', code, source, { transactionId = id, status = 'payment_pending' })
    local removed, removeErr = MZHousesMoney.removeBank(source, amount, {
      houseCode = code, transactionKey = key, transactionId = id, mode = mode
    })
    if not removed then
      debugStage('debit_failed', code, source, { transactionId = id, reason = removeErr or 'payment_failed' })
      -- Excecao no export ocorre depois do inicio do debito e nao prova que o
      -- saldo permaneceu intacto. Bloqueia nova tentativa para revisao manual.
      if removeErr == 'money_export_failed' then
        return manualReviewTransaction(
          id, code, options.actorSource or source, buyer, 'debit_result_ambiguous'
        )
      end
      return failTransaction(id, code, options.actorSource or source, buyer, removeErr or 'payment_failed')
    end
    recovery.charged = true
    debugStage('debit_completed', code, source, { transactionId = id, status = 'money_removed' })
    local marked = MZHousesRepository.updateTransaction(id, 'money_removed', { amount = amount, mode = mode }, false)
    if not marked then return refundAfterFailure(source, id, key, code, buyer, amount, 'transaction_state_failed', recovery) end

    local snapshotOk, keySnapshot = pcall(MZHousesRepository.listKeys, code)
    if not snapshotOk or type(keySnapshot) ~= 'table' then
      return refundAfterFailure(source, id, key, code, buyer, amount, 'key_snapshot_failed', recovery)
    end
    recovery.keysSnapshot = keySnapshot

    debugStage('cas_started', code, source, { transactionId = id })
    recovery.casStarted = true
    local claimed, claimErr = MZHousesRepository.claimPurchase(code, buyer, amount, mode)
    recovery.casResolved = true
    if not claimed then
      debugStage('cas_failed', code, source, { transactionId = id, reason = claimErr or 'purchase_conflict' })
      return refundAfterFailure(source, id, key, code, buyer, amount, claimErr or 'purchase_conflict', recovery)
    end
    recovery.claimed = true
    debugStage('cas_completed', code, source, { transactionId = id, status = 'owner_claimed' })

    recovery.keyCleanupStarted = true
    local keysOk, keysResult = pcall(function() return MZHousesRepository.clearKeys(code) end)
    if not keysOk or keysResult ~= true then
      local restored = MZHousesRepository.restoreKeys(code, recovery.keysSnapshot)
      local rolledBack = restored == true
        and MZHousesRepository.rollbackPurchaseClaim(code, buyer, amount, mode) or false
      if restored == true and rolledBack then
        recovery.claimed = false
        return refundAfterFailure(source, id, key, code, buyer, amount, 'key_cleanup_failed', recovery)
      end
      MZHousesRepository.updateTransaction(id, 'manual_review', {
        reason = restored == true and 'claim_rollback_failed' or 'key_restore_failed'
      }, false)
      MZHousesService.refreshProperty(code)
      MZHousesService.log('property.purchase.manual_review', code, options.actorSource or source, buyer, {
        amount = amount,
        transactionId = id,
        reason = restored == true and 'claim_rollback_failed' or 'key_restore_failed'
      })
      return false, 'purchase_manual_review'
    end
    recovery.keysCleared = true

    local refreshed = MZHousesService.refreshProperty(code)
    if refreshed ~= true then
      MZHousesRepository.updateTransaction(id, 'manual_review', { reason = 'runtime_refresh_failed' }, false)
      return false, 'purchase_manual_review'
    end
    local transactionCompleted = MZHousesRepository.updateTransaction(id, 'completed', {
      amount = amount, mode = mode, keysCleared = true
    }, true)
    if transactionCompleted ~= true then
      MZHousesRepository.updateTransaction(id, 'manual_review', { reason = 'transaction_complete_failed' }, false)
      recovery.completed = true
      recovery.charged = false
      return false, 'purchase_manual_review'
    end
    recovery.completed = true
    recovery.charged = false
    local taxState = nil
    if type(MZHousesTax) == 'table' and type(MZHousesTax.initializeForOwner) == 'function' then
      local taxCallOk, taxOk, taxResult = pcall(
        MZHousesTax.initializeForOwner, code, buyer, 'property_purchase_completed'
      )
      if taxCallOk and taxOk == true then
        taxState = taxResult
      else
        pcall(MZHousesService.log, 'property.tax.initialize.failed', code, options.actorSource or source, buyer, {
          reason = taxCallOk and taxResult or 'tax_initialize_exception',
          purchaseCompleted = true,
          transactionId = id
        })
      end
    end
    pcall(MZHousesService.log, 'property.purchase.completed', code, options.actorSource or source, buyer, {
      amount = amount, mode = mode, transactionId = id, transactionType = transactionType
    })
    pcall(MZHousesService.log, 'property.sale.disabled', code, options.actorSource or source, buyer, {
      reason = 'purchase_completed', transactionId = id
    })
    if options.adminSale == true then
      pcall(MZHousesService.log, 'property.sale.admin.completed', code, options.actorSource, buyer, {
        amount = amount, transactionId = id
      })
    end
    local purchasedHouse = MZHousesRepository.getHouseByCode(code) or {}
    pcall(TriggerEvent, 'mz_houses:server:propertyOwnershipChanged', {
      houseCode = code,
      propertyId = tonumber(purchasedHouse.id),
      previousOwner = nil,
      newOwner = buyer,
      reason = 'property_purchase_completed',
      actorSource = tonumber(options.actorSource or source),
      transactionId = id
    })
    pcall(TriggerEvent, 'mz_houses:server:propertyAccessChanged', code, 'property_purchase_completed')
    return true, {
      houseCode = code,
      amount = amount,
      paymentMethod = 'bank',
      transactionId = id,
      saleMode = mode,
      tax = taxState
    }
  end, safeTraceback)

  PurchaseLocks[code] = nil
  if not ok then
    debugStage('exception_captured', code, source, { transactionId = recovery.id, reason = 'unexpected_error' })
    if recovery.charged and not recovery.completed and recovery.id then
      if recovery.casStarted == true and recovery.casResolved ~= true and recovery.claimed ~= true then
        local readOk, current = pcall(MZHousesRepository.getHouseByCode, code)
        if readOk and type(current) == 'table' then
          local currentOwner = trim(current.owner_citizenid or current.owner)
          if currentOwner == recovery.buyer then
            recovery.claimed = true
            recovery.casResolved = true
          else
            -- Outro owner ou owner vazio provam que este comprador nao obteve
            -- o claim. O refund permanece seguro e o CAS nao e revertido.
            recovery.casResolved = true
          end
        end
      end
      if recovery.claimed then
        local restoreOk, restored = pcall(
          MZHousesRepository.restoreKeys, code, recovery.keysSnapshot or {}
        )
        if restoreOk and restored == true then
          local rollbackOk, rolledBack = pcall(
            MZHousesRepository.rollbackPurchaseClaim,
            code, recovery.buyer, recovery.amount, recovery.mode
          )
          if rollbackOk and rolledBack == true then recovery.claimed = false end
        end
      end
      if recovery.casStarted == true and recovery.casResolved ~= true and recovery.claimed ~= true then
        pcall(MZHousesRepository.updateTransaction, recovery.id, 'manual_review', {
          reason = 'cas_result_ambiguous', traceback = tostring(success)
        }, false)
        recovery.manualReview = true
      elseif not recovery.claimed then
        pcall(
          refundAfterFailure,
          source, recovery.id, recovery.key, code, recovery.buyer, recovery.amount,
          'unexpected_error', recovery, { traceback = tostring(success) }
        )
      else
        pcall(MZHousesRepository.updateTransaction, recovery.id, 'manual_review', {
          reason = 'unexpected_error_after_claim_or_key_restore', traceback = tostring(success)
        }, false)
        recovery.manualReview = true
      end
      pcall(MZHousesService.refreshProperty, code)
    end
    pcall(MZHousesService.log, 'property.purchase.failed', code, options.actorSource or source, nil, { reason = 'unexpected_error' })
    print(('[mz_houses][commerce] purchase exception house=%s error=%s'):format(code, tostring(success)))
    if recovery.manualReview == true
      or (recovery.refundAttempted == true and recovery.refunded ~= true) then
      return false, 'purchase_manual_review'
    end
    return false, 'purchase_failed'
  end
  return success, result
end

function MZHousesCommerce.recoverInterruptedTransactions()
  return MZHousesRepository.recoverInterruptedTransactions()
end

if MZHousesConfig and (MZHousesConfig.CommerceDebug == true or MZHousesConfig.Debug == true) then
  print('[mz_houses][commerce] API carregada: getSaleState, configureSale, purchase, isPurchaseLocked, recoverInterruptedTransactions')
end
