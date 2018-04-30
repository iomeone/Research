--  Quickrace loader V 0.1
--  Supplies code-created scenario info for the quickrace selection screen.
--  The created scenarios contain the available tracks.
--  This code also loads the scenario, creating the vehicle, needed prefabs
--  and race checkpoints, and also sets the scenario data so that the scenario_race.lua
--  can be used to handle the race logic.

local logTag = 'quickraceLoader'

local M = {}
M.quickRaceModules  = {'scenario_scenarios', 'statistics_statistics', 'scenario_waypoints', 'scenario_quickRace'}

local function getLevelList()
  if not FS:directoryExists('levels/') then
    return {}
  end
  local files = FS:findFilesByPattern('game:levels/', 'info.json', 1, true, false)

  -- filter paths to only return filename without extension
  for k,v in pairs(files) do
    files[k] = string.gsub(files[k], "(.*/)(.*)/(.*)", "%2")
  end
  return files
end

local function mimicProcTracks ()
  local res = {}
  local supportedList = readJsonFile('game:levels/driver_training/scenarios/quickRaceProcedural/tracks.json')
  local scenData = readJsonFile('game:levels/driver_training/scenarios/career_prototype_gymkhana.json')[1]

  for i=1, 10, 1 do
    local help = deepcopy(scenData)

    help.name = supportedList[i].name
    help.previews = supportedList[i].previews

    table.insert(res, help)
  end

  return res
end


-- this function returns a list containing all levels that contain quickraces.
-- each level has a 'tracks'-property, which contains a list of all quickrace tracks for this level.
local function getQuickraceList()
  local files = M.getLevelList()

  local proceduralLevel = {}
  local levels = {}
  local addingProcedural = true
  for _, levelName in ipairs(files) do

    local path = 'levels/' .. levelName .. '/quickrace/'
    local t3dpath = 'game:/' .. path -- the leading slash is a workaround for a bug in FS:findFilesByRootPattern
    local quickraceFiles =  FS:findFilesByPattern(t3dpath, '*.json', -1, true, false)
    if #quickraceFiles > 0 then -- only add the level if it has quickraces inside!
      local newLevel = {}

      newLevel.radiusMultiplierAI = 2
      newLevel.levelObjects = {
        tod   = { time = 0.9, dayLength = 120, play = false },
        sunsky  = { colorize = "0.427451 0.572549 0.737255 1" }
      }
      newLevel.prefabs = {}

      newLevel.playersCountRange = { min = 1, max = 1 }
      newLevel.uilayout = 'quickraceScenario'
      newLevel.levelName = levelName
      newLevel.levelInfo =  readJsonFile('game:/levels/'..levelName..'/info.json') -- this contains the level info for the UI!
      newLevel.official = isOfficialContent(FS:getFileRealPath('levels/'..levelName..'/info.json'))
      if not newLevel.levelInfo then
        log('W', 'quickrace', 'could not load info-file for level ' .. levelName)
      else
        newLevel.name = newLevel.levelInfo.title
      end

      if newLevel.levelName == "driver_training" then
        newLevel.levelInfo.title = 'Procedural Tracks'
        newLevel.name = newLevel.levelInfo.title
        newLevel.uilayout = 'proceduralScenario'
      end

      if newLevel.levelName == "smallgrid" then
        newLevel.levelInfo.title = "Track Editor Tracks"
        newLevel.name = newLevel.levelInfo.title
      end

      newLevel.scenarioName = newLevel.name

      newLevel.previews = M.customPreviewLoader(newLevel, levelName)


      if newLevel.levelName == "smallgrid" then
        newLevel.tracks = M.getTrackEditorTracks(quickraceFiles, levelName)
        if newLevel.tracks and #(newLevel.tracks) > 0 then
          newLevel.previews = newLevel.tracks[1].previews
        end
      else
        newLevel.tracks = M.getTracks(quickraceFiles, levelName, newLevel.levelName)
      end

      newLevel.trackCount = #newLevel.tracks

      newLevel.vehicles = {
        scenario_player0 = {
          driver = { player = true, startFocus = true, required = true }
        }
      }
      newLevel.vehicles['*'] = {}

      if #newLevel.tracks > 0 then
        if newLevel.previews and #newLevel.previews > 0 then
          newLevel.preview = newLevel.previews[1]
          newLevel.preImgIndex = 0
        end

        newLevel.maxPlayers = 0

        if newLevel.playersCountRange and newLevel.playersCountRange.max then
          newLevel.maxPlayers = newLevel.playersCountRange.max
        else
          for _,v in pairs(newLevel.vehicles) do
            if v.playerUsable == true or (v.driver and v.driver.player == true) then
              newLevel.maxPlayers = newLevel.maxPlayers + 1
            end
          end
        end

        if newLevel.playersCountRange and newLevel.playersCountRange.min then
          newLevel.minPlayers = newLevel.playersCountRange.min
        else
          newLevel.minPlayers = newLevel.maxPlayers;
        end
        table.insert(levels, newLevel)
      end
    --  if addingProcedural then
   --     addingProcedural = false
    --  end
     end
    end

  return levels
