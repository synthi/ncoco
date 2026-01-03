-- ncoco.lua v2005
-- name: Ncoco
-- desc: Hexaquantus Lo-Fi Delay & Chaos Computer.
--       A Ciat-Lonbarde inspired instrument.
-- tags: delay, lo-fi, chaos, feedback
--
-- v2005 CHANGELOG:
-- 1. SEQUENCER ENGINE: Replaced 'Sleep' logic with 'Absolute Time Scheduler'.
--    Fixes timing freeze during Overdub/Insert. High-res scanning (100Hz).

engine.name = 'Ncoco'

local status, G = pcall(include, 'ncoco/lib/globals')
if not status then print("CRITICAL: globals missing"); return end
local status, SC = pcall(include, 'ncoco/lib/sc_utils')
local status, GridNav = pcall(include, 'ncoco/lib/grid_nav')
local status, UI = pcall(include, 'ncoco/lib/ui')
local status, _16n = pcall(include, 'ncoco/lib/16n')
local status, Params = pcall(include, 'ncoco/lib/param_set')
local status, Storage = pcall(include, 'ncoco/lib/storage') 

local g = grid.connect()
local m = midi.connect()
local grid_metro, screen_metro

if not util.file_exists(_path.audio .. "ncoco") then
  util.make_dir(_path.audio .. "ncoco")
end

-- --- ABSOLUTE TIME SEQUENCER ENGINE ---
local function run_sequencer(id, grid_device)
  local s = G.sequencers[id]
  s.playhead = 0
  s.last_cpu_time = util.time()
  
  -- Helper to trigger events in a time window
  local function trigger_window(t_start, t_end)
     for _, event in ipairs(s.data) do
        -- Check if event falls in this window [start, end)
        if event.dt >= t_start and event.dt < t_end then
           GridNav.key(G, grid_device, event.x, event.y, event.z, true)
        end
     end
  end

  while true do
    -- Only run if Playing (2) or Dubbing (4) and has duration
    if (s.state == 2 or s.state == 4) and s.duration > 0.01 then
       local now = util.time()
       local delta = now - s.last_cpu_time
       s.last_cpu_time = now
       
       -- Advance playhead
       local old_head = s.playhead
       s.playhead = s.playhead + delta
       
       if s.playhead >= s.duration then
          -- WRAP AROUND (LOOP)
          -- 1. Trigger events from old_head to End
          trigger_window(old_head, s.duration + 0.001) -- +margin
          
          -- 2. Wrap
          s.playhead = s.playhead % s.duration
          
          -- 3. Trigger events from Start to new playhead
          trigger_window(0, s.playhead)
          
          -- Sync start_time for DUB logic alignment
          s.start_time = now - s.playhead
       else
          -- NORMAL ADVANCE
          trigger_window(old_head, s.playhead)
       end
       
       clock.sleep(0.01) -- High res tick (10ms)
    else
       -- If Stopped or Empty, just update timestamp to avoid jumps on start
       s.last_cpu_time = util.time()
       s.playhead = 0
       clock.sleep(0.1) -- Idle sleep
    end
  end
end

function init()
  GridNav.init_map(G)
  Params.init(SC, G)
  
  params.action_write = function(filename, name, number) Storage.save(G, number) end
  params.action_read = function(filename, silent, number) Storage.load(G, SC, number) end

  osc.event = function(path, args, from)
    if path == '/update' then
      G.coco[1].pos = args[1]; G.coco[2].pos = args[2]
      G.coco[1].gate_rec = args[3]; G.coco[2].gate_rec = args[4]
      G.coco[1].gate_flip = args[5]; G.coco[2].gate_flip = args[6] 
      G.coco[1].gate_skip = args[7]; G.coco[2].gate_skip = args[8]
      for i=1, 6 do G.sources_val[i] = args[8+i] end
      G.sources_val[7] = args[15]; G.sources_val[8] = args[16]
      G.sources_val[9] = args[17]; G.sources_val[10] = args[18]
      G.coco[1].real_speed = args[19]; G.coco[2].real_speed = args[20]
      G.coco[1].out_level = args[21]; G.coco[2].out_level = args[22]
      
    elseif path == '/buffer_info' then
      local dur = args[2]
      if dur > 0 then
         dur = util.clamp(dur, 0.1, 60.0)
         params:set("tape_len", dur)
      end
    end
  end

  clock.run(function() 
    clock.sleep(0.5) 
    
    SC.set_rec(1, 0); SC.set_rec(2, 0)
    SC.set_feedback(1, 0.9); SC.set_feedback(2, 0.9)
    SC.set_loop_len(8.0)
    SC.set_bitdepth(1, 8); SC.set_bitdepth(2, 8) 
    engine.skipMode(0)

    for i=1, 6 do
      local seed_lfo = 0.2 + (math.random() * 0.9)
      local seed_aud = 100 + (math.random() * 500)
      params:set("p"..i.."f_lfo", seed_lfo)
      params:set("p"..i.."f_aud", seed_aud)
      SC.set_petal_freq(i, seed_lfo)
    end
    
    -- START SEQUENCERS (Pass 'g' object)
    for i=1, 4 do clock.run(function() run_sequencer(i, g) end) end

    grid_metro = metro.init(); grid_metro.time = 1/20
    grid_metro.event = function() pcall(GridNav.redraw, G, g) end
    grid_metro:start()

    screen_metro = metro.init(); screen_metro.time = 1/30
    screen_metro.event = function() redraw() end
    screen_metro:start()
    
    G.loaded = true 
    print("Ncoco v2005 Ready.")
  end)

  _16n.init(function(msg) 
    local id = _16n.cc_2_slider_id(msg.cc)
    if id and id <= 6 then 
       local r = params:get("p"..id.."range")
       local target = (r==1) and "p"..id.."f_lfo" or "p"..id.."f_aud"
       local min, max = (r==1) and 0.01 or 20, (r==1) and 20 or 2000
       params:set(target, util.linexp(0, 127, min, max, msg.val)) 
    end
  end)
