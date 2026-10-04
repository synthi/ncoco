-- lib/globals.lua v3.07
-- v3.07: SOLO la etiqueta de version. El codigo de este archivo NO se toco.
-- CHANGELOG v3.01:
-- 1. NEW: M.last_osc_time — marca del ultimo /update recibido de SC. La usa
--    el detector de OSC parado en ncoco.lua. NO actua: solo registra.
-- CHANGELOG v2.02:
-- 1. CLEANUP: Removed M.fader_inverted (moved to 16n.lua as _16n.inverted).

-- CLEANUP (v3.00 Fase 1): removed unused state (MAX/HIGH/MED/DIM/OFF_BRIGHT,
--   state_file, tape_path_1/2, M.input) — zero references project-wide.
--   M.input was shadowed by params: preamp/envSlew live in the PARAMETERS menu.
--   M.FADER_BG is kept intentionally (possible legacy/preset meaning).
--
-- CHANGELOG v2.01:
-- 1. META: Version bump to 2.01 (project-wide alignment).
-- CHANGELOG v9000:
-- 1. DATA: Increased Scope History and Sources Values arrays to 12 (to support Coco Outs).
-- 2. MATRIX: Increased patch matrix size to 12 sources.

local M = {}

M.loaded = false

M.SPEED_TABLE = {0.002, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0}
M.FADER_BG = {2, 2, 2, 4, 2, 2, 2}

M.coco = {
  { pos=0, gate_rec=0, gate_flip=1, gate_skip=0, real_speed=1.0, out_level=0, base_speed=1.0 },
  { pos=0, gate_rec=0, gate_flip=1, gate_skip=0, real_speed=1.0, out_level=0, base_speed=1.0 }
}

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
-- [v3.00] Marca de tiempo del ultimo /update recibido de SuperCollider.
-- Sirve para el watchdog del grid: si el OSC deja de llegar, los valores se
-- congelan y la rejilla muestra lo ultimo recibido (tipicamente al maximo).
M.last_osc_time = 0 
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