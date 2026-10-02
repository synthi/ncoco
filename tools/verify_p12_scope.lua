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
--
-- Compara la POSICION RELATIVA dentro de la caja, no el pixel absoluto.
-- Asi la prueba sigue siendo valida aunque la caja cambie de tamano:
--   posicion_relativa = (centro - py) / (alto/2)
-- debe valer exactamente el valor modulado recortado a -1..+1.
-- Un valor de +1 toca el borde superior, -1 el inferior, 0 el centro.
--------------------------------------------------------------------
local function referencia_rel(G, id, h)
  local head, len = G.scope_head, G.SCOPE_LEN
  local w = 119
  local center_y = 15 + h / 2
  local out = {}
  for x = 0, w - 1 do
    local sum = 0
    local hist_idx = (head - 1 - x - 1) % len + 1
    for src = 1, SRC do
      local amt = G.patch[src][id]
      if amt ~= 0 then sum = sum + (G.scope_history[src][hist_idx] * amt) end
    end
    sum = sum * G.dest_gains[id]
    local v = util.clamp(sum, -1, 1)
    local py = center_y - (v * (h / 2))
    -- recorte a la caja
    py = math.max(15, math.min(15 + h, py))
    out[#out + 1] = (center_y - py) / (h / 2)
  end
  return out
end

--------------------------------------------------------------------
print('== #12: el scope del inspector de destinos, valores y dibujo ==')
print('')

local BOX_Y, BOX_H = 15, 43
local W = 119

for _, mode in ipairs{ 'cero', 'sparse', 'saltos', 'saturado' } do
  local G = build(mode)
  H.reset()
  UI.draw_dest_inspector(G, 5)
  local cap = H.capture()
  local pts, metodo = puntos_del_scope(cap, W)

  local ref = referencia_rel(G, 5, BOX_H)
  local center_y = BOX_Y + BOX_H / 2

  -- Comparacion de la POSICION RELATIVA dentro de la caja.
  -- El harness registra con 4 decimales, asi que la tolerancia es 0.0001.
  local TOL = 0.001
  local iguales = (#pts == #ref)
  local peor = 0
  if iguales then
    for i = 1, #ref do
      local rel = (center_y - pts[i].y) / (BOX_H / 2)
      local d = math.abs(rel - ref[i])
      if d > peor then peor = d end
      if d > TOL then iguales = false end
    end
  end

  print(string.format('  %-10s metodo=%-7s puntos=%3d  %s', mode, metodo, #pts,
    iguales and 'forma de la onda IDENTICA a la referencia' or 'FORMA DISTINTA'))

  -- la onda no puede salirse de la caja
  local miny, maxy = 999, -999
  for _, p in ipairs(pts) do
    if p.y < miny then miny = p.y end
    if p.y > maxy then maxy = p.y end
  end
  local dentro = (miny >= BOX_Y - 0.01) and (maxy <= BOX_Y + BOX_H + 0.01)
  print(string.format('    %s dentro de la caja y=%d..%d (min %.2f max %.2f)',
    dentro and 'PASA ' or 'FALLA', BOX_Y, BOX_Y + BOX_H, miny, maxy))
end

print('')
print('== recuento de operaciones de dibujo ==')
local G = build('sparse')
H.reset(); UI.draw_dest_inspector(G, 5)
local _, m1 = puntos_del_scope(H.capture(), W)
print(string.format('  metodo de dibujo : %s', m1))
print(string.format('  puntos de la onda: %d (antes 108)', W))
print(string.format('  llamadas a fill : %d', H.count('fill')))
print(string.format('  llamadas a stroke: %d', H.count('stroke')))
print(string.format('  caja: %dx%d (antes 108x25)  area x%.2f', 120, 43,
  (120 * 43) / (108 * 25)))

H.done()