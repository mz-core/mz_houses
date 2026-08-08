local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local function expect(condition, message)
  if not condition then error(message, 2) end
end

local config = read('mz_houses/shared/config.lua')
local repository = read('mz_houses/server/repository.lua')
local accessPolicy = read('mz_houses/server/access_policy.lua')
local service = read('mz_houses/server/service.lua')
local main = read('mz_houses/server/main.lua')

expect(config:find('activities = false', 1, true), 'activities must default to disabled')
expect(repository:find("'stash', 'wardrobe', 'garage', 'furniture', 'activities'", 1, true),
  'repository must persist the activities feature')
expect(accessPolicy:find('activities = true', 1, true), 'access policy must know activities')
expect(accessPolicy:find('activities_organization_only', 1, true),
  'activities policy must reject player/public modes')
expect(service:find("featureName ~= 'activities'", 1, true),
  'feature authority must accept activities')
expect(service:find('function MZHousesService.getIntegrationPropertyContext', 1, true),
  'minimal integration context is missing')
expect(main:find("exports('GetConfirmedInteriorSession'", 1, true),
  'confirmed interior session export is missing')
expect(main:find('confirmedInteriorFeatureSession(source, houseCode)', 1, true),
  'integration export must reuse authoritative session validation')

print('[mz_houses][test] activities feature contract harness passed')
