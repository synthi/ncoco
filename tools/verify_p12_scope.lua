-- Verificacion del punto #12 de la Fase 3: unificar el metodo de dibujo del
-- scope del inspector de destinos con el de los inspectores de fuentes.
--
-- ANTES: 108 puntos sueltos, cada uno con su propio screen.fill().
--         -> cuando el valor salta, quedan huecos: parece "saltarse lineas".
-- AHORA: una linea continua (move/line) con un unico screen.stroke(),
--         igual que hace UI.draw_scope para los inspectores de fuentes.
--
-- LO QUE NO CAMBIA (esto es lo que verifica esta test):
--   - el calculo de py en los 108 puntos
--   - el rango bipolar -1..+1 con el cero en el centro
--   - el recorte a la caja 30..54
--   - la linea horizontal de umbral
-- Solo cambia COMO se pinta lo mismo.

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')
local UI = dofile('lib/ui.lua')

local SRC, DEST = 12, 24

--------------------------------------------------------------------
-- Extrae la secuencia de puntos (x, y) que dibuja el scope del inspector
-- de destinos, tanto si usa puntos sueltos como si usa linea continua.
--------------------------------------------------------------------
--------------------------------------------------------------------
-- El inspector de destinos dibuja, en este orden:
--   1) el fondo (fill)
--   2) la caja (stroke)
--   3) la linea de umbral (28 puntos sueltos, solo en algunos destinos)
--   4) el scope (108 puntos)   <-- esto es lo que comparamos
-- Los ultimos 108 puntos de la captura son siempre el scope.
--------------------------------------------------------------------
local function puntos_del_scope(captura, n_esperado)
  -- recorrer EN ORDEN: cada "pixel X Y" y cada "line X Y" aporta un punto
  local orden = {}
  for linea in captura:gmatch('([^\n]+)') do
    local a, b = linea:match('^pixel ([%d%.%-]+) ([%d%.%-]+)')
    if a then
      orden[#orden + 1] = { x = tonumber(a), y = tonumber(b), op = 'pixel' }
    else
      a, b = linea:match('^line ([%d%.%-]+) ([%d%.%-]+)')
      if a then
        orden[#orden + 1] = { x = tonumber(a), y = tonumber(b), op = 'line' }
      end
    end
  end

  -- los puntos del scope son los ultimos n_esperado
  local desde = #orden - n_esperado + 1
  if desde < 1 then desde = 1 end
  local out, metodo = {}, 'puntos'
  for i = desde, #orden do
    out[#out + 1] = orden[i]
    if orden[i].op == 'line' then metodo = 'linea' end
  end
  return out, metodo, #orden
end

--------------------------------------------------------------------
local function build(mode)
  local G = {}
  G.patch = {}
  for s = 1, SRC do
    G.patch[s] = {}
    for d = 1, DEST do G.patch[s][d] = 0.0 end
  end
  if mode == 'sparse' then
    G.patch[1][5] = 0.7; G.patch[3][5] = -0.4; G.patch[7][5] = 0.25
  elseif mode == 'saltos' then
    -- valores que hacen SALTAZOS verticales: el caso que deja huecos
    for s = 1, SRC do G.patch[s][5] = (s % 2 == 0) and 1.0 or -1.0 end
    G.patch[1][5] = 1.0
  elseif mode == 'saturado' then
    for s = 1, SRC do G.patch[s][5] = 1.0 end
  elseif mode == 'cero' then
    G.patch[1][5] = 0.0
  end
  G.SCOPE_LEN = 64
  G.scope_head = 33
  G.dest_gains = {}
  for d = 1, DEST do G.dest_gains[d] = 1.0 end
  G.dest_gains[5] = 0.85
  G.scope_history = {}
  for s = 1, SRC do
    G.scope_history[s] = {}
    for i = 1, G.SCOPE_LEN do
      G.scope_history[s][i] = math.sin(i * 0.55 + s * 1.9) * 0.9
    end
  end
  G.focus = {}
  G.sources_val = {}
  for i = 1, 12 do G.sources_val[i] = math.sin(i) * 0.5 end
  G.coco = { { out_level = 0.4 }, { out_level = 0.6 } }
  G.popup = { active = false }
  return G
end

--------------------------------------------------------------------
-- Referencia: los mismos valores calculados a mano, sin dibujar.
-- Es el "verdadero" contra el que se comparan ambas versiones.
--------------------------------------------------------------------
local function referencia_py(G, id)
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
  return out
end

--------------------------------------------------------------------
print('== #12: el scope del inspector de destinos, valores y dibujo ==')
print('')

for _, mode in ipairs{ 'cero', 'sparse', 'saltos', 'saturado' } do
  local G = build(mode)
  H.reset()
  UI.draw_dest_inspector(G, 5)
  local cap = H.capture()
  local pts, metodo = puntos_del_scope(cap, 108)

  local ref = referencia_py(G, 5)

  -- Comparacion con tolerancia: el harness registra los numeros con 4
  -- decimales, la referencia con 6. Se comparan como valores numericos.
  local TOL = 0.0001
  local iguales = (#pts == #ref)
  local peor = 0
  if iguales then
    for i = 1, #ref do
      local d = math.abs(pts[i].y - ref[i])
      if d > peor then peor = d end
      if d > TOL then iguales = false end
    end
  end

  print(string.format('  %-10s metodo=%-7s puntos=%3d  %s', mode, metodo, #pts,
    iguales and 'valores IDENTICOS al calculo de referencia' or 'VALORES DISTINTOS'))

  -- rango bipolar conservado: el cero esta en el centro de la caja
  local miny, maxy = 999, -999
  for _, p in ipairs(pts) do
    if p.y < miny then miny = p.y end
    if p.y > maxy then maxy = p.y end
  end
  if miny < 30 or maxy > 54.001 then
    print(string.format('    ATENCION: sale de la caja (min %.2f max %.2f)', miny, maxy))
  end
end

print('')
print('== recuento de operaciones de dibujo ==')
local G = build('sparse')
H.reset(); UI.draw_dest_inspector(G, 5); local c1 = H.capture()
local _, m1 = puntos_del_scope(c1, 108)
print(string.format('  metodo de dibujo : %s', m1))
print(string.format('  llamadas a fill : %d', H.count('fill')))
print(string.format('  llamadas a stroke: %d', H.count('stroke')))
print(string.format('  total de operaciones: %d', select(2, H.capture():gsub('\n', '\n')) + 1))

H.done()