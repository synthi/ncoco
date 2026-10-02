-- ncoco.lua v3.03
-- CHANGELOG v3.03 (FALSA ALARMA DEL LATIDO + PARPADEO DEL GRID):
-- 1. FIX: v3.02 disparaba "GRID RECOVERY (sin redraw)" sobre una rejilla SANA.
--    Visto en maiden: "sin redraw desde hace 4.7s -> recuperando" y luego otra
--    vez a 3.2s; el grid parpadeo pero siguio funcionando. CAUSA VERIFICADA en
--    norns matron/src/events.cc: hay UN SOLO event_loop() con UNA sola cola
--    FIFO, y w_handle_metro() y w_handle_clock_resume() llaman al MISMO estado
--    Lua (lvm). Metro y latido estan SERIALIZADOS: si cualquier manejador de
--    Lua se bloquea N segundos se paran LOS DOS, y al reanudarse el latido
--    mide util.time() (reloj de pared) frente a un last_redraw de ANTES del
--    bloqueo. Ve N segundos y decide "congelado" cuando en realidad se trataba
--    de un bloqueo transitorio del bucle, del que la rejilla se recuperaba sola
--    en el siguiente tick.
-- 2. FIX: el latido mide ahora SU PROPIO atraso (late). late >= 1s prueba que
--    el cuello es el bucle de Lua entero y NO la rejilla => se informa y NO se
--    toca la rejilla. Con el latido puntual, la decision exige DOS avisos
--    separados por un ciclo entero antes de recuperar. La logica esta en
--    GridNav.heartbeat_step(), funcion pura y testeada.
-- 3. NEW: grid_ticks, contador de ticks de metro. El mensaje de maiden lleva ya
--    la prueba en vez de una sospecha: "+0 ticks" = el metro no disparo;
--    ">0 ticks" = el redraw no llega a terminar.
-- 4. FIX: PARPADEO. recover_grid() hacia g:all(0): apagaba los 128 LEDs y el
--    siguiente tick los repintaba (~67ms). Era EL FLASH. Verificado en
--    matron/src/device/device_monome.cc, dev_monome_grid_set_led(): se marca
--    md->dirty[q] = true SIN comparar el valor, asi que reset_cache() (-1 en
--    las 128 celdas) ya fuerza el reenvio completo de los 4 quads en el
--    siguiente redraw, sin el frame en negro. Ademas la rejilla CONSERVA su
--    imagen durante una congelacion real en vez de quedarse apagada.
-- 5. TEST: tools/verify_p28_heartbeat.lua (4 escenarios + control negativo que
--    demuestra que la regla de v3.02 si disparaba recuperacion en el caso
--    transitorio).
-- 6. VERSION: todo el proyecto pasa a 3.03.
-- v3.02 — UNIFICACIÓN DE VERSIONES. Antes cada archivo llevaba su propio
-- 1. FIX: snapshots borrados por toques CORTOS y seguidos (el fallo "sin
--    patron claro"). La corrutina de un toque VIEJA comparaba un sello
--    COMPARTIDO por todos los toques; al despertar durante un toque NUEVO veia
--    ese sello (distinto de 0) y borraba el snapshot aunque el toque durara
--    milisegundos. Cada corrutina lleva ahora SU PROPIO sello. Mantener >1.6s
--    sigue borrando igual: el gesto de borrado por diseño NO cambio.
--    Test: tools/verify_p26_snap_taps.lua (16 toques reales en 4.8s,
--    control negativo contra 45c06fd -> 6 fallos, 11 clear1 espurios).
-- 2. FIX: K2/K3. Deberian ser REC COCO 1 / REC COCO 2 en la pantalla principal.
--    Antes eran la MISMA linea (ponia recL y recR juntas), asi que K2 grababa
--    los DOS cocos a la vez y K3 no hacia nada. Y el codigo se llegaba desde
--    DOS popups (fuentes 7..10 y destinos que no son SKIP), que no tenian
--    return: K2 "grababa" con el inspector abierto.
--    Test: tools/verify_p27_keys.lua (ejecuta key() real; control negativo
--    contra ee0ba94 -> 6 fallos, exactamente el sintoma reportado).
-- 3. FIX: inspector de SKIP. El titulo es SIEMPRE la etiqueta de la pagina
--    ("SKIP 1", no "SKIP 1: SINGLE") y el modo se muestra aparte como
--    "K2/K3: SINGLE". La pista "K2/3: MODE" se elimino porque a y=55 tocaba el
--    borde de la caja del scope (acaba en y=50).
-- 4. FIX: release de una tecla sin press previo hacia "util.time() - nil" ->
--    error de aritmetica dentro de la rejilla.
-- 5. VERSION: todo el proyecto pasa a 3.02.
-- v3.01 — UNIFICACIÓN DE VERSIONES. Antes cada archivo llevaba su propio
--   "vN.NN" y el banner del script quedó en v2.14 durante toda la v3.00: no
--   había una única fuente de verdad. Desde v3.01 TODOS los archivos del
--   proyecto comparten el mismo número, y NCOCO_VERSION (abajo) es la fuente
--   autoritativa de lo que se muestra al arrancar.
-- CHANGELOG v3.01:
-- 1. FIX: el latido (heartbeat) no se registraba en clock_ids, así que
--    cleanup() no lo cancelaba: quedaba corriendo tras cambiar de script.
--    Y cleanup() usaba ipairs sobre una tabla dispersa (1..5 y 7): se
--    detenía en el hueco. Ahora usa pairs. Es la MISMA trampa de ipairs que
--    rompió el 16n con midi.devices.
-- 2. FIX: refresh() del grid se llama siempre (ver lib/grid_nav.lua v2.06).
-- 3. NEW: VERSION centralizada (NCOCO_VERSION). Antes la versión estaba
--    dispersa en cada archivo y el banner quedó en v2.14 durante toda la v3.00.
-- 4. NEW: recuperacion del grid EN CALIENTE (recover_grid). Rehace lo que un
--    reinicio de norns le hace a la rejilla --reengancha el vport con
--    dispositivo, fuerza reenvio completo (all()+refresh) y reinicia el metro--
--    sin recargar el script. Se dispara sola ante "sin redraw >3s" y
--    "g.device nil" (estados que YA son el fallo, sin falsos positivos), y a
--    mano con >> recover_grid() desde maiden para el caso no detectable desde
--    Lua. El caso "el /update de SC se para" NO se toca: engine.load()
--    re-asignaria los buffers de 60 s y cortaria el audio.
-- 5. NEW: guardas or 0 en las 24 lecturas de /update (args[23]/[24] incluidos):
--    si SC manda menos argumentos, no reventaba el handler OSC.
-- CLEANUP v3.00 FASE 1 (no functional change):
-- 1. REVERTED: is_bipolar_param() + 2nd arg of normalize() restored (breaking
--    the 16n when normalize() came back to its 2-arg signature).
-- 2. /update: args[23]/[24] nil-guards use the same `or 0` style as the rest.
-- CHANGELOG v2.14:
-- 1. FIX: NICAM — 2× BLowPass4 anti-aliasing + 2× reconstrucción + TPDF dither.
-- 2. FIX: E4 bits text only visible in NICAM mode.
-- 3. FIX: GLOBALS group count 6→7 (16n_orient was outside).
-- CHANGELOG v2.13:
-- 1. REWRITE: "1bit CVSD" → "NICAM" (Block Floating Point + J.17).
-- 2. HARDCODE: DFM1 gain fijado a 0.32, param dfm1_gain eliminado.
-- 3. NEW: NICAM Bits L/R params (nicam_bits_l, nicam_bits_r), default 10.
-- CHANGELOG v2.05:
-- 1. FIX: Grid freeze recovery — logging, nuclear option (g:all(0)), g = grid.connect() on reconnect.
-- 2. FIX: 16n orientation now uses taper pivot 80/47 instead of inverting values.
-- 3. NEW: ADPCM 6-bit G.726 mode replaces 16-bit (bitDepth=14).
-- CHANGELOG v2.04:
-- 1. NEW: 16n fader orientation param (Normal/Inverted) via _16n.set_inverted().
-- 2. FIX: Uses _16n.normalize() with power curve for bipolar params (log-taper linearization).
-- CHANGELOG v2.03:
-- 1. FIX: Added math.randomseed() for random petal seeds at script start.
-- 2. FIX: Replaced recursive copy_table with shallow copy for safety.
-- 3. FIX: Clock IDs now tracked and cancelled in cleanup() to prevent leaks.
-- 4. FIX: Improved pcall(include) error messages for debugging.
-- 5. FIX: Added #args validation in OSC handler.
-- 6. OPT: Reduced sequencer tick rate from 100Hz to 30Hz.
-- CHANGELOG v2.02:
-- 1. NEW: Sequencers can now record/play snapshot button presses.
-- 2. FIX: Removed legacy snapshot comment (code was always present).
-- CHANGELOG v2.01:
-- 1. OPT: Sequencer simulated events skip g:led/g:refresh to reduce USB traffic.
-- CHANGELOG v2.00:
-- 1. FIX: Protected OSC handler with nil guards (args[N] or 0) to prevent grid freeze.
-- 2. FIX: Added error logging to grid_metro pcall for debugging grid redraw failures.
-- 3. OPT: Reduced auto-heal threshold from 60 to 30 frames for faster recovery.
-- CHANGELOG v9006:
-- 1. SYSTEM: Added Grid auto-refresh and cache reset to fix frozen LEDs.
-- 2. PRESET: Fixed params:default() placement for correct loading.
-- CHANGELOG v9004:
-- 1. ENC MAPPING: Added E3 control for Coco Output Slew when focusing on Sources 11/12.
-- 2. BASE: v9000.

engine.name = 'Ncoco'
-- [v3.01] Version centralizada. Antes cada archivo llevaba su "vN.NN" y el
-- banner del script se quedo en v2.14 durante toda la v3.00: no habia una
-- unica fuente de verdad. Esto es lo que se muestra al arrancar.
local NCOCO_VERSION = "3.03"

local function safe_include(name)
  local ok, result = pcall(include, name)
  if not ok then print("CRITICAL: " .. name .. " - " .. tostring(result)); return nil end
  return result
end
local G = safe_include('ncoco/lib/globals')
if not G then return end
local SC = safe_include('ncoco/lib/sc_utils')
local GridNav = safe_include('ncoco/lib/grid_nav')
local UI = safe_include('ncoco/lib/ui')
local _16n = safe_include('ncoco/lib/16n')
local Params = safe_include('ncoco/lib/param_set')
local Storage = safe_include('ncoco/lib/storage') 

-- DEFINED LOCAL METROS & CLOCK TRACKING
local g = grid.connect()
local grid_metro
local screen_metro
local clock_ids = {}
local grid_recover_cid   -- [v3.01] id del clock de recuperacion del grid

if not util.file_exists(_path.audio .. "ncoco") then
  util.make_dir(_path.audio .. "ncoco")
end

-- SNAPSHOT FUNCTIONS
local SNAP_NAMES = {"A", "B", "C", "D"}
local function shallow_copy_patch(t)
  -- Patch matrix is 12x24 numbers, no recursion needed
  local res = {}
  for s=1, 12 do
    res[s] = {}
    for d=1, 24 do
      res[s][d] = (t[s] and t[s][d]) or 0
    end
  end
  return res
end
function G.snap_capture()
  local data = {}
  data.patch = shallow_copy_patch(G.patch)
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
     -- v3.00 Fase 3: rellenar la matriz ENTERA y despues enviar una sola vez
     -- por destino. Antes se llamaba a update_matrix dentro del bucle de
     -- fuentes: 12x24 = 288 llamadas OSC, de las que 264 eran redundantes
     -- (el motor solo conserva la ultima de cada destino).
     -- VERIFICADO con tools/verify_p8_matrix.lua: el estado final en las 288
     -- celdas es identico. Ver ncoco.lua historial para el detalle.
     for s=1, 12 do
        for d=1, 24 do
           G.patch[s][d] = data.patch[s][d] or 0
        end
     end
     for d=1, 24 do
        SC.update_matrix(d, G)
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
local function is_bipolar_param(p_name)
   return p_name == "filtL" or p_name == "filtR" or
          p_name == "speed_offsetL" or p_name == "speed_offsetR" or
          p_name == "pan_l" or p_name == "pan_r"
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
       clock.sleep(1/30) 
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

-- [v3.01] RECUPERACION DE LA REJILLA EN CALIENTE (sin re-seleccionar el script).
-- Rehace, en vivo, lo que un reinicio de norns le hace a la rejilla. Cada paso
-- esta confrontado con el codigo oficial, no con una hipotesis:
--   1. REENGANCHE DE VPORT. grid.connect(n) devuelve Grid.vports[n] y su campo
--      .device lo pone Grid.update_devices() (grid.lua). Si el aparato reengancho
--      con otro nombre, queda en otro vport y el 1 se queda sin .device (eso
--      convierte cada g:led en un no-op silencioso, vport.lua).
--      GridNav.find_device_port() escanea los 4 vports y devuelve el que SI tiene
--      dispositivo; aqui se reengancha.
--   2. REENVIO COMPLETO SIN APAGAR (v3.03). Antes esto era g:all(0)+g:refresh():
--      mandaba TODOS los LEDs a 0 y el siguiente tick los repintaba. Ese frame
--      en negro ES el parpadeo que delato la falsa alarma del latido.
--      Verificado en matron/src/device/device_monome.cc, dev_monome_grid_set_led():
--         md->dirty[q] = true;    // se marca SIN mirar el valor anterior
--      Asi que GridNav.reset_cache() (-1 en las 128 celdas) hace que el
--      siguiente redraw reescriba TODAS y deje los 4 quads sucios: el
--      refresh() que cierra GridNav.redraw() manda el mapa completo. Mismo
--      reenvio garantizado, cero frame en negro, y durante una congelacion real
--      la rejilla CONSERVA su imagen en vez de quedarse apagada esperando.
--      Prueba empirica: reset_cache() solo ya se dispara cada 75 frames (5 s)
--      desde v2.04 y nunca ha parpadeado.
--   3. REINICIO DEL METRO. Metro:start() REUSA el mismo id (metro.lua: solo
--      metro.init() consume de Metro.available), asi que no hay fuga de ids.
--      Se hace fuera del propio callback (en el sistema clock) para no
--      re-entrar en el metro desde dentro de su evento.
-- NO se toca el motor de SuperCollider: el caso "el /update de SC se para" solo
-- lo rearma engine.load(), que re-asigna los buffers de 60 s y cortaria el audio
-- en directo. Ese caso se REGISTRA, no se "arregla" a ciegas.
local last_recover = 0
local grid_was_attached = true
local function recover_grid(reason)
   local now = util.time()
   if now - last_recover < 2.0 then return end      -- antirrebote
   last_recover = now
   print("GRID RECOVERY (" .. tostring(reason) .. ")")
   local port = GridNav.find_device_port()
   if port and g ~= grid.connect(port) then
      g = grid.connect(port)
      print("  -> reenganchado a vport " .. port)
   end
   -- [v3.03] SIN g:all(0): era eso lo que parpadeaba (ver comentario arriba).
   -- reset_cache() solo ya fuerza el reenvio completo en el proximo tick.
   GridNav.reset_cache()
   if grid_recover_cid then clock.cancel(grid_recover_cid) end
   grid_recover_cid = clock.run(function()
      clock.sleep(0.05)
      if grid_metro then grid_metro:stop(); grid_metro:start() end
   end)
   clock_ids[8] = grid_recover_cid
   grid_was_attached = (g.device ~= nil)
end
-- Disponible desde maiden para el caso que NO se puede detectar desde Lua
-- (congelado por debajo de Lua):  >> recover_grid()
_G.recover_grid = function() recover_grid("manual") end

function init()
  -- Seed random generator for unique petal sounds each session
  -- (PSETs overwrite these values on load, so consistency is preserved)
  math.randomseed(os.time())
  
  GridNav.init_map(G)
  Params.init(SC, G, _16n)
  
  params.action_write = function(filename, name, number) Storage.save(G, number) end
  params.action_read = function(filename, silent, number) Storage.load(G, SC, number) end

  osc.event = function(path, args, from)
    if path == '/update' then
      if #args < 24 then
         print("OSC WARNING: /update truncated (" .. tostring(#args) .. " args)")
      end
      G.coco[1].pos = args[1] or 0; G.coco[2].pos = args[2] or 0
      G.coco[1].gate_rec = args[3] or 0; G.coco[2].gate_rec = args[4] or 0
      G.coco[1].gate_flip = args[5] or 0; G.coco[2].gate_flip = args[6] or 0 
      G.coco[1].gate_skip = args[7] or 0; G.coco[2].gate_skip = args[8] or 0
      for i=1, 6 do G.sources_val[i] = (args[8+i] or 0) end
      G.sources_val[7] = (args[15] or 0); G.sources_val[8] = (args[16] or 0)
      G.sources_val[9] = (args[17] or 0); G.sources_val[10] = (args[18] or 0)
      G.coco[1].real_speed = (args[19] or 0); G.coco[2].real_speed = (args[20] or 0)
      G.coco[1].out_level = (args[21] or 0); G.coco[2].out_level = (args[22] or 0)
      
      G.sources_val[11] = (args[23] or 0)
      G.sources_val[12] = (args[24] or 0)
      -- [v3.00] El watchdog del grid necesita saber cuando llego el ultimo dato.
      G.last_osc_time = util.time()
      
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
    SC.set_mode(1, 0); SC.set_mode(2, 0)   -- 0 = 8bit (default)
    
    engine.skipModeL(0); engine.skipModeR(0)
    engine.driftAmt(0.005)

    for i=1, 6 do
      local seed_lfo = 0.2 + (math.random() * 0.9)
      local seed_aud = 100 + (math.random() * 500)
      params:set("p"..i.."f_lfo", seed_lfo)
      params:set("p"..i.."f_aud", seed_aud)
      SC.set_petal_freq(i, seed_lfo)
    end
    
    -- [FIX] Load last saved preset (overwriting random init values)
    params:default()
    
    for i=1, 4 do
       local cid = clock.run(function() run_sequencer(i, g) end)
       clock_ids[i] = cid
    end

    grid_metro = metro.init(); grid_metro.time = 1/15
    local grid_error_count = 0
    -- [v3.03] EVIDENCIA para el latido: ticks de metro realmente disparados.
    -- Con "+0 ticks" el metro no corrio; con "ticks > 0" el redraw no termino.
    -- Antes el latido solo podia decir "sin redraw" y adivinar el porque.
    local grid_ticks = 0
    -- [v3.00] WATCHDOG: el congelado del grid NO era un error de Lua, era que
    -- los valores dejaba de llegar. /update viene de SuperCollider via OSC; si
    -- ese hilo muere (SC se cuelga, el motor se cae), sources_val se queda con
    -- el ultimo valor recibido --tipicamente 1.0 => brillo maximo-- y como el
    -- redraw es diferencial, nunca se detecta cambio: la rejilla se queda fija
    -- pero SIGUE respondiendo a las pulsaciones. Eso es exactamente el sintoma.
    -- Detectar "no llegan datos" es lo que faltaba; el pcall de abajo solo
    -- detecta "el codigo de Lua falla", que es otro problema.
    local grid_stale_count = 0
    local osc_watch_start = util.time()
    local osc_never_warned = false
    grid_metro.event = function()
       grid_ticks = grid_ticks + 1
       local ok, err = pcall(GridNav.redraw, G, g)
       if not ok then
          grid_error_count = grid_error_count + 1
          print("GRID_REDRAW_ERROR [" .. grid_error_count .. "]: " .. tostring(err))
          GridNav.reset_cache()
          if grid_error_count >= 10 then
             print("GRID FREEZE DETECTED (redraw fallando) - recuperando")
             recover_grid("redraw error x10")
             grid_error_count = 0
          end
       else
          grid_error_count = 0
       end

       -- [v3.01] Detector de OSC parado. NO actua sobre SuperCollider.
       -- REALIDAD verificada (lib/Engine_Ncoco.sc): /update lo emite
       --   SendReply.kr(Impulse.kr(30), '/update', [...]) DENTRO del synth
       --   NcocoCore, y un OSCFunc de sclang lo reenvia a norns:10111.
       --   Es decir: /update vive y muere con el motor de SC.
       -- La unica forma de rearmarlo desde Lua seria engine.load(), que re-ejecuta
       --   init y RE-ASIGNA los buffers de 60 s -> cortaria el audio en directo.
       --   Por eso NO se dispara solo: seria peor que el fallo. Se registra y
       --   ademas se cubre el caso "nunca arranco" (last_osc_time == 0), que antes
       --   quedaba invisible porque el guardia exigia > 0.
       if G.last_osc_time > 0 then
          local stale = util.time() - G.last_osc_time
          if stale > 1.5 and grid_stale_count == 0 then
             print("OSC STALLED: no /update desde hace " .. string.format("%.1f", stale) .. "s")
          end
          if stale > 1.5 then grid_stale_count = grid_stale_count + 1
          else grid_stale_count = 0 end
       elseif not osc_never_warned and (util.time() - osc_watch_start) > 5.0 then
          osc_never_warned = true
          print("OSC NEVER STARTED: no ha llegado ni un /update en 5s (motor SC?)")
       end
    end
    grid_metro:start()

    -- [v3.01/v3.03] LATIDO / HEARTBEAT.
    --
    -- V3.02 disparo RECOVERY sobre una rejilla SANA (visto en maiden: dos avisos
    -- "sin redraw 4.7s" / "3.2s" y el grid parpadeo, pero siguio funcionando).
    -- Por que paso, VERIFICADO en matron/src/events.cc: hay UN SOLO event_loop()
    -- con UNA sola cola FIFO, y w_handle_metro() y w_handle_clock_resume()
    -- llaman al MISMO estado Lua (lvm) => metro y latido estan SERIALIZADOS.
    -- Si cualquier manejador de Lua se bloquea N segundos se paran LOS DOS, y al
    -- reanudarse el latido mide con util.time() (reloj de pared) frente a un
    -- last_redraw de ANTES del bloqueo: ve N s y decide "congelado". Recuperar
    -- ahi mandaba g:all(0) = APAGAR una rejilla que estaba viva. Ese era el
    -- parpadeo.
    --
    -- v3.03 separa los dos casos con dos pruebas independientes y exige DOS
    -- avisos (GridNav.heartbeat_step, test en tools/verify_p28_heartbeat.lua):
    --   block   : el latido llego tarde => se bloqueo el bucle ENTERO. Solo
    --             informa, NO toca la rejilla (se cura sola y tocarla parpadea).
    --   warn    : latido puntual + metro sin disparar => aviso 1/2, nada mas.
    --   recover : igual un ciclo entero despues => ahi si se recupera.
    -- El contador grid_ticks (metro) da la prueba en el mensaje: "+0 ticks" es
    -- el metro muerto, ">0" es un redraw que no llega a terminar.
    -- El latido vive en el sistema clock (aparte del metro), asi que sigue
    -- disparando aunque el metro este muerto.
    local grid_boot = util.time()
    local hb_pending = nil          -- instante del aviso 1/2 de "sin redraw"
    local hb_pending_dev = nil      -- instante del aviso 1/2 de "g.device nil"
    local cid_heartbeat = clock.run(function()
       local t0 = util.time()       -- inicio de ESTE ciclo
       while true do
          clock.sleep(2.0)
          local now = util.time()
          -- Atraso real de este despertar. ~0 en un bucle sano; grande si el
          -- bucle de Lua se bloqueo mientras dormiamos (ahi NO se recupera).
          local late = (now - t0) - 2.0
          if late < 0 then late = 0 end
          t0 = now
          local ticks_seen = grid_ticks
          grid_ticks = 0

          local last = GridNav.last_redraw
          local ref = (last and last > 0) and last or grid_boot
          local stall = now - ref

          local action, msg = GridNav.heartbeat_step(stall, late, ticks_seen, hb_pending, now)
          if action == "ok" then
             hb_pending = nil
          else
             if action == "warn" then hb_pending = now end
             if action == "recover" then hb_pending = nil end
             print(msg)
             if action == "recover" then recover_grid("sin redraw x2") end
          end

          -- g.device = nil => los g:led/g:refresh son no-ops silenciosos
          -- (vport.lua): los LEDs tampoco llegan. Tambien exige 2 avisos: el
          -- reenganche USB puede ser transitorio y no debe apagar la rejilla.
          if not g.device then
             if grid_was_attached then
                if hb_pending_dev then
                   if (now - hb_pending_dev) >= GridNav.HEART_CONFIRM then
                      hb_pending_dev = nil
                      print("GRID HEARTBEAT: g.device = nil (LEDs no llegan) tras 2 avisos -> recuperando")
                      recover_grid("g.device nil x2")
                   end
                else
                   hb_pending_dev = now
                   print("GRID HEARTBEAT: g.device = nil (LEDs no llegan) -> aviso 1/2 (NO recupero aun)")
                end
             end
          else
             grid_was_attached = true
             hb_pending_dev = nil
          end
       end
    end)
    clock_ids[7] = cid_heartbeat
    -- NOTE: clock_ids queda DISPERSO a proposito (1..5, 7 y 8). cleanup() lo
    -- recorre con pairs, nunca con ipairs. Ver el comentario de cleanup().
    
    -- [v3.01] Grid auto-heal. grid.add recibe el dispositivo nuevo (grid.lua:
    -- Grid.add(g)), asi que se engancha SU vport, no el 1 a ciegas. Antes era
    -- grid.connect sin argumento => SIEMPRE vport 1: si el aparato reenganchaba
    -- en otro vport, el 1 se quedaba sin .device y todos los LEDs eran no-ops
    -- silenciosos (bug latente, verificado en grid.lua/vport.lua).
    grid.add = function(dev)
       local port = dev and dev.port
       print("Grid Reconnected - Resetting Cache" .. (port and (" (vport "..port..")") or ""))
       if port then g = grid.connect(port) end
       GridNav.reset_cache()
       grid_was_attached = (g.device ~= nil)
    end

    screen_metro = metro.init(); screen_metro.time = 1/30
    screen_metro.event = function() redraw() end
    screen_metro:start()
    
    local cid_16n = clock.run(function()
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

                local val_calibrated = _16n.normalize(msg.val, is_bipolar_param(p_name))
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
    clock_ids[5] = cid_16n
    
    G.loaded = true 
    print("Ncoco v" .. NCOCO_VERSION .. " Ready.")
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
  -- [v3.01] pairs, NO ipairs. clock_ids es DISPERSO (1..5 y 7: el 6 no existe),
  -- e ipairs se detiene en el primer hueco: el latido del indice 7 nunca se
  -- cancelaria y seguiria imprimiendo tras cambiar de script.
  -- Es la misma trampa que rompio el 16n al recorrer midi.devices con ipairs.
  for cid_id, cid in pairs(clock_ids) do
     if cid then clock.cancel(cid) end
  end
  clock_ids = {}
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
          local v = params:get("bitsL"); params:set("bitsL", (v%4)+1)
          if is_link then params:set("bitsR", (v%4)+1) end
       end
    elseif G.focus.edit_r then 
       if n==3 then local v=params:get("bitsR"); params:set("bitsR", (v%4)+1) end
    else 
       -- [v3.02] SOLO en la pantalla principal. Mismo criterio que redraw():
       -- si hay un popup de fuente o de destino abierto, K2/K3 son la
       -- funcion de ESA pantalla, no REC.
       -- Antes las dos grabaciones eran la MISMA linea: K2 ponia recL y recR
       -- JUNTAS (grababa COCO 1 y 2 a la vez) y K3 no hacia nada.
       local in_popup = (G.focus.source ~= nil) or (G.focus.inspect_dest ~= nil)
       if not in_popup then
          if n == 2 then
             params:set("recL", 1 - params:get("recL"))     -- K2 -> COCO 1
          elseif n == 3 then
             params:set("recR", 1 - params:get("recR"))     -- K3 -> COCO 2
          end
       end
    end
  end
end