end

local function getLevel(levelName)
  local raceList = getQuickraceList()
  if raceList then
    for _,raceLevel in ipairs(raceList) do
      if raceLevel.levelInfo.title == levelName or raceLevel.name == levelName then
        return raceLevel
      end
    end
  end

  return nil
end

local function getLevelTrack(levelName, trackName)
  local level = getLevel(levelName)
  if level and level.tracks and level.trackCount > 0 then
    for _,track in ipairs(level.tracks) do
      if track.name == trackName then
        return track
      end
    end
  end

  return nil
end

-- loads the previews for the levels. This code is copied and slightly modified from the scenario_scenarios.lua ...
local function  customPreviewLoader( scenarioData, levelName)
  -- figure out the previews automatically and check for errors


  scenarioData.directory = '/levels/'..levelName
  scenarioData.previews = {}

  local tmp = FS:findFilesByRootPattern("game:/levels/"..levelName.."/",levelName..'_preview*.png', 0, true, false)
  for _, p in pairs(tmp) do
    table.insert(scenarioData.previews, p)
  end
  tmp = FS:findFilesByRootPattern("game:/levels/"..levelName.."/",levelName..'_preview*.jpg', 0, true, false)
  for _, p in pairs(tmp) do
    table.insert(scenarioData.previews, p)
  end

  if #scenarioData.previews == 0 then
    log('W', 'scenarios', 'scenario has no previews: ' .. tostring(scenarioData.scenarioName))
  end
  return scenarioData.previews
end


local function getTrackEditorTracks()
  local tracks = {}
  local simpleSplineTrack = require('util/simpleSplineTrack')
  local names = simpleSplineTrack.getCustomTracks()


  for _, name in ipairs(names) do
    local trackData = simpleSplineTrack.loadJSON(name)
    if trackData then
      local file = {
        name = name,
        description =" ",
        authors = trackData.author or "",
        difficulty = 0,
        date = trackData.date or 1521828000,
        lapCount = 2,
        reversible = false,
        closed = trackData.connected or false,
        allowRollingStart= false,
        length = trackData.length or nil,
        lapConfig = {},
        customData = {
          name = name
        }
      }

      if trackData.connected then
        file.lapCount = 1
      end
      file.sourceFile = "quickraceLoader.getTrackEditorTracks()"
      file.trackName = "TrackEditorTrack_"..name
      file.directory = "generatedFile"

      file.official = false
      file.prefabs = {}
      file.reversePrefabs = {}
      file.forwardPrefabs = {}

      file.luaFile = "game:/lua/ge/extensions/util/trackEditorSetup"

      file.previews = {"/ui/modules/trackBuilder/trackEdit.jpg"}
      file.preview = "/ui/modules/trackBuilder/trackEdit.jpg"

      file.spawnSpheres = {}
       
      file.lapCount = 2

      file.spawnSpheres.standing = "_standing_spawn"
      file.spawnSpheres.standingReverse = "_standingReverse_spawn"
      file.spawnSpheres.rolling = "_rolling_spawn"
      file.spawnSpheres.rollingReverse = "_rollingReverse_spawn"

      file.tod = file.tod or 3


      file.introType = 'none'

      table.insert(tracks, file)
    end
  end

  return tracks

end



