-- Diagnostico del punto #12: la linea de umbral se ve mas gruesa.
--
-- Muestra el ORDEN exacto de las operaciones de dibujo del inspector de
-- destinos, para ver que se hace con los 28 puntos de la linea de umbral.
--
-- Uso: lua tools/verify_p12_umbral.lua

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')

local function construir()
  local G = { SCOPE_LEN = 64, scope_head = 33, focus = {}, sources_val = {},
              coco = { { out_level = 0.4 }, { out_level = 0.6 } },
              popup = { active = false } }
  G.patch = {}
  for s = 1, 12 do
    G.patch[s] = {}
    for d = 1, 24 do G.patch[s][d] = 0.0 end
  end
  G.patch[1][5] = 0.7
  G.dest_gains = {}
  for d = 1, 24 do G.dest_gains[d] = 1.0 end
  G.scope_history = {}
  for s = 1, 12 do
    G.scope_history[s] = {}
    for i = 1, G.SCOPE_LEN do G.scope_history[s][i] = math.sin(i * 0.3 + s) * 0.8 end
  end
  for i = 1, 12 do G.sources_val[i] = 0.5 end
  return G
end

local function ops_de(ruta)
  local UI = dofile(ruta)
  H.set_param("skip_modeL", 1)
  H.reset()
  UI.draw_dest_inspector(construir(), 5)
  local ops = {}
  for l in H.capture():gmatch('[^\n]+') do ops[#ops + 1] = l end
  return ops, H.count('fill'), H.count('stroke')
end

local ruta_antes = arg[1]
local ruta_ahora = 'lib/ui.lua'

local function informe(titulo, ruta)
  local ops, fills, strokes = ops_de(ruta)
  print('--- ' .. titulo .. ' ---')
  print(('  fill=%d  stroke=%d  total=%d'):format(fills, strokes, #ops))

  -- ¿qué operación sigue a la última línea de umbral?
  -- Los puntos de umbral son una fila de pixels consecutivos con la MISMA Y
  -- (muchos de ellos). Se detecta esa fila, en vez de fijar la coordenada,
  -- para que la prueba siga valiendo si la caja cambia de sitio.
  local conteo_y = {}
  for i, o in ipairs(ops) do
    local x, y = o:match('^pixel ([%d%.%-]+) ([%d%.%-]+)$')
    if x then
      y = tonumber(y)
      conteo_y[y] = (conteo_y[y] or 0) + 1
    end
  end
  local mejor_y, mejor_n = nil, 0
  for y, n in pairs(conteo_y) do
    if n > mejor_n then mejor_y, mejor_n = y, n end
  end
  local ultimo
  if mejor_y then
    for i, o in ipairs(ops) do
      local x, y = o:match('^pixel ([%d%.%-]+) ([%d%.%-]+)$')
      if x and tonumber(y) == mejor_y then ultimo = i end
    end
  end
  if ultimo then
    print(('  último punto de umbral en la operación %d'):format(ultimo))
    for i = ultimo, math.min(ultimo + 4, #ops) do
      print(('    %d: %s'):format(i, ops[i]))
    end
  end

  -- ¿algún fill o stroke aparece DESPUÉS de los 28 puntos y ANTES
  -- de dibujarlos como puntos rellenos?
  local primera_despuues
  for i = ultimo + 1, #ops do
    local op = ops[i]
    if op == 'fill' or op == 'stroke' then primera_despuues = op break end
  end
  print(("  primera operacion de pintado tras el umbral: %s"):format(tostring(primera_despuues)))
  print('')
end

if ruta_antes then informe('ANTES (version anterior)', ruta_antes) end
informe('AHORA (version actual)', ruta_ahora)

print('LECTURA')
print('  Si tras los 28 puntos del umbral aparece un FILL, los puntitos se')
print('  pintan como puntos rellenos finos (lo original).')
print('  Si aparece un STROKE, los puntitos se pintan por el borde del trazo')
print('  y se ven mas gruesos: eso es el fallo.')