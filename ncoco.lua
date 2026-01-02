-- ncoco.lua v600 (GOLD MASTER)
engine.name = 'Ncoco'

local status, G = pcall(include, 'ncoco/lib/globals')
if not status then print("CRITICAL: globals missing"); return end
local status, SC = pcall(include, 'ncoco/lib/sc_utils')
local status, GridNav = pcall(include, 'ncoco/lib/grid_nav')
local status, UI = pcall(include, 'ncoco/lib/ui')
local status, _16n = pcall(include, 'ncoco/lib/16n')

local g = grid.connect()
local m = midi.connect()
local grid_metro, screen_metro

function init()
  GridNav.init_map(G)

  osc.event = function(path, args, from)
    if path == '/update' then
      G.coco[1].pos = args[1]; G.coco[2].pos = args[2]
      G.coco[1].gate_rec = args[3]; G.coco[2].gate_rec = args[4]
      G.coco[1].gate_flip = args[5]; G.coco[2].gate_flip = args[6]
      G.coco[1].gate_skip = args[7]; G.coco[2].gate_skip = args[8]
      for i=1, 6 do G.sources_val[i] = args[8+i] end
      G.sources_val[7] = args[15]
      G.sources_val[8] = args[16]
    end
  end

  params:add_separator("NCOCO v600")
  
  params:add_control("global_vol", "Master Vol", controlspec.new(0, 2, "lin", 0, 1))
  params:set_action("global_vol", function(x) SC.set_amp(1, x); SC.set_amp(2, x) end)
  
  params:add_control("global_chaos", "Global Chaos", controlspec.new(0, 1, "lin", 0, 0))
  params:set_action("global_chaos", function(x) 
    for i=1,6 do 
      G.petals[i].chaos = x 
      SC.set_petal_chaos(i, x) 
    end
  end)
  
  params:add_group("TAPE OPS", 4)
  params:add_option("tape_target", "Target", {"Left", "Right", "Both"}, 3)
  params:add_control("tape_len", "Loop Length", controlspec.new(0.1, 60, "lin", 0.1, 8.0, "s"))
  params:set_action("tape_len", function(x) SC.set_loop_len(x) end)
  params:add_trigger("save_tape", "Save New Tape")
  params:set_action("save_tape", function() save_manual_tape() end)
  params:add_file("load_tape", "Load Tape")
  params:set_action("load_tape", function(f) load_manual_tape(f) end)

  params:add_text("tape_path_l", "Tape L Path", ""); params:hide("tape_path_l")
  params:add_text("tape_path_r", "Tape R Path", ""); params:hide("tape_path_r")

  params.action_write = function(filename, name, number)
    local t = os.date("%Y%m%d_%H%M%S")
    local pathL = _path.data .. "ncoco/tapeL_" .. t .. ".wav"
    local pathR = _path.data .. "ncoco/tapeR_" .. t .. ".wav"
    local len = params:get("tape_len")
    engine.write_tape(0, pathL, len)
    engine.write_tape(1, pathR, len)
    params:set("tape_path_l", pathL); params:set("tape_path_r", pathR)
  end

  params.action_read = function(filename, silent, number)
    local pathL = params:get("tape_path_l")
    local pathR = params:get("tape_path_r")
    if util.file_exists(pathL) then engine.read_tape(0, pathL) end
    if util.file_exists(pathR) then engine.read_tape(1, pathR) end
  end

  SC.set_rec(1, 0); SC.set_rec(2, 0)
  SC.set_feedback(1, 0.8); SC.set_feedback(2, 0.8)
  SC.set_loop_len(8.0)
  SC.set_bitdepth(1, 8); SC.set_bitdepth(2, 8) 

  grid_metro = metro.init(); grid_metro.time = 1/30
  grid_metro.event = function() pcall(GridNav.redraw, G, g) end
  grid_metro:start()

  screen_metro = metro.init(); screen_metro.time = 1/15
  screen_metro.event = function() redraw() end
  screen_metro:start()

  _16n.init(function(msg) 
    local id = _16n.cc_2_slider_id(msg.cc)
    if id and id<=6 then params:set("p"..id.."f", util.linexp(0, 127, 0.1, 20, msg.val)) end
  end)
  G.loaded = true 
end

function save_manual_tape()
  local t = os.date("%Y%m%d_%H%M%S")
  local target = params:get("tape_target")
  local len = params:get("tape_len")
  if target == 1 or target == 3 then engine.write_tape(0, _path.data .. "ncoco/L_" .. t .. ".wav", len) end
  if target == 2 or target == 3 then engine.write_tape(1, _path.data .. "ncoco/R_" .. t .. ".wav", len) end
  print("Tape Saved.")
end

function load_manual_tape(file)
  if file == "-" then return end
  local target = params:get("tape_target")
  if target == 1 or target == 3 then engine.read_tape(0, file) end
  if target == 2 or target == 3 then engine.read_tape(1, file) end
  print("Tape Loaded.")
