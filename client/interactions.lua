local RegisteredInteractPoints = {}
local UsingMzInteract = false

local function getHouseEntrance(house)
  if not MZHouses or type(MZHouses.AsVector3) ~= 'function' then
    return nil
  end

  return MZHouses.AsVector3(house and house.entrance)
end

local function removeInteractPoints()
  if GetResourceState('mz_interact') ~= 'started' then
    RegisteredInteractPoints = {}
    return
  end

  for _, pointId in ipairs(RegisteredInteractPoints) do
    pcall(function()
      exports['mz_interact']:RemovePoint(pointId)
    end)
  end

  RegisteredInteractPoints = {}
end

local function registerMzInteractPoints()
  local interaction = MZHousesConfig.Interaction or {}
  if interaction.useMzInteract ~= true then
    return false
  end

  if GetResourceState('mz_interact') ~= 'started' then
    return false
  end

  removeInteractPoints()

  local added = 0
  for code, house in pairs(MZHousesConfig.Houses or {}) do
    if type(house) == 'table' and house.enabled ~= false then
      local coords = getHouseEntrance(house)
      if coords then
        local pointId = ('mz_houses:%s:entrance'):format(code)
        local ok, result = pcall(function()
          return exports['mz_interact']:AddPoint({
            id = pointId,
            coords = coords,
            drawDistance = tonumber(interaction.markerDistance) or 15.0,
            interactDistance = tonumber(interaction.distance) or 2.0,
            key = tonumber(interaction.key) or 38,
            text = {
              enabled = true,
              label = ('[E] Entrar - %s'):format(tostring(house.label or code))
            },
            marker = {
              enabled = true,
              type = 2,
              size = vector3(0.35, 0.35, 0.35),
              color = { r = 80, g = 180, b = 255, a = 180 },
              bobUpAndDown = false,
              rotate = true
            },
            event = {
              type = 'client',
              name = 'mz_houses:client:enterHouse',
              args = { code }
            }
          })
        end)

        if ok and result == true then
          RegisteredInteractPoints[#RegisteredInteractPoints + 1] = pointId
          added = added + 1
        elseif MZHouses and MZHouses.Debug then
          MZHouses.Debug('mz_interact_add_failed', {
            house = code,
            result = result
          })
        end
      end
    end
  end

  UsingMzInteract = added > 0
  return UsingMzInteract
end

local function drawText3d(coords, text, scale)
  local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
  if not onScreen then
    return
  end

  SetTextScale(scale or 0.32, scale or 0.32)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextColour(255, 255, 255, 230)
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(text)
  DrawText(x, y)

  local factor = string.len(text) / 370
  DrawRect(x, y + 0.0125, 0.018 + factor, 0.03, 0, 0, 0, 95)
end

local function drawHouseMarker(coords)
  local interaction = MZHousesConfig.Interaction or {}
  local marker = interaction.marker or {}
  if marker.enabled == false then
    return
  end

  local color = marker.color or {}
  local size = marker.size or vector3(0.35, 0.35, 0.35)
  local z = coords.z + (tonumber(marker.offsetZ) or 0.15)

  DrawMarker(
    tonumber(marker.type) or 2,
    coords.x, coords.y, z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    size.x, size.y, size.z,
    tonumber(color.r) or 80,
    tonumber(color.g) or 180,
    tonumber(color.b) or 255,
    tonumber(color.a) or 180,
    false,
    true,
    2,
    false,
    nil,
    nil,
    false
  )
end

local function runFallbackMarkerLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      local interaction = MZHousesConfig.Interaction or {}

      if interaction.fallbackMarkers == true and not UsingMzInteract and not (MZHouses and MZHouses.IsInsideHouse and MZHouses.IsInsideHouse()) then
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local markerDistance = tonumber(interaction.markerDistance) or 15.0
        local interactDistance = tonumber(interaction.distance) or 2.0
        local key = tonumber(interaction.key) or 38

        for code, house in pairs(MZHousesConfig.Houses or {}) do
          if type(house) == 'table' and house.enabled ~= false then
            local coords = getHouseEntrance(house)
            if coords then
              local distance = #(playerCoords - coords)
              if distance <= markerDistance then
                waitMs = 0
                drawHouseMarker(coords)

                if distance <= interactDistance then
                  local textConfig = interaction.text or {}
                  if textConfig.enabled ~= false then
                    drawText3d(
                      vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.45)),
                      ('[E] Entrar - %s'):format(tostring(house.label or code)),
                      tonumber(textConfig.scale) or 0.32
                    )
                  end

                  if IsControlJustReleased(0, key) then
                    TriggerEvent('mz_houses:client:enterHouse', code)
                    Wait(500)
                  end
                end
              end
            end
          end
        end
      end

      Wait(waitMs)
    end
  end)
end

CreateThread(function()
  Wait(700)
  local ok = registerMzInteractPoints()
  if ok then
    MZHouses.Debug('using_mz_interact', {
      points = #RegisteredInteractPoints
    })
  else
    MZHouses.Debug('using_fallback_markers')
  end

  runFallbackMarkerLoop()
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then
    return
  end

  removeInteractPoints()
end)
