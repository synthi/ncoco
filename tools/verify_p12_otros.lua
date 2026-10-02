-- Comprobacion de que el cambio #12 NO ha tocado ninguna otra pantalla.
--
-- El test verify_p14_pixels.lua compara el inspector de DESTINOS contra la
-- version anterior, y ahora falla a proposito: ese inspector es justo el que
-- se ha cambiado de proposito (puntos sueltos -> linea continua).
--
-- Este test compara TODAS LAS DEMAS pantallas:
--   - pantalla principal (radares, barras, hexagonos)
--   - inspector de petalos (hexagonos)
--   - inspector de envolventes
--   - inspector de amarillos (ruido de direccion)
--   - inspector de coco
--   - menu de patch
--
-- Uso:
--   lua tools/verify_p12_otros.lua --old <ruta_ui_anterior.lua>

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')

local function construir(id_foco)
  local G = {}
  local SRC, DEST = 12, 24

  -- valores por defecto de los parametros que se leen al dibujar
  H.set_param("global_vol", 1.0)
  H.set_param("monitor_vol", 0.85)
  H.set_param("global_chaos", 0.2)
  for i = 1, 6 do
    H.set_param("p" .. i .. "f_lfo", 0.5 + i * 0.05)
    H.set_param("p" .. i .. "f_aud", 200 + i * 50)
    H.set_param("p" .. i .. "chaos", 0.3)
    H.set_param("p" .. i .. "shape", (i % 2) + 1)
    H.set_param("p" .. i .. "range", (i % 2) + 1)
  end
  for _, side in ipairs{ "L", "R" } do
    H.set_param("rec" .. side, 0)
    H.set_param("skip_mode" .. side, 1)
    H.set_param("stutter_chaos" .. side, 0.4)
    H.set_param("stutter_rate" .. side, 0.12)
    H.set_param("preamp" .. side, 1.0)
    H.set_param("envSlew" .. side, 0.05)
    H.set_param("coco" .. (side == "L" and "1" or "2") .. "_out_mode", 1)
    H.set_param("coco" .. (side == "L" and "1" or "2") .. "_slew", 0.3)
    H.set_param("speed" .. side, 1.0)
    H.set_param("filt" .. side, 0.0)
  end
  G.patch = {}
  for s = 1, SRC do
    G.patch[s] = {}
    for d = 1, DEST do G.patch[s][d] = 0.0 end
  end
  G.patch[1][5] = 0.7; G.patch[3][5] = -0.4; G.patch[7][5] = 0.25
  G.patch[2][9] = 0.5; G.patch[11][9] = 0.3
  G.SCOPE_LEN = 64
  G.scope_head = 33
  G.dest_gains = {}
  for d = 1, DEST do G.dest_gains[d] = 1.0 end
  G.scope_history = {}
  for s = 1, SRC do
    G.scope_history[s] = {}
    for i = 1, G.SCOPE_LEN do G.scope_history[s][i] = math.sin(i * 0.3 + s) * 0.8 end
  end
  G.focus = { source = id_foco }
  G.sources_val = {}
  for i = 1, 12 do G.sources_val[i] = math.sin(i * 1.3) * 0.5 end
  G.sources_val[7] = 0.3; G.sources_val[8] = 0.6
  G.coco = {
    { out_level = 0.4, pos = 0.3 },
    { out_level = 0.6, pos = 0.7 },
  }
  G.popup = { active = false }
  G.TRAIL_SIZE = 16
  G.trail_head = { 1, 1 }
  -- historial de los radares: un valor por posicion de cinta
  G.trails = {}
  for i = 1, 2 do
    G.trails[i] = {}
    for k = 1, G.TRAIL_SIZE do G.trails[i][k] = ((k * 7 + i * 3) % G.TRAIL_SIZE) / G.TRAIL_SIZE end
  end
  G.active_snapshot = 0
  return G
end

local function capturar_todo(path_ui)
  local UI = dofile(path_ui)
  local out = {}
  local n = 0

  -- pantalla principal
  H.reset(); H.semilla(12345); UI.draw_main(construir(nil))
  out[#out + 1] = 'main\n' .. H.capture()

  -- inspectores de cada tipo de fuente
  for id = 1, 12 do
    n = n + 1
    H.reset(); H.semilla(1000 + id); UI.draw_main(construir(id))
    out[#out + 1] = 'inspector_fuente_' .. id .. '\n' .. H.capture()
  end

  -- menu de patch (cuando hay un destino seleccionado)
  local G = construir(1)
  G.focus.last_dest = 5
  H.reset(); H.semilla(777); UI.draw_main(G)
  out[#out + 1] = 'menu_patch\n' .. H.capture()

  return table.concat(out, '\n=====\n')
end

--------------------------------------------------------------------
local old_path
do
  local i = 1
  while arg[i] do
    if arg[i] == '--old' then old_path = arg[i + 1] end
    i = i + 1
  end
end

if not old_path then
  print('usa --old <ruta_ui_anterior.lua> para comparar')
  os.exit(1)
end

print('== #12: el resto de pantallas NO ha cambiado ==')
print('')
local ahora = capturar_todo('lib/ui.lua')
local antes = capturar_todo(old_path)

if ahora == antes then
  print('  PASA  las 14 pantallas (principal + 12 inspectores + menu de patch)')
  print('        son IDENTICAS antes y despues del cambio')
else
  local la, lb = {}, {}
  for l in (ahora .. '\n'):gmatch('([^\n]*)\n') do la[#la + 1] = l end
  for l in (antes .. '\n'):gmatch('([^\n]*)\n') do lb[#lb + 1] = l end
  local n, primera = 0, true
  for i = 1, math.max(#la, #lb) do
    if la[i] ~= lb[i] then
      n = n + 1
      if primera then
        print('  primera diferencia en la linea ' .. i .. ':')
        print('    antes: ' .. tostring(lb[i]))
        print('    ahora: ' .. tostring(la[i]))
        primera = false
      end
    end
  end
  print(string.format('  FALLA %d lineas difieren', n))
  os.exit(1)
end