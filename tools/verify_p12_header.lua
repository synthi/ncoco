-- Comprobacion de la CABECERA del inspector de destinos.
--
-- Al compactar "IN GAIN" y su valor en una sola linea hay que asegurarse de
-- que ningun texto se sale de la pantalla ni se solapa con otro.
--
-- La fuente de norns es de 6 px de ancho por caracter (fuente 6x13), asi que
-- un texto de N caracteres ocupa 6*N pixeles.

local ANCHO_CARACTER = 6
local PANTALLA = 128

local function ancho(txt) return #txt * ANCHO_CARACTER end

local function comprobar(nombre, x, txt, alineado_derecha)
  local w = ancho(txt)
  local x0, x1
  if alineado_derecha then
    x1 = x
    x0 = x - w
  else
    x0 = x
    x1 = x + w
  end
  local dentro = x0 >= 0 and x1 <= PANTALLA
  print(string.format('  %-22s x=%3d..%3d  (%2d car.)  %s', nombre, x0, x1, #txt,
    dentro and 'PASA' or 'FALLA (se sale de 128)'))
  return x0, x1
end

print('== cabecera del inspector de destinos: que nada se salga ni se solape ==')
print('')

-- texto mas largo de cada tipo
local TITULO_MAX = 'SKIP 1: SINGLE'   -- el destino mas largo (skip)
local TITULO_TIPICO = 'SPD 1'
local SUB = 'K2/3: MODE'
local GAIN_MAX = '12.34x'

local x_tit0, x_tit1 = comprobar('titulo (mas largo)', 4, TITULO_MAX, false)
local x_sub0, x_sub1 = comprobar('sub (derecha)', 126, SUB, true)
print('')
comprobar('titulo (tipico)', 4, TITULO_TIPICO, false)
comprobar('etiqueta IN GAIN', 5, 'IN GAIN', false)
comprobar('valor gain (max)', 50, GAIN_MAX, false)

print('')
print('SOLAPES EN LA MISMA LINEA (y=6):')
local solapa_tit_sub = (x_tit1 > x_sub0)
if solapa_tit_sub then
  print(string.format('  ATENCION: el titulo mas largo llega a %d y la sub empieza en %d (se cruzan %d px)',
    x_tit1, x_sub0, x_tit1 - x_sub0))
else
  print(string.format('  PASA  titulo %d..%d y sub %d..%d no se tocan', x_tit0, x_tit1, x_sub0, x_sub1))
end

print('')
print('SOLAPES EN LA LINEA DEL GAIN (y=16):')
local _, lbl1 = comprobar('  etiqueta', 5, 'IN GAIN', false)
local v0, v1 = comprobar('  valor', 50, GAIN_MAX, false)
if lbl1 > v0 then
  print(string.format('  FALLA la etiqueta llega a %d y el valor empieza en %d', lbl1, v0))
else
  print(string.format('  PASA  etiqueta 5..%d y valor %d..%d no se tocan', lbl1, v0, v1))
end

print('')
print('LINEAS VERTICALES USADAS:')
print('  y=6   titulo (izq) + sub (der)')
print('  y=16  IN GAIN + valor')
print('  y=22  borde superior de la caja')
print('  y=57  borde inferior de la caja')
print('  y=62  pista inferior')
print('')
print('El alto de la fuente es 13 px, asi que el titulo ocupa de 6 a 19 y el')
print('gain de 16 a 29: se solapan en las filas 16..19. Eso ya ocurria antes')
print('(el gain estaba en y=10..23 y el titulo en y=20..33) y no se nota')
print('porque los caracteres no ocupan toda la caja del glifo.')