local RegisteredInteractPoints = {}
local RegisteredInteractLabels = {}
local UsingMzInteract = false

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function getHouseEntrance(house)
  if not MZHouses or type(MZHouses.AsVector3) ~= 'function' then return nil end
  return MZHouses.AsVector3(house and house.entrance)
end

local function visibilityEnabled()
  return (MZHousesConfig.Visibility or {}).enabled == true
end

local function getHouseCode(key, house)
  if type(key) == 'number' then return tostring(house and house.code or '') end
  return tostring(key or '')
end

local function shouldShowEntry(house)
  if visibilityEnabled() then return type(house) == 'table' and house.entryVisible == true end
  return true
end

local function pointCount()
  local count = 0
  for _ in pairs(RegisteredInteractPoints) do count = count + 1 end
  return count
end

local function removeInteractPoint(code)
  local pointId = RegisteredInteractPoints[trim(code)]
  if not pointId then return end
  if GetResourceState('mz_interact') == 'started' then
    pcall(function() exports['mz_interact']:RemovePoint(pointId) end)
  end
  RegisteredInteractPoints[trim(code)] = nil
  RegisteredInteractLabels[trim(code)] = nil
end

local function removeInteractPoints()
  if GetResourceState('mz_interact') == 'started' then
    for _, pointId in pairs(RegisteredInteractPoints) do
      pcall(function() exports['mz_interact']:RemovePoint(pointId) end)
    end
  end
  RegisteredInteractPoints = {}
  RegisteredInteractLabels = {}
end

local function canShowDoorAction(code, house)
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return false end
  local coords = getHouseEntrance(house)
  if not coords then return false end
  local distance = #(GetEntityCoords(ped) - coords)
  if distance > (tonumber((MZHousesConfig.Interaction or {}).distance) or 2.0) then return false end
  local presentation = MZHouses.GetDoorPresentation(code, house)
  return presentation.canControl == true and (presentation.state == 'locked' or presentation.state == 'unlocked')
end

local function formatCurrency(value)
  local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local updated, count = text:gsub('^(%-?%d+)(%d%d%d)', '%1.%2')
    text = updated
    if count == 0 then break end
  end
  return ('R$ %s'):format(text)
end

local function doorText(code, house, showDoorAction)
  local presentation = MZHouses.GetDoorPresentation(code, house)
  local action = showDoorAction == true and presentation.actionLabel or nil
  local base
  if tostring(house.subtype) == 'apartment_building' then
    base = '[E] Interfone'
  elseif house.saleEnabled == true and tostring(house.saleMode) == 'direct' then
    base = ('[E] Comprar | %s'):format(formatCurrency(house.salePrice))
  elseif house.saleEnabled == true and tostring(house.saleMode) == 'admin' then
    base = ('À venda | %s'):format(formatCurrency(house.salePrice))
  else
    base = '[E] Entrar'
  end
  local text = ('%s | Porta: %s'):format(base, presentation.stateLabel)
  if action then
    text = ('%s | [%s] %s'):format(
      text,
      tostring((MZHousesConfig.Interaction or {}).doorKeyLabel or 'G'),
      action
    )
  end
  return text
end

