local RegisteredInteractPoints = {}
local UsingMzInteract = false

local function getHouseEntrance(house)
  if not MZHouses or type(MZHouses.AsVector3) ~= 'function' then
    return nil
  end

  return MZHouses.AsVector3(house and house.entrance)
end

local function visibilityEnabled()
  return (MZHousesConfig.Visibility or {}).enabled == true
end

local function getHouseCode(key, house)
  if type(key) == 'number' then
    return tostring(house and house.code or '')
  end

  return tostring(key or '')
end

local function shouldShowEntry(house)
  if visibilityEnabled() then
    return type(house) == 'table' and house.entryVisible == true
  end

  return true
end

local function getListingCoords(house)
  local listing = type(house) == 'table' and type(house.listing) == 'table' and house.listing or nil
  local sign = listing and type(listing.sign) == 'table' and listing.sign or nil

  if sign and sign.enabled == true then
    local coords = MZHouses.AsVector3(sign.coords)
    if coords then
      return coords
    end
  end

  return getHouseEntrance(house)
end

local function shouldShowListing(house)
  -- Listing e apenas metadata nesta fase. Placa/marker fica para mz_realestate.
  return false
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
    UsingMzInteract = false
    return false
  end

  if GetResourceState('mz_interact') ~= 'started' then
    UsingMzInteract = false
    return false
  end

  removeInteractPoints()

  local added = 0
  local houses = MZHouses.GetVisibleHouses and MZHouses.GetVisibleHouses(true) or (MZHousesConfig.Houses or {})
  for key, house in pairs(houses or {}) do
    local code = getHouseCode(key, house)
    if code ~= '' and type(house) == 'table' and house.enabled ~= false then
      local coords = getHouseEntrance(house)
      if coords and shouldShowEntry(house) then
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
              label = ('[E] %s - %s'):format(
                tostring(house.subtype) == 'apartment_building' and 'Interfone' or 'Entrar',
                tostring(house.label or code)
              )
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

      if shouldShowListing(house) then
        local listingCoords = getListingCoords(house)
        local listing = house.listing or {}
        if listingCoords then
          local pointId = ('mz_houses:%s:listing'):format(code)
          local ok, result = pcall(function()
            return exports['mz_interact']:AddPoint({
              id = pointId,
              coords = listingCoords,
              drawDistance = tonumber(interaction.markerDistance) or 15.0,
              interactDistance = tonumber(interaction.distance) or 2.0,
              key = tonumber(interaction.key) or 38,
              text = {
                enabled = true,
                label = ('[E] %s'):format(tostring(listing.label or 'Imovel a venda'))
              },
              marker = {
                enabled = true,
                type = 2,
                size = vector3(0.35, 0.35, 0.35),
                color = { r = 255, g = 210, b = 80, a = 180 },
                bobUpAndDown = false,
                rotate = true
              },
              event = {
                type = 'client',
                name = 'mz_houses:client:listingInfo',
                args = { code }
              }
            })
          end)

          if ok and result == true then
            RegisteredInteractPoints[#RegisteredInteractPoints + 1] = pointId
            added = added + 1
          elseif MZHouses and MZHouses.Debug then
            MZHouses.Debug('mz_interact_listing_add_failed', {
              house = code,
              result = result
            })
          end
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

        local houses = MZHouses.GetVisibleHouses and MZHouses.GetVisibleHouses(false) or (MZHousesConfig.Houses or {})
        for houseKey, house in pairs(houses or {}) do
          local code = getHouseCode(houseKey, house)
          if code ~= '' and type(house) == 'table' and house.enabled ~= false then
            local coords = getHouseEntrance(house)
            if coords and shouldShowEntry(house) then
              local distance = #(playerCoords - coords)
              if distance <= markerDistance then
                waitMs = 0
                drawHouseMarker(coords)

                if distance <= interactDistance then
                  local textConfig = interaction.text or {}
                  if textConfig.enabled ~= false then
                    drawText3d(
                      vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.45)),
                      tostring(house.subtype) == 'apartment_building'
                        and ('[E] Interfone - %s'):format(tostring(house.label or code))
                        or ('[E] Entrar - %s'):format(tostring(house.label or code)),
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

            if shouldShowListing(house) then
              local listingCoords = getListingCoords(house)
              local listing = house.listing or {}
              if listingCoords then
                local distance = #(playerCoords - listingCoords)
                if distance <= markerDistance then
                  waitMs = 0
                  drawHouseMarker(listingCoords)

                  if distance <= interactDistance then
                    local textConfig = interaction.text or {}
                    if textConfig.enabled ~= false then
                      drawText3d(
                        vector3(listingCoords.x, listingCoords.y, listingCoords.z + (tonumber(textConfig.offsetZ) or 0.45)),
                        ('[E] %s'):format(tostring(listing.label or 'Imovel a venda')),
                        tonumber(textConfig.scale) or 0.32
                      )
                    end

                    if IsControlJustReleased(0, key) then
                      TriggerEvent('mz_houses:client:listingInfo', code)
                      Wait(500)
                    end
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

RegisterNetEvent('mz_houses:client:visibilityUpdated', function(reason)
  Wait(50)
  local ok = registerMzInteractPoints()
  MZHouses.Debug('visibility_points_refreshed', {
    reason = reason,
    usingMzInteract = ok == true,
    points = #RegisteredInteractPoints
  })
end)

CreateThread(function()
  Wait(700)
  if MZHouses and MZHouses.RefreshVisibleHouses then
    MZHouses.RefreshVisibleHouses(true)
  end
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
