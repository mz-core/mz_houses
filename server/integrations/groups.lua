MZHousesGroups = MZHousesGroups or {}

local GroupCache = {}
local GROUP_CACHE_SECONDS = 10

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function coreExport(name, ...)
  if GetResourceState('mz_core') ~= 'started' then
    return nil, 'core_unavailable'
  end

  local args = { ... }
  local ok, result = pcall(function()
    local core = exports['mz_core']
    return core[name](core, table.unpack(args))
  end)
  if not ok then return nil, 'group_provider_failed' end
  return result
end

local function validType(value)
  value = trim(value):lower()
  return (value == 'gang' or value == 'job') and value or nil
end

function MZHousesGroups.list(groupType)
  groupType = validType(groupType)
  if not groupType then return nil, 'invalid_group_type' end

  local rows, err = coreExport('ListOrgs', groupType)
  if type(rows) ~= 'table' then return nil, err or 'group_provider_failed' end

  local out = {}
  for _, row in ipairs(rows) do
    local code = trim(row.code)
    local rowType = validType(row.type or row.typeCode)
    if code ~= '' and rowType == groupType and row.active ~= false then
      local item = {
        code = code,
        label = trim(row.name) ~= '' and trim(row.name) or code,
        type = rowType
      }
      out[#out + 1] = item
      GroupCache[('%s:%s'):format(rowType, code)] = { value = item, expiresAt = os.time() + GROUP_CACHE_SECONDS }
    end
  end
  table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
  return out
end

function MZHousesGroups.get(groupType, code)
  groupType = validType(groupType)
  code = trim(code)
  if not groupType or code == '' then return nil, 'invalid_group' end

  local cacheKey = ('%s:%s'):format(groupType, code)
  local cached = GroupCache[cacheKey]
  if cached and cached.expiresAt > os.time() then
    return cached.value or nil, cached.value and nil or 'group_not_found'
  end

  local row, err = coreExport('GetOrgByCode', code)
  if type(row) ~= 'table' then
    if err == nil or err == 'group_not_found' then
      GroupCache[cacheKey] = { value = false, expiresAt = os.time() + GROUP_CACHE_SECONDS }
    end
    return nil, err or 'group_not_found'
  end
  if validType(row.type or row.typeCode) ~= groupType or row.active == false then
    GroupCache[cacheKey] = { value = false, expiresAt = os.time() + GROUP_CACHE_SECONDS }
    return nil, 'group_not_found'
  end
  local item = { code = code, label = trim(row.name) ~= '' and trim(row.name) or code, type = groupType }
  GroupCache[cacheKey] = { value = item, expiresAt = os.time() + GROUP_CACHE_SECONDS }
  return item
end

function MZHousesGroups.memberships(source)
  local rows, err = coreExport('GetPlayerOrgs', source)
  if type(rows) ~= 'table' then return nil, err or 'group_provider_failed' end

  local out = {}
  for _, row in ipairs(rows) do
    local groupType = validType(row.type or row.typeCode)
    local code = trim(row.code or row.orgCode or row.org_code)
    if groupType and code ~= '' then
      local grade = type(row.grade) == 'table' and tonumber(row.grade.level) or tonumber(row.grade)
      out[#out + 1] = {
        type = groupType,
        code = code,
        grade = grade or tonumber(row.gradeLevel) or 0,
        duty = row.duty == true
      }
    end
  end
  return out
end
