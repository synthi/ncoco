-- lib/storage.lua v2003
-- CHANGELOG v2003:
-- 1. PERSISTENCE: Added 'sequencers' table to Save/Load routine.

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
  
  local data = {
    patch = G.patch,
    dest_gains = G.dest_gains,
    tape_path_l = path1,
    tape_path_r = path2,
    tape_len = len,
    sequencers = G.sequencers -- NEW: Save ghost hands
  }
  
  tab.save(data, Storage.get_filename(pset_number))
end

function Storage.load(G, SC, pset_number)
  if not pset_number then return end
  local file = Storage.get_filename(pset_number)
  
  if util.file_exists(file) then
    local data = tab.load(file)
    if data then
      if data.patch then
        G.patch = data.patch
        for src=1, 10 do
          for dst=1, 20 do if G.patch[src][dst] ~= 0 then SC.update_matrix(dst, G) end end
        end
      end
      if data.dest_gains then G.dest_gains = data.dest_gains; SC.update_dest_gains(G) end
      if data.tape_len then params:set("tape_len", data.tape_len) end
      
      -- NEW: Restore Sequencers
      if data.sequencers then
         G.sequencers = data.sequencers
         -- Reset non-serializable runtime properties
         for i=1,4 do 
            G.sequencers[i].double_click_timer = nil 
            -- If loaded state was active, keep it active? Or default to STOP?
            -- Let's default to STOP (3) to avoid chaos on load
            if G.sequencers[i].state == 2 or G.sequencers[i].state == 4 then
               G.sequencers[i].state = 3
            end
         end
      end
      
      if data.tape_path_l and util.file_exists(data.tape_path_l) then engine.read_tape(1, data.tape_path_l) end
      if data.tape_path_r and util.file_exists(data.tape_path_r) then engine.read_tape(2, data.tape_path_r) end
    end
  end
end

return Storage
