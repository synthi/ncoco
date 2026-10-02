-- Redimension del scope del inspector de destinos.
--
-- ESPACIO REAL de la pantalla: 128 x 64.
-- La fuente de norns mide 6 px de ancho por caracter.
--
-- Lo que ocupaba antes:
--   y=10  "IN GAIN:"          (alineado a la derecha)
--   y=18  valor de la ganancia (alineado a la derecha)
--   y=20  titulo (centrado)
--   y=30..54  caja del scope  (108 x 25)
--   y=62  pista inferior
-- -> la cabecera se comia 2 lineas enteras solo para el gain.
--
-- Lo que se propone: titulo y gain en UNA sola linea, y la caja desde y=14.
--
--   y=8   titulo (izquierda) + IN GAIN + valor (derecha)
--   y=14..57   caja del scope (116 x 43)
--   y=62  pista inferior
--
-- COLISION A EVITAR: el titulo mas largo es "SKIP 1: SINGLE" (14 car = 84 px).
-- Con la etiqueta "IN GAIN" a la derecha no caben en la misma linea, asi que
-- los destinos 6 y 13 (SKIP) muestran "K2/3" a la derecha y su valor de
-- ganancia va solo, sin etiqueta.

local ANCHO_CARACTER = 6
local PANTALLA_W, PANTALLA_H = 128, 64

local function ancho(t) return #t * ANCHO_CARACTER end

print('== cuanto cabe en una linea de 128 px ==')
print('')

local titulos = {
  { t = 'SPD 1',            x = 4,    car = 5  },
  { t = 'AUD IN 1',         x = 4,    car = 7  },
  { t = 'P3 FRQ',           x = 4,    car = 6  },
  { t = 'SKIP 1: AUTO',     x = 4,    car = 12 },
  { t = 'SKIP 1: SINGLE',   x = 4,    car = 14 },
}

for _, v in ipairs(titulos) do
  local fin = v.x + ancho(v.t)
  print(string.format('  titulo %-16s %2d car -> x=%3d..%3d', v.t, v.car, v.x, fin))
end
print('')
print('  etiqueta "IN GAIN" alineada a la derecha en x=92  -> x=50..92')
print('  valor "0.85x" alineado a la derecha en x=126        -> x=96..126')
print('  sub "K2/3" alineado a la derecha en x=126            -> x=102..126')
print('')

local function chk(etiqueta, ok, detalle)
  print(string.format('  %s  %s%s', ok and 'PASA ' or 'FALLA', etiqueta,
    detalle and ('  -> ' .. detalle) or ''))
end

print('COLISIONES:')
-- titulo tipico mas largo sin SKIP: "AUD IN 1" = 7 car -> 4..46
chk('titulo normal + etiqueta IN GAIN',
  (4 + ancho('AUD IN 1')) <= 50,
  string.format('el mas largo acaba en %d, la etiqueta empieza en 50', 4 + ancho('AUD IN 1')))

-- titulo mas largo con SKIP: 14 car -> 4..88, debe caber con "K2/3" (102..126)
chk('titulo mas largo (SKIP) + sub K2/3',
  (4 + ancho('SKIP 1: SINGLE')) <= 102,
  string.format('el titulo acaba en %d, la sub empieza en 102', 4 + ancho('SKIP 1: SINGLE')))

-- etiqueta y valor no se tocan
chk('etiqueta IN GAIN y valor no se tocan', 92 <= 96, 'etiqueta acaba en 92, valor empieza en 96')

print('')
print('CAJA:')
local BOX_X, BOX_Y, BOX_W, BOX_H = 6, 14, 116, 43
local antes_w, antes_h = 108, 25

chk('cabe en la pantalla',
  BOX_X + BOX_W <= PANTALLA_W and BOX_Y + BOX_H <= 60,
  string.format('extremo derecho %d de %d; extremo inferior %d, la pista empieza en 62',
    BOX_X + BOX_W, PANTALLA_W, BOX_Y + BOX_H))

chk('deja sitio para la linea de texto de y=8',
  BOX_Y >= 12, string.format('la caja empieza en y=%d', BOX_Y))

print('')
print(string.format('  ALTO:  de %d a %d px  (%+.0f%%)', antes_h, BOX_H,
  (BOX_H - antes_h) / antes_h * 100))
print(string.format('  ANCHO: de %d a %d px  (%+.0f%%)', antes_w, BOX_W,
  (BOX_W - antes_w) / antes_w * 100))
print(string.format('  AREA:  de %d a %d px  (x%.2f)', antes_w * antes_h,
  BOX_W * BOX_H, (BOX_W * BOX_H) / (antes_w * antes_h)))
print(string.format('  ondas: de 108 a %d puntos', BOX_W - 1))
print('')
print(string.format('  cero en y=%.1f (antes y=42.5)', BOX_Y + BOX_H / 2))
print(string.format('  umbral en y=%d (antes 36, un 24%% desde arriba de la caja)',
  BOX_Y + math.floor(BOX_H * 0.25)))