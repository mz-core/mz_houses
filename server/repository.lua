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

local function rowToHouse(row)
  if type(row) ~= 'table' then return nil end

  row.entrance = decodeJson(row.entrance_json, nil)
  row.garage = decodeJson(row.garage_json, nil)
  row.enabled = databaseBool(row.enabled)
  row.public = databaseBool(row.public)
  return row
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

  if not existing then
    MySQL.insert.await([[
      INSERT INTO mz_houses (
        code, label, type, shell, entrance_json, garage_json, status, enabled, public, owner_citizenid
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      code,
      label,
      houseType,
      shell,
      entranceJson,
      garageJson,
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

  MySQL.update.await([[
    UPDATE mz_houses
    SET label = ?, type = ?, shell = ?, entrance_json = ?, garage_json = ?, status = ?, enabled = ?, public = ?
    WHERE code = ?
  ]], {
    label,
    houseType,
    shell,
    entranceJson,
    garageJson,
    status,
    enabled,
    nextPublic,
    code
  })

  return true, 'updated'
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
