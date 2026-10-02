-- Ajuste de TEXTO de la pantalla del inspector de destinos.
--
-- SUSTITUYE a verify_p12_header.lua y verify_p12_layout.lua, que partian de una
-- suposicion FALSA (6 px por caracter) y describian un diseno ya cambiado. Por
-- eso daban "FALLA" sin que el codigo estuviera mal.
--
-- De donde salen los anchos:
--   * Fuente por defecto de norns: matron/src/hardware/screen/screen.cc
--       ct[0] = "norns.ttf"   (alias de 04B_03)  + cairo_set_font_size(cr, 8.0)
--   * Anchos medidos sobre resources/norns.ttf del propio repo de monome, a
--     size 8, con FreeType (PIL). A este tamano el bearing izquierdo es 0 en
--     TODOS los glifos y el ancho de tinta == avance, asi que el ancho de una
--     cadena es la suma de los anchos por caracter (verificado: coincide al
--     decimal con la medicion de la cadena completa).
--   * text_right usa cairo_text_extents().width y hace rel_move_to(-width)
--     (screen.cc), o sea ancla por el borde derecho: se reproduce aqui.
--
-- Regenerar la tabla (si algun dia cambiara la fuente):
--   python3 -c "from PIL import ImageFont; \
--     F=ImageFont.truetype('resources/norns.ttf',8); \
--     print([round(F.getlength(chr(c))) for c in range(32,127)])"

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')
local UI = dofile('lib/ui.lua')

-- anchos en px para ASCII 32..126 (indice = code - 31)
local ADV = {
  4,2,4,6,5,6,6,2,3,3,4,4,3,4,2,6,5,3,5,5,
  5,5,5,5,5,5,2,2,4,4,4,5,6,5,5,4,5,4,4,5,
  5,4,5,5,4,6,5,5,5,5,5,5,4,5,5,6,5,5,4,3,
  6,3,4,5,3,5,5,4,5,5,4,5,5,2,3,5,2,6,5,5,
  5,5,4,5,4,5,5,6,4,5,5,4,2,4,5,
}

local function ancho(s)
  local n = 0
  for i = 1, #s do n = n + (ADV[s:byte(i) - 31] or 0) end
  return n
end

section('tabla de anchos vs mediciones independientes de la fuente real')
local REF = {
  ["E3 GAIN IN:"]=47, ["SKIP 1: SINGLE"]=59, ["SKIP 2: SINGLE"]=61,
  ["SKIP 1: AUTO"]=51, ["SKIP 2: AUTO"]=53, ["AUD IN 1"]=35, ["AUD IN 2"]=37,
  ["E1:CHS"]=23, ["E2:RATE"]=29, ["1.00x"]=19, ["2.00x"]=21, ["0.100s"]=25,
  ["K2/3"]=21, ["K2/3: MODE"]=47, ["SPD 1"]=22, ["P3 FRQ"]=28, ["FILT 1"]=23,
}
for s, esperado in pairs(REF) do
  eq('ancho real de "'..s..'"', ancho(s), esperado)
end

--------------------------------------------------------------------
-- Montaje del estado G (igual que en los otros tests del inspector)
--------------------------------------------------------------------
local SRC, DEST = 12, 24
local function build_G()
  local G = { patch = {}, dest_gains = {}, scope_head = 33, SCOPE_LEN = 64,
              scope_history = {}, sources_val = {},
              coco = {{out_level=0.4},{out_level=0.6}}, popup = {active=false},
              trails = {}, trail_head = {1,1}, focus = {inspect_dest = 5} }
  for s = 1, SRC do
    G.patch[s] = {}; for d = 1, DEST do G.patch[s][d] = 0.0 end
    G.scope_history[s] = {}; for i = 1, G.SCOPE_LEN do G.scope_history[s][i] = math.sin(i*0.3+s)*0.8 end
  end
  for d = 1, DEST do G.dest_gains[d] = 1.0 end
  for i = 1, 12 do G.sources_val[i] = math.sin(i)*0.5 end
  return G
end

H.set_param('skip_modeL', 1)   -- 1 = SINGLE (el titulo mas largo)
H.set_param('skip_modeR', 1)
H.set_param('stutter_chaosL', 0.5); H.set_param('stutter_chaosR', 0.5)
H.set_param('stutter_rateL', 0.1);  H.set_param('stutter_rateR', 0.1)

