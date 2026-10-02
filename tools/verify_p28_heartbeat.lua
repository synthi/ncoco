-- Falsa alarma del latido: que el latido DIAGNOSE, que no recupere por un
-- bloqueo transitorio, y que la recuperacion ya NO apague la rejilla.
--
-- El fallo real (v3.02, visto en maiden): "GRID HEARTBEAT: sin redraw desde hace
-- 4.7s -> recuperando" + "GRID RECOVERY (sin redraw)" sobre una rejilla SANA; el
-- grid parpadeo pero siguio funcionando. Se repitio a los pocos segundos con 3.2s.
--
-- CAUSA VERIFICADA en norns matron/src/events.cc:
--   event_loop() es UN SOLO hilo que drena UNA cola FIFO, y w_handle_metro() y
--   w_handle_clock_resume() llaman al MISMO estado Lua (lvm). Metro y latido
--   estan SERIALIZADOS: un bloqueo de N s en cualquier manejador de Lua para a
--   LOS DOS, y al reanudarse el latido mide util.time() (reloj de pared) frente
--   a un last_redraw de ANTES del bloqueo => ve N s y decide "congelado" de una
--   rejilla que se iba a recuperar sola en el siguiente tick de metro.
--
-- Y el parpadeo, VERIFICADO en matron/src/device/device_monome.cc:
--   dev_monome_grid_set_led() pone md->dirty[q] = true SIN comparar el valor,
--   asi que reset_cache() (-1 en las 128 celdas) ya fuerza el reenvio completo
--   de los 4 quads. g:all(0) era redundante Y era el frame en negro.
--
-- Este test EJECUTA la decision real (GridNav.heartbeat_step) y la compara contra
-- la regla de v3.02 como control negativo.

local fails = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FALLA " .. name .. (detail and ("  -- " .. detail) or "")); fails = fails + 1 end
end
local function read(p) local f = io.open(p, 'r'); local s = f:read('*a'); f:close(); return s end

local nav = read('lib/grid_nav.lua')
local ncoco = read('ncoco.lua')

