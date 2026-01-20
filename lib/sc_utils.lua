-- lib/sc_utils.lua v9004
-- CHANGELOG v9004:
-- 1. ADDED: set_coco_slew command with safety check.

local SC = {}

local dest_names = {
  [1]="mod_speedL", [2]="mod_ampL", [3]="mod_fbL", [4]="mod_filtL", 
  [5]="mod_flipL", [6]="mod_skipL", [7]="mod_recL",
  [8]="mod_speedR", [9]="mod_ampR", [10]="mod_fbR", [11]="mod_filtR", 
  [12]="mod_flipR", [13]="mod_skipR", [14]="mod_recR",
  [15]="mod_p1", [16]="mod_p2", [17]="mod_p3", 
  [18]="mod_p4", [19]="mod_p5", [20]="mod_p6",
  [21]="mod_volL", [22]="mod_volR",
  [23]="mod_audioInL", [24]="mod_audioInR"
}

function SC.update_matrix(dest_id, G)
  local args = {}
  for src=1, 12 do table.insert(args, G.patch[src][dest_id]) end
  local cmd = dest_names[dest_id]
  if cmd and engine[cmd] then engine[cmd](table.unpack(args)) end
end

function SC.update_dest_gains(G)
  if engine.dest_gains then engine.dest_gains(table.unpack(G.dest_gains)) end
end

function SC.set_speed(id, val) 
  local cmd = id==1 and "speedL" or "speedR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_rec(id, val)
  local cmd = id==1 and "recL" or "recR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_flip(id, val)
  local cmd = id==1 and "flipL" or "flipR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_skip(id, val)
  local cmd = id==1 and "skipL" or "skipR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_feedback(id, val)
  local cmd = id==1 and "fbL" or "fbR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_bitdepth(id, val)
  local cmd = id==1 and "bitDepthL" or "bitDepthR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_filter(id, val)
  local cmd = id==1 and "filtL" or "filtR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_amp(id, val)
  local cmd = id==1 and "ampL" or "ampR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_pan(id, val)
  local cmd = id==1 and "panL" or "panR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_petal_freq(id, val)
  local cmd = "p"..id.."f"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_petal_chaos(id, val)
  local cmd = "p"..id.."chaos"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_petal_shape(id, val)
  local cmd = "p"..id.."shape"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_preamp(id, val)
  local cmd = id==1 and "preampL" or "preampR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_env_slew(id, val)
  local cmd = id==1 and "envSlewL" or "envSlewR"
  if engine[cmd] then engine[cmd](val) end
end

function SC.set_loop_len(val)
  if engine.loopLen then engine.loopLen(val) end
end

function SC.set_monitor_level(val)
   if engine.monitorLevel then engine.monitorLevel(val) end
end

function SC.set_global_chaos(val)
   if engine.global_chaos then engine.global_chaos(val) end
end

function SC.set_coco_out_mode(id, val)
   if id==1 and engine.coco1_out_mode then engine.coco1_out_mode(val) end
   if id==2 and engine.coco2_out_mode then engine.coco2_out_mode(val) end
end

-- NEW v9004
function SC.set_coco_slew(id, val)
   local cmd = id==1 and "cocoSlewL" or "cocoSlewR"
   if engine[cmd] then engine[cmd](val) end
end

return SC