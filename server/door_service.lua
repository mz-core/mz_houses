MZHousesDoorService = MZHousesDoorService or {}

local function keyData(access, citizenid)
  local key = type(access) == 'table' and type(access.keys) == 'table' and access.keys[citizenid] or nil
  if key == true then return { role = 'access', canEnter = true, canControlDoor = false } end
  return type(key) == 'table' and key or nil
end

function MZHousesDoorService.resolve(house)
  if type(house) == 'table' and type(house.door) == 'table' then return house.door, 'persisted' end
  local property = MZHousesRepository.normalizePropertyFields(house)
  local policy = type(house) == 'table' and house.accessPolicy or nil
  local state = 'locked'
  if property.subtype == 'apartment_building' or (policy and policy.mode == 'public') then state = 'unlocked' end
  if policy and policy.mode == 'admin' then state = 'blocked' end
  return MZHousesRepository.normalizeDoor({ state = state, defaultState = state }), 'fallback'
end

function MZHousesDoorService.canEnter(source, house, access, isAdmin)
  local door = MZHousesDoorService.resolve(house)
  if isAdmin == true then return true, { reason = 'admin', doorState = door.state, isGuest = false } end
  if door.state == 'blocked' then return false, 'door_blocked' end
  if door.state == 'unlocked' then return true, { reason = 'public_unlocked', doorState = door.state, isGuest = true } end

  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then return false, citizenErr or 'player_not_loaded' end
  if access.owner == citizenid then return true, { reason = 'owner', citizenid = citizenid, doorState = door.state } end
  local key = keyData(access, citizenid)
  if key and key.canEnter ~= false then
    return true, { reason = key.role == 'control' and 'key_control' or 'key_access', citizenid = citizenid, doorState = door.state }
  end
  local allowed, result = MZHousesAccessPolicy.evaluate(source, house, access, false)
  if allowed then
    result.doorState = door.state
    return true, result
  end
  return false, result or 'door_locked'
end

function MZHousesDoorService.canControl(source, house, access, isAdmin)
  if isAdmin == true then return true, { reason = 'admin' } end
  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then return false, citizenErr or 'player_not_loaded' end
  if access.owner == citizenid then return true, { reason = 'owner' } end
  local key = keyData(access, citizenid)
  if key and key.role == 'control' then return true, { reason = 'key_control' } end

  local policy = type(house) == 'table' and house.accessPolicy or nil
  if not policy or policy.mode ~= 'rules' then return false, 'door_control_denied' end
  local memberships, membershipErr = MZHousesGroups.memberships(source)
  if not memberships then return false, membershipErr or 'group_provider_failed' end
  for _, rule in ipairs(policy.rules or {}) do
    local required = tonumber(rule.canControlDoorFromGrade)
    if required then
      for _, membership in ipairs(memberships) do
        if membership.type == rule.type and membership.code == rule.name
          and membership.grade >= (tonumber(rule.minimumGrade) or 0) and membership.grade >= required
          and not (rule.type == 'job' and rule.requireDuty == true and membership.duty ~= true) then
          local active = MZHousesGroups.get(rule.type, rule.name)
          if active then return true, { reason = rule.type == 'gang' and 'gang_rule' or 'job_rule' } end
        end
      end
    end
  end
  return false, 'door_control_denied'
end

function MZHousesDoorService.canUseInheritedAccess(source, house, access, isAdmin)
  if isAdmin == true then return true, { reason = 'admin' } end
  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then return false, citizenErr or 'player_not_loaded' end
  if access.owner == citizenid then return true, { reason = 'owner' } end
  local key = keyData(access, citizenid)
  if key and key.canEnter ~= false then return true, { reason = key.role == 'control' and 'key_control' or 'key_access' } end
  return MZHousesAccessPolicy.evaluate(source, house, access, false)
end