end

function redraw()
  UI.update_histories(G) -- FIX: Called every frame
  screen.clear()
  if G.focus.source then
    if G.focus.last_dest then UI.draw_patch_menu(G)
    elseif G.focus.source <= 6 then UI.draw_petal_inspector(G, G.focus.source)
    elseif G.focus.source <= 8 then UI.draw_env_inspector(G, G.focus.source) end
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

function g.key(x,y,z) GridNav.key(G, g, x,y,z) end

function enc(n,d)
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
      local p = G.petals[id]
      if n==2 then 
         local min = (p.range==0) and 0.01 or 20
         local max = (p.range==0) and 20 or 2000
         p.freq = util.clamp(p.freq + (p.range==0 and d/100 or d), min, max)
         SC.set_petal_freq(id, p.freq)
      elseif n==3 then
         p.chaos = util.clamp(p.chaos + d/100, 0, 1)
         SC.set_petal_chaos(id, p.chaos)
      end
    elseif id <= 8 then 
      local inp = G.input[id-6]
      if n==2 then inp.preamp = util.clamp(inp.preamp + d/10, 1.0, 20.0); SC.set_preamp(id-6, inp.preamp)
      elseif n==3 then inp.slew = util.clamp(inp.slew + d/100, 0.001, 1.0); SC.set_env_slew(id-6, inp.slew) end
    end
    return
  end

  local is_link = G.focus.edit_l and G.focus.edit_r
  
  if G.focus.edit_l or is_link then
    local c = G.coco[1]
    if n==1 then 
       c.filt = util.clamp(c.filt + d/100, -1, 1); SC.set_filter(1, c.filt)
       if is_link then G.coco[2].filt=c.filt; SC.set_filter(2, c.filt) end
    elseif n==2 then 
       c.speed = util.clamp(c.speed + d/100, 0.001, 3.0)
       SC.set_speed(1, math.abs(c.speed) * c.flip)
       if is_link then G.coco[2].speed=c.speed; SC.set_speed(2, math.abs(c.speed) * c.flip) end
    elseif n==3 then 
       c.vol_fb = util.clamp(c.vol_fb + d/100, 0, 1.2); SC.set_feedback(1, c.vol_fb)
       if is_link then G.coco[2].vol_fb=c.vol_fb; SC.set_feedback(2, c.vol_fb) end
    end
  elseif G.focus.edit_r then
    local c = G.coco[2]
    if n==1 then c.filt = util.clamp(c.filt + d/100, -1, 1); SC.set_filter(2, c.filt)
    elseif n==2 then c.speed = util.clamp(c.speed + d/100, 0.001, 3.0); SC.set_speed(2, math.abs(c.speed) * c.flip)
    elseif n==3 then c.vol_fb = util.clamp(c.vol_fb + d/100, 0, 1.2); SC.set_feedback(2, c.vol_fb) end
  else
    if n==1 then params:delta("global_vol", d) end
    if n==2 then 
      for i=1,2 do local c=G.coco[i]; c.speed=util.clamp(c.speed+d/100,0.001,3.0); SC.set_speed(i,math.abs(c.speed)*c.flip) end
    end
    if n==3 then params:delta("global_chaos", d) end
  end
end

function key(n,z)
  if n==1 then return end 
  if z==1 then
    if G.focus.source and G.focus.source <= 6 then
      local id = G.focus.source; local p = G.petals[id]
      if n==2 then p.range=1-p.range; SC.set_petal_freq(id, p.freq)
      elseif n==3 then p.shape=1-p.shape; SC.set_petal_shape(id, p.shape) end
      return
    end
    
    local is_link = G.focus.edit_l and G.focus.edit_r
    if G.focus.edit_l or is_link then 
       if n==2 then G.coco[1].dolby=(G.coco[1].dolby+1)%3; SC.set_dolby(1,G.coco[1].dolby) end
       if n==3 then 
          local c = G.coco[1]
          c.bits = (c.bits==8) and 12 or (c.bits==12 and 16 or 8)
          SC.set_bitdepth(1, c.bits)
          if is_link then G.coco[2].bits=c.bits; SC.set_bitdepth(2, c.bits) end
       end
    elseif G.focus.edit_r then 
       if n==2 then G.coco[2].dolby=(G.coco[2].dolby+1)%3; SC.set_dolby(2,G.coco[2].dolby) end
       if n==3 then local c=G.coco[2]; c.bits=(c.bits==8) and 12 or (c.bits==12 and 16 or 8); SC.set_bitdepth(2, c.bits) end
    else 
       if n==2 then local r=1-G.coco[1].rec; G.coco[1].rec=r; G.coco[2].rec=r; SC.set_rec(1,r); SC.set_rec(2,r) end 
    end
  end
end