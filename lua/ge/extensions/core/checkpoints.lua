-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
local M = {}
M.state = {}
local helper = require('scenario/scenariohelper')

local logTag = 'checkpoint'

local function resetData()
  local state = M.state
  state.vehicleCheckpoints = {}
  state.aiVehiclePath = {}
end

local function enableCheckpoints(scenario)
  return scenario and scenario.enableCheckpoints and scenario.lapConfig and (#scenario.lapConfig > 1)
end

local function removeCheckpoint(vehicleId)  
  M.state.vehicleCheckpoints[vehicleId] = nil
end

local function saveCheckpoint(vehicleId, vehicleName, cpData)
  local vehicle = be:getObjectByID(vehicleId)
  if not vehicle then return end
  -- log('I', logTag,'saving point for '..vehicleName)

  local vehicleCheckpoints = M.state.vehicleCheckpoints
  if not vehicleCheckpoints[vehicleId] then
    vehicleCheckpoints[vehicleId] = {}
  end
  if not vehicleName then
    vehicleName = 'unnamed_'..vehicleId
  end
  vehicleCheckpoints[vehicleId].vehicleName = vehicleName
  vehicleCheckpoints[vehicleId].checkTimer = 0
  vehicleCheckpoints[vehicleId].pos = (cpData and vec3(cpData.desiredPos)) or vec3(vehicle:getPosition())
  vehicleCheckpoints[vehicleId].dirVec = (cpData and vec3(cpData.desiredDir)) or vec3(vehicle:getDirectionVector())
  vehicleCheckpoints[vehicleId].upVec =  vec3(vehicle:getDirectionVectorUp())  
end

local function completeReset(vehicleId, vehicleName)
  log('I', logTag,'completeReset called for vid: '..tostring(vehicleId) .. " vehName: "..tostring(vehicleName))
  local aiVehiclePath = M.state.aiVehiclePath
  local arg = aiVehiclePath[vehicleId]    
  if arg then
    helper.setAiPath(arg)   
    -- dump(arg)         
  end
end

local function ResetToSavedCheckpoint(vehicle, vehicleName)
  -- log('I', logTag,'resetting to saved checkpoint for '..vehicleName)
  local vehId = vehicle:getID()
  local vehicleCheckpoints = M.state.vehicleCheckpoints
  local pos = vehicleCheckpoints[vehId].pos
  local dirVec = vehicleCheckpoints[vehId].dirVec
  local upVec = vehicleCheckpoints[vehId].upVec
  local rot = quatFromDir(-dirVec, upVec)
  -- log('I', logTag, 'dirVec: '..tostring(dirVec))
  -- log('I', logTag, 'upVec: '..tostring(upVec))
  -- log('I', logTag, 'rot: '..tostring(rot.x) ..', '..tostring(rot.y)..', '..tostring(rot.z)..', '..tostring(rot.w))
  
  vehicle:resetBrokenFlexMesh()
  vehicle:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
  -- Queued for round trip to allow setpositionrotation to take effect
  local callbackCommand = string.format('obj:queueGameEngineLua("if be:getObjectByID('..vehId..') then be:getObjectByID('..vehId..'):autoplace(); core_checkpoints.completeReset(%u,%s) end")', vehId, "'"..vehicleName.."'")
  vehicle:queueLuaCommand(callbackCommand)  
  local command = string.format("recovery.clear()")
  vehicle:queueLuaCommand(command)  
end

local function saveAIPath(vehicleName, arg)
  -- log('I', logTag,'saveAIPath called for '..vehicleName)
  local vehicle = scenetree.findObject(vehicleName)
  if vehicle then
    local vehId = vehicle:getID()
    M.state.aiVehiclePath[vehId] = arg
    -- dump(arg)
  end
end

local function initialiseCheckpointData(vehicleId)
  local vehicle = be:getObjectByID(vehicleId)
  if vehicle and (vehicle.playerUsable or checkVehicleProperty(vehicleId, 'isAIControlled', '1')) then
    local state = M.state
    local vehName = vehicle:getField('name', '')
    saveCheckpoint(vehicleId, vehName)
    state.vehicleCheckpoints[vehicleId].initialPos = state.vehicleCheckpoints[vehicleId].pos
  end  
end

local function setCheckpoint(playerId)
  -- log('I', logTag, 'setCheckpoint called...'..tostring(playerId))
  local vehicle = be:getPlayerVehicle(playerId)
  if vehicle then 
    saveCheckpoint(vehicle:getID(), vehicle:getField('name', ''))    
    -- dump(M.state)
  end
end

local function teleportToCheckpoint(playerId)
  -- log('I', logTag, 'teleportToCheckpoint called...'..tostring(playerId))
  local vehicle = be:getPlayerVehicle(playerId)
  if vehicle then 
    ResetToSavedCheckpoint(vehicle, vehicle:getField('name', ''))    
  end  
end

local function onRaceWaypointReached(data)
  local scenario = scenario_scenarios.getScenario()
  if not scenario then 
    return 
  end

  -- log('I', logTag,'onRaceWaypointReached called')
  -- dump(data)
  local vehWpData = scenario_waypoints.getVehicleWaypointData(data.vehicleId)
  -- dump(vehWpData)
  
  local cpData = {}
  cpData.desiredPos = data.curPos

  if vehWpData.nextWp then
    cpData.desiredDir = (data.curPos - vehWpData.nextWp.pos):normalized()
  end
  saveCheckpoint(data.vehicleId, data.vehicleName, cpData)

  local state = M.state
  local vehicleCheckpoints = state.vehicleCheckpoints
  local aiVehiclePath = state.aiVehiclePath

  if scenario_waypoints.isFinalWaypoint(data.vehicleId, data.waypointName) then
    vehicleCheckpoints[data.vehicleId].raceOver = true
  end

  if aiVehiclePath[data.vehicleId] then
    -- dump(aiVehiclePath[data.vehicleId])
    -- dump(data.waypointName)
    local waypoints = aiVehiclePath[data.vehicleId].waypoints
    for index, wpName in ipairs(waypoints) do
      if wpName == data.waypointName then
        -- log('I', logTag,'removing '..wpName)
        table.remove(waypoints, index)
        break
      end
    end
    -- dump(aiVehiclePath[data.vehicleId])    
  end
end

local function onPreRender(dt)
  local scenario = scenario_scenarios and scenario_scenarios.getScenario()
  if not scenario or scenario.state ~= 'running' or (not enableCheckpoints(scenario)) then 
    return 
  end

  -- Reset AI control vehicles to the last checkpoint if  they are not moving
  local vehicleCheckpoints = M.state.vehicleCheckpoints
  for vid,data in pairs(vehicleCheckpoints) do
    data.checkTimer = data.checkTimer + dt
    if data.checkTimer >= 4 then
      data.checkTimer = data.checkTimer - 4
      local vehicle = be:getObjectByID(vid)
      if vehicle and not vehicle.playerUsable then
        local vehPos = vec3(vehicle:getPosition())
        if (vehPos - data.initialPos):squaredLength() > 1 then
          if data.prevVehPos and not data.raceOver then
            if (vehPos - data.prevVehPos):squaredLength() < 0.0016 then
              log('I', logTag,'Resetting '..data.vehicleName..' to last checkpoint')
              ResetToSavedCheckpoint(vehicle, data.vehicleName)
            end
          end
        end
        data.prevVehPos = vehPos
      end
    end
  end
end

local function onScenarioRestarted(scenario)
  log('I', logTag,'onScenarioRestarted called')
  resetData()
  for _, vid in pairs(scenario.vehicleNameToId or {}) do
    initialiseCheckpointData(vid)   
  end
end

local function onSerialize()
  -- log('D', logTag, 'onSerialize called...')
  local data = {}
  local state = M.state
  data.vehicleCheckpoints = convertVehicleIdKeysToVehicleNameKeys(state.vehicleCheckpoints)
  data.aiVehiclePath = convertVehicleIdKeysToVehicleNameKeys(state.aiVehiclePath)
  -- dump(data)
  --writeFile("checkpoints.txt", dumps(data))
  return data
end

local function onDeserialized(data)
  -- log('D', logTag, 'onDeserialized called...')
  local state = M.state
  state.vehicleCheckpoints = convertVehicleNameKeysToVehicleIdKeys(data.vehicleCheckpoints)
  state.aiVehiclePath = convertVehicleNameKeysToVehicleIdKeys(data.aiVehiclePath)
end

local function onVehicleSpawned(vehId)
  -- local vehicle = be:getObjectByID(vehId)
  -- local msg = 'onVehicleSpawned called... vehId: '..tostring(vehId)
  -- if vehicle then
  --   local vehName = vehicle:getField('name', '')
  --   msg = msg .. ' name: '..tostring(vehName)

  --   if vehicle.playerUsable then
  --     msg = msg .. ' playerUsable: '..tostring(vehicle.playerUsable)
  --   end
  -- else
  --   msg = msg .. '. Vehicle not found.'
  -- end
  -- log('I', logTag, msg)
  -- dump(state)
  initialiseCheckpointData(vehId)  
end 

local function onVehicleDestroyed(vid)
  -- local vehicle = be:getObjectByID(vid)
  -- local msg = 'onVehicleDestroyed called... vid: '..tostring(vid)
  -- if vehicle then
  --   local vehName = vehicle:getField('name', '')
  --   msg = msg .. ' name: '..tostring(vehName)

  --   if vehicle.playerUsable then
  --     msg = msg .. ' playerUsable: '..tostring(vehicle.playerUsable)
  --   end
  -- end
  -- log('I', logTag, msg)
  -- dump(state)

  removeCheckpoint(vid)
end

local function onClientPreStartMission( mission )
  -- log('I', logTag, 'onClientPreStartMission called...')
  resetData()
end

local function onClientEndMission( mission )
  -- log('I', logTag, 'onClientEndMission called...')
  resetData()
end

local function onVehicleAIStateChanged(data)
  if data and data.aiControlled == true then
    initialiseCheckpointData(data.vehicleId)
  end
end

local function onSaveCampaign(saveCallback)
  local data = {}
  local state = M.state
  data.vehicleCheckpoints = convertVehicleIdKeysToVehicleNameKeys(state.vehicleCheckpoints)
  -- data.aiVehiclePath = convertVehicleIdKeysToVehicleNameKeys(state.aiVehiclePath)
  saveCallback(M.__globalAlias__, data)
end

local function onResumeCampaign(campaignInProgress, data)
  log('I', logTag, 'resume campaign called.....')
  local state = M.state
  state.vehicleCheckpoints = convertVehicleNameKeysToVehicleIdKeys(data.vehicleCheckpoints)
  -- state.aiVehiclePath = convertVehicleNameKeysToVehicleIdKeys(data.aiVehiclePath)  
end

-- public interface
M.onVehicleSpawned            = onVehicleSpawned
M.onVehicleDestroyed          = onVehicleDestroyed
M.onClientPreStartMission     = onClientPreStartMission
M.onClientEndMission          = onClientEndMission
M.completeReset               = completeReset
M.onRaceWaypointReached       = onRaceWaypointReached
M.onSerialize                 = onSerialize
M.onDeserialized              = onDeserialized
M.onVehicleAIStateChanged     = onVehicleAIStateChanged

M.onScenarioRestarted         = onScenarioRestarted
M.onPreRender                 = onPreRender
M.onSaveCampaign              = onSaveCampaign
M.onResumeCampaign            = onResumeCampaign

M.setCheckpoint               = setCheckpoint
M.teleportToCheckpoint        = teleportToCheckpoint
M.saveAIPath                  = saveAIPath
return M
