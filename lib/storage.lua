-- lib/storage.lua v2000
-- NEW ARCHITECTURE: Based on Avant_lab_V
-- Handles robust data persistence including Matrix, Gains, and Tape Paths.

local Storage = {}

function Storage.get_filename(pset_number)
  local name = string.format("%02d", pset_number)
  return _path.data .. "ncoco/" .. name .. "_data.lua"
end

function Storage.save(G, pset_number)
  if not pset_number then return end
  
  print("Storage: Saving PSET " .. pset_number)
  
  -- 1. Create Data Directory if missing
  if not util.file_exists(_path.data .. "ncoco") then
    util.make_dir(_path.data .. "ncoco")
  end
  
  -- 2. Snapshot Audio (Avant Style)
  -- We save the current buffer content to a unique file linked to this PSET
  local t = os.date("%y%m%d_%H%M%S")
  local path1 = _path.audio .. "ncoco/pset_" .. pset_number .. "_L_" .. t .. ".wav"
  local path2 = _path.audio .. "ncoco/pset_" .. pset_number .. "_R_" .. t .. ".wav"
  
  -- Trigger Engine Write
  local len = params:get("tape_len")
  engine.write_tape(1, path1, len) -- 1 = L
  engine.write_tape(2, path2, len) -- 2 = R
  
  -- 3. Construct Data Table
  local data = {
    patch = G.patch,
    dest_gains = G.dest_gains,
    tape_path_l = path1,
    tape_path_r = path2,
    tape_len = len,
    -- We can add extra state here like LFO positions if needed
  }
  
  -- 4. Write to Disk
  tab.save(data, Storage.get_filename(pset_number))
end

function Storage.load(G, SC, pset_number)
  if not pset_number then return end
  local file = Storage.get_filename(pset_number)
  
  if util.file_exists(file) then
    print("Storage: Loading " .. file)
    local data = tab.load(file)
    
    if data then
      -- A. Restore Patch Matrix
      if data.patch then
        G.patch = data.patch
        for src=1, 10 do
          for dst=1, 20 do
            if G.patch[src][dst] ~= 0 then SC.update_matrix(dst, G) end
          end
        end
      end
      
      -- B. Restore Gains
      if data.dest_gains then
        G.dest_gains = data.dest_gains
        SC.update_dest_gains(G)
      end
      
      -- C. Restore Loop Length
      if data.tape_len then
        params:set("tape_len", data.tape_len)
      end
      
      -- D. Load Audio (Avant Style - Non-Destructive)
      if data.tape_path_l and util.file_exists(data.tape_path_l) then
        print("Storage: Loading Tape L -> " .. data.tape_path_l)
        engine.read_tape(1, data.tape_path_l)
      end
      
      if data.tape_path_r and util.file_exists(data.tape_path_r) then
        print("Storage: Loading Tape R -> " .. data.tape_path_r)
        engine.read_tape(2, data.tape_path_r)
      end
    end
  else
    print("Storage: No data file for PSET " .. pset_number)
  end
end

return Storage
