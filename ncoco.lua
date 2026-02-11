-- ncoco.lua v9005
-- CHANGELOG v9005:
-- 1. ENC MAPPING: Added E3 control for Coco Output Slew when focusing on Sources 11/12. load last pset
-- 2. BASE: v9000.

engine.name = 'Ncoco'

local status, G = pcall(include, 'ncoco/lib/globals')
if not status then print("CRITICAL: globals missing"); return end
local status, SC = pcall(include, 'ncoco/lib/sc_utils')
local status, GridNav = pcall(include, 'ncoco/lib/grid_nav')
local status, UI = pcall(include, 'ncoco/lib/ui')
local status, _16n = pcall(include, 'ncoco/lib/16n')
local status, Params = pcall(include, 'ncoco/lib/param_set')
local status, Storage = pcall(include, 'ncoco/lib/storage') 

-- DEFINED LOCAL METROS
local g = grid.connect()
local grid_metro
local screen_metro

if not util.file_exists(_path.audio .. "ncoco") then
  util.make_dir(_path.audio .. "ncoco")
end

-- SNAPSHOT LOGIC REMOVED FOR BREVITY (It is identical to v4003)
-- ... [Assuming Snapshot code is here as in previous versions] ...
-- Re-inserting required minimal snapshot code to prevent errors
local SNAP_NAMES = {"A", "B", "C", "D"}
local function copy_table(t)
  if type(t) ~= 'table' then return t end
  local res = {}
  for k, v in pairs(t) do res[copy_table(k)] = copy_table(v) end
  return res
end
function G.snap_capture()
  local data = {}
  data.patch = copy_table(G.patch)
  data.petals = {}
  for i=1, 6 do
     data.petals[i] = {
        freq_lfo = params:get("p"..i.."f_lfo"),
        freq_aud = params:get("p"..i.."f_aud"),
        chaos = params:get("p"..i.."chaos"),
        shape = params:get("p"..i.."shape"),
        range = params:get("p"..i.."range")
     }
  end
  data.transport = {
     speedL = params:get("speedL"), speedR = params:get("speedR"),
     recL = params:get("recL"), recR = params:get("recR"),
     flipL = params:get("flipL"), flipR = params:get("flipR"),
     skipModeL = params:get("skip_modeL"), skipModeR = params:get("skip_modeR"),
     rateL = params:get("stutter_rateL"), rateR = params:get("stutter_rateR"),
     chaosL = params:get("stutter_chaosL"), chaosR = params:get("stutter_chaosR"),
     envSlewL = params:get("envSlewL"), envSlewR = params:get("envSlewR"),
     lenL = params:get("tape_len_L"), lenR = params:get("tape_len_R")
  }
  return data
end
function G.snap_apply(data)
  if not data then return end
  if data.patch then
     for s=1, 12 do
        for d=1, 24 do
           G.patch[s][d] = data.patch[s][d] or 0
           SC.update_matrix(d, G)
        end
     end
  end
  if data.petals then
     for i=1, 6 do
        local p = data.petals[i]
        if p then
           params:set("p"..i.."f_lfo", p.freq_lfo or 0.5)
           params:set("p"..i.."f_aud", p.freq_aud or 200)
           params:set("p"..i.."chaos", p.chaos or 0)
           params:set("p"..i.."shape", p.shape or 1)
           params:set("p"..i.."range", p.range or 1)
        end
     end
  end
  if data.transport then
     local t = data.transport
     params:set("speedL", t.speedL or 1); params:set("speedR", t.speedR or 1)
     params:set("recL", t.recL or 0); params:set("recR", t.recR or 0)
     params:set("flipL", t.flipL or 0); params:set("flipR", t.flipR or 0)
     params:set("skip_modeL", t.skipModeL or 1); params:set("skip_modeR", t.skipModeR or 1)
     params:set("stutter_rateL", t.rateL or 0.1); params:set("stutter_rateR", t.rateR or 0.1)
     params:set("stutter_chaosL", t.chaosL or 0); params:set("stutter_chaosR", t.chaosR or 0)
     params:set("envSlewL", t.envSlewL or 0.05); params:set("envSlewR", t.envSlewR or 0.05)
     if t.lenL then params:set("tape_len_L", t.lenL) end
     if t.lenR then params:set("tape_len_R", t.lenR) end
  end
  G.popup.name = "SNAPSHOT LOADED"
  G.popup.value = ""
  G.popup.active = true; G.popup.deadline = util.time() + 2.0
