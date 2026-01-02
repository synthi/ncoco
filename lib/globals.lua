-- lib/globals.lua v600
local M = {}

M.loaded = false 

-- Palette
M.MAX_BRIGHT = 15
M.HIGH_BRIGHT = 10 
M.MED_BRIGHT = 6
M.DIM_BRIGHT = 4
M.OFF_BRIGHT = 2

-- Speed Table (Center-Out Reference)
-- 1=Drift, 2=-2oct, 3=-1oct, 4=1x(Anchor), 5=+5th, 6=+1oct, 7=+Tritave
M.SPEED_TABLE = {0.002, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0}

-- Fader Background (Reference at index 4)
M.FADER_BG = {2, 2, 2, 4, 2, 2, 2}

M.coco = {
  { speed=1.0, speed_idx=4, vol_in=1.0, vol_fb=0.8, rec=0, flip=1, skip=0, pos=0, env=0, dolby=0, bits=8, gate_rec=0, filt=0 },
  { speed=1.0, speed_idx=4, vol_in=1.0, vol_fb=0.8, rec=0, flip=1, skip=0, pos=0, env=0, dolby=0, bits=8, gate_rec=0, filt=0 }
}

-- Input Params
M.input = { { preamp=1.0, slew=0.05 }, { preamp=1.0, slew=0.05 } }

-- Ring Buffers
M.TRAIL_SIZE = 10
M.trails = { {}, {} } 
for i=1, M.TRAIL_SIZE do M.trails[1][i]=0; M.trails[2][i]=0 end
M.trail_head = {1, 1}

M.SCOPE_LEN = 60
M.scope_history = {}
M.sources_val = {0,0,0,0,0,0,0,0}
for i=1, 8 do 
  M.scope_history[i] = {}
  for j=1, M.SCOPE_LEN do M.scope_history[i][j] = 0 end
end
M.scope_head = 1

M.petals = {}
for i=1, 6 do M.petals[i] = { freq=0.5, chaos=0.0, shape=0, range=0 } end

-- Matrix (20 Destinos)
M.patch = {}
for s=1, 8 do
  M.patch[s] = {}
  for d=1, 20 do M.patch[s][d] = 0.0 end
end

M.focus = {
  edit_l = false, edit_r = false,
  source = nil, dest = nil, last_dest = nil, dest_timer = 0, inspect_dest = nil
}

M.grid_map = {}

return M