-- v3.02: los números de versión y el cambio de versión en caliente.
-- Dos cosas quedan guardadas aquí:
--   1. Todos los archivos declaran la MISMA versión (antes cada uno iba por su
--      cuenta y el banner del script quedó en v2.14 durante toda la v3.00).
--   2. cleanup() recorre clock_ids con pairs. Esa tabla es DISPERSA (1..5 y 7),
--      así que ipairs se detendría en el hueco y el latido nunca se cancelaría.
--      Es la MISMA trampa que rompió el 16n con midi.devices.

local fails = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FALLA " .. name .. (detail and ("  -- " .. detail) or "")); fails = fails + 1 end
end

local VERSION = "3.02"

local files = {
  "ncoco.lua",
  "lib/Engine_Ncoco.sc",
  "lib/16n.lua",
  "lib/globals.lua",
  "lib/grid_nav.lua",
  "lib/param_set.lua",
  "lib/quantussy.lua",
  "lib/sc_utils.lua",
  "lib/storage.lua",
  "lib/ui.lua",
}

print("1. Todos los archivos declaran v" .. VERSION)
for _, path in ipairs(files) do
  local f = io.open(path, 'r')
  if not f then
    check("cabecera de " .. path, false, "no se pudo abrir")
  else
    local first = f:read('*l') or ""
    f:close()
    -- Acepta "-- lib/x.lua v3.02", "-- ncoco.lua v3.02" y "// x.sc v3.02".
    check("cabecera de " .. path,
          first:match("v" .. VERSION .. "%s*$") ~= nil,
          "cabecera: " .. first)
  end
end

print("2. NCOCO_VERSION es la fuente autoritativa")
local f = io.open('ncoco.lua', 'r'); local nc = f:read('*a'); f:close()
check("define NCOCO_VERSION = \"" .. VERSION .. "\"",
      nc:match('NCOCO_VERSION%s*=%s*"' .. VERSION .. '"'))
check("el banner usa la variable, no un literal",
      nc:match('Ncoco v" %s*%.%.%s*NCOCO_VERSION') ~= nil,
      "no debe volver a quedar un número fijo en el banner")

print("3. cleanup() usa pairs sobre la tabla dispersa")
check("clock_ids se recorre con pairs",
      nc:match('for%s+[%w_]+%s*,%s*[%w_]+%s+in%s+pairs%(clock_ids%)') ~= nil)
check("NO se recorre clock_ids con ipairs",
      nc:match('in%s+ipairs%(clock_ids%)') == nil,
      "ipairs se detiene en el hueco 6 y no cancelaria el latido")

print("4. El latido está registrado para poder cancelarlo")
check("cid_heartbeat se guarda en clock_ids",
      nc:match('clock_ids%[[%d]+%]%s*=%s*cid_heartbeat'))

if fails > 0 then
  print("RESULTADO: " .. fails .. " fallos")
  os.exit(1)
end
print("RESULTADO: v" .. VERSION .. " unificada y cleanup() segura")