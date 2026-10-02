-- Que hacen K2 y K3 en cada pantalla.
--
-- El autor reporto: "deberia ser K2 rec coco1 y k3 rec coco2, pero parece que
-- esta siendo K2 rec COCOS 1 y 2 y k3 nada".
--
-- CAUSA. En ncoco.lua la rama sin foco tenia UNA sola linea:
--     params:set("recL", v); params:set("recR", v)
-- Las DOS grabaciones en el mismo gesto de K2, y K3 no tenia rama propia.
--
-- Ademas el codigo llegaba ahi tambien desde DOS popups (fuentes 7..10 y
-- destinos que no son SKIP), porque esos casos no tenian return: K2 "grababa"
-- con el inspector abierto.
--
-- ARREGLO: solo en la pantalla principal (mismo criterio que redraw()), K2 ->
-- recL (COCO 1) y K3 -> recR (COCO 2).
--
-- Este test ejecuta key() REAL. ncoco.lua se carga entero en el banco de pruebas
-- y se captura la tabla G que devuelve lib/globals.lua a traves del stub de
-- include.

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')

-- ncoco.lua usa el global _path de norns para crear ~/dust/audio/ncoco.
_G._path = setmetatable({audio = '/tmp/'},
  {__index = function() return '/tmp/' end})

local inner_include = _G.include
local G = nil
_G.include = function(path)
  local mod = inner_include(path)
  if path:find('globals') then G = mod end
  return mod
end

local ok_load, err_load = pcall(dofile, 'ncoco.lua')

section('0. ncoco.lua se carga en el banco de pruebas')
check('ncoco.lua carga', ok_load, tostring(err_load))
check('key() es funcion', type(rawget(_G, 'key')) == 'function')
check('G capturada', G ~= nil)
if not ok_load or G == nil or type(rawget(_G, 'key')) ~= 'function' then
  H.done()
end

-- key() se niega a funcionar mientras G.loaded es false (estado inicial de
-- lib/globals.lua). Sin esto TODAS las comprobaciones pasarian por vacias.
G.loaded = true

local function focus(src, last_dest, edit_l, edit_r, inspect_dest)
  G.focus.source = src;           G.focus.last_dest = last_dest
  G.focus.edit_l = edit_l;        G.focus.edit_r = edit_r
  G.focus.inspect_dest = inspect_dest
end
local function reset()
  G.loaded = true
  focus(nil, nil, nil, nil, nil)
  H.set_param('recL', 0); H.set_param('recR', 0)
  H.set_param('bitsL', 1); H.set_param('bitsR', 1)
  H.set_param('p1range', 1); H.set_param('p1shape', 1)
  H.set_param('coco1_out_mode', 1)
end
local function get(k) return H.params:get(k) end

section('1. PANTALLA PRINCIPAL: K2 = COCO 1, K3 = COCO 2')
reset()
key(2, 1)
eq('K2 graba solo COCO 1', get('recL'), 1)
eq('K2 NO toca COCO 2', get('recR'), 0)
key(3, 1)
eq('K3 graba solo COCO 2', get('recR'), 1)
eq('K3 no cambia COCO 1', get('recL'), 1)
key(2, 1)
eq('K2 vuelve a apagar COCO 1', get('recL'), 0)
eq('COCO 2 sigue grabando', get('recR'), 1)
key(3, 1)
eq('K3 apaga COCO 2', get('recR'), 0)
reset()
key(1, 1)
eq('K1 no hace nada', get('recL'), 0)

section('2. POPUP DE FUENTE (ENV 1): K2/K3 no graban')
reset()
focus(7, nil, nil, nil, nil)
key(2, 1); key(3, 1)
eq('K2 no graba en el popup de fuente', get('recL'), 0)
eq('K3 no graba en el popup de fuente', get('recR'), 0)

section('3. POPUP DE DESTINO (FILT 1): K2/K3 no graban')
reset()
focus(nil, nil, nil, nil, 5)
key(2, 1); key(3, 1)
eq('K2 no graba en el inspector de destino', get('recL'), 0)
eq('K3 no graba en el inspector de destino', get('recR'), 0)

section('4. POPUP DE PETALO: K2 cambia range, no graba')
reset()
focus(1, nil, nil, nil, nil)
key(2, 1)
eq('K2 cambia el range del petalo', get('p1range'), 3 - 1)
eq('K2 no graba con el petalo abierto', get('recL'), 0)

section('5. POPUP COCO: K2 cambia el modo, no graba')
reset()
focus(11, nil, nil, nil, nil)
key(2, 1)
eq('K2 cambia el modo de COCO 1', get('coco1_out_mode'), 3 - 1)
eq('K2 no graba con el popup COCO abierto', get('recL'), 0)

section('6. MENU EDIT L: K3 cambia bits, no graba')
reset()
focus(nil, nil, true, nil, nil)
key(3, 1)
eq('K3 cambia los bits', get('bitsL'), (1 % 4) + 1)
eq('K3 no graba con el menu de edicion abierto', get('recL'), 0)
eq('K3 no graba COCO 2 en edicion', get('recR'), 0)

section('7. el menu de edicion de la derecha tambien')
reset()
focus(nil, nil, nil, true, nil)
key(3, 1)
eq('K3 cambia los bits de la derecha', get('bitsR'), (1 % 4) + 1)
eq('sin grabacion', get('recR'), 0)

H.done()