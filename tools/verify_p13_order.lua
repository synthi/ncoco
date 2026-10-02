-- Verificacion del punto #13 de la Fase 3: ¿se puede usar busqueda binaria?
--
-- El secuenciador recorre TODOS los eventos en cada ventana de tiempo:
--   for _, event in ipairs(s.data) do
--      if event.dt >= t_start and event.dt < t_end then ... end
--   end
-- Con muchos eventos son ~1,2 millones de comprobaciones por segundo.
-- La busqueda binaria evitaria eso, PERO solo funciona si s.data esta
-- ordenado por dt.
--
-- Esta test replica la logica de grabacion REAL de lib/grid_nav.lua:102-116
-- y comprueba si los datos llegan ordenados al reproducirse:
--
--   state 1 = GRABANDO   dt = now - start_time            -> crece solo
--   state 4 = OVERDUB    dt = (now - start_time) % duration
--                        y despues table.sort (linea 113)
--
-- En overdub el dt puede "darse la vuelta" y ser MENOR que el del ultimo
-- evento ya presente. La unica defensa es el table.sort de la linea 113.
-- Esta test comprueba que ese sort basta, en vez de suponerlo.

--------------------------------------------------------------------
-- Estado de un secuenciador, igual que lib/globals.lua:29-39
--------------------------------------------------------------------
local function nuevo_sequenciador()
  return { data = {}, state = 0, playhead = 0.0, start_time = 0, duration = 0 }
end

local reloj = 0.0
local function ahora() return reloj end

-- GRABACION: copia de lib/grid_nav.lua:102-116
local function pulsar(s, x, y, z)
  local now = ahora()
  if s.state == 1 or s.state == 4 then
    local dt = now - s.start_time
    if s.state == 4 and s.duration > 0 then dt = dt % s.duration end
    if #s.data < 10000 then
      table.insert(s.data, { x = x, y = y, z = z, dt = dt })
    end
    if s.state == 4 then table.sort(s.data, function(a, b) return a.dt < b.dt end) end
  end
end

local function esta_ordenada(data)
  for i = 2, #data do
    if data[i - 1].dt > data[i].dt then return false, i end
  end
  return true, 0
end

-- Escenario 1: grabar y reproducir (states 0 -> 1 -> 2)
local function escenario_grabacion(n, semilla)
  math.randomseed(semilla)
  local s = nuevo_sequenciador()
  s.state = 1; s.data = {}; s.start_time = ahora()
  for i = 1, n do
    reloj = reloj + math.random() * 0.09
    pulsar(s, i % 16, i % 8, 1)
  end
  local ok, pos = esta_ordenada(s.data)
  s.duration = ahora() - s.start_time
  if s.duration < 0.1 then s.duration = 0.1 end
  s.state = 2; s.start_time = ahora()
  return s, ok, pos
end

-- Escenario 2: overdub sobre una grabacion en curso (states 0 -> 1 -> 4).
-- Caso peligroso: el dt se toma modulo la duracion y puede salir menor.
local function escenario_overdub(n, semilla)
  math.randomseed(semilla)
  local s = nuevo_sequenciador()
  s.state = 1; s.data = {}; s.start_time = ahora()
  for i = 1, n do
    reloj = reloj + math.random() * 0.09
    pulsar(s, i % 16, i % 8, 1)
  end
  s.duration = ahora() - s.start_time
  if s.duration < 0.1 then s.duration = 0.1 end

  s.state = 4
  s.start_time = ahora()
  for i = 1, n do
    reloj = reloj + math.random() * 0.05
    pulsar(s, (i * 3) % 16, (i * 5) % 8, 1)
  end
  local ok, pos = esta_ordenada(s.data)
  return s, ok, pos
end

--------------------------------------------------------------------
local fallos = 0

local function comprobar(nombre, s, ok, pos)
  local n = #s.data
  if n == 0 then
    print(string.format('  --   %s (sin eventos)', nombre))
    return
  end
  if ok then
    print(string.format('  PASA %s: %d eventos, ORDENADOS (la binaria es valida)', nombre, n))
  else
    fallos = fallos + 1
    print(string.format('  FALLA %s: %d eventos DESORDENADOS en pos %d (dt %s > %s)', nombre, n, pos,
      tostring(s.data[pos - 1].dt), tostring(s.data[pos].dt)))
  end
end

print('== #13: ¿los eventos llegan ordenados cuando se reproducen? ==')
print('')
print('-- Escenario 1: grabar y reproducir --')
comprobar('20 eventos',   escenario_grabacion(20, 1))
comprobar('500 eventos',  escenario_grabacion(500, 2))
comprobar('3000 eventos', escenario_grabacion(3000, 3))
print('')
print('-- Escenario 2: overdub (el dt da la vuelta; el sort debe arreglarlo) --')
comprobar('20 + 20',      escenario_overdub(20, 11))
comprobar('500 + 500',    escenario_overdub(500, 12))
comprobar('3000 + 3000',  escenario_overdub(3000, 13))

print('')
if fallos == 0 then
  print('RESULTADO: los datos SIEMPRE llegan ordenados.')
  print('La busqueda binaria es aplicable, pero solo si se mantiene la garantia.')
else
  print(string.format('RESULTADO: %d escenarios con datos desordenados.', fallos))
  print('La busqueda binaria NO es aplicable sin ordenar antes.')
end