MZHousesPrepare = MZHousesPrepare or {}

local MYSQL_READY_TIMEOUT_MS = 15000

local function debugLog(message)
  if MZHousesConfig and MZHousesConfig.Debug == true then
    print(('[mz_houses][prepare] %s'):format(tostring(message)))
  end
end

local function databaseEnabled()
  return MZHousesConfig
    and MZHousesConfig.Database
    and MZHousesConfig.Database.enabled == true
end

local function isMySQLReady()
  return MySQL
    and type(MySQL.query) == 'table'
    and type(MySQL.query.await) == 'function'
    and type(MySQL.single) == 'table'
    and type(MySQL.single.await) == 'function'
    and type(MySQL.insert) == 'table'
    and type(MySQL.insert.await) == 'function'
    and type(MySQL.update) == 'table'
    and type(MySQL.update.await) == 'function'
end

local function waitForMySQLReady()
  local startedAt = GetGameTimer()

  while not isMySQLReady() do
    if GetGameTimer() - startedAt >= MYSQL_READY_TIMEOUT_MS then
      return false, 'mysql_not_ready'
    end

    Wait(250)
  end

  return true
end

local statements = {
  [[CREATE TABLE IF NOT EXISTS mz_houses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL,
    label VARCHAR(120) NOT NULL,
    category VARCHAR(40) NOT NULL DEFAULT 'residential',
    subtype VARCHAR(40) NOT NULL DEFAULT 'house',
    owner_type VARCHAR(40) NOT NULL DEFAULT 'player',
    parent_code VARCHAR(80) NULL,
    unit_number VARCHAR(30) NULL,
    org_code VARCHAR(80) NULL,
    business_code VARCHAR(80) NULL,
    building_json LONGTEXT NULL,
    type VARCHAR(30) NOT NULL DEFAULT 'shell',
    shell VARCHAR(80) NULL,
    entrance_json LONGTEXT NULL,
    garage_json LONGTEXT NULL,
    features_json LONGTEXT NULL,
    interior_json LONGTEXT NULL,
    metadata_json LONGTEXT NULL,
    access_json LONGTEXT NULL,
    door_json LONGTEXT NULL,
    visibility VARCHAR(30) NOT NULL DEFAULT 'auto',
    listing_json LONGTEXT NULL,
    realestate_json LONGTEXT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'active',
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    public TINYINT(1) NOT NULL DEFAULT 0,
    owner_citizenid VARCHAR(64) NULL,
    sale_enabled TINYINT(1) NOT NULL DEFAULT 0,
    sale_mode VARCHAR(20) NOT NULL DEFAULT 'none',
    sale_price BIGINT UNSIGNED NOT NULL DEFAULT 0,
    tax_enabled TINYINT(1) NOT NULL DEFAULT 0,
    tax_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
    tax_interval_days INT UNSIGNED NOT NULL DEFAULT 7,
    tax_grace_period_days INT UNSIGNED NOT NULL DEFAULT 3,
    tax_due_at DATETIME NULL,
    tax_grace_until DATETIME NULL,
    tax_status VARCHAR(20) NOT NULL DEFAULT 'disabled',
    tax_last_paid_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_houses_code (code),
    KEY idx_mz_houses_status (status),
    KEY idx_mz_houses_enabled (enabled),
    KEY idx_mz_houses_owner (owner_citizenid),
    KEY idx_mz_houses_category (category),
    KEY idx_mz_houses_owner_type (owner_type),
    KEY idx_mz_houses_parent_code (parent_code),
    KEY idx_mz_houses_unit_number (unit_number),
    KEY idx_mz_houses_org_code (org_code)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_house_keys (
    id INT AUTO_INCREMENT PRIMARY KEY,
    house_code VARCHAR(80) NOT NULL,
    citizenid VARCHAR(64) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'key',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_house_keys_house_citizenid (house_code, citizenid),
    KEY idx_mz_house_keys_house (house_code),
    KEY idx_mz_house_keys_citizenid (citizenid)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_house_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    house_code VARCHAR(80) NULL,
    action VARCHAR(80) NOT NULL,
    actor_citizenid VARCHAR(64) NULL,
    target_citizenid VARCHAR(64) NULL,
    meta_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_mz_house_logs_house (house_code),
    KEY idx_mz_house_logs_action (action),
    KEY idx_mz_house_logs_actor (actor_citizenid)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_house_transactions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_key VARCHAR(96) NOT NULL,
    house_code VARCHAR(80) NOT NULL,
    buyer_citizenid VARCHAR(64) NOT NULL,
    actor_citizenid VARCHAR(64) NULL,
    seller_type VARCHAR(30) NOT NULL DEFAULT 'server',
    amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
    payment_method VARCHAR(20) NOT NULL DEFAULT 'bank',
    mode VARCHAR(20) NOT NULL,
    transaction_type VARCHAR(30) NOT NULL DEFAULT 'purchase',
    status VARCHAR(30) NOT NULL DEFAULT 'initiated',
    meta_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    UNIQUE KEY uq_mz_house_transactions_key (transaction_key),
    KEY idx_mz_house_transactions_house (house_code, id),
    KEY idx_mz_house_transactions_buyer (buyer_citizenid, id),
    KEY idx_mz_house_transactions_status (status, updated_at)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_house_tax_payments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_key VARCHAR(96) NOT NULL,
    house_code VARCHAR(80) NOT NULL,
    owner_citizenid VARCHAR(64) NOT NULL,
    amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
    payment_method VARCHAR(20) NOT NULL DEFAULT 'bank',
    period_start DATETIME NULL,
    period_end DATETIME NULL,
    due_at DATETIME NOT NULL,
    paid_at DATETIME NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'initiated',
    transaction_reference VARCHAR(96) NOT NULL,
    metadata_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    UNIQUE KEY uq_mz_house_tax_payments_key (transaction_key),
    UNIQUE KEY uq_mz_house_tax_payments_reference (transaction_reference),
    KEY idx_mz_house_tax_payments_house (house_code, id),
    KEY idx_mz_house_tax_payments_owner (owner_citizenid, id),
    KEY idx_mz_house_tax_payments_status (status, updated_at),
    KEY idx_mz_house_tax_payments_due (due_at, id)
  )]]
}

