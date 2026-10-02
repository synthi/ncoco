-- Test del punto #14 de la Fase 3: el inspector de destino recalcula, para cada
-- uno de los 108 pixeles de la scope, las 12 fuentes de modulacion, aunque la
-- mayoria sean 0. Con una matriz dispersa (uso normal) eso son ~1300 busquedas
-- por cuadro.
--
-- Objetivo: precalcular la lista de fuentes activas una sola vez por cuadro y
-- comprobar que el DIBUJO RESULTANTE ES IDENTICO, pixel a pixel.

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')
local UI = dofile('lib/ui.lua')

local SRC, DEST = 12, 24

local function build_patch(mode)
  local p = {}
  for s = 1, SRC do
    p[s] = {}
    for d = 1, DEST do p[s][d] = 0.0 end
  end
  if mode == 'sparse' then
    -- uso tipico: pocas conexiones
    p[1][5] = 0.7; p[3][5] = -0.4; p[7][5] = 0.25
    p[2][9] = 0.5; p[11][9] = 0.3
  elseif mode == 'dense' then
    -- peor caso: todas las fuentes conectadas
    for s = 1, SRC do p[s][5] = (s % 7) / 7 - 0.5 end
  elseif mode == 'empty' then
    -- ninguna conexion
  end
  return p
end

local function build_G(mode)
  local G = { patch = build_patch(mode) }
  G.SCOPE_LEN = 64
  G.scope_head = 33
  G.dest_gains = {}
  for d = 1, DEST do G.dest_gains[d] = 1.0 end
  G.dest_gains[5] = 0.85
  G.scope_history = {}
  for s = 1, SRC do
    G.scope_history[s] = {}
    for i = 1, G.SCOPE_LEN do
      G.scope_history[s][i] = math.sin(i * 0.3 + s) * 0.8
    end
  end
  G.focus = { inspect_dest = 5 }
  G.sources_val = {}
  for i = 1, 12 do G.sources_val[i] = math.sin(i) * 0.5 end
  G.coco = { { out_level = 0.4 }, { out_level = 0.6 } }
  G.popup = { active = false }
  G.trails = {}
  G.trail_head = { 1, 1 }
  return G
end

--------------------------------------------------------------------
-- Implementacion ACTUAL (la que esta en lib/ui.lua ahora mismo)
--------------------------------------------------------------------
local function scope_actual(G, id)
  local head, len = G.scope_head, G.SCOPE_LEN
  local w, h = 108, 25
  local center_y = 30 + h / 2
  local out = {}
  for x = 0, w - 1 do
    local sum = 0
    local hist_idx = (head - 1 - x - 1) % len + 1
    for src = 1, SRC do
      local amt = G.patch[src][id]
      if amt ~= 0 then sum = sum + (G.scope_history[src][hist_idx] * amt) end
    end
    sum = sum * G.dest_gains[id]
    local py = center_y - (util.clamp(sum, -1, 1) * (h / 2))
    py = util.clamp(py, 30, 54)
    out[#out + 1] = string.format('%.6f', py)
  end
  return table.concat(out, ',')
end

--------------------------------------------------------------------
-- Implementacion PROPUESTA: lista de fuentes activas precalculada
--------------------------------------------------------------------
local function scope_propuesta(G, id)
  local head, len = G.scope_head, G.SCOPE_LEN
  local w, h = 108, 25
  local center_y = 30 + h / 2

  -- precalcular: que fuentes tienen valor distinto de cero
  local activos = {}
  for src = 1, SRC do
    local amt = G.patch[src][id]
    if amt ~= 0 then activos[#activos + 1] = src end
  end

  local out = {}
  for x = 0, w - 1 do
    local sum = 0
    local hist_idx = (head - 1 - x - 1) % len + 1
    for _, src in ipairs(activos) do
      sum = sum + (G.scope_history[src][hist_idx] * G.patch[src][id])
    end
    sum = sum * G.dest_gains[id]
    local py = center_y - (util.clamp(sum, -1, 1) * (h / 2))
    py = util.clamp(py, 30, 54)
    out[#out + 1] = string.format('%.6f', py)
  end
  return table.concat(out, ','), #activos
end

--------------------------------------------------------------------
-- Comparacion
--------------------------------------------------------------------
for _, mode in ipairs{ 'empty', 'sparse', 'dense' } do
  section('matriz ' .. mode)
  local G = build_G(mode)
  local a = scope_actual(G, 5)
  local b, n_act = scope_propuesta(G, 5)
  check('resultado del scope IDENTICO', a == b)
  eq('fuentes activas detectadas', n_act,
     (function() local n = 0; for s = 1, SRC do if G.patch[s][5] ~= 0 then n = n + 1 end end return n end)())
end

--------------------------------------------------------------------
-- Comprobacion sobre el DIBUJO real de la pantalla
--
-- Para el destino 5 se dibujan 108 pixeles de scope + 28 de la linea de
-- umbral (tx = 10,14,...,118) = 136 en total. El destino 6 NO dibuja la
-- linea de umbral, asi que debe dar 108 exactos.
--------------------------------------------------------------------
section('dibujo real en pantalla (lib/ui.lua tal cual esta)')

-- El codigo dibuja la linea de umbral para los destinos
-- 5, 6, 7, 12, 13 y 14 (ui.lua:149). El resto dibujan solo los 108 del scope.
H.reset()
UI.draw_dest_inspector(build_G('sparse'), 5)
eq('destino 5: pixeles totales (108 scope + 28 umbral)', H.count('pixel'), 136)

H.reset()
UI.draw_dest_inspector(build_G('sparse'), 6)
eq('destino 6: tambien lleva umbral', H.count('pixel'), 136)

H.reset()
UI.draw_dest_inspector(build_G('sparse'), 9)
eq('destino 9: sin umbral, 108 exactos', H.count('pixel'), 108)

H.reset()
UI.draw_dest_inspector(build_G('sparse'), 24)
eq('destino 24: sin umbral, 108 exactos', H.count('pixel'), 108)

-- determinismo: dos dibujos seguidos deben ser identicos
local function draw_twice(id)
  H.reset(); UI.draw_dest_inspector(build_G('dense'), id); local a = H.capture()
  H.reset(); UI.draw_dest_inspector(build_G('dense'), id); local b = H.capture()
  return a == b
end
check('dibujo determinista (id 5)', draw_twice(5))
check('dibujo determinista (id 9)', draw_twice(9))

H.done()