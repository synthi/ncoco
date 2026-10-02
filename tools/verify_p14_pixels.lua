-- Prueba de equivalencia pixel a pixel del punto #14 de la Fase 3.
--
-- Idea: se ejecuta el DIBUJO REAL de lib/ui.lua con el codigo actual y con
-- una copia de la version anterior, y se comparan las 24 capturas de los 24
-- destinos. Si una sola llamada de dibujo difiere, la prueba falla.
--
-- Modo de uso:
--   lua tools/verify_p14_pixels.lua           (estado actual)
--   lua tools/verify_p14_pixels.lua --old <ruta_al_ui_antiguo.lua>
--
-- Con --old se compara el archivo actual contra el pasado; el resultado debe
-- ser identico en los 24 destinos.

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')

local function capture_all(path_ui)
  local UI = dofile(path_ui)
  local out = {}
  local SRC, DEST = 12, 24

  local function build(mode)
    local G = {}
    G.patch = {}
    for s = 1, SRC do
      G.patch[s] = {}
      for d = 1, DEST do G.patch[s][d] = 0.0 end
    end
    if mode == 'sparse' then
      G.patch[1][5] = 0.7; G.patch[3][5] = -0.4; G.patch[7][5] = 0.25
      G.patch[2][9] = 0.5; G.patch[11][9] = 0.3; G.patch[12][5] = 0.9
      G.patch[1][1] = -1.0; G.patch[5][13] = 0.6; G.patch[9][24] = 0.33
    elseif mode == 'dense' then
      for s = 1, SRC do
        for d = 1, DEST do G.patch[s][d] = ((s * 13 + d * 7) % 21) / 21 - 0.5 end
      end
    elseif mode == 'negative' then
      for s = 1, SRC do G.patch[s][2] = -0.99 end
      G.patch[6][17] = 0.15
    elseif mode == 'empty' then
      -- sin cables
    end
    G.SCOPE_LEN = 64
    G.scope_head = 33
    G.dest_gains = {}
    for d = 1, DEST do G.dest_gains[d] = 1.0 end
    G.dest_gains[1] = 0.0
    G.dest_gains[12] = 1.2
    G.scope_history = {}
    for s = 1, SRC do
      G.scope_history[s] = {}
      for i = 1, G.SCOPE_LEN do
        G.scope_history[s][i] = math.sin(i * 0.3 + s * 1.7) * 0.8
      end
    end
    G.focus = {}
    G.sources_val = {}
    for i = 1, 12 do G.sources_val[i] = math.sin(i) * 0.5 end
    G.coco = { { out_level = 0.4 }, { out_level = 0.6 } }
    G.popup = { active = false }
    G.trails = { {}, {} }
    G.trail_head = { 1, 1 }
    return G
  end

  for _, mode in ipairs{ 'empty', 'sparse', 'dense', 'negative' } do
    for dest = 1, DEST do
      H.reset()
      UI.draw_dest_inspector(build(mode), dest)
      out[#out + 1] = mode .. '/dest' .. dest .. '\n' .. H.capture()
    end
  end
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

if old_path then
  section('comparacion pixel a pixel: actual vs version anterior')
  local ahora = capture_all('lib/ui.lua')
  local antes = capture_all(old_path)
  if ahora == antes then
    print('  PASA  los 96 dibujos (4 matrices x 24 destinos) son IDENTICOS')
  else
    -- localizar las diferencias
    local la, lb = {}, {}
    for line in (ahora .. '\n'):gmatch('([^\n]*)\n') do la[#la + 1] = line end
    for line in (antes .. '\n'):gmatch('([^\n]*)\n') do lb[#lb + 1] = line end
    local n = 0
    for i = 1, math.max(#la, #lb) do
      if la[i] ~= lb[i] then
        n = n + 1
        if n <= 5 then
          print(string.format('  linea %d difiere:\n    antes: %s\n    ahora: %s', i, tostring(lb[i]), tostring(la[i])))
        end
      end
    end
    print(string.format('  FALLA %d lineas difieren', n))
  end
else
  section('captura de referencia (estado actual)')
  local c = capture_all('lib/ui.lua')
  print(string.format('  %d caracteres capturados', #c))
  print('  usa --old <ruta> para comparar contra una version anterior')
end

H.done()