local function queryAwait(statement, params)
  return MySQL.query.await(statement, params or {})
end

local function hasColumn(tableName, columnName)
  local row = MySQL.single.await([[
    SELECT COUNT(1) AS total
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = ?
      AND column_name = ?
  ]], { tableName, columnName })

  return row and tonumber(row.total) and tonumber(row.total) > 0
end

local function ensureColumn(tableName, columnName, definition)
  if hasColumn(tableName, columnName) then
    return
  end

  queryAwait(('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, definition))
end

local function ensureTaxPaymentReference()
  local row = MySQL.single.await([[
    SELECT is_nullable
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'mz_house_tax_payments'
      AND column_name = 'transaction_reference'
    LIMIT 1
  ]], {})
  if not row then return end
  queryAwait([[
    UPDATE mz_house_tax_payments
    SET transaction_reference = transaction_key
    WHERE transaction_reference IS NULL OR transaction_reference = ''
  ]])
  if tostring(row.is_nullable or row.IS_NULLABLE):upper() == 'YES' then
    queryAwait([[
      ALTER TABLE mz_house_tax_payments
      MODIFY COLUMN transaction_reference VARCHAR(96) NOT NULL
    ]])
  end
end

local function hasIndex(tableName, indexName)
  local row = MySQL.single.await([[
    SELECT COUNT(1) AS total
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = ?
      AND index_name = ?
  ]], { tableName, indexName })

  return row and tonumber(row.total) and tonumber(row.total) > 0
end

local function ensureIndex(tableName, indexName, definition)
  if hasIndex(tableName, indexName) then
    return
  end

  queryAwait(('ALTER TABLE `%s` ADD INDEX `%s` %s'):format(tableName, indexName, definition))
end

local function ensureUniqueIndex(tableName, indexName, definition)
  if hasIndex(tableName, indexName) then
    return
  end

  queryAwait(('ALTER TABLE `%s` ADD UNIQUE INDEX `%s` %s'):format(tableName, indexName, definition))
end

local function ensureHousePropertyColumns()
  ensureColumn('mz_houses', 'category', "`category` VARCHAR(40) NOT NULL DEFAULT 'residential'")
  ensureColumn('mz_houses', 'subtype', "`subtype` VARCHAR(40) NOT NULL DEFAULT 'house'")
  ensureColumn('mz_houses', 'owner_type', "`owner_type` VARCHAR(40) NOT NULL DEFAULT 'player'")
  ensureColumn('mz_houses', 'parent_code', '`parent_code` VARCHAR(80) NULL')
  ensureColumn('mz_houses', 'unit_number', '`unit_number` VARCHAR(30) NULL')
  ensureColumn('mz_houses', 'org_code', '`org_code` VARCHAR(80) NULL')
  ensureColumn('mz_houses', 'business_code', '`business_code` VARCHAR(80) NULL')
  ensureColumn('mz_houses', 'building_json', '`building_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'features_json', '`features_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'interior_json', '`interior_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'metadata_json', '`metadata_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'access_json', '`access_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'door_json', '`door_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'visibility', "`visibility` VARCHAR(30) NOT NULL DEFAULT 'auto'")
  ensureColumn('mz_houses', 'listing_json', '`listing_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'realestate_json', '`realestate_json` LONGTEXT NULL')
  ensureColumn('mz_houses', 'sale_enabled', '`sale_enabled` TINYINT(1) NOT NULL DEFAULT 0')
  ensureColumn('mz_houses', 'sale_mode', "`sale_mode` VARCHAR(20) NOT NULL DEFAULT 'none'")
  ensureColumn('mz_houses', 'sale_price', '`sale_price` BIGINT UNSIGNED NOT NULL DEFAULT 0')
  ensureColumn('mz_houses', 'tax_enabled', '`tax_enabled` TINYINT(1) NOT NULL DEFAULT 0')
  ensureColumn('mz_houses', 'tax_amount', '`tax_amount` BIGINT UNSIGNED NOT NULL DEFAULT 0')
  ensureColumn('mz_houses', 'tax_interval_days', '`tax_interval_days` INT UNSIGNED NOT NULL DEFAULT 7')
  ensureColumn('mz_houses', 'tax_grace_period_days', '`tax_grace_period_days` INT UNSIGNED NOT NULL DEFAULT 3')
  ensureColumn('mz_houses', 'tax_due_at', '`tax_due_at` DATETIME NULL')
  ensureColumn('mz_houses', 'tax_grace_until', '`tax_grace_until` DATETIME NULL')
  ensureColumn('mz_houses', 'tax_status', "`tax_status` VARCHAR(20) NOT NULL DEFAULT 'disabled'")
  ensureColumn('mz_houses', 'tax_last_paid_at', '`tax_last_paid_at` DATETIME NULL')

  ensureIndex('mz_houses', 'idx_mz_houses_category', '(`category`)')
  ensureIndex('mz_houses', 'idx_mz_houses_enabled', '(`enabled`)')
  ensureIndex('mz_houses', 'idx_mz_houses_owner_type', '(`owner_type`)')
  ensureIndex('mz_houses', 'idx_mz_houses_parent_code', '(`parent_code`)')
  ensureIndex('mz_houses', 'idx_mz_houses_unit_number', '(`unit_number`)')
  ensureIndex('mz_houses', 'idx_mz_houses_org_code', '(`org_code`)')
  ensureIndex('mz_houses', 'idx_mz_houses_sale', '(`sale_enabled`, `sale_mode`)')
  ensureIndex('mz_houses', 'idx_mz_houses_tax_due', '(`tax_enabled`, `tax_status`, `tax_due_at`)')
  ensureIndex('mz_houses', 'idx_mz_houses_tax_owner', '(`owner_citizenid`, `tax_enabled`)')
  ensureTaxPaymentReference()
  ensureUniqueIndex('mz_house_tax_payments', 'uq_mz_house_tax_payments_reference', '(`transaction_reference`)')
  ensureIndex('mz_house_tax_payments', 'idx_mz_house_tax_payments_due', '(`due_at`, `id`)')
end

function MZHousesPrepare.run()
  if not databaseEnabled() then
    debugLog('database disabled; skipping prepare')
    return true
  end

  local ready, readyErr = waitForMySQLReady()
  if not ready then
    print(('[mz_houses][prepare] failed: %s'):format(tostring(readyErr)))
    return false, readyErr
  end

  for _, statement in ipairs(statements) do
    queryAwait(statement)
  end

  ensureHousePropertyColumns()

  debugLog('tables ready')
  return true
end
