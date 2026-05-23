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
    type VARCHAR(30) NOT NULL DEFAULT 'shell',
    shell VARCHAR(80) NULL,
    entrance_json LONGTEXT NULL,
    garage_json LONGTEXT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'active',
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    public TINYINT(1) NOT NULL DEFAULT 0,
    owner_citizenid VARCHAR(64) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_houses_code (code),
    KEY idx_mz_houses_status (status),
    KEY idx_mz_houses_owner (owner_citizenid)
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
  )]]
}

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
    MySQL.query.await(statement)
  end

  debugLog('tables ready')
  return true
end
