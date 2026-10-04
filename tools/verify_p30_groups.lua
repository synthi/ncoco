-- verify_p30_groups.lua -- TODO grupo de params declara exactamente los params
-- que tiene dentro.
--
-- POR QUE EXISTE ESTE TEST
-- params:add_group(nombre, N): el segundo argumento es el NUMERO de params que
-- van dentro del grupo, NO un indice. Si te quedas corto, los ultimos params
-- se caen del grupo y acaban sueltos al final del menu de norns. El fallo es
-- mudo: no hay error, no hay aviso, el param funciona... simplemente aparece
-- donde no toca.
--
-- Ha pasado TRES veces en este proyecto, siempre por anadir params a un grupo
-- sin subir el contador:
--   1. v2.14: GLOBALS declaraba 6 y "16n_orient" quedo fuera.
--   2. v3.00: COCO declaraba 18 y "Volume 2" cayo dentro de COCO 1.
--   3. v3.04: GLOBALS declaraba 7 y las DOS opciones nuevas de petalos
--      ("Petal Polarity" y "Petal S&H/T&H") quedaron fuera.
--
-- El caso 2 tiene su propio guard (verify_p22_grupo_coco.lua) desde entonces;
-- los grupos COCO y PETAL, ademas, viven en un bucle. El agujero era que
-- GLOBALS y TAPE OPS no los vigilaba nadie. Este test cierra el agujero para
-- TODOS los grupos a la vez, presente y futuro.
--
-- COMO CUENTA
-- Recorre el fuente en orden. Al encontrar un add_group abre un grupo; cuenta
-- las lineas de params:add* que vienen despues hasta el siguiente add_group (o
-- el final del fichero). "params:add*" cubre de una vez add_control, add_option,
-- add_binary, add_trigger y la forma con tabla params:add{...}.
--
-- Se saltan dos cosas a proposito:
--   - las lineas comentadas: en COCO hay un params:add_option comentado
--     ("Skip Mode") que NO debe contarse.
--   - params:add_separator: separa visualmente, no es un param.
--
-- OJO AL LEER EL RESULTADO: un bucle recorre el fuente UNA vez aunque el grupo
-- se ejecute seis veces (PETAL 1..6). El conteo sigue siendo valido porque las
-- 6 iteraciones declaran el mismo numero de params.

local fails = 0
local function check(name, cond, detail)
  if cond then print("  PASA  " .. name)
  else print("  FALLA " .. name .. (detail and ("  -- " .. detail) or "")); fails = fails + 1 end
end

local f = io.open('lib/param_set.lua', 'r')
if not f then print("FALLA no se pudo abrir lib/param_set.lua"); os.exit(1) end
local src = f:read('*a'); f:close()

-- OJO: [^\n]* y NO [^\n]+. Con "+" las lineas vacias no se capturan y todos
-- los numeros de linea que se imprimen abajo salen desplazados (apuntan a la
-- linea equivocada, que es peor que no decir nada).
local lines = {}
for line in (src .. '\n'):gmatch('([^\n]*)\n') do lines[#lines+1] = line end

-- Un param de verdad: params:add_control / add_option / add_binary /
-- add_trigger / add{ ...}. Fuera los separadores y las lineas comentadas.
local function es_param(linea)
  local t = linea:gsub('^%s+', '')
  if t:match('^%-%-') then return false end              -- comentada
  if t:match('^params:add_separator') then return false end
  return t:match('^params:add') ~= nil
end

-- Grupos en orden de aparicion.
local grupos = {}
for i, line in ipairs(lines) do
  local nombre, sufijo, decl = line:match('add_group%(%s*"([^"]*)"%s*([^,]-),%s*(%d+)%s*%)')
  if nombre then
    grupos[#grupos+1] = { linea = i, nombre = nombre, sufijo = sufijo, decl = tonumber(decl) }
  end
end

print("== los grupos declarados y los que realmente tienen ==")
print("")

-- Control negativo: si el parser deja de encontrar grupos, el test no debe
-- pasar en silencio (seria un test que no prueba nada).
check("se han encontrado los 4 add_group del fuente (control negativo)",
      #grupos == 4, "encontrados: " .. #grupos)
if #grupos ~= 4 then
  print("")
  print("RESULTADO: " .. fails .. " fallidos (abortado: el conteo no es fiable)")
  os.exit(1)
end

-- Un param antes del primer add_group quedaria fuera de todo grupo: norns lo
-- pondria al final del menu, que es justo el sintoma que este test persigue.
local sueltos = 0
for i = 1, grupos[1].linea - 1 do
  if es_param(lines[i]) then sueltos = sueltos + 1 end
end
check("no hay ningun param antes del primer grupo", sueltos == 0,
      sueltos .. " suelto(s)")

for g = 1, #grupos do
  local ini = grupos[g].linea
  local fin = grupos[g+1] and (grupos[g+1].linea - 1) or #lines

  local real = 0
  for i = ini + 1, fin do
    if es_param(lines[i]) then real = real + 1 end
  end

  local etiqueta = grupos[g].nombre .. grupos[g].sufijo
  local ok = (real == grupos[g].decl)
  print(string.format("  %-16s declarado %2d   real %2d   %s",
        etiqueta, grupos[g].decl, real, ok and "OK" or "DESCUADRE"))

  if not ok then
    print(string.format("       -> linea %d. Los %d params de mas se caen del grupo:",
          ini, math.abs(real - grupos[g].decl)))
    print("          sube el contador a " .. real .. " en esa linea.")
  end
  fails = fails + (ok and 0 or 1)
end

print("")
print("== el conteo no depende de leer el numero a mano ==")
-- Si alguien "arregla" el descuadre tocando SOLO el contador del fuente, este
-- test lo acepta (es la correccion correcta). Pero si en el futuro se anade un
-- param y no se sube el contador, vuelve a fallar. Aqui solo se deja
-- constancia del total, que es util al comparar presupuestos.
local total = 0
for i = 1, #lines do if es_param(lines[i]) then total = total + 1 end end
print(string.format("  grupos: %d   params dentro de grupos: %d", #grupos, total))

print("")
if fails == 0 then print("RESULTADO: todos los grupos cuadran")
else print("RESULTADO: " .. fails .. " grupo(s) descuadrados") end
os.exit(fails == 0 and 0 or 1)
