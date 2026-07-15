MZHousesAccessPolicy = MZHousesAccessPolicy or {}

local FEATURE_NAMES = { stash = true, wardrobe = true, garage = true }

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function persistedPolicy(house)
  return type(house) == 'table' and type(house.accessPolicy) == 'table' and house.accessPolicy or nil
end

local function validateRules(rules, allowDoorControl)
  rules = type(rules) == 'table' and rules or {}
  if #rules > 16 then return false, 'too_many_access_rules' end
  for _, rule in ipairs(rules) do
    if type(rule) ~= 'table' then return false, 'invalid_access_rule' end
    local ruleType = trim(rule.type):lower()
    local name = trim(rule.name)
    local grade = tonumber(rule.minimumGrade)
    if (ruleType ~= 'gang' and ruleType ~= 'job') or name == '' then return false, 'invalid_access_rule' end
    if not grade or grade ~= math.floor(grade) or grade < 0 or grade > 1000 then return false, 'invalid_minimum_grade' end
    if rule.requireDuty ~= nil and type(rule.requireDuty) ~= 'boolean' then return false, 'invalid_require_duty' end
    if ruleType ~= 'job' and rule.requireDuty == true then return false, 'duty_only_supported_for_job' end
    if allowDoorControl == true and rule.canControlDoorFromGrade ~= nil then
      local controlGrade = tonumber(rule.canControlDoorFromGrade)
      if not controlGrade or controlGrade ~= math.floor(controlGrade) or controlGrade < 0 or controlGrade > 1000 then
        return false, 'invalid_control_grade'
      end
    end
    local group, groupErr = MZHousesGroups.get(ruleType, name)
    if not group then return false, groupErr or 'group_not_found' end
  end
  return true
end

local function evaluateRules(source, rules)
  local memberships, membershipErr = MZHousesGroups.memberships(source)
  if not memberships then return false, membershipErr or 'group_provider_failed' end
  local denial = 'group_not_found'
  for _, rule in ipairs(rules or {}) do
    for _, membership in ipairs(memberships) do
      if membership.type == rule.type and membership.code == rule.name then
        if membership.grade < (tonumber(rule.minimumGrade) or 0) then
          denial = denial == 'group_not_found' and 'grade_denied' or denial
        elseif rule.type == 'job' and rule.requireDuty == true and membership.duty ~= true then
          denial = denial == 'group_not_found' and 'duty_required' or denial
        else
          local activeGroup, groupErr = MZHousesGroups.get(rule.type, rule.name)
          if not activeGroup then return false, groupErr or 'group_not_found' end
          return true, {
            reason = rule.type == 'gang' and 'gang_rule' or 'job_rule',
            group = rule.name,
            grade = membership.grade
          }
        end
      end
    end
  end
  return false, denial
end

function MZHousesAccessPolicy.resolve(house)
  local policy = persistedPolicy(house)
  if policy then return policy, 'persisted' end
  local property = MZHousesRepository.normalizePropertyFields(house)
  if property.subtype == 'apartment_building' then
    return MZHousesRepository.normalizeAccessPolicy({ mode = 'public', match = 'any', rules = {} }), 'fallback_public'
  end
  if property.category == 'residential' and property.ownerType == 'player'
    and (property.subtype == 'house' or property.subtype == 'apartment_unit' or property.subtype == 'apartment') then
    return MZHousesRepository.normalizeAccessPolicy({ mode = 'owner', match = 'any', rules = {} }), 'fallback_owner'
  end
  return nil, 'legacy_property_type_retired'
end

function MZHousesAccessPolicy.validateFeaturePolicy(featureName, raw)
  featureName = trim(featureName):lower()
  if not FEATURE_NAMES[featureName] or type(raw) ~= 'table' then return false, 'invalid_feature_policy' end
  local mode = trim(raw.mode):lower()
  if mode == 'none' then mode = 'admin' end
  local allowed = { inherit = true, disabled = true, owner = true, keys = true, rules = true, public = true, admin = true }
  if not allowed[mode] then return false, 'invalid_feature_mode' end
  if raw.match ~= nil and trim(raw.match):lower() ~= 'any' then return false, 'invalid_access_match' end
  local rules = type(raw.rules) == 'table' and raw.rules or {}
  if mode == 'rules' and #rules == 0 then return false, 'feature_rule_required' end
  if mode ~= 'rules' and #rules > 0 then return false, 'rules_not_allowed_for_mode' end
  local rulesOk, rulesErr = validateRules(rules, false)
  if not rulesOk then return false, rulesErr end
  return true, MZHousesRepository.normalizeFeaturePolicy({ mode = mode, match = 'any', rules = rules })
end

