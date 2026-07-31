MZHousesDecorationPolicy = MZHousesDecorationPolicy or {}

local RESIDENTIAL_SUBTYPES = {
  house = true,
  apartment = true,
  apartment_unit = true
}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function MZHousesDecorationPolicy.Evaluate(input)
  input = type(input) == 'table' and input or {}
  local session = type(input.session) == 'table' and input.session or {}
  local property = type(input.property) == 'table' and input.property or {}
  local access = type(input.access) == 'table' and input.access or {}
  local code = trim(input.code)

  if code == '' or session.confirmed ~= true or trim(session.code) ~= code then
    return false, 'invalid_decoration_session'
  end
  if trim(session.kind):lower() ~= 'interior' then return false, 'not_inside_property' end
  if session.isGuest == true then return false, 'guest_decoration_denied' end

  local expectedBucket = tonumber(session.bucket)
  local currentBucket = tonumber(input.currentBucket)
  if not expectedBucket or expectedBucket <= 0 or not currentBucket or currentBucket ~= expectedBucket then
    return false, 'routing_bucket_mismatch'
  end

  if access.enabled ~= true or trim(access.status):lower() ~= 'active' then
    return false, 'house_disabled'
  end
  if trim(property.category):lower() ~= 'residential' then
    return false, 'residential_property_required'
  end
  if trim(property.ownerType or property.owner_type):lower() ~= 'player' then
    return false, 'player_owned_property_required'
  end
  if not RESIDENTIAL_SUBTYPES[trim(property.subtype):lower()] then
    return false, 'residential_subtype_required'
  end
  if type(property.features) ~= 'table' or property.features.furniture ~= true then
    return false, 'furniture_disabled'
  end

  local citizenid = trim(input.citizenid)
  local owner = trim(access.owner)
  if citizenid == '' then return false, 'player_not_loaded' end
  if owner == '' then return false, 'property_without_owner' end
  if owner ~= citizenid then return false, 'property_owner_required' end

  if input.boundsReady ~= true or type(input.bounds) ~= 'table' then
    return false, input.boundsError or 'furniture_bounds_required'
  end

  return true, {
    reason = 'property_owner',
    houseCode = code,
    propertyId = tonumber(input.propertyId),
    citizenid = citizenid,
    bucket = expectedBucket,
    shell = trim(input.shell),
    boundsRevision = tonumber(input.bounds.revision) or 1
  }
end

