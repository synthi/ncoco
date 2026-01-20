-- lib/globals.lua v9000
-- CHANGELOG v9000:
-- 1. DATA: Increased Scope History and Sources Values arrays to 12 (to support Coco Outs).
-- 2. MATRIX: Increased patch matrix size to 12 sources.

local M = {}

M.loaded = false 
M.state_file = _path.data .. "ncoco/patch_state.data"

M.tape_path_1 = ""
M.tape_path_2 = ""

M.MAX_BRIGHT = 15
M.HIGH_BRIGHT = 10 
M.MED_BRIGHT = 6
M.DIM_BRIGHT = 4
M.OFF_BRIGHT = 2

M.SPEED_TABLE = {0.002, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0}
M.FADER_BG = {2, 2, 2, 4, 2, 2, 2}

M.coco = {
  { pos=0, gate_rec=0, gate_flip=1, gate_skip=0, real_speed=1.0, out_level=0, base_speed=1.0 },
  { pos=0, gate_rec=0, gate_flip=1, gate_skip=0, real_speed=1.0, out_level=0, base_speed=1.0 }
}

M.input = { { preamp=1.0, slew=0.05 }, { preamp=1.0, slew=0.05 } }

M.sequencers = {}
for i=1, 4 do
  M.sequencers[i] = {
    data = {},
    state = 0,
    playhead = 0.0,
    last_cpu_time = 0,
    start_time = 0,
    duration = 0,
    double_click_timer = nil
  }
end

M.snapshots = {nil, nil, nil, nil} 
M.active_snapshot = 0 

M.fader_latched = {}
for i=1, 16 do M.fader_latched[i] = false end

M.popup = {
  active = false,
  name = "",
  value = "",
  deadline = 0
}

M.TRAIL_SIZE = 10
M.trails = { {}, {} } 
for i=1, M.TRAIL_SIZE do M.trails[1][i]=0; M.trails[2][i]=0 end
M.trail_head = {1, 1}

M.SCOPE_LEN = 128
M.scope_history = {}
-- INCREASED TO 12
M.sources_val = {0,0,0,0,0,0,0,0,0,0,0,0} 
for i=1, 12 do 
  M.scope_history[i] = {}
  for j=1, M.SCOPE_LEN do M.scope_history[i][j] = 0 end
end
M.scope_head = 1

M.petals = {} 
for i=1, 6 do M.petals[i] = { freq=0.5, chaos=0.0 } end

-- EXPANDED MATRIX (12 Sources x 24 Dest)
M.patch = {}
for s=1, 12 do
  M.patch[s] = {}
  for d=1, 24 do M.patch[s][d] = 0.0 end
end

M.dest_gains = {}
for d=1, 24 do M.dest_gains[d] = 1.0 end

M.focus = {
  edit_l = false, edit_r = false,
  source = nil, dest = nil, last_dest = nil, dest_timer = 0, inspect_dest = nil
}

M.grid_map = {}

return M