-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- this utility compiles .dae to .cdae for faster loading
-- keep in mind that existing .cdae will be reused. Delete them beforehand if a clean state is required

-- path to compile dae files in. They are loaded separetly in their subfolders
local compilePaths = {'art/', 'vehicles/', 'levels/', 'content/'}

local M = {}

local function resetObjects(cleanOnly)
  -- clean the old one before
  SimObject.setDefaultAddGroup('')

  if scenetree.ObjectsTempGroup then
    scenetree.ObjectsTempGroup:deleteAllObjects()
    scenetree.ObjectsTempGroup:delete()
  end
  -- recreate it freshly
  if not cleanOnly then
    createObject("SimGroup"):registerObject('ObjectsTempGroup')
    SimObject.setDefaultAddGroup('ObjectsTempGroup')
  end
end

local function loadMaterials(path)
  -- old material.cs support
  local matFiles = FS:findFilesByRootPattern( path, 'materials.cs', -1, true, false)
  for k,v in pairs(matFiles) do
    TorqueScript.exec(v)
  end
  local matFiles = FS:findFilesByRootPattern( path, '.material.json', -1, true, false)
  for k,v in pairs(matFiles) do
    Sim.deserializeObjectsFromFile(v, false)
  end
end

local function work(job)
  TorqueScript.eval("$disableTerrainMaterialCollisionWarning=1;$disableCachedColladaNotification=1;")

  local allFilesCheckOnly = FS:findFilesByRootPattern('', '*.dae', -1, true, false) -- do not use for iterating

  local fileCount = #allFilesCheckOnly
  local fileCountDone = 0
  local compiledFiles = {}
  local cacheDir = 'collada_cache' -- set to nil to disable caching logic
  if cacheDir then
    --log('I', 'collada compile', '*** Using cache folder: ' .. tostring(cacheDir))
    if not FS:directoryExists(cacheDir) then
      FS:directoryCreate(cacheDir)
    end
    if not FS:directoryCreate(cacheDir, true) then
      log('E', 'collada compile', '*** Unable to create cache folder: ' .. tostring(cacheDir))
    end
  else
    log('W', 'collada compile', '*** Performance warning: consider using -daecachefolder')
  end

  local hardLinkFilesTodo = {}

  local cacheHits = 0
  local cacheMisses = 0

  local log_progress_timer = hptimer() -- we use a timer here, to prevent flooding the log
  -- we need to load the separate folders isolated, as the names of materials and objects will clash otherwise
  for _, baseDir in pairs(compilePaths) do
    local dirs = getDirectories(baseDir)
    for _, dir in pairs(dirs) do
      local inited = false

      --log('D', 'collada compile', '*** Converting collada files in path: ' .. tostring(dir))
      local files = FS:findFilesByRootPattern( dir, '*.dae', -1, true, false)
      -- filter paths to only return filename without extension
      for i = 1, #files do
        job.yield() -- lets give the game some time and space :)
        local f = files[i]
        local dir, filename, ext = string.match(f, "(.-)([^/]-([^%.]+))$")
        local src = f
        local dst = dir .. filename:sub(1, -4) .. 'cdae'
        local dstData = '' -- dir .. filename:sub(1, -4) .. 'meshes.json' -- do not use this feature for now
        local cacheFilename = nil
        local fileok = false
        if cacheDir then
          -- we try to look up the cache
          local src_hash = FS:hashFileSHA1(src)
          cacheFilename = cacheDir .. '/' .. src_hash .. '.cdae'
          --print('cacheFilename = ' .. tostring(cacheFilename) .. ' / ' .. tostring(FS:fileExists(cacheFilename)))
          if FS:fileExists(cacheFilename) then
            --print(' cache file found, using it: ' .. cacheFilename)
            table.insert(hardLinkFilesTodo, {src_hash .. '.cdae', dst})
            compiledFiles[src] = 2
            cacheHits = cacheHits + 1
            fileok = true
          end
        end
        if not fileok then
          if not inited then
            resetObjects()
            loadMaterials(dir)
            inited = true
          end
          --log('D', 'collada compile', 'compiling: '..src .. ' to ' .. dst)
          if compileCollada(src, dst, dstData) ~= 0 then
            log('E', 'collada compile', 'unable to compile file: '..src)
          else
            --log('D', 'collada compile', '* '..src .. ' : OK')
            compiledFiles[src] = 1
            if cacheDir then
              -- cache the file
              if FS:copyFile(dst, cacheFilename) ~= 0 then
                log('E', 'collada compile', '*** error copying file to cache: ' .. tostring(cacheFilename))
              end
              cacheMisses = cacheMisses + 1
              fileok = true
            end
          end
        end
        fileCountDone = fileCountDone + 1
        if log_progress_timer:stop() > 3000 then
          log('A', 'compilemeshes', 'progress: file ' .. fileCountDone .. ' / ' .. fileCount .. ' ( ' .. round((fileCountDone/fileCount)*100) .. '% ) - ' .. tostring(cacheMisses) .. ' misses / '.. tostring(cacheHits) .. ' hits')
          log_progress_timer:reset()
        end
      end
    end
  end
  --resetObjects(true)

  --dump(compiledFiles)

  log('I', 'compilemeshes', 'saved files to be hard linked to file: cdae_compilation_hardlink_todo.json')
  serializeJsonToFile('cdae_compilation_hardlink_todo.json', hardLinkFilesTodo, true)


  -- checking for missed files
  local exitCode = 0
  local missedFiles = 0
  for _, f in pairs(allFilesCheckOnly) do
    if f:sub(1,1) == '/' then f = f:sub(2) end -- remove leading slash until the FS is fixed properly
    if not compiledFiles[f] then
      log('E', 'compilemeshes', '--- Missed compilation of file: ' .. tostring(f))
      exitCode = 1
      missedFiles = missedFiles + 1
    end
  end

  log('I', 'compilemeshes', ' *** done: ' .. fileCount .. ' files (' .. tostring(missedFiles) .. ' missed) ' .. tostring(cacheHits) .. ' cache hits (' .. round((cacheHits/(cacheHits + cacheMisses))*100) .. '%) and ' .. tostring(cacheMisses) .. ' cache misses.')

  log('D', 'compilemeshes', 'Script done. Exit code: ' .. tostring(exitCode))
  shutdown(exitCode)
end

local function onExtensionLoaded()
  Lua:blacklistLogLevel("DA")
  extensions.core_jobsystem.create(work, 1) -- yield every second, good for background tasks
end

-- interface
M.onExtensionLoaded = onExtensionLoaded
M.work = work

return M
