-- Reproduce el congelado del grid: los valores dejan de llegar por OSC y la
-- rejilla se queda con el ultimo brillo recibido (tipicamente 15) aunque siga
-- respondiendo a las pulsaciones.
-- Contexto: 7956c34 metio un pcall por si fallaba Lua. No era eso: Lua nunca
-- fallaba. Lo que se detenia eran los DATOS. Este test comprueba las dos
--properties que lo evitan.

local fails = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FALLA " .. name .. (detail and ("  -- " .. detail) or "")); fails = fails + 1 end
end

local f = io.open('ncoco.lua', 'r'); local ncoco = f:read('*a'); f:close()
local f = io.open('lib/grid_nav.lua', 'r'); local nav = f:read('*a'); f:close()
local f = io.open('lib/ui.lua', 'r'); local ui = f:read('*a'); f:close()
local f = io.open('lib/globals.lua', 'r'); local gl = f:read('*a'); f:close()

print("1. El OSC marca su llegada")
check("osc.event actualiza G.last_osc_time", ncoco:match('G%.last_osc_time%s*=%s*util%.time%(%)'))
check("globals inicializa last_osc_time", gl:match('last_osc_time%s*=%s*0'))

print("2. El watchdog DETECTA pero NO actua")
check("el metro mide el retraso", ncoco:match('util%.time%(%)%s*-%s*G%.last_osc_time'))
check("avisa cuando los datos se congelan", ncoco:match('OSC STALLED'))
-- Decision de diseno: ante un falso positivo, borrar la rejilla seria peor
-- que el fallo. El watchdog solo registra; la recuperacion no es automatica.
check("no borra la rejilla por un falso positivo",
      not ncoco:match('OSC DEAD'),
      "el watchdog no debe actuar a ciegas")

print("3. Ningun estado puede quedar colgado")
-- El flash de snap guardaba un flag que solo apagaba una corrutina. Si esa
-- corrutina moria, el boton se quedaba en 15 para siempre. Ahora expira por tiempo.
check("el flash de snap expira por tiempo, no por flag",
      nav:match('util%.time%(%)%s*-%s*flash%s*%)%s*<%s*1%.6'),
      "snap_timers vuelve a depender de una corrutina")

-- refresh() siempre: un error a mitad de bucle no puede varar un quad sucio.
-- Se busca la LLAMADA real (linea que empieza por "  g:refresh()"), no el texto
-- del comentario que explica el cambio.
check("refresh() se llama siempre (no solo si cambio algo)",
      nav:match('\n%s+g:refresh%(%)%s*\n') ~= nil and
      nav:match('\n%s+if changed then g:refresh') == nil)

-- sources_val se lee sin proteccion en ui.lua -> un nil tumba el redraw de pantalla.
check("ui.lua protege sources_val[7]", ui:match('%(G%.sources_val%[7%] or 0%)'))

if fails > 0 then
  print("RESULTADO: " .. fails .. " fallos")
  os.exit(1)
end
print("RESULTADO: todos los requisitos del watchdog presentes")