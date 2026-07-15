MZHousesMoney = MZHousesMoney or {}

local function metadata(action, houseCode, transactionKey, extra)
  return {
    reason = action,
    category = action == 'property_purchase_refund' and 'refund' or 'property_purchase',
    source_resource = 'mz_houses',
    source_type = 'property_commerce',
    counts_as_income = false,
    counts_as_expense = action ~= 'property_purchase_refund',
    external_ref = transactionKey,
    data = {
      action = action,
      house_code = tostring(houseCode or ''),
      transaction_key = tostring(transactionKey or ''),
      payment_method = 'bank',
      extra = type(extra) == 'table' and extra or nil
    }
  }
end

local function taxMetadata(action, houseCode, transactionKey, extra)
  local refund = action == 'property_tax_refund'
  return {
    reason = action,
    category = refund and 'refund' or 'property_tax',
    source_resource = 'mz_houses',
    source_type = 'property_tax',
    counts_as_income = false,
    counts_as_expense = not refund,
    external_ref = transactionKey,
    data = {
      action = action,
      house_code = tostring(houseCode or ''),
      transaction_key = tostring(transactionKey or ''),
      payment_method = 'bank',
      extra = type(extra) == 'table' and extra or nil
    }
  }
end

local function coreReady()
  return GetResourceState('mz_core') == 'started'
end

function MZHousesMoney.getBalance(source)
  source = tonumber(source)
  if not source or source <= 0 or not GetPlayerName(source) then return nil, 'player_not_loaded' end
  if not coreReady() then return nil, 'core_unavailable' end
  local ok, money = pcall(function() return exports['mz_core']:GetMoney(source) end)
  if not ok or type(money) ~= 'table' then return nil, 'money_export_failed' end
  return math.max(0, math.floor(tonumber(money.bank) or 0))
end

function MZHousesMoney.removeBank(source, amount, context)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return false, 'invalid_amount' end
  if not coreReady() then return false, 'core_unavailable' end
  context = type(context) == 'table' and context or {}
  local ok, success, err = pcall(function()
    return exports['mz_core']:RemoveMoney(source, 'bank', amount, metadata(
      'property_purchase', context.houseCode, context.transactionKey, context
    ))
  end)
  if not ok then return false, 'money_export_failed' end
  if success ~= true then return false, err or 'payment_failed' end
  return true
end

function MZHousesMoney.refundBank(source, amount, context)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return false, 'invalid_amount' end
  if not coreReady() then return false, 'core_unavailable' end
  context = type(context) == 'table' and context or {}
  local ok, success, err = pcall(function()
    return exports['mz_core']:AddMoney(source, 'bank', amount, metadata(
      'property_purchase_refund', context.houseCode, context.transactionKey, context
    ))
  end)
  if not ok then return false, 'money_export_failed' end
  if success ~= true then return false, err or 'refund_failed' end
  return true
end


function MZHousesMoney.removeTaxBank(source, amount, context)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return false, 'invalid_amount' end
  if not coreReady() then return false, 'core_unavailable' end
  context = type(context) == 'table' and context or {}
  local ok, success, err = pcall(function()
    return exports['mz_core']:RemoveMoney(source, 'bank', amount, taxMetadata(
      'property_tax_payment', context.houseCode, context.transactionKey, context
    ))
  end)
  if not ok then return false, 'money_export_failed' end
  if success ~= true then return false, err or 'payment_failed' end
  return true
end

function MZHousesMoney.refundTaxBank(source, amount, context)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return false, 'invalid_amount' end
  if not coreReady() then return false, 'core_unavailable' end
  context = type(context) == 'table' and context or {}
  local ok, success, err = pcall(function()
    return exports['mz_core']:AddMoney(source, 'bank', amount, taxMetadata(
      'property_tax_refund', context.houseCode, context.transactionKey, context
    ))
  end)
  if not ok then return false, 'money_export_failed' end
  if success ~= true then return false, err or 'refund_failed' end
  return true
end
