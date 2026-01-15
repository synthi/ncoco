-- lib/storage.lua v4000
-- CHANGELOG v4000:
-- 1. TOTAL RECALL: Added snapshot data & state persistence.
-- 2. CASCADE LOAD: Implemented staggered loading (Clock Run) to avoid CPU spikes.

local Storage = {}

function Storage.get_filename(pset_number)
  local name = string.format("%02d", pset_number)
  return _path.data .. "ncoco/" .. name .. "_data.lua"
end

function Storage.save(G, pset_number)
  if not pset_number then return end
  
  if not util.file_exists(_path.data .. "ncoco") then
    util.make_dir(_path.data .. "ncoco")
  end
  
  local t = os.date("%y%m%d_%H%M%S")
  local path1 = _path.audio .. "ncoco/pset_" .. pset_number .. "_L_" .. t .. ".wav"
  local path2 = _path.audio .. "ncoco/pset_" .. pset_number .. "_R_" .. t .. ".wav"
  
  local len = params:get("tape_len")
  engine.write_tape(1, path1, len)
  engine.write_tape(2, path2, len)
  
  -- Gather Sequencer Active States
  local seq_states = {}
  for i=1, 4 do
     if G.sequencers[i].state == 2 then seq_states[i] = true else seq_states[i] = false end
  end
  
  local data = {
    patch = G.patch,
    dest_gains = G.dest_gains,
    tape_path_l = path1,
    tape_path_r = path2,
    tape_len = len,
    sequencers = G.sequencers,
    
    -- v4000 Additions
    snapshots = G.snapshots,
    active_snapshot = G.active_snapshot,
    seq_active_states = seq_states
  }
  
  tab.save(data, Storage.get_filename(pset_number))
end

function Storage.load(G, SC, pset_number)
  if not pset_number then return end
  local file = Storage.get_filename(pset_number)
  
  if util.file_exists(file) then
    local data = tab.load(file)
    if data then
      -- 1. Restore Static Data (Instant)
      if data.patch then
        for src=1, 10 do
          if data.patch[src] then 
             for dst=1, 24 do 
                local val = data.patch[src][dst] or 0.0 
                G.patch[src][dst] = val
                if val ~= 0 then SC.update_matrix(dst, G) end
             end
          end
        end
      end
      
      if data.dest_gains then 
         for i=1, 24 do G.dest_gains[i] = data.dest_gains[i] or 1.0 end
         SC.update_dest_gains(G) 
      end
      
      if data.tape_len then params:set("tape_len", data.tape_len) end
      
      -- Load Snapshots to Memory
      if data.snapshots then G.snapshots = data.snapshots end
      G.active_snapshot = data.active_snapshot or 0
      
      -- Load Sequencer Data (But don't start yet)
      if data.sequencers then
         G.sequencers = data.sequencers
         for i=1,4 do 
            G.sequencers[i].double_click_timer = nil 
            G.sequencers[i].state = 3 -- Default to Stopped
         end
      end
      
      -- Load Audio (Async in engine usually)
      if data.tape_path_l and util.file_exists(data.tape_path_l) then engine.read_tape(1, data.tape_path_l) end
      if data.tape_path_r and util.file_exists(data.tape_path_r) then engine.read_tape(2, data.tape_path_r) end
      
      -- 2. CASCADE LOADING (Total Recall)
      -- Recover state slowly to avoid CPU choke
      clock.run(function()
         clock.sleep(0.1)
         
         -- Apply Active Snapshot if exists
         if G.active_snapshot > 0 and G.snapshots[G.active_snapshot] then
            print("Total Recall: Restoring Snapshot " .. G.active_snapshot)
            G.snap_apply(G.snapshots[G.active_snapshot])
         end
         
         clock.sleep(0.1)
         
         -- Restart Sequencers
         if data.seq_active_states then
            for i=1, 4 do
               if data.seq_active_states[i] then
                  print("Total Recall: Starting Seq " .. i)
                  G.sequencers[i].state = 2
                  G.sequencers[i].start_time = util.time()
                  G.sequencers[i].step = 1
               end
            end
         end
      end)
      
    end
  end
end

return Storage