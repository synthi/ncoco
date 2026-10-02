-- Congelado del grid: que se detecta, que se recupera y que NO se toca a ciegas.
--
-- Historial (por que este test cambio):
--   7956c34 metio un pcall "por si fallaba Lua". No era eso.
--   Luego se anadio un watchdog que solo REGISTRABA.
--   REPRO REAL (en directo): el grid se volvio a congelar, maiden NO imprimio
--   NADA, y cargar un pset no lo recupero; hubo que reiniciar ncoco.
--   => el silencio del latido prueba que el redraw de Lua SEGUIA latiendo y que
--      g.device NO era nil. Es decir: el congelado NO era ninguna de las causas
--      que Lua ve. Combinado con device_monome.cc (g:led marca dirty SIN
--      comparar el valor => el desfase de cache se auto-curaria en 5 s), queda
--      que el corte esta POR DEBAJO de Lua (serial/USB de monome o binding
--      dispositivo<->vport).
--   Por eso ahora, ademas de detectar, se RECUPERA en caliente rehaciendo lo que
--   un reinicio de norns le hace a la rejilla (verificado en lua/core/script.lua:
--   Script.clear -> grid.cleanup() = dev:all(0)+dev:refresh() y metro.free_all()).

local fails = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FALLA " .. name .. (detail and ("  -- " .. detail) or "")); fails = fails + 1 end
end
local function read(p) local f = io.open(p, 'r'); local s = f:read('*a'); f:close(); return s end

local ncoco = read('ncoco.lua')
local nav   = read('lib/grid_nav.lua')
local ui    = read('lib/ui.lua')
local gl    = read('lib/globals.lua')

-- Las comprobaciones NEGATIVAS deben mirar CODIGO, no comentarios: un comentario
-- que explique "lo rearmaria engine.load()" no es una llamada a engine.load().
local function strip_comments(s)
  local out = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    local i, cut, inq = 1, nil, false
    while i <= #line do
      local c = line:sub(i, i)
      if c == "'" then inq = not inq
      elseif not inq and c == '-' and line:sub(i + 1, i + 1) == '-' then cut = i; break end
      i = i + 1
    end
    out[#out + 1] = cut and line:sub(1, cut - 1) or line
  end
  return table.concat(out, '\n')
end
local ncoco_code = strip_comments(ncoco)

print("1. El OSC marca su llegada; se cubre tambien 'nunca arranco'")
check("osc.event actualiza G.last_osc_time", ncoco:match('G%.last_osc_time%s*=%s*util%.time%(%)'))
check("globals inicializa last_osc_time", gl:match('last_osc_time%s*=%s*0'))
check("avisa si no llego ni un /update (last_osc_time == 0)",
      ncoco:match('OSC NEVER STARTED'),
      "antes el guardia exigia > 0 y ese caso quedaba invisible")

print("2. El OSC parado (causa de SC) NO se toca a ciegas")
-- /update lo emite SendReply.kr dentro del synth de SC (Engine_Ncoco.sc). Solo
-- lo rearmaria engine.load(), que re-asigna los buffers de 60 s -> corta audio.
check("recover no recarga el motor", not ncoco_code:match('engine%.load%s*%('),
      "engine.load() cortaria el audio en directo")
check("avisa del OSC parado", ncoco:match('OSC STALLED'))

print("3. Recuperacion en caliente del grid (recover_grid)")
check("esta definida", ncoco:match('local function recover_grid'))
check("se expone a maiden para el caso no detectable",
      ncoco:match('_G%.recover_grid%s*=%s*function'))
check("fuerza reenvio completo (all + refresh)",
      ncoco:match('g:all%(0%); g:refresh%(%)'))
check("reinicia el metro (stop/start reusa id, sin fuga)",
      ncoco:match('grid_metro:stop%(%); grid_metro:start%(%)'))
check("reengancha el vport con dispositivo", ncoco:match('GridNav%.find_device_port%(%)'))
check("se dispara sola ante 'sin redraw'", ncoco:match('recover_grid%("sin redraw"%)'))
check("se dispara sola ante 'g.device nil'", ncoco:match('recover_grid%("g.device nil"%)'))
check("el pcall de redraw usa recover_grid (no un all(0) suelto)",
      ncoco:match('recover_grid%("redraw error x10"%)'))

print("4. grid.add engancha EL vport del dispositivo, no el 1 a ciegas")
check("grid.add recibe el dispositivo", ncoco:match('grid%.add%s*=%s*function%(dev%)'))
local addblock = ncoco:match('grid%.add%s*=%s*function%(dev%)(.-)grid_was_attached')
check("dentro de grid.add usa dev.port", addblock and addblock:match('g%s*=%s*grid%.connect%(port%)'))
check("dentro de grid.add NO hay un grid.connect() a ciegas",
      addblock and not addblock:match('grid%.connect%(%)'),
      "un connect sin arg dentro de grid.add fijaria vport 1 a ciegas")

print("5. find_device_port: SIMULADO con vports reales")
-- Se EJECUTA el codigo real de grid_nav.lua con un grid falso cuyo vport 3 SI
-- tiene dispositivo. Demuestra que se ESCANEA (no se asume el 1).
local function with_grid(vports, fn)
  local saved_include, saved_grid = _G.include, _G.grid
  _G.include = function() return {} end
  _G.grid = { connect = function(n) return vports[n] end }
  local ok, res = pcall(fn)
  _G.include, _G.grid = saved_include, saved_grid
  return ok, res
end
local vp3 = { [1]={device=nil}, [2]={device=nil}, [3]={device={}}, [4]={device=nil} }
local vp_none = { [1]={device=nil}, [2]={device=nil}, [3]={device=nil}, [4]={device=nil} }
local ok3, found3 = with_grid(vp3, function()
  local mod = assert(loadfile('lib/grid_nav.lua'))(); return mod.find_device_port()
end)
local ok0, found0 = with_grid(vp_none, function()
  local mod = assert(loadfile('lib/grid_nav.lua'))(); return mod.find_device_port()
end)
check("grid_nav.lua carga y localiza el vport 3 (no asume el 1)",
      ok3 and found3 == 3, "ok="..tostring(ok3).." found="..tostring(found3))
check("devuelve nil si ningun vport tiene dispositivo",
      ok0 and found0 == nil, "ok="..tostring(ok0).." found="..tostring(found0))

print("6. Ningun estado puede quedar colgado")
check("el flash de snap expira por tiempo, no por flag",
      nav:match('util%.time%(%)%s*-%s*flash%s*%)%s*<%s*1%.6'),
      "snap_timers volveria a depender de una corrutina")
check("refresh() se llama siempre (no solo si cambio algo)",
      nav:match('\n%s+g:refresh%(%)%s*\n') ~= nil and
      nav:match('\n%s+if changed then g:refresh') == nil)
check("ui.lua protege sources_val[7]", ui:match('%(G%.sources_val%[7%] or 0%)'))

if fails > 0 then
  print("RESULTADO: " .. fails .. " fallos")
  os.exit(1)
end
print("RESULTADO: deteccion + recuperacion del grid presentes y simuladas")