end
function G.snap_save(id)
  G.snapshots[id] = G.snap_capture()
  G.active_snapshot = id
  print("Snapshot "..SNAP_NAMES[id].." Saved.")
  G.popup.name = "SNAPSHOT "..SNAP_NAMES[id]
  G.popup.value = "SAVED"
  G.popup.active = true; G.popup.deadline = util.time() + 2.0
  GridNav.redraw(G, g) 
end
function G.snap_update(id)
  G.snapshots[id] = G.snap_capture()
  print("Snapshot "..SNAP_NAMES[id].." Updated.")
  G.popup.name = "SNAPSHOT "..SNAP_NAMES[id]
  G.popup.value = "UPDATED"
  G.popup.active = true; G.popup.deadline = util.time() + 2.0
end
function G.snap_load(id)
  if G.snapshots[id] then
     G.snap_apply(G.snapshots[id])
     G.active_snapshot = id
     print("Snapshot "..SNAP_NAMES[id].." Loaded.")
     G.popup.name = "SNAPSHOT "..SNAP_NAMES[id]
     G.popup.value = "SELECTED"
     G.popup.active = true; G.popup.deadline = util.time() + 2.0
  end
end
function G.snap_clear(id)
  G.snapshots[id] = nil
  if G.active_snapshot == id then G.active_snapshot = 0 end
  print("Snapshot "..SNAP_NAMES[id].." Cleared.")
  G.popup.name = "SNAPSHOT "..SNAP_NAMES[id]
  G.popup.value = "CLEARED"
  G.popup.active = true; G.popup.deadline = util.time() + 2.0
  GridNav.redraw(G, g)
end

-- --- HELPERS FOR 16n ---
local function normalize_input(midi_val)
   if midi_val < 1 then return 0.0 end
   if midi_val > 126 then return 1.0 end
   if midi_val <= 80 then return util.linlin(1, 80, 0.0, 0.5, midi_val)
   else return util.linlin(80, 126, 0.5, 1.0, midi_val) end
end
local function apply_glue(val_norm, param_id)
   if param_id == "speed_offsetL" or param_id == "speed_offsetR" or 
      param_id == "filtL" or param_id == "filtR" or 
      param_id == "pan_l" or param_id == "pan_r" then
      local center = 0.5
      local width = 0.02
      if math.abs(val_norm - center) < width then return center end
      if val_norm < (center - width) then return util.linlin(0, center-width, 0, center, val_norm)
      else return util.linlin(center+width, 1, center, 1, val_norm) end
   end
   if param_id == "vol_l" or param_id == "vol_r" then
      local center = 0.75
      local width = 0.02
      if math.abs(val_norm - center) < width then return center end
      if val_norm < (center - width) then return util.linlin(0, center-width, 0, center, val_norm)
      else return util.linlin(center+width, 1, center, 1, val_norm) end
   end
   return val_norm
end
local function apply_curve(val_norm, param_id)
   if param_id == "fbL" or param_id == "fbR" then
      if val_norm < 0.40 then
         return util.linlin(0, 0.40, 0.0, 0.70, val_norm)
      else
         return util.linlin(0.40, 1.0, 0.70, 1.20, val_norm)
      end
   end
   if param_id == "vol_l" or param_id == "vol_r" then
      if val_norm < 0.75 then
         return util.linlin(0, 0.75, 0.0, 1.0, val_norm)
      else
         return util.linlin(0.75, 1.0, 1.0, 2.0, val_norm)
      end
   end
   if param_id == "preampL" or param_id == "preampR" then
      if val_norm < 0.5 then
          return util.linlin(0, 0.5, 1.0, 3.0, val_norm)
      else
          return util.linlin(0.5, 1.0, 3.0, 20.0, val_norm)
      end
   end
   if param_id == "filtL" or param_id == "filtR" then
      return util.linlin(0, 1, -1.0, 1.0, val_norm)
   end
   if param_id == "speed_offsetL" or param_id == "speed_offsetR" then
      return util.linlin(0, 1, -0.25, 0.25, val_norm)
   end
   local p = params:lookup_param(param_id)
   if p then return p.controlspec:map(val_norm) end
   return val_norm