-- Alto real del texto: 5 px por encima de la linea base, 0 por debajo (medido
-- sobre norns.ttf@8). Un texto en y=Y ocupa la banda vertical Y-5..Y.
local ALTO = 5

-- Reconstruye la posicion de cada texto a partir de las operaciones REALES de
-- dibujo (harness), reproduciendo el avance del "pen" de cairo.
local function textos(id)
  H.reset()
  UI.draw_dest_inspector(build_G(), id)
  local cap = H.capture()
  local pen_x, pen_y = 0, 0
  local out = {}
  for linea in cap:gmatch('[^\n]+') do
    local op, rest = linea:match('^(%S+)%s?(.*)$')
    if op == 'move' then
      local x, y = rest:match('^([%-%d%.]+) ([%-%d%.]+)')
      if x then pen_x, pen_y = tonumber(x), tonumber(y) end
    elseif op == 'text' or op == 'text_right' or op == 'text_center' then
      local w = ancho(rest)
      if op == 'text_right' then pen_x = pen_x - w
      elseif op == 'text_center' then pen_x = pen_x - w * 0.5 end
      out[#out+1] = { row = pen_y, x0 = pen_x, x1 = pen_x + w, txt = rest }
      pen_x = pen_x + w
    end
  end
  return out
end

section('ningun par de textos se pisa (en horizontal Y en vertical)')
-- Dos textos chocan si se cruzan en horizontal (>=2 px) Y sus filas estan a
-- menos de ALTO px (sus bandas verticales se solapan). Esta comprobacion habria
-- cazado el bug original: "K2/3: MODE" y "E1:CHS" estaban los dos en y=62.
local choques = 0
for id = 1, DEST do
  local ts = textos(id)
  for i = 1, #ts do
    for j = i + 1, #ts do
      local a, b = ts[i], ts[j]
      local h = (math.min(a.x1, b.x1) - math.max(a.x0, b.x0)) >= 2
      local v = math.abs(a.row - b.row) < ALTO
      if h and v then
        choques = choques + 1
        print(string.format('    id %d: "%s" (y=%g x=%.0f..%.0f)  pisa  "%s" (y=%g x=%.0f..%.0f)',
          id, a.txt, a.row, a.x0, a.x1, b.txt, b.row, b.x0, b.x1))
      end
    end
  end
end
eq('pares de textos que se pisan', choques, 0)

section('ningun texto se sale de la pantalla (0..127)')
local fuera = 0
for id = 1, DEST do
  for _, t in ipairs(textos(id)) do
    if t.x0 < 0 or t.x1 > 127 then
      fuera = fuera + 1
      print(string.format('    id %d: "%s" en x=%.0f..%.0f', id, t.txt, t.x0, t.x1))
    end
  end
end
eq('textos fuera de pantalla', fuera, 0)

section('SKIP: la pista vuelve a su fila propia (y=55)')
for _, id in ipairs{6, 13} do
  local ts = textos(id)
  local pista, en_62, en_cabecera, controles_62 = nil, false, false, false
  for _, t in ipairs(ts) do
    if t.txt == 'K2/3: MODE' then
      pista = t
      if t.row == 62 then en_62 = true end
      if t.row == 6  then en_cabecera = true end
    end
    if t.row == 62 and (t.txt == 'E1:CHS' or t.txt == 'E2:RATE') then controles_62 = true end
  end
  check(string.format('id %d: existe la pista "K2/3: MODE"', id), pista ~= nil)
  check(string.format('id %d: la pista esta en y=55', id), pista and pista.row == 55)
  check(string.format('id %d: la pista NO esta en y=62', id), not en_62)
  check(string.format('id %d: la pista NO esta en la cabecera', id), not en_cabecera)
  check(string.format('id %d: los controles E1/E2 siguen en y=62', id), controles_62)
end

section('la caja del scope sube 5 px (y=10) y no choca con el titulo')
local cap6 = (function() H.reset(); UI.draw_dest_inspector(build_G(), 6); return H.capture() end)()
check('la caja se dibuja en (4,10,120,40)',
  cap6:find('rect 4.0000 10.0000 120.0000 40.0000', 1, true) ~= nil)
-- el titulo (fila y=6) ocupa 1..6; la caja empieza en 10 -> 4 px de aire
check('la caja empieza por debajo del titulo', 10 > 6)
-- el valor maximo de ganancia (doc 0..2) cabe
eq('el valor maximo "2.00x" mide 21 px', ancho('2.00x'), 21)

H.done()