-- lib/sc_utils.lua v1005
-- CHANGELOG v1005:
-- 1. Added update_dest_gains function.

local SC = {}

local dest_names = {
  [1]="mod_speedL", [2]="mod_ampL", [3]="mod_fbL", [4]="mod_filtL", 
  [5]="mod_flipL", [6]="mod_skipL", [7]="mod_recL",
  [8]="mod_speedR", [9]="mod_ampR", [10]="mod_fbR", [11]="mod_filtR", 
  [12]="mod_flipR", [13]="mod_skipR", [14]="mod_recR",
  [15]="mod_p1", [16]="mod_p2", [17]="mod_p3", 
  [18]="mod_p4", [19]="mod_p5", [20]="mod_p6"
}

function SC.update_matrix(dest_id, G)
  local args = {}
  for src=1, 10 do table.insert(args, G.patch[src][dest_id]) end
  local cmd = dest_names[dest_id]
  if cmd and engine[cmd] then engine[cmd](table.unpack(args)) end
end

function SC.update_dest_gains(G)
  if engine.dest_gains then engine.dest_gains(table.unpack(G.dest_gains)) end
end

function SC.set_speed(id, val) engine[id==1 and "speedL" or "speedR"](val) end
function SC.set_rec(id, val) engine[id==1 and "recL" or "recR"](val) end
function SC.set_flip(id, val) engine[id==1 and "flipL" or "flipR"](val) end
function SC.set_skip(id, val) engine[id==1 and "skipL" or "skipR"](val) end
function SC.set_feedback(id, val) engine[id==1 and "fbL" or "fbR"](val) end
function SC.set_bitdepth(id, val) engine[id==1 and "bitDepthL" or "bitDepthR"](val) end
function SC.set_dolby(id, val) engine[id==1 and "dolbyL" or "dolbyR"](val) end
function SC.set_filter(id, val) engine[id==1 and "filtL" or "filtR"](val) end
function SC.set_amp(id, val) engine[id==1 and "ampL" or "ampR"](val) end
function SC.set_pan(id, val) engine[id==1 and "panL" or "panR"](val) end

function SC.set_petal_freq(id, val) engine["p"..id.."f"](val) end
function SC.set_petal_chaos(id, val) engine["p"..id.."chaos"](val) end
function SC.set_petal_shape(id, val) engine["p"..id.."shape"](val) end

function SC.set_preamp(id, val) engine[id==1 and "preampL" or "preampR"](val) end
function SC.set_env_slew(id, val) engine[id==1 and "envSlewL" or "envSlewR"](val) end
function SC.set_loop_len(val) engine.loopLen(val) end

return SC