end

-- SEQUENCER ENGINE
local function run_sequencer(id, grid_device)
  local s = G.sequencers[id]
  s.playhead = 0
  s.last_cpu_time = util.time()
  local function trigger_window(t_start, t_end)
     for _, event in ipairs(s.data) do
        if event.dt >= t_start and event.dt < t_end then
           GridNav.key(G, grid_device, event.x, event.y, event.z, true)
        end
     end
  end
  while true do
    if (s.state == 2 or s.state == 4) and s.duration > 0.01 then
       local now = util.time()
       local delta = now - s.last_cpu_time
       s.last_cpu_time = now
       local old_head = s.playhead
       s.playhead = s.playhead + delta
       if s.playhead >= s.duration then
          trigger_window(old_head, s.duration + 0.001) 
          s.playhead = s.playhead % s.duration
          trigger_window(0, s.playhead)
          s.start_time = now - s.playhead
       else
          trigger_window(old_head, s.playhead)
       end
       clock.sleep(0.01) 
    else
       s.last_cpu_time = util.time()
       s.playhead = 0
       clock.sleep(0.1) 
    end
  end
end

-- 16n MAP
local fader_map_def = {
  [7]="speed_offsetL", [8]="speed_offsetR",
  [9]="preampL", [10]="preampR",
  [11]="fbL", [12]="fbR",
  [13]="vol_l", [14]="vol_r",
  [15]="filtL", [16]="filtR"
}

