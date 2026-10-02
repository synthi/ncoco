-- Bug: snapshots borrados por toques cortos y seguidos.
--
-- Sintoma real que describia el autor: sin mantener pulsado, dando al boton muy
-- seguido, un dia de esos aparece "cleared" y el snapshot desaparece. Sin patron
-- claro y no reproducible a proposito.
--
-- CAUSA (lib/grid_nav.lua): al pulsar se guardaba el tiempo en
-- GridNav.snap_timers[id] y se lanzaba una corrutina que dormia 1.6s y hacia:
--       if GridNav.snap_timers[obj.id] ~= 0 then ... snap_clear ...
-- Ese valor es COMPARTIDO por todos los toques. La corrutina de un toque VIEJA,
-- al despertar mientras un toque NUEVO estaba activo, veia un sello distinto de
-- 0 (el del toque nuevo) y borraba, aunque ese toque durara milisegundos.
--
-- Con el ritmo real de un humano (un toque cada 300ms) la primera pulsacion
-- vence 1.6s despues, que cae DENTRO de la pulsacion n.6. Asi que tarde o
-- temprano dispara: por eso "sin patron claro".
--
-- Arreglo: cada corrutina lleva capturado SU PROPIO sello y solo actua si el
-- sello sigue siendo exactamente el suyo (release -> 0, otro toque -> distinto).
--
-- Ejecuta GridNav.key REAL, no una copia. El harness controla util.time() y
-- clock, asi que los tiempos son exactos y reproducibles.
--
-- CONTROL NEGATIVO (que el test caza el bug de verdad):
--   git show 45c06fd:lib/grid_nav.lua > /tmp/grid_nav_buggy.lua
--   lua tools/verify_p26_snap_taps.lua /tmp/grid_nav_buggy.lua   -> DEBE fallar
-- 45c06fd es la ultima version ANTES de este fix: con ella el test da 6 fallos
-- y muestra 11 clear1 espurios en la sesion de 16 toques.

package.path = './?.lua;' .. package.path
local H = dofile('tools/harness.lua')

local GRID_NAV_PATH = (arg and arg[1]) or 'lib/grid_nav.lua'

-- Reloj controlado: clock.run guarda la corrutina con su vencimiento;
-- clock.sleep no hace nada (la corrutina llega a la comprobacion cuando
-- avanzamos el reloj manualmente).
local jobs = {}
local fired_active = 0   -- corrutinas que vencieron con un press ACTIVO