function MZHousesAccessPolicy.validate(raw)
  if type(raw) ~= 'table' then return false, 'invalid_access_policy' end
  local mode = trim(raw.mode):lower()
  if mode ~= 'owner' and mode ~= 'rules' and mode ~= 'public' and mode ~= 'admin' and mode ~= 'none' then
    return false, 'invalid_access_mode'
  end
  if raw.match ~= nil and trim(raw.match):lower() ~= 'any' then return false, 'invalid_access_match' end
  local rules = type(raw.rules) == 'table' and raw.rules or {}
  if mode == 'rules' and #rules == 0 then return false, 'access_rule_required' end
  if mode ~= 'rules' and #rules > 0 then return false, 'rules_not_allowed_for_mode' end
  local rulesOk, rulesErr = validateRules(rules, true)
  if not rulesOk then return false, rulesErr end
  for featureName in pairs(FEATURE_NAMES) do
    local featureRaw = type(raw.features) == 'table' and raw.features[featureName] or { mode = 'inherit' }
    local featureOk, featureErr = MZHousesAccessPolicy.validateFeaturePolicy(featureName, featureRaw)
    if not featureOk then return false, featureErr end
  end
  local normalized = MZHousesRepository.normalizeAccessPolicy(raw)
  if not normalized then return false, 'invalid_access_policy' end
  return true, normalized
end

function MZHousesAccessPolicy.evaluate(source, house, runtimeAccess, isAdmin)
  runtimeAccess = type(runtimeAccess) == 'table' and runtimeAccess or {}
  local policy, policySource = MZHousesAccessPolicy.resolve(house)
  if isAdmin == true then return true, { reason = 'admin', policySource = policySource } end
  if not policy then return false, policySource or 'no_access_rule' end
  if policy.mode == 'admin' or policy.mode == 'none' then return false, 'no_access_rule' end
  if policy.mode == 'public' then return true, { reason = 'public', policySource = policySource } end
  if policy.mode == 'owner' then
    local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
    if not citizenid then return false, citizenErr or 'player_not_loaded' end
    if runtimeAccess.owner == citizenid then return true, { reason = 'owner', citizenid = citizenid, policySource = policySource } end
    local key = type(runtimeAccess.keys) == 'table' and runtimeAccess.keys[citizenid] or nil
    if key == true or (type(key) == 'table' and key.canEnter ~= false) then
      return true, { reason = type(key) == 'table' and key.role == 'control' and 'key_control' or 'key_access', citizenid = citizenid, policySource = policySource }
    end
    return false, 'no_house_access'
  end
  local allowed, result = evaluateRules(source, policy.rules)
  if allowed and type(result) == 'table' then result.policySource = policySource end
  return allowed, result
end

function MZHousesAccessPolicy.evaluateFeature(source, house, runtimeAccess, featureName, isAdmin, isGuest)
  featureName = trim(featureName):lower()
  if not FEATURE_NAMES[featureName] then return false, 'invalid_feature' end
  runtimeAccess = type(runtimeAccess) == 'table' and runtimeAccess or {}
  local policy, policySource = MZHousesAccessPolicy.resolve(house)
  if not policy then return false, policySource or 'no_access_rule' end
  local feature = type(policy.features) == 'table' and policy.features[featureName] or { mode = 'inherit' }
  feature = MZHousesRepository.normalizeFeaturePolicy(feature)
  if feature.mode == 'disabled' then return false, 'feature_disabled' end
  if feature.mode == 'public' then return true, { reason = 'feature_public', feature = featureName, policySource = policySource } end
  if isGuest == true then return false, 'guest_resource_denied' end
  if isAdmin == true then return true, { reason = 'admin', feature = featureName, policySource = policySource } end
  if feature.mode == 'admin' then return false, 'feature_admin_required' end
  if feature.mode == 'inherit' then return MZHousesAccessPolicy.evaluate(source, house, runtimeAccess, false) end

  local citizenid, citizenErr = MZHousesService.getPlayerCitizenId(source)
  if not citizenid then return false, citizenErr or 'player_not_loaded' end
  if feature.mode == 'owner' then
    return runtimeAccess.owner == citizenid,
      runtimeAccess.owner == citizenid and { reason = 'feature_owner', feature = featureName } or 'feature_owner_required'
  end
  if feature.mode == 'keys' then
    if runtimeAccess.owner == citizenid then return true, { reason = 'feature_owner', feature = featureName } end
    local key = type(runtimeAccess.keys) == 'table' and runtimeAccess.keys[citizenid] or nil
    if key == true or type(key) == 'table' then return true, { reason = 'feature_key', feature = featureName } end
    return false, 'feature_key_required'
  end
  local allowed, result = evaluateRules(source, feature.rules)
  if allowed and type(result) == 'table' then result.feature = featureName end
  return allowed, result
end