end

function redraw()
  if not G.loaded then return end
  UI.update_histories(G)
  screen.clear()
  if G.focus.source then
    if G.focus.last_dest then UI.draw_patch_menu(G)
    elseif G.focus.source <= 6 then UI.draw_petal_inspector(G, G.focus.source)
    elseif G.focus.source <= 8 then UI.draw_env_inspector(G, G.focus.source) 
    else UI.draw_yellow_inspector(G, G.focus.source) end
  elseif G.focus.inspect_dest then
    UI.draw_dest_inspector(G, G.focus.inspect_dest)
  elseif G.focus.edit_l then UI.draw_edit_menu(G, 1)
  elseif G.focus.edit_r then UI.draw_edit_menu(G, 2)
  else UI.draw_main(G) end
  screen.update()
end

function cleanup()
  if grid_metro then grid_metro:stop() end
  if screen_metro then screen_metro:stop() end
end

function g.key(x,y,z) 
  if not G.loaded then return end
  GridNav.key(G, g, x,y,z) 
end

function enc(n,d)
  if not G.loaded then return end
  
  if G.focus.inspect_dest then
    if n==3 then
      local id = G.focus.inspect_dest
      G.dest_gains[id] = util.clamp(G.dest_gains[id] + d/100, 0, 2)
      SC.update_dest_gains(G)
    end
    return
  end

  if G.focus.source and G.focus.last_dest then
    if n==3 then
      local s, dt = G.focus.source, G.focus.last_dest
      local val = util.clamp(G.patch[s][dt] + d/100, -1, 1)
      G.patch[s][dt] = val; SC.update_matrix(dt, G)
    end
    return
  end

  if G.focus.source then
    local id = G.focus.source
    if id <= 6 then 
      if n==2 then 
        local r = params:get("p"..id.."range")
        local target = (r==1) and "p"..id.."f_lfo" or "p"..id.."f_aud"
        params:delta(target, d)
      elseif n==3 then params:delta("p"..id.."chaos", d) end
    elseif id <= 8 then 
      local side = (id==7) and "L" or "R"
      if n==2 then params:delta("preamp"..side, d/10)
      elseif n==3 then params:delta("envSlew"..side, d) end
    end
    return
  end

  local is_link = G.focus.edit_l and G.focus.edit_r
  
  if G.focus.edit_l or is_link then
    local c = "L"
    if n==1 then params:delta("filt"..c, d); if is_link then params:delta("filtR", d) end
    elseif n==2 then params:delta("speed"..c, d/10); if is_link then params:delta("speedR", d/10) end
    elseif n==3 then 
       params:delta("fb"..c, d/3); 
       if is_link then params:delta("fbR", d/3) end
    end
  elseif G.focus.edit_r then
    local c = "R"
    if n==1 then params:delta("filt"..c, d)
    elseif n==2 then params:delta("speed"..c, d/10)
    elseif n==3 then params:delta("fb"..c, d/3) end 
  else
    if n==1 then params:delta("global_vol", d) end
    if n==2 then params:delta("speedL", d/10); params:delta("speedR", d/10) end
    if n==3 then params:delta("global_chaos", d) end
  end
end

function key(n,z)
  if not G.loaded then return end
  if n==1 then return end 
  if z==1 then
    if G.focus.source and G.focus.source <= 6 then
      local id = G.focus.source; 
      if n==2 then 
        local curr = params:get("p"..id.."range")
        params:set("p"..id.."range", 3-curr) 
      elseif n==3 then 
        local curr = params:get("p"..id.."shape")
        params:set("p"..id.."shape", 3-curr) 
      end
      return
    end
    
    local is_link = G.focus.edit_l and G.focus.edit_r
    if G.focus.edit_l or is_link then 
       if n==2 then 
         local v = params:get("dolbyL"); params:set("dolbyL", (v%9)+1)
         if is_link then params:set("dolbyR", (v%9)+1) end
       end
       if n==3 then 
          local v = params:get("bitsL"); params:set("bitsL", (v%3)+1)
          if is_link then params:set("bitsR", (v%3)+1) end
       end
    elseif G.focus.edit_r then 
       if n==2 then local v=params:get("dolbyR"); params:set("dolbyR", (v%9)+1) end
       if n==3 then local v=params:get("bitsR"); params:set("bitsR", (v%3)+1) end
    else 
       if n==2 then 
         local v = 1 - params:get("recL")
         params:set("recL", v); params:set("recR", v)
       end 
       if n==3 then
         engine.skipMode(params:get("skip_mode") == 1 and 1 or 0) 
       end
    end
  end
end