_G.clock.run = function(f)
  jobs[#jobs + 1] = { f = f, due = (H.fake_time or 0) + 1.6 }
  return #jobs
end
_G.clock.sleep = function() end

local GridNav = dofile(GRID_NAV_PATH)

local log = {}
local function advance_to(t)
  H.fake_time = t
  local work = true
  while work do
    work = false
    for i, job in ipairs(jobs) do
      if job.due <= t then
        table.remove(jobs, i)
        local st = GridNav.snap_timers[1]
        if st and st ~= 0 and st ~= -1 then fired_active = fired_active + 1 end
        job.f()
        work = true
        break
      end
    end
  end
end

local G = {}
GridNav.init_map(G)
G.sequencers = nil
G.active_snapshot = 0
G.snapshots = {}
function G.snap_save(id)    log[#log+1] = 'save'..id;    G.snapshots[id] = {d = 1} end
function G.snap_update(id)  log[#log+1] = 'update'..id end
function G.snap_load(id)    log[#log+1] = 'load'..id end
function G.snap_clear(id)   log[#log+1] = 'clear'..id;   G.snapshots[id] = nil end

local function reset()
  jobs = {}
  fired_active = 0
  GridNav.snap_timers = {}
  GridNav.debounce = {}
  G.snapshots = {}
  G.active_snapshot = 0
  log = {}
end

-- Snapshots: x=1..4, y=1 (id = x). Siempre probamos el boton 1.
local function press(t, x)   H.fake_time = t; GridNav.key(G, nil, x, 1, 1, false) end
local function release(t, x) H.fake_time = t; GridNav.key(G, nil, x, 1, 0, false) end
local function has_clear() return table.concat(log, ''):find('clear') ~= nil end

--------------------------------------------------------------------
-- RITMO HUMANO REALISTA
--   pulsacion: 120..160 ms (rango natural de un toque en la rejilla)
--   separacion entre toques: 300 ms -> 3.3 toques por segundo
--   16 toques -> 4.6 s de sesion completa
--------------------------------------------------------------------
local T0 = 100                      -- reloj inicial, tipo util.time() de norns
local PERIOD = 0.30                 -- 3.3 toques/segundo
local HOLDS = { 0.13, 0.15, 0.12, 0.14, 0.16, 0.13, 0.15, 0.12,
                0.14, 0.13, 0.16, 0.12, 0.15, 0.14, 0.13, 0.15 }
local NTAPS = #HOLDS                -- 16

print(string.format('  ritmo: %d toques en %.1fs (%.1f toques/s), pulsacion %.0f-%.0f ms',
  NTAPS, NTAPS * PERIOD, 1 / PERIOD,
  math.min(table.unpack(HOLDS)) * 1000, math.max(table.unpack(HOLDS)) * 1000))

-- Toca n veces con ese ritmo. El reloj avanza DURANTE cada pulsacion, que es
-- donde estan las ventanas de riesgo (la corrutina de un toque venciendo dentro
-- de otro toque). Devuelve el tiempo final.
local function session(n)
  local t = T0
  for k = 1, n do
    local hold = HOLDS[(k - 1) % NTAPS + 1]
    press(t, 1)
    advance_to(t + hold)
    release(t + hold, 1)
    t = t + PERIOD
  end
  advance_to(t + 1.0)   -- corrutinas residuales, fuera de pulsacion
  return t
end

section('1. un toque corto real (130 ms): guarda y no se borra')
reset()
press(T0, 1)
release(T0 + 0.13, 1)
check('guarda el snapshot', G.snapshots[1] ~= nil, 'log='..table.concat(log, ','))
advance_to(T0 + 5.0)
check('la corrutina vencida no lo borra', G.snapshots[1] ~= nil)

section('2. la 1a pulsacion vence DENTRO de una pulsacion posterior (el bug)')
reset()
session(8)
check('la ventana de riesgo se ejercito', fired_active > 0, 'fired_active='..fired_active)
check('NO borra aunque vence con un press activo', not has_clear(),
      'log='..table.concat(log, ','))
check('el snapshot sigue ahi', G.snapshots[1] ~= nil)

section('3. mantener >1.6s SI borra (gesto de borrado por diseño)')
reset()
G.snapshots[1] = {d = 1}
press(T0, 1)
advance_to(T0 + 1.7)
check('borra al mantener >1.6s', G.snapshots[1] == nil, 'log='..table.concat(log, ','))
check('se registra clear', has_clear())
release(T0 + 1.8, 1)
check('el release tras el clear no hace nada', G.snapshots[1] == nil)

section(string.format('4. sesion realista: %d toques en %.1fs', NTAPS, NTAPS * PERIOD))
reset()
G.snapshots[1] = {d = 1}
session(NTAPS)
check('la ventana se ejercito (no es un test vacio)', fired_active > 0,
      'fired_active='..fired_active)
check('ningun clear durante la sesion', not has_clear(), 'log='..table.concat(log, ','))
check('el snapshot sigue ahi al final', G.snapshots[1] ~= nil)
local loads = 0
for _ in table.concat(log, ','):gmatch('load1') do loads = loads + 1 end
check('todos los toques actuaron (si no, el test no vale)', loads == NTAPS, 'loads='..loads)

section('5. release sin press previo no lanza error de aritmetica')
reset()
local ok = pcall(function() GridNav.key(G, nil, 1, 1, 0, false) end)
check('release sin press no revienta', ok)

print('')
print('  codigo bajo prueba: ' .. GRID_NAV_PATH)
H.done()