-- Banco de pruebas headless para ncoco.
-- Simula el entorno de norns (screen, params, util, ...) para poder EJECUTAR
-- el codigo real de dibujo y ui y comparar el resultado pixel a pixel.
--
-- Uso:
--   lua tools/harness.lua <archivo_de_prueba.lua>
--
-- Cada test escribe su veredicto por stdout y llama a check() / fail().

local H = {}
H.log = {}

--------------------------------------------------------------------
-- screen: registra cada operacion de dibujo con sus argumentos
--------------------------------------------------------------------
local screen = {}
local calls = {}

local function rec(name, ...)
  local parts = { name }
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    if type(v) == 'number' then
      parts[#parts+1] = string.format('%.4f', v)
    else
      parts[#parts+1] = tostring(v)
    end
  end
  calls[#calls+1] = table.concat(parts, ' ')
end

for _, name in ipairs{
  'save','restore','translate','rotate','level','fill','stroke',
  'move','rect','pixel','circle','arc','line','update','clear',
  'text','text_center','text_right',
} do
  screen[name] = function(...) rec(name, ...) end
end
screen.color = function() end
screen.pixel = function(...) rec('pixel', ...) end

--------------------------------------------------------------------
-- params: tabla simple con valores por defecto
--------------------------------------------------------------------
local params = {}
local param_values = {}
params.__index = params

function params:get(k)
  return param_values[k]
end
function params:set(k, v)
  param_values[k] = v
end
function params:add_control() end
function params:add_option() end
function params:set_action() end
function params:add_group() end
function params:add() end
function params:bang() end
function params:save() end
function params:int() return 1 end
function params:text() return "" end

H.params = params
H.set_param = function(k, v) param_values[k] = v end

--------------------------------------------------------------------
-- util
--------------------------------------------------------------------
local util = {}
function util.time() return H.fake_time or 1.0 end
function util.linlin(x, inmin, inmax, outmin, outmax)
  return outmin + (x - inmin) * (outmax - outmin) / (inmax - inmin)
end
function util.clamp(x, a, b) return math.max(a, math.min(b, x)) end
function util.round(x) return math.floor(x + 0.5) end
function util.table_copy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end
function util.wrap(v, min, max) return min + (v - min) % (max - min) end
function util.file_exists() return false end
function util.make_dir() end
function util.string_ext(s) return s:match('%.([^.]+)$') end
function util.trim_string_to_width(s) return s end

--------------------------------------------------------------------
-- otros modulos que ncoco puede necesitar
--------------------------------------------------------------------
local engine = setmetatable({}, { __index = function() return function() end end })
H.engine = engine

local audio = { level_dry = function() end, level_wet = function() end }
local osc = { event = function() end, send = function() end, send_c = function() end }
local clock = {
  run = function() return 1 end,
  cancel = function() end,
  sleep = function() end,
}
local metro = { init = function() return { start=function() end, stop=function() end } end }
local grid = { connect = function() return setmetatable({}, {__index=function() return function() end end}) end }
local midi = { devices = {}, connect = function() return {} end, to_msg = function() return {} end }

--------------------------------------------------------------------
-- marco de pruebas
--------------------------------------------------------------------
local passed, failed = 0, 0

function H.reset() calls = {} end

-- captura la lista de operaciones de dibujo
function H.capture()
  return table.concat(calls, '\n')
end

-- cuenta un tipo de operacion
function H.count(op)
  local n = 0
  local prefix = op .. ' '
  local plen = #prefix
  for _, c in ipairs(calls) do
    if c == op or c:sub(1, plen) == prefix then n = n + 1 end
  end
  return n
end

function check(label, ok, detail)
  if ok then
    passed = passed + 1
    print(string.format('  PASA  %s%s', label, detail and ('  (' .. detail .. ')') or ''))
  else
    failed = failed + 1
    print(string.format('  FALLA %s%s', label, detail and ('  (' .. detail .. ')') or ''))
  end
end

function eq(label, a, b)
  local ok = (a == b)
  check(label, ok, ok and '' or ('esperado ' .. tostring(b) .. ', obtenido ' .. tostring(a)))
end

function section(t) print('\n== ' .. t .. ' ==') end

function H.done()
  print('')
  print(string.format('RESULTADO: %d correctos, %d fallidos', passed, failed))
  if failed > 0 then os.exit(1) end
  os.exit(0)
end

--------------------------------------------------------------------
-- globals que ncoco espera encontrar
--------------------------------------------------------------------
_G.screen = screen
_G.params = params
_G.util = util
_G.engine = engine
_G.audio = audio
_G.osc = osc
_G.clock = clock
_G.metro = metro
_G.grid = grid
_G.midi = midi
_G.include = function(path)
  local f = io.open(path, 'r')
  if not f then
    -- los modulos se cargan con dofile desde el test, no via include
    return nil
  end
  f:close()
  return dofile(path)
end
_G.print = print

return H