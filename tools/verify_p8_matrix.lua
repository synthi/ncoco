-- Verificacion Fase 3 / punto #8: llamadas OSC redundantes en snap_apply.
-- Reproduce update_matrix() de lib/sc_utils.lua y las dos versiones
-- candidatas de ncoco.lua:108-117 (snap_apply).
--
-- Salida esperada: mismo estado final en las 288 celdas, menos llamadas OSC.

-- Copia exacta de SC.update_matrix (lib/sc_utils.lua:20-25)
local function update_matrix(dest_id, patch, sink)
  local args = {}
  for src = 1, 12 do args[#args + 1] = patch[src][dest_id] end
  sink[#sink + 1] = { dest = dest_id, args = args }
end

-- estado final en el motor por destino (la ultima llamada de cada destino gana)
local function engine_state(sink)
  local st = {}
  for _, c in ipairs(sink) do st[c.dest] = c.args end
  return st
end

local function mk_patch()
  local p = {}
  for s = 1, 12 do
    p[s] = {}
    for d = 1, 24 do p[s][d] = (s * 100 + d) end
  end
  return p
end

-- VERSION A: la actual. update_matrix dentro del bucle de fuentes.
local function apply_A(data)
  local patch = mk_patch()
  local sink = {}
  for s = 1, 12 do
    for d = 1, 24 do
      patch[s][d] = data[s][d] or 0
      update_matrix(d, patch, sink)
    end
  end
  return sink, engine_state(sink)
end

-- VERSION B: rellenar toda la matriz primero, luego 1 llamada por destino.
local function apply_B(data)
  local patch = mk_patch()
  local sink = {}
  for s = 1, 12 do
    for d = 1, 24 do patch[s][d] = data[s][d] or 0 end
  end
  for d = 1, 24 do update_matrix(d, patch, sink) end
  return sink, engine_state(sink)
end

-- datos de snapshot sinteticos
local data = {}
for s = 1, 12 do
  data[s] = {}
  for d = 1, 24 do data[s][d] = (s * 7 + d * 3) % 11 end
end

local sinkA, stA = apply_A(data)
local sinkB, stB = apply_B(data)

print(string.format("VERSION A (actual) : %4d llamadas OSC", #sinkA))
print(string.format("VERSION B (nueva)  : %4d llamadas OSC", #sinkB))
print(string.format("ahorro            : %4d llamadas (%.0fx menos)", #sinkA - #sinkB, #sinkA / #sinkB))
print("")

-- comparar el estado final celda a celda
local diff, cells = 0, 0
for d = 1, 24 do
  for i = 1, 12 do
    cells = cells + 1
    if stA[d][i] ~= stB[d][i] then diff = diff + 1 end
  end
end

if diff == 0 then
  print(string.format("RESULTADO: estado final IDENTICO en las %d celdas", cells))
  print("Las llamadas intermedias de A eran redundantes: el motor nunca las ve.")
else
  print(string.format("RESULTADO: %d celdas DISTINTAS  <-- NO APLICAR", diff))
end