-- this function parses the quickrace files, and returns a list of all tracks for one level.
local function getTracks(quickraceFiles, levelName, lvlName)
  local tracks = {}
  local procedurals = lvlName == "driver_training"
  for _, trackFile in ipairs(quickraceFiles) do
    local file = readJsonFile(trackFile)
    if not file then
      log('E', 'failed to load this track ' , tostring(trackFile).. ' Check Json file')
    elseif procedurals ~= not file.procedural then -- no this cannot be changed to procedurals == file.procedural, becaus then false == nil -> false
      file.sourceFile = trackFile
      file.trackName = string.gsub(trackFile, "(.*/)(.*)%.json", "%2")
      file.directory = string.gsub(trackFile, "(.*)/(.*)%.json", "%1")
      file.raceFile = "game:/levels/"..levelName.."/quickrace/"..file.trackName..'.json'
      file.official = isOfficialContent(FS:getFileRealPath("levels/"..levelName.."/quickrace/"..file.trackName..'.json'))

      file.prefabs = file.prefabs or {}
      file.reversePrefabs = file.reversePrefabs or {}
      file.forwardPrefabs = file.forwardPrefabs or {}


      if file.luaFile then
        file.luaFile = "game:/levels/"..levelName.."/quickrace/"..file.luaFile
      else
        file.luaFile = nil
      end

      if file.procedural then
        file.customData.seed = math.random(500*500*500*500)
      end

      -- find preview for forward and reverse
      local tmp = FS:findFilesByRootPattern('game:'..file.directory, file.trackName..'.jpg', 0, true, false)
      file.previews = {}
      for _, p in pairs(tmp) do
        table.insert(file.previews, p)
      end

      local tmp = FS:findFilesByRootPattern('game:'..file.directory, file.trackName..'_reverse.jpg', 0, true, false)
      file.reversePreviews = {}
      for _, p in pairs(tmp) do
        table.insert(file.reversePreviews, p)
      end


      -- set spawnSpheres.
      if not file.spawnSpheres then
        file.spawnSpheres = {}
      end

      if not file.closed then
        file.lapCount = 1
      end

      file.lapCount = file.lapCount or 1

      file.spawnSpheres.standing = file.spawnSpheres.standing or file.trackName.."_standing_spawn"
      file.spawnSpheres.standingReverse = file.spawnSpheres.standingReverse or file.trackName.."_standingReverse_spawn"
      file.spawnSpheres.rolling = file.spawnSpheres.rolling or file.trackName.."_rolling_spawn"
      file.spawnSpheres.rollingReverse = file.spawnSpheres.rollingReverse or file.trackName.."_rollingReverse_spawn"

      file.tod = file.tod or 3

      -- figure out if a html start file is existing
      local htmldiscovered = false
      if not file.startHTML then
        file.startHTML = "quickrace/"..file.trackName .. '.html'
        htmldiscovered = true
      end
      if not FS:fileExists("game:/levels/"..levelName..'/'..file.startHTML) then
        if not htmldiscovered then
          log('W', 'scenarios', 'start html not found, disabled: ' .. file.startHTML)
        end
        file.startHTML = nil
        file.introType = 'none'
      end

      if not file.introType then
          file.introType = 'htmlOnly'
      end

      table.insert(tracks, file)
    end
  end

  return tracks
end


