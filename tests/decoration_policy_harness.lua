MZHousesDecorationPolicy = nil
dofile('mz_houses/server/decoration_policy.lua')

local function expect(condition, message)
  if not condition then error(message, 2) end
end

local function validInput()
  return {
    code = 'casa_01',
    propertyId = 10,
    property = {
      category = 'residential',
      subtype = 'house',
      ownerType = 'player',
      features = { furniture = true }
    },
    access = {
      enabled = true,
      status = 'active',
      owner = 'CID-OWNER',
      keys = { ['CID-KEY'] = true }
    },
    citizenid = 'CID-OWNER',
    session = {
      code = 'casa_01',
      confirmed = true,
      kind = 'interior',
      bucket = 5001,
      isGuest = false
    },
    currentBucket = 5001,
    shell = 'shell_test',
    boundsReady = true,
    bounds = { revision = 1 }
  }
end

local allowed, context = MZHousesDecorationPolicy.Evaluate(validInput())
expect(allowed == true and context.reason == 'property_owner', 'owner inside own residence must pass')

local outside = validInput()
outside.session.confirmed = false
local outsideAllowed, outsideReason = MZHousesDecorationPolicy.Evaluate(outside)
expect(outsideAllowed == false and outsideReason == 'invalid_decoration_session', 'owner outside must fail')

local keyholder = validInput()
keyholder.citizenid = 'CID-KEY'
local keyAllowed, keyReason = MZHousesDecorationPolicy.Evaluate(keyholder)
expect(keyAllowed == false and keyReason == 'property_owner_required', 'keyholder must not decorate')

local guest = validInput()
guest.session.isGuest = true
local guestAllowed, guestReason = MZHousesDecorationPolicy.Evaluate(guest)
expect(guestAllowed == false and guestReason == 'guest_decoration_denied', 'guest must not decorate')

local staff = validInput()
staff.citizenid = 'CID-STAFF'
staff.isAdmin = true
local staffAllowed, staffReason = MZHousesDecorationPolicy.Evaluate(staff)
expect(staffAllowed == false and staffReason == 'property_owner_required', 'Staff must not bypass ownership')

local organization = validInput()
organization.property.category = 'organization'
organization.property.ownerType = 'org'
local orgAllowed, orgReason = MZHousesDecorationPolicy.Evaluate(organization)
expect(orgAllowed == false and orgReason == 'residential_property_required', 'organization property must fail')

local public = validInput()
public.property.category = 'public'
local publicAllowed, publicReason = MZHousesDecorationPolicy.Evaluate(public)
expect(publicAllowed == false and publicReason == 'residential_property_required', 'public property must fail')

local disabled = validInput()
disabled.property.features.furniture = false
local disabledAllowed, disabledReason = MZHousesDecorationPolicy.Evaluate(disabled)
expect(disabledAllowed == false and disabledReason == 'furniture_disabled', 'feature-off house must fail')

local noBounds = validInput()
noBounds.boundsReady = false
noBounds.bounds = nil
local boundsAllowed, boundsReason = MZHousesDecorationPolicy.Evaluate(noBounds)
expect(boundsAllowed == false and boundsReason == 'furniture_bounds_required', 'shell without bounds must fail')

local wrongBucket = validInput()
wrongBucket.currentBucket = 9999
local bucketAllowed, bucketReason = MZHousesDecorationPolicy.Evaluate(wrongBucket)
expect(bucketAllowed == false and bucketReason == 'routing_bucket_mismatch', 'bucket change must invalidate context')

local building = validInput()
building.property.subtype = 'apartment_building'
local buildingAllowed, buildingReason = MZHousesDecorationPolicy.Evaluate(building)
expect(buildingAllowed == false and buildingReason == 'residential_subtype_required', 'building container must fail')

print('[mz_houses][test] decoration policy harness passed')

