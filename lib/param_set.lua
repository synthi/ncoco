-- lib/param_set.lua v10018
-- CHANGELOG v9005:
-- 1. NEW: Added 'bleed_routing' (Pre/Post Filter) option.
-- fix load file message in sc

local Params = {}

function Params.init(SC, G)
  params:add_separator("Ncoco")
  
  params:add_group("GLOBALS", 5) -- Increased count
  params:add_control("global_vol", "Master Vol", controlspec.new(0, 2, "lin", 0, 1))
  params:set_action("global_vol", function(x) params:set("vol_l", x); params:set("vol_r", x) end)
  
  params:add_control("monitor_vol", "Monitor Level", controlspec.new(0, 1.2, "lin", 0, 0.0))
  params:set_action("monitor_vol", function(x) SC.set_monitor_level(x) end)
  
  params:add_control("global_chaos", "Global Chaos", controlspec.new(0, 1, "lin", 0, 0))
  params:set_action("global_chaos", function(x) SC.set_global_chaos(x) end)
  
  params:add_control("tape_drift", "Tape Drift", controlspec.new(0, 1, "lin", 0.0001, 0.5))
  params:set_action("tape_drift", function(x) engine.driftAmt(x * 0.01) end)

  -- [NEW] Bleed Routing
  params:add_option("bleed_routing", "Bleed Routing", {"Pre-Filter", "Post-Filter"}, 1)
  params:set_action("bleed_routing", function(x) engine.bleedPost(x-1) end)

  params:add_group("TAPE OPS", 7)
  params:add_option("tape_target", "Target", {"Left", "Right", "Both"}, 3)
  
  params:add_control("tape_len_L", "Loop Length L", controlspec.new(0.01, 60, "exp", 0, 8.0, "s"))
  params:set_action("tape_len_L", function(x) engine.loopLenL(x) end)
  
  params:add_control("tape_len_R", "Loop Length R", controlspec.new(0.01, 60, "exp", 0, 8.0, "s"))
  params:set_action("tape_len_R", function(x) engine.loopLenR(x) end)
  
  params:add_control("tape_len", "Loop Length (Legacy)", controlspec.new(0.1, 60, "lin", 0.1, 8.0))
  params:set_action("tape_len", function(x) 
     params:set("tape_len_L", x)
     params:set("tape_len_R", x)
  end)
  params:hide("tape_len")
  
  params:add_trigger("save_tape", "Save New Tape")
  params:set_action("save_tape", function() if params.action_write then params.action_write() end end)
  
  params:add{type="file", id="load_tape", name="Load Tape", path=_path.audio, action=function(path) 
    -- [FIX] Security check: Ignore folders and non-audio files
    if path and path ~= "cancel" and path ~= "" and string.sub(path, -1) ~= "/" then
       -- Check extension
       if string.find(string.lower(path), "%.wav") or string.find(string.lower(path), "%.aif") then
           local t = params:get("tape_target")
           if t==1 or t==3 then engine.read_tape(1, path) end 
           if t==2 or t==3 then engine.read_tape(2, path) end 
       end
    end
  end}
  
  params:add_trigger("clear_tape", "Clear Tape")
  params:set_action("clear_tape", function() 
    local t = params:get("tape_target")
    if t==1 or t==3 then engine.clear_tape(0) end
    if t==2 or t==3 then engine.clear_tape(1) end
  end)

  -- 2. COCO CHANNEL STRIPS
  for i=1, 2 do
    local s = (i==1) and "L" or "R"
    local num = (i==1) and "1" or "2"
    
    params:add_group("COCO "..num, 17) 
    
    params:add_control("vol_"..string.lower(s), "Volume "..num, controlspec.new(0, 2.0, "lin", 0, 1.0))
    params:set_action("vol_"..string.lower(s), function(x) SC.set_amp(i, x) end)

    params:add_control("preamp"..s, "Preamp "..num, controlspec.new(1.0, 20.0, "lin", 0, 1.0))
    params:set_action("preamp"..s, function(x) SC.set_preamp(i,x) end)
    params:add_control("envSlew"..s, "Env Slew "..num, controlspec.new(0.001, 1.0, "exp", 0, 0.05))
    params:set_action("envSlew"..s, function(x) SC.set_env_slew(i,x) end)
    
    params:add_control("speed"..s, "Speed "..num, controlspec.new(0.001, 3.0, "lin", 0, 1.0))
    params:set_action("speed"..s, function(x) SC.set_speed(i, x) end)
    
    params:add_control("speed_offset"..s, "Speed Offset "..num, controlspec.new(-0.5, 0.5, "lin", 0, 0.0))
    params:set_action("speed_offset"..s, function(offset) 
       local base = G.coco[i].base_speed or 1.0
       params:set("speed"..s, base + offset)
    end)
    
    params:add_control("fb"..s, "Feedback "..num, controlspec.new(0, 1.2, "lin", 0, 0.85))
    params:set_action("fb"..s, function(x) SC.set_feedback(i,x) end)
    
    params:add_control("filt"..s, "Filter "..num, controlspec.new(-1, 1, "lin", 0, 0))
    params:set_action("filt"..s, function(x) SC.set_filter(i,x) end)
    
    params:add_option("bits"..s, "Bits "..num, {"8bit", "12bit", "16bit"}, 1)
    params:set_action("bits"..s, function(x) 
       local b = (x==1) and 8 or ((x==2) and 12 or 16)
       SC.set_bitdepth(i,b) 
    end)
    
    params:add_option("coco"..num.."_out_mode", "Out Mode "..num, {"Envelope", "Audio"}, 1)
    params:set_action("coco"..num.."_out_mode", function(x)
       SC.set_coco_out_mode(i, x-1) 
    end)
    
    params:add_control("coco"..num.."_slew", "Out Slew "..num, controlspec.new(0.001, 1.5, "exp", 0, 0.1))
    params:set_action("coco"..num.."_slew", function(x) SC.set_coco_slew(i, x) end)
    
    params:add_binary("rec"..s, "Rec "..num, "toggle", 0)
    params:set_action("rec"..s, function(x) SC.set_rec(i,x) end)
    params:add_binary("flip"..s, "Flip "..num, "toggle", 0)
    params:set_action("flip"..s, function(x) SC.set_flip(i, x) end)
    params:add_binary("skip"..s, "Skip "..num, "momentary", 0)
    params:set_action("skip"..s, function(x) SC.set_skip(i,x) end)
    
    params:add_option("skip_mode"..s, "Skip Mode "..num, {"Single Jump", "Auto Repeat"}, 1)
    params:set_action("skip_mode"..s, function(x) 
      if s=="L" then engine.skipModeL(x-1) else engine.skipModeR(x-1) end
      
      if x == 1 then
         params:hide("stutter_rate"..s)
         params:hide("stutter_chaos"..s)
      else
         params:show("stutter_rate"..s)
         params:show("stutter_chaos"..s)
      end
      _menu.rebuild_params()
    end)

    params:add_control("stutter_rate"..s, "Repeat Rate "..num, controlspec.new(0, 1, "lin", 0, 0.3))
    params:set_action("stutter_rate"..s, function(x)
       local val
       if x < 0.5 then
          val = util.linlin(0, 0.5, 0.001, 0.030, x)
       else
          val = util.linlin(0.5, 1.0, 0.030, 0.350, x)
       end
       if s=="L" then engine.stutterRateL(val) else engine.stutterRateR(val) end
    end)

    params:add_control("stutter_chaos"..s, "Repeat Chaos "..num, controlspec.new(0, 1, "lin", 0, 0, "%"))
    params:set_action("stutter_chaos"..s, function(x)
       if s=="L" then engine.stutterChaosL(x) else engine.stutterChaosR(x) end
    end)
    
    params:hide("stutter_rate"..s)
    params:hide("stutter_chaos"..s)
    
    params:add_control("pan"..((i==1) and "_l" or "_r"), "Pan "..num, controlspec.new(-1, 1, "lin", 0, (i==1) and -0.5 or 0.5))
    params:set_action("pan"..((i==1) and "_l" or "_r"), function(x) SC.set_pan(i,x) end)
  end
  
  -- 3. HEXAQUANTUS
  for i=1, 6 do
    params:add_group("PETAL "..i, 5)
    
    params:add_option("p"..i.."range", "Range", {"LFO", "Audio"}, 1)
    params:set_action("p"..i.."range", function(x)
       if x == 1 then
         params:show("p"..i.."f_lfo")
         params:hide("p"..i.."f_aud")
         SC.set_petal_freq(i, params:get("p"..i.."f_lfo"))
       else
         params:hide("p"..i.."f_lfo")
         params:show("p"..i.."f_aud")
         SC.set_petal_freq(i, params:get("p"..i.."f_aud"))
       end
       _menu.rebuild_params()
    end)

    params:add_control("p"..i.."f_lfo", "Freq (LFO)", controlspec.new(0.01, 20, "exp", 0, 1))
    params:set_action("p"..i.."f_lfo", function(x) 
      if params:get("p"..i.."range") == 1 then SC.set_petal_freq(i,x) end 
    end)
    
    params:add_control("p"..i.."f_aud", "Freq (Aud)", controlspec.new(20, 2000, "exp", 0, 200))
    params:set_action("p"..i.."f_aud", function(x) 
      if params:get("p"..i.."range") == 2 then SC.set_petal_freq(i,x) end 
    end)
    params:hide("p"..i.."f_aud") 

    params:add_control("p"..i.."chaos", "Chaos", controlspec.new(0, 1, "lin", 0, 0))
    params:set_action("p"..i.."chaos", function(x) SC.set_petal_chaos(i,x) end)
    
    params:add_option("p"..i.."shape", "Shape", {"Tri", "Castle"}, 1)
    params:set_action("p"..i.."shape", function(x) SC.set_petal_shape(i,x-1) end)
  end
end

return Params
