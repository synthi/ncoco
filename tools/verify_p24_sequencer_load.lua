-- Bug del secuenciador: "grabo y al darle play suena vacio".
-- run_sequencer() hace `local s = G.sequencers[id]` UNA vez y guarda esa
-- referencia para siempre. Si Storage.load reemplazaba la tabla
-- (G.sequencers = data.sequencers), la corrutina seguia leyendo la tabla VIEJA
-- mientras la grabacion escribia en la NUEVA. Este test guarda que el load
-- MUTE en sitio y nunca reasigne G.sequencers.

local fails = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FALLA " .. name .. (detail and ("  -- " .. detail) or "")); fails = fails + 1 end
end

local f = io.open('lib/storage.lua', 'r'); local st = f:read('*a'); f:close()
local f = io.open('ncoco.lua', 'r'); local nc = f:read('*a'); f:close()

print("1. Storage.load no reemplaza G.sequencers")
-- Se busca la SENTENCIA real (linea que empieza por G.sequencers =), no el
-- texto del comentario que explica por que NO se debe hacer.
check("no hay la sentencia 'G.sequencers = data.sequencers'",
      st:match('\n%s*G%.sequencers%s*=%s*data%.sequencers') == nil,
      "reasignar la tabla invalida la referencia que guarda run_sequencer")

print("2. Copia campo a campo (muta en sitio)")
check("copia dst.data desde src", st:match('dst%.data%s*=%s*src%.data'))
check("copia dst.duration", st:match('dst%.duration%s*=%s*src%.duration'))
check("recorre i=1,4", st:match('for i=1,4 do'))

print("3. run_sequencer sigue capturando la referencia (por eso importa)")
check("run_sequencer usa 'local s = G.sequencers[id]'",
      nc:match('local s%s*=%s*G%.sequencers%[id%]'))

if fails > 0 then
  print("RESULTADO: " .. fails .. " fallos")
  os.exit(1)
end
print("RESULTADO: el load conserva las referencias del secuenciador")