local function loadQuickrace(scenarioKey, scenarioFile, trackFile, vehicleFile)

  -- dump(vehicleFile.color)
  if not vehicleFile.color then
    vehicleFile.color = "1 1 1 1"
  end

  scenarioFile.track = trackFile
  scenarioFile.vehicle = vehicleFile
  scenarioFile.name = trackFile.name
  if trackFile.trackEditorFile then
    scenarioFile.name = "trackEditor_"..scenarioFile.name
  end
  scenarioFile.scenarioName = trackFile.trackName
  scenarioFile.lapCount = trackFile.lapCount
  scenarioFile.lapConfig = trackFile.lapConfig

  -- add automatic prefabs only if they exist
  if FS:fileExists("levels/"..scenarioFile.levelName.."/quickrace/"..trackFile.trackName..'.prefab') then
    trackFile.prefabs[#trackFile.prefabs+1] = "levels/"..scenarioFile.levelName.."/quickrace/"..trackFile.trackName..'.prefab'
  end
  if FS:fileExists("levels/"..scenarioFile.levelName.."/quickrace/"..trackFile.trackName..'_reverse.prefab') then
    trackFile.reversePrefabs[#trackFile.reversePrefabs+1] = "levels/"..scenarioFile.levelName.."/quickrace/"..trackFile.trackName..'_reverse.prefab'
  end
  if FS:fileExists("levels/"..scenarioFile.levelName.."/quickrace/"..trackFile.trackName..'_forward.prefab') then
    trackFile.forwardPrefabs[#trackFile.forwardPrefabs+1] = "levels/"..scenarioFile.levelName.."/quickrace/"..trackFile.trackName..'_forward.prefab'
  end

  if trackFile.reverse then
    for _,p in ipairs(trackFile.reversePrefabs) do
      trackFile.prefabs[#trackFile.prefabs+1] = p
    end
  else
    for _,p in ipairs(trackFile.forwardPrefabs) do
      trackFile.prefabs[#trackFile.prefabs+1] = p
    end
  end

  scenarioFile.prefabs = trackFile.prefabs

  scenarioFile.startHTML = trackFile.startHTML
  scenarioFile.introType = trackFile.introType

  scenarioFile.isReverse = false
  scenarioFile.isReverse = false

  if trackFile.reverse then
    local rev = {}
    for i,c in ipairs(scenarioFile.lapConfig) do
      rev[#scenarioFile.lapConfig +1 - i] = c
    end
    scenarioFile.isReverse = true
    scenarioFile.lapConfig = rev

    if not trackFile.closed then
      local tmp = trackFile.finishLineCheckpoint
      trackFile.finishLineCheckpoint = trackFile.startLineCheckpoint
      trackFile.startLineCheckpoint = tmp
    end

  end

  scenarioFile.lapConfig[#scenarioFile.lapConfig+1] = trackFile.finishLineCheckpoint

  if trackFile.rollingStart then
    if trackFile.closed then
      scenarioFile.startTimerCheckpoint = trackFile.finishLineCheckpoint
    else
      scenarioFile.startTimerCheckpoint = trackFile.startLineCheckpoint
    end
    scenarioFile.rollingStart = true
  end
  --dump(scenarioFile.lapConfig)

  --  dump("End = " .. trackFile.startLineCheckpoint)

  local tod = {0.5, 0.775, 0.85, 0.9, 0, 0.1, 0.175, 0.23, 0.245, 0.5}

  scenarioFile.levelObjects= {
        tod = {
            axisTilt=10,
            time = tod[trackFile.tod+1],
            dayLength = 120,
            play = false,
            azimuthOverride = 0
        }
    }
 --dump(trackFile.tod)

  scenarioFile.isQuickRace = true
  local processedScenario = scenario_scenariosLoader.processScenarioData(scenarioKey, scenarioFile)
  return processedScenario
end

local function starQuickRaceFromUI(scenarioFile, trackFile, vehicleFile)
  if scenetree.MissionGroup then
    log('D', logTag, 'Delaying start of quickrace until current level is unloaded...')

    M.triggerDelayedStart = function()
      log('D', logTag, 'Triggering a delayed start of quickrace...')
      M.triggerDelayedStart = nil
      M.startQuickrace(scenarioFile, trackFile, vehicleFile)
    end

    endActiveGameMode(M.triggerDelayedStart)
  else
    log('I', logTag, 'Start of quickrace: ' .. dumps(trackFile))
    local modules = {}
    for _,m in ipairs(M.quickRaceModules) do
      modules[#modules+1] = m
    end
    modules[#modules+1] = trackFile.luaFile
    log("I",logTag,"Make Modules.." .. dumps(modules))
    loadGameModeModules(modules)

    local quickraceScenario = loadQuickrace(nil, scenarioFile, trackFile, vehicleFile)

    -- dump(quickraceScenario)
    scenario_scenarios.executeScenario(quickraceScenario)
  end
end

-- This function will merge the track and vehicle data into the scenario and start the scenario.
local function startQuickrace(scenarioFile, trackFile, vehicleFile)
  if campaign_exploration and campaign_exploration.getExplorationActive() then
    campaign_exploration.startTimeTrail(scenarioFile, trackFile, vehicleFile)
  else
    starQuickRaceFromUI(scenarioFile, trackFile, vehicleFile)
  end
end


M.loadQuickrace = loadQuickrace
M.getQuickraceList = getQuickraceList
M.customPreviewLoader = customPreviewLoader
M.getTracks = getTracks
M.startQuickrace = startQuickrace
M.getLevelList = getLevelList
M.getLevel = getLevel
M.getLevelTrack = getLevelTrack
M.getTrackEditorTracks = getTrackEditorTracks
return M