local function addMzInteractPoint(code, house)
  local interaction = MZHousesConfig.Interaction or {}
  if interaction.useMzInteract ~= true or GetResourceState('mz_interact') ~= 'started' then return false end
  if code == '' or type(house) ~= 'table' or house.enabled == false or not shouldShowEntry(house) then
    removeInteractPoint(code)
    return false
  end
  local coords = getHouseEntrance(house)
  if not coords then removeInteractPoint(code) return false end

  local pointId = ('mz_houses:%s:entrance'):format(code)
  local label = doorText(code, house, canShowDoorAction(code, house))
  if RegisteredInteractPoints[code] == pointId and RegisteredInteractLabels[code] == label then return true end
  local ok, result = pcall(function()
    return exports['mz_interact']:AddPoint({
      id = pointId,
      coords = coords,
      drawDistance = tonumber(interaction.markerDistance) or 15.0,
      interactDistance = tonumber(interaction.distance) or 2.0,
      key = tonumber(interaction.enterKey or interaction.key) or 38,
      text = { enabled = true, label = label },
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
    RegisteredInteractPoints[code] = pointId
    RegisteredInteractLabels[code] = label
    return true
  end
  MZHouses.Debug('mz_interact_add_failed', { house = code, result = result })
  return false
end

local function registerMzInteractPoints()
  local interaction = MZHousesConfig.Interaction or {}
  if interaction.useMzInteract ~= true or GetResourceState('mz_interact') ~= 'started' then
    UsingMzInteract = false
    return false
  end
  removeInteractPoints()
  local houses = MZHouses.GetVisibleHouses and MZHouses.GetVisibleHouses(true) or (MZHousesConfig.Houses or {})
  for key, house in pairs(houses or {}) do
    addMzInteractPoint(getHouseCode(key, house), house)
  end
  UsingMzInteract = pointCount() > 0
  return UsingMzInteract
end

local function drawText3d(coords, text, scale)
  local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
  if not onScreen then return end
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
  local marker = (MZHousesConfig.Interaction or {}).marker or {}
  if marker.enabled == false then return end
  local color = marker.color or {}
  local size = marker.size or vector3(0.35, 0.35, 0.35)
  DrawMarker(
    tonumber(marker.type) or 2,
    coords.x, coords.y, coords.z + (tonumber(marker.offsetZ) or 0.15),
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    size.x, size.y, size.z,
    tonumber(color.r) or 80, tonumber(color.g) or 180, tonumber(color.b) or 255, tonumber(color.a) or 180,
    false, true, 2, false, nil, nil, false
  )
end

local function runFallbackMarkerLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      local interaction = MZHousesConfig.Interaction or {}
      if interaction.fallbackMarkers == true and not UsingMzInteract
        and not (MZHouses and MZHouses.IsInsideHouse and MZHouses.IsInsideHouse()) then
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local markerDistance = tonumber(interaction.markerDistance) or 15.0
        local interactDistance = tonumber(interaction.distance) or 2.0
        local enterKey = tonumber(interaction.enterKey or interaction.key) or 38
        local houses = MZHouses.GetVisibleHouses and MZHouses.GetVisibleHouses(false) or (MZHousesConfig.Houses or {})
        for houseKey, house in pairs(houses or {}) do
          local code = getHouseCode(houseKey, house)
          local coords = getHouseEntrance(house)
          if code ~= '' and type(house) == 'table' and house.enabled ~= false and coords and shouldShowEntry(house) then
            local distance = #(playerCoords - coords)
            if distance <= markerDistance then
              waitMs = 0
              drawHouseMarker(coords)
              if distance <= interactDistance then
                local onFoot = not IsPedInAnyVehicle(ped, false)
                if onFoot then MZHouses.GetDoorContext(code, false) end
                local canUseDoorKey = onFoot and canShowDoorAction(code, house)
                local textConfig = interaction.text or {}
                if textConfig.enabled ~= false then
                  drawText3d(
                    vector3(coords.x, coords.y, coords.z + (tonumber(textConfig.offsetZ) or 0.45)),
                    doorText(code, house, canUseDoorKey),
                    tonumber(textConfig.scale) or 0.32
                  )
                end
                if canUseDoorKey then
                  local doorKey = tonumber(interaction.doorKey) or 47
                  DisableControlAction(0, doorKey, true)
                  if IsDisabledControlJustReleased(0, doorKey) then MZHouses.ToggleDoor(code) end
                end
                if IsControlJustReleased(0, enterKey) then
                  TriggerEvent('mz_houses:client:enterHouse', code)
                  Wait(500)
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

local function runMzInteractDoorContextLoop()
  CreateThread(function()
    while true do
      local waitMs = 1000
      if UsingMzInteract and not MZHouses.IsInsideHouse() then
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local maxDistance = tonumber((MZHousesConfig.Interaction or {}).distance) or 2.0
        local closestCode, closestDistance
        for key, house in pairs(MZHouses.GetVisibleHouses(false) or {}) do
          local code = getHouseCode(key, house)
          local coords = getHouseEntrance(house)
          if code ~= '' and coords and shouldShowEntry(house) then
            local distance = #(playerCoords - coords)
            if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
              closestCode, closestDistance = code, distance
            end
          end
        end
        if closestCode then
          local house = MZHouses.GetVisibleHouseByCode(closestCode)
          local onFoot = not IsPedInAnyVehicle(ped, false)
          if onFoot then MZHouses.GetDoorContext(closestCode, false) end
          if type(house) == 'table' then addMzInteractPoint(closestCode, house) end
          if onFoot and type(house) == 'table' and canShowDoorAction(closestCode, house) then
            waitMs = 0
            local doorKey = tonumber((MZHousesConfig.Interaction or {}).doorKey) or 47
            DisableControlAction(0, doorKey, true)
            if IsDisabledControlJustReleased(0, doorKey) then MZHouses.ToggleDoor(closestCode) end
          else
            waitMs = 250
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
  MZHouses.Debug('visibility_points_refreshed', { reason = reason, usingMzInteract = ok == true, points = pointCount() })
end)

RegisterNetEvent('mz_houses:client:doorPresentationChanged', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode)
  local house = MZHouses.GetVisibleHouseByCode(code)
  if UsingMzInteract and type(house) == 'table' then addMzInteractPoint(code, house) end
end)

RegisterNetEvent('mz_houses:client:doorVisibilityRefreshed', function(payload)
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.houseCode)
  if payload.house == false then
    removeInteractPoint(code)
    UsingMzInteract = pointCount() > 0
  elseif type(payload.house) == 'table' and (MZHousesConfig.Interaction or {}).useMzInteract == true then
    addMzInteractPoint(code, payload.house)
    UsingMzInteract = pointCount() > 0
  end
end)

CreateThread(function()
  Wait(700)
  if MZHouses and MZHouses.RefreshVisibleHouses then MZHouses.RefreshVisibleHouses(true) end
  local ok = registerMzInteractPoints()
  MZHouses.Debug(ok and 'using_mz_interact' or 'using_fallback_markers', { points = pointCount() })
  runFallbackMarkerLoop()
  runMzInteractDoorContextLoop()
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then removeInteractPoints() end
end)
