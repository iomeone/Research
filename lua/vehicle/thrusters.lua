-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local activeThrusters = {}
local thrusterState = {}
local autoThrusters = {}
local impulseState = {}
local thrusting = false
local dtSim = obj:getPhysicsDt()

local function update()
  -- node1 is source, node2 is destination
  -- we apply and measure forces/velocity for node2

  local t
  for _, thruster in ipairs(autoThrusters) do
    local vel = -obj:getNodeVelocity(thruster.id2, thruster.id1)
    if vel > 0.3 then
      t = (vel *vel) * thruster.factor
      if thrusting then
        t = math.min( math.max(obj:getNodeForce(thruster.id1, thruster.id2), 0) + t, thruster.thrustLimit)
      else
        t = math.min( t, thruster.thrustLimit)
      end
      obj:applyForce(thruster.id2, thruster.id1, t )
    end
  end

  for _, thruster in ipairs(thrusterState) do
    -- applyForce(node1, node2, forceMagnitude)
    obj:applyForce(thruster[2], thruster[1], thruster[3])
  end

  local impulseCount = #impulseState
  if impulseCount > 0 then
    for i = impulseCount, 1, -1 do
      -- applyForce(node1, node2, forceMagnitude)
      local thruster = impulseState[i]
      obj:applyForce(thruster[1], thruster[2], thruster[3])
      local ttl = thruster[4]
      ttl = ttl - dtSim
      if ttl <= 0 then
        table.remove(impulseState, i)
      else
        thruster[4] = ttl
      end
    end

    if #activeThrusters + #impulseState + #autoThrusters == 0 then
      M.update = nop
    end
  end
end

local function updateGFX()
  table.clear(thrusterState)
  for _, thruster in ipairs(activeThrusters) do
    if thruster.control == '+axisX' and input.axisX > 0 then
      table.insert(thrusterState, {thruster.id1, thruster.id2, math.min(input.axisX * thruster.factor, thruster.thrustLimit)})
    elseif thruster.control == '-axisX' and input.axisX < 0 then
      table.insert(thrusterState, {thruster.id1, thruster.id2, math.min(-input.axisX * thruster.factor, thruster.thrustLimit)})
    elseif thruster.control == '+axisY' and input.axisY > 0 then
      table.insert(thrusterState, {thruster.id1, thruster.id2, math.min(input.axisY * thruster.factor, thruster.thrustLimit)})
    elseif thruster.control == '-axisY' and input.axisY < 0 then
      table.insert(thrusterState, {thruster.id1, thruster.id2, math.min(-input.axisY * thruster.factor, thruster.thrustLimit)})
    elseif electrics.values[thruster.control] then
      table.insert(thrusterState, {thruster.id1, thruster.id2, math.min(electrics.values[thruster.control] * thruster.factor, thruster.thrustLimit)})
    elseif input.keys[thruster.control] then
      table.insert(thrusterState, {thruster.id1, thruster.id2, thruster.thrustLimit})
    end
  end

  thrusting = #thrusterState > 0
end

local function applyImpulse(n1, n2, force, dt)
  for _, thruster in ipairs(impulseState) do
    if thruster[1] == n1 and thruster[2] == n2 then
      thruster[3] = force
      thruster[4] = dt
      return
    end
  end

  table.insert(impulseState, {n1, n2, force, dt})
  M.update = update
end

local function init()
  -- update public interface
  if v.data.thrusters == nil or next(v.data.thrusters) == nil then
    M.update = nop
    M.updateGFX = nop
    return
  else
    M.update = update
    M.updateGFX = updateGFX
  end

  thrusterState = {}
  autoThrusters = {}
  impulseState = {}
  activeThrusters = {}
  for _, thruster in pairs(v.data.thrusters) do
    if thruster.control == 'auto' then
      table.insert(autoThrusters, thruster)
    else
      table.insert(activeThrusters, thruster)
    end
  end

  for _, thruster in pairs(activeThrusters) do
    thruster.factor = thruster.factor or 1
    thruster.thrustLimit = thruster.thrustLimit or math.huge
  end
end

-- public interface
M.reset       = init
M.init        = init
M.update      = nop
M.updateGFX   = nop
M.applyImpulse = applyImpulse

return M