local function get_petal_param(id)
   local r = params:get("p"..id.."range")
   return (r==1) and "p"..id.."f_lfo" or "p"..id.."f_aud"
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
      
      if args[23] then G.sources_val[11] = args[23] end
      if args[24] then G.sources_val[12] = args[24] end
      
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
    engine.loopLenL(8.0); engine.loopLenR(8.0)
    SC.set_bitdepth(1, 8); SC.set_bitdepth(2, 8) 
    
    engine.skipModeL(0); engine.skipModeR(0)
    engine.driftAmt(0.005)

    for i=1, 6 do
      local seed_lfo = 0.2 + (math.random() * 0.9)
      local seed_aud = 100 + (math.random() * 500)
      params:set("p"..i.."f_lfo", seed_lfo)
      params:set("p"..i.."f_aud", seed_aud)
      SC.set_petal_freq(i, seed_lfo)
    end

     -- carga last pset
      params:default()
    
    for i=1, 4 do clock.run(function() run_sequencer(i, g) end) end

    grid_metro = metro.init(); grid_metro.time = 1/15
    grid_metro.event = function() pcall(GridNav.redraw, G, g) end
    grid_metro:start()

    screen_metro = metro.init(); screen_metro.time = 1/30
    screen_metro.event = function() redraw() end
    screen_metro:start()
    
    clock.run(function()
       clock.sleep(2.0)
       _16n.init(function(msg) 
          local id = _16n.cc_2_slider_id(msg.cc)
          if id then
             local p_name = nil
             if id <= 6 then p_name = get_petal_param(id)
             elseif fader_map_def[id] then p_name = fader_map_def[id] end
             
             if p_name then
                local p_obj = params:lookup_param(p_name)
                if not p_obj then return end

                local val_calibrated = normalize_input(msg.val)
                local val_glued = apply_glue(val_calibrated, p_name)
                
                local current_norm = params:get_raw(p_name)
                local current_val_real = params:get(p_name)
                local target_val_real = apply_curve(val_glued, p_name)
                
                local target_norm_check = p_obj.controlspec:unmap(target_val_real)
                local diff = math.abs(target_norm_check - current_norm)
                
                if not G.fader_latched[id] then
                   if diff < 0.05 then
                      G.fader_latched[id] = true
                   else
                      G.popup.name = "* " .. p_obj.name
                      local display_val = string.format("%.2f", target_val_real)
                      local display_curr = string.format("%.2f", current_val_real)
                      
                      if p_name == "fbL" or p_name == "fbR" then
                         display_val = math.floor(target_val_real * 100) .. "%"
                         display_curr = math.floor(current_val_real * 100) .. "%"
                      elseif p_name == "speed_offsetL" or p_name == "speed_offsetR" then
                          display_val = string.format("%+.3f", target_val_real)
                          display_curr = string.format("%+.3f", current_val_real)
                      end
                      
                      G.popup.value = display_val .. " -> " .. display_curr
                      G.popup.active = true; G.popup.deadline = util.time() + 1.5
                      return
                   end
                end
                
                if G.fader_latched[id] then
                   if diff > 0.15 then 
                      G.fader_latched[id] = false 
                   else
                      params:set(p_name, target_val_real)
                      
                      G.popup.name = p_obj.name
                      local display_val = p_obj:string()
                      if p_name == "fbL" or p_name == "fbR" then
                         display_val = math.floor(target_val_real * 100) .. "%"
                      elseif p_name == "speed_offsetL" or p_name == "speed_offsetR" then
                          display_val = string.format("%+.3f", target_val_real)
                      end
                      
                      G.popup.value = display_val
                      G.popup.active = true; G.popup.deadline = util.time() + 1.5
                   end
                end
             end
          end
       end)
       print("16n initialized.")
    end)
    
    G.loaded = true 
    print("Ncoco v9004 Ready.")
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
    elseif G.focus.source <= 10 then UI.draw_yellow_inspector(G, G.focus.source) 
    else UI.draw_coco_inspector(G, G.focus.source)
    end
  
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
  
  if G.focus.source and G.focus.last_dest then
    if n==3 then
      local s, dt = G.focus.source, G.focus.last_dest
      local val = util.clamp(G.patch[s][dt] + d/100, -1, 1)
      G.patch[s][dt] = val; SC.update_matrix(dt, G)
    end
    return
  end
  
  if G.focus.inspect_dest then
    local id = G.focus.inspect_dest
    
    if id == 6 or id == 13 then
       local side = (id == 6) and "L" or "R"
       if n == 1 then params:delta("stutter_chaos"..side, d)
       elseif n == 2 then params:delta("stutter_rate"..side, d)
       elseif n == 3 then 
          G.dest_gains[id] = util.clamp(G.dest_gains[id] + d/100, 0, 2)
          SC.update_dest_gains(G)
       end
       return
    end
    
    if n==3 then
      G.dest_gains[id] = util.clamp(G.dest_gains[id] + d/100, 0, 2)
      SC.update_dest_gains(G)
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
    -- NEW: Coco Output Slew Control
    elseif id == 11 or id == 12 then
       local side = (id==11) and "1" or "2"
       if n==3 then params:delta("coco"..side.."_slew", d) end
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
    if n==2 then params:delta("monitor_vol", d) end 
    if n==3 then params:delta("global_chaos", d) end
  end
end

function key(n,z)
  if not G.loaded then return end
  
  if G.focus.source and G.focus.last_dest and z==1 then
     if n==2 or n==3 then
        local s, dt = G.focus.source, G.focus.last_dest
        G.patch[s][dt] = G.patch[s][dt] * -1
        SC.update_matrix(dt, G)
        return
     end
  end
  
  if G.focus.source and (G.focus.source == 11 or G.focus.source == 12) and z==1 then
      if n==2 or n==3 then
         local id = (G.focus.source == 11) and 1 or 2
         local p_name = "coco"..id.."_out_mode"
         local curr = params:get(p_name)
         params:set(p_name, 3-curr) 
      end
      return
  end
  
  if G.focus.inspect_dest and z==1 then
     local id = G.focus.inspect_dest
     if id == 6 or id == 13 then
        local side = (id == 6) and "L" or "R"
        if n == 2 or n == 3 then
           local mode = params:get("skip_mode"..side)
           params:set("skip_mode"..side, 3 - mode) 
        end
        return
     end
  end

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
       if n==3 then 
          local v = params:get("bitsL"); params:set("bitsL", (v%3)+1)
          if is_link then params:set("bitsR", (v%3)+1) end
       end
    elseif G.focus.edit_r then 
       if n==3 then local v=params:get("bitsR"); params:set("bitsR", (v%3)+1) end
    else 
       if n==2 then 
         local v = 1 - params:get("recL")
         params:set("recL", v); params:set("recR", v)
       end 
    end
  end
end