-- Comentarios fuera: las comprobaciones negativas miran CODIGO, no prosa.
local function strip_comments(s)
  local out = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    local i, cut, inq = 1, nil, false
    while i <= #line do
      local c = line:sub(i, i)
      if c == "'" then inq = not inq
      elseif not inq and c == '-' and line:sub(i + 1, i + 1) == '-' then cut = i; break end
      i = i + 1
    end
    out[#out + 1] = cut and line:sub(1, cut - 1) or line
  end
  return table.concat(out, '\n')
end
local ncoco_code = strip_comments(ncoco)

-- Carga el modulo REAL de la rejilla con stubs (mismo truco que verify_p23).
local saved_include, saved_grid = _G.include, _G.grid
_G.include = function() return {} end
_G.grid = { connect = function() return {} end }
local chunk, chunk_err = loadfile('lib/grid_nav.lua')
local okload, GridNav = false, chunk_err
if chunk then okload, GridNav = pcall(chunk) end
_G.include, _G.grid = saved_include, saved_grid
check("grid_nav.lua carga", okload and type(GridNav) == 'table',
      tostring(GridNav))

local HS = assert(GridNav.heartbeat_step, "GridNav.heartbeat_step no existe")

-- La regla de v3.02, tal cual: "sin redraw > 3s => recuperar YA".
-- Es el control negativo: tiene que fallar exactamente en el caso transitorio.
local function v302_rule(stall) return stall > 3.0 and "recover" or "none" end


print("1. Escenario del fallo real: bloqueo transitorio de 4.7s, rejilla SANA")
-- stall 4.7 = lo que vio maiden; late 2.7 = el PROPIO latido llego tarde porque
-- el bucle de Lua estaba parado (metro y latido en la misma cola FIFO).
local a_act, a_msg = HS(4.7, 2.7, 0, nil, 100.0)
check("el latido NO manda a recuperar (v3.02 si lo hacia)",
      a_act == "block", "accion=" .. tostring(a_act))
check("v3.02 SI disparaba recuperacion aqui (control negativo)",
      v302_rule(4.7) == "recover",
      "prueba de que la falsa alarma salia de la regla, no del hardware")
check("informa que el bloqueo es del bucle, no de la rejilla",
      a_msg and a_msg:match("el bucle de Lua se bloqueo") ~= nil, a_msg)
check("dice explicitamente que NO toca la rejilla",
      a_msg and a_msg:match("NO se toca la rejilla") ~= nil, a_msg)

print("2. Metro MUERTO de verdad: latido puntual, dos avisos")
local b1, b1m = HS(3.2, 0.05, 0, nil, 100.0)
check("1er ciclo: aviso, pero NO recupera", b1 == "warn", "accion=" .. tostring(b1))
check("el aviso dice que todavia no recupera",
      b1m and b1m:match("aviso 1/2") ~= nil, b1m)
check("el aviso lleva la prueba de los ticks",
      b1m and b1m:match("metro %+0 ticks") ~= nil, b1m)
local b2_early = HS(5.4, 0.03, 0, 100.0, 101.0)
check("aun falta un ciclo entero tras el aviso: sigue sin recuperar",
      b2_early == "warn", "accion=" .. tostring(b2_early))
local b2, b2m = HS(5.4, 0.03, 0, 100.0, 102.0)
check("un ciclo entero despues sigue parado: RECUPERA", b2 == "recover",
      "accion=" .. tostring(b2))
check("el motivo lleva 'sin redraw' y la prueba de ticks",
      b2m and b2m:match("sin redraw") ~= nil and b2m:match("metro %+0 ticks") ~= nil, b2m)

print("3. Redraw que NO termina: latido puntual pero ticks > 0")
local c1 = HS(4.0, 0.1, 30, nil, 100.0)
check("1er ciclo: aviso", c1 == "warn", "accion=" .. tostring(c1))
local c2, c2m = HS(6.0, 0.1, 31, 100.0, 102.0)
check("2º ciclo: recupera", c2 == "recover", "accion=" .. tostring(c2))
check("el mensaje refleja que el metro SI disparo (metro +31)",
      c2m and c2m:match("metro %+31 ticks") ~= nil, c2m)

print("4. Rejilla sana: ni aviso ni recuperacion")
local d_act, d_msg = HS(0.05, 0.0, 15, nil, 100.0)
check("stall bajo el umbral => ok", d_act == "ok", "accion=" .. tostring(d_act))
check("y no imprime nada", d_msg == nil)
local d2 = HS(3.0, 0.0, 45, nil, 100.0)
check("en el umbral exacto (3.0) sigue siendo ok", d2 == "ok", "accion=" .. tostring(d2))

print("5. Umbral de atraso del latido")
local e1 = HS(4.0, 0.99, 0, nil, 100.0)
check("late 0.99 (ruido normal de planificacion) => NO es bloqueo: es aviso",
      e1 == "warn", "accion=" .. tostring(e1))
local e2 = HS(4.0, 1.0, 0, nil, 100.0)
check("late 1.0 exacto => bloqueo del bucle, no de la rejilla",
      e2 == "block", "accion=" .. tostring(e2))

print("6. Integracion en ncoco.lua (codigo, no comentarios)")
check("el latido usa la decision pura", ncoco:match('GridNav%.heartbeat_step%('))
check("mide SU PROPIO atraso (late)", ncoco:match('local late = %(now %-% t0%) %-% 2%.0'))
check("cuenta ticks de metro como evidencia", ncoco:match('grid_ticks = grid_ticks %+ 1'))
check("reinicia ese contador en cada ciclo del latido", ncoco:match('grid_ticks = 0'))
check("conserva el aviso hasta que pasa el ciclo de confirmacion",
      ncoco:match('hb_pending = now'))
check("g.device nil tambien exige 2 avisos",
      ncoco:match('recover_grid%("g.device nil x2"%)'))
check("sin redraw recupera solo en el 2º aviso",
      ncoco:match('recover_grid%("sin redraw x2"%)'))
check("NO hay recuperacion directa en el primer aviso",
      not ncoco_code:match('recover_grid%("sin redraw"%)'),
      "seria la regla v3.02: recuperar de primera")
check("el latido vive en clock y no en el metro (sigue si el metro muere)",
      ncoco:match('local cid_heartbeat = clock%.run'))

print("7. La recuperacion ya NO apaga la rejilla (el parpadeo)")
check("sin g:all(0) en codigo", not ncoco_code:match('g:all%(0%)'),
      "g:all(0) mandaba los 128 LEDs a 0 y era el flash")
check("reenvio completo via reset_cache",
      ncoco:match('GridNav%.reset_cache%(%)'))
check("sigue reenganchando el vport", ncoco:match('GridNav%.find_device_port%(%)'))
check("sigue reiniciando el metro", ncoco:match('grid_metro:stop%(%); grid_metro:start%(%)'))
check("reset_cache pone -1 => distinto de cualquier brillo => las 128 se reescriben",
      nav:match('GridNav%.cache%[x%]%[y%] = %-1'))

print("8. REPLAY del incidente reportado (lo que se vio en maiden)")
-- Lo que paso: "sin redraw 4.7s -> recuperando" + GRID RECOVERY (sin redraw),
-- y unos segundos despues otra vez con 3.2s. Con la rejilla perfectamente sana.

-- 8a. El caso era un bloqueo transitorio del bucle. Se reproduce lo que hacia
-- la regla de v3.02 y lo que hace ahora la misma secuencia.
local old_recover = 0
-- v3.02: stall > 3.0 => recuperar, siempre, sin mirar nada mas.
local old_stall
for _, step in ipairs({ {2.7, 4.7}, {2.0, 6.7} }) do
   old_stall = step[2]
   if old_stall > 3.0 then old_recover = old_recover + 1 end
end
check("v3.02 habria recuperado (y parpadeado) dos veces en este replay",
      old_recover == 2, "recuperaciones=" .. old_recover)

-- v3.03 sobre la misma secuencia: el primer despertar llega tarde (el bucle
-- estaba parado), luego todo vuelve a su ritmo.
local t0 = 100.0
local new_recover = 0
local pending, messages = nil, {}
for _, step in ipairs({ {2.7, 4.7}, {0.05, 0.07} }) do
   local late, stall = step[1], step[2]
   local a, m = HS(stall, late, 0, pending, t0)
   if a == "warn" then pending = t0
   elseif a == "recover" then pending = nil; new_recover = new_recover + 1 end
   if a ~= "ok" then messages[#messages+1] = m end
   t0 = t0 + 2.0
end
check("v3.03 NO recupera en el replay (0 parpadeos)",
      new_recover == 0, "recuperaciones=" .. new_recover)
check("y lo dice en un unico mensaje, sin apagar nada",
      #messages == 1 and messages[1]:match("el bucle de Lua se bloqueo") ~= nil,
      messages[1] or "sin mensajes")

-- 8b. El caso bueno: el metro SI se murio. Tambien debe autorizarse solo.
t0, pending = 100.0, nil
new_recover, messages = 0, {}
for i = 1, 4 do
   local stall = (i == 1) and 3.4 or (i == 2 and 5.4 or 0.07)
   local a, m = HS(stall, 0.04, 0, pending, t0)
   if a == "warn" then pending = t0
   elseif a == "recover" then pending = nil; new_recover = new_recover + 1 end
   if a ~= "ok" then messages[#messages+1] = m end
   t0 = t0 + 2.0
end
check("metro muerto de verdad: recupera (una vez, tras confirmar)",
      new_recover == 1, "recuperaciones=" .. new_recover)
check("y se calla solo cuando la rejilla vuelve", #messages == 2,
      "mensajes=" .. #messages)
check("la recuperacion real sigue existiendo", messages[2] ~= nil
      and messages[2]:match("tras 2 avisos") ~= nil, messages[2] or "")


if fails > 0 then
  print("RESULTADO: " .. fails .. " fallos")
  os.exit(1)
end
print("RESULTADO: el latido diagnostica en vez de adivinar, y ya no parpadea")

