local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local function expect(condition, message)
  if not condition then error(message, 2) end
end

local service = read('mz_houses/server/service.lua')
local repository = read('mz_houses/server/repository.lua')
local apartments = read('mz_houses/server/apartments.lua')
local config = read('mz_houses/shared/config.lua')

local defaultsStart = assert(service:find('local function defaultAdminFeatures()', 1, true))
local defaultsEnd = assert(service:find('\nend', defaultsStart, true))
local defaults = service:sub(defaultsStart, defaultsEnd)
expect(defaults:find('furniture = true', 1, true),
  'new residential houses must enable owner-only furniture by default')
expect(service:find('garage = building.sharedGarage == true, furniture = true', 1, true)
  and service:find('garage = garageEnabled, furniture = true', 1, true),
  'new apartment units must enable furniture by default')
expect(repository:find('garage = data.sharedGarage == true,\n    furniture = true', 1, true),
  'normalized apartment defaults disable furniture')
expect(apartments:find('garage = false, furniture = true', 1, true),
  'apartment template fallback disables furniture')
expect(config:find("MZHousesConfig.PropertyDefaults", 1, true)
  and config:find('furniture = true', 1, true),
  'residential configuration defaults disable furniture')

print('[mz_houses][test] residential creation defaults harness passed')
