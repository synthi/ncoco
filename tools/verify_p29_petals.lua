-- verify_p29_petals.lua -- bipolaridad y Track & Hold de los 6 petalos (v3.04)
--
-- Los dos modos son opt-in y su default (0) reproduce v3.03 sample a sample. Eso
-- no se puede afirmar solo leyendo el menu: hay que fijar las tres cosas que lo
-- sostienen a la vez.
--
--   1. pBipolar=0 / pGate=0 en la cabecera del SynthDef -> Select elige la rama 0
--   2. La rama 0 es la MISMA senal, no una aproximacion   -> pN / Latch(...)
--   3. El index se manda como entero                    -> addCommand con "i"
--      (un float 0.9999999 como indice de Select cae fuera de rango)
--
-- Este test cubre ademas el presupuesto, que es la razon de disenarlo reutilizando
-- p1..p6 y c1..c6 en vez de crear r1..r6 y cT1..cT6:
--
--   vars 208->208 (+0)  LocalIn/LocalOut 10/10 (+0)  slots de array 312 (+0)
--   ugens 210->234 (+24)  6 Select + 6 Select + 6 Gate + 6 Lag
--
-- Si alguien quita el math.abs, cambia un default, o introduce vars nuevas, este
-- test falla y obliga a re-auditar el presupuesto del motor.

local H = dofile('tools/harness.lua')

local function read(p)
  local f = io.open(p, 'r'); if not f then return '' end
  local s = f:read('*a'); f:close(); return s
end

-- Los comentarios no cuentan como codigo: varias comprobaciones negativas miran
-- cosas que el propio cambio escribe en la prosa.
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

local sc   = read('lib/Engine_Ncoco.sc')
local pset = strip_comments(read('lib/param_set.lua'))
local grid = strip_comments(read('lib/grid_nav.lua'))

local function count(s, pat) local n = 0 for _ in s:gmatch(pat) do n = n + 1 end return n end

--------------------------------------------------------------------
section('PRESUPUESTO: sin vars nuevas, sin canales nuevos')
--------------------------------------------------------------------
-- Solo el interior de los SynthDefs. El cuerpo de la clase tambien declara vars
-- (<synth_core, <b_tape, ...) y no forman parte del presupuesto del motor.
local function vars_de(txt)
  local i = txt:find('VARS %-%-%-')
  local body = i and txt:sub(i) or txt
  local n = 0
  for line in body:gmatch('([^\n]*)\n') do
    local s = line:match('^%s*var%s(.*)$')
    if s then
      s = s:gsub('=[^,;]*', '')            -- fuera el default y la llamada
      for part in s:gmatch('[^,;]+') do
        if part:match('^%s*[%a_]') then n = n + 1 end
      end
    end
  end
  return n
end
-- "0!12" son 12 slots cuyo valor por defecto es 0, y "1!24" son 24 con defecto 1.
-- Lo que se gasta contra MAX_CONTROL es el TAMANO del array, no el valor por defecto.
local function slots_de_array(txt)
  local n = 0
  for decl in txt:gmatch('%d+%s*!%s*%d+') do
    n = n + (tonumber(decl:match('!(%d+)$')) or 0)
  end
  return n
end

-- Baseline de v3.03. Si esto falla, RE-AUDITA el presupuesto antes de subirlo.
eq('vars del motor = 208 (baseline v3.03, +0)', vars_de(sc), 208)
eq('slots de NamedControl = 312 (baseline v3.03, +0)', slots_de_array(sc), 312)
check('LocalIn sigue en 10 canales', sc:match('LocalIn%.ar%(10%)') ~= nil)
local lo = sc:match('LocalOut%.ar%(%[([^%]]*)%]%)')
eq('LocalOut = 10, cuadrados con LocalIn',
   lo and (select(2, lo:gsub('[^,]+', ''))) or -1, 10)
eq('ugens = 234 (baseline 210, +24)', count(sc, '%w+%.ar%(') + count(sc, '%w+%.kr%('), 234)

--------------------------------------------------------------------
section('MENU: los defaults son Abs y S&H')
--------------------------------------------------------------------
check('opcion Petal Polarity = {Abs, Bipolar}, default Abs',
      pset:match('add_option%("petal_polarity", "Petal Polarity", {"Abs", "Bipolar"}, 1%)') ~= nil)
check('opcion Petal S&H/T&H = {S&H, T&H}, default S&H',
      pset:match('add_option%("petal_gate_mode", "Petal S&H/T&H", {"S&H", "T&H"}, 1%)') ~= nil)
check('las dos acciones traducen 1-based a 0/1 antes de llamar al motor',
      pset:match('SC%.set_petal_polarity%(x%-1%)') ~= nil and
      pset:match('SC%.set_petal_gate%(x%-1%)') ~= nil)
check('no se toco el indice del grupo GLOBALS (add_group(_, 7) es indice, no contador)',
      pset:match('add_group%("GLOBALS", 7%)') ~= nil)

--------------------------------------------------------------------
section('SC: los setters recortan a 0/1')
--------------------------------------------------------------------
local ok_load, SC = pcall(loadfile('lib/sc_utils.lua'))
if not ok_load or type(SC) ~= 'table' then SC = _G.SC end
check('sc_utils.lua carga y expone SC', type(SC) == 'table', tostring(SC))

local sent
engine.p_bipolar = function(v) sent = v end
engine.p_gate     = function(v) sent = v end

check('SC.set_petal_polarity existe', type(SC.set_petal_polarity) == 'function')
check('SC.set_petal_gate existe', type(SC.set_petal_gate) == 'function')

if SC.set_petal_polarity and SC.set_petal_gate then
  SC.set_petal_polarity(0);  eq('polarity(0)  -> motor 0 (Abs)', sent, 0)
  SC.set_petal_polarity(1);  eq('polarity(1)  -> motor 1 (Bipolar)', sent, 1)
  -- Fallo hacia atras: si el valor no es exactamente 1, se elige la rama 0, que es
-- la de v3.03. Un dato corrupto NO debe activar un modo que el usuario no pidio.
  SC.set_petal_polarity(7);  eq('polarity(7)  -> motor 0, fallback seguro', sent, 0)
  SC.set_petal_polarity(-3); eq('polarity(-3) -> motor 0, fallback seguro', sent, 0)
  SC.set_petal_gate(0);     eq('gate(0)     -> motor 0 (S&H)', sent, 0)
  SC.set_petal_gate(1);     eq('gate(1)     -> motor 1 (T&H)', sent, 1)
  SC.set_petal_gate(99);    eq('gate(99)    -> motor 0, fallback seguro', sent, 0)
  SC.set_petal_gate(-1);    eq('gate(-1)    -> motor 0, fallback seguro', sent, 0)
end

--------------------------------------------------------------------
section('DIBUJO: bipolar no puede romper la pantalla')
--------------------------------------------------------------------
check('quantussy normaliza con math.abs en la unica lectura de sources_val',
      strip_comments(read('lib/quantussy.lua'))
        :match('local val = math%.abs%(G%.sources_val%[i%] or 0%)') ~= nil)
check('grid_nav.lua ya se protege solo en sus dos usos (no hay que tocarlo)',
      grid:match('math%.abs%(G%.sources_val%[obj%.id%] or 0%)') ~= nil and
      grid:match('math%.abs%(%(G%.sources_val%[src%] or 0%) %* amt%)') ~= nil)

-- Prueba funcional: en bipolar los petalos envian NEGATIVOS por el OSC /update.
-- Sin normalizar, el tamano sale negativo y el petalo desaparece de la pantalla.
local Q = include('ncoco/lib/quantussy')
check('quantussy carga', type(Q) == 'table', tostring(Q))

if type(Q) == 'table' and Q.draw then
  local G = { sources_val = {} }
  for i = 1, 6 do
    G.sources_val[i] = 0
    H.set_param('p'..i..'chaos', 0)
    H.set_param('p'..i..'shape', 1)
    H.set_param('p'..i..'range', 1)
    H.set_param('p'..i..'f_lfo', 100)
  end

  local function draw_con(valor)
    for i = 1, 6 do
      G.sources_val[i] = valor
      Q.history[i] = { valor, valor, valor, valor }
    end
    H.semilla(1234)
    H.reset()
    Q.draw(G)
    return H.capture()
  end

  local cap_pos = draw_con(0.4)
  local cap_neg = draw_con(-0.4)

  check('el dibujo bipolar no esta vacio (si no, el test no probaria nada)',
        #cap_neg > 0, cap_neg:sub(1, 40))

  local bad
  for w, h in cap_neg:gmatch('rect %S+ %S+ (%S+) (%S+)') do
    local nw, nh = tonumber(w), tonumber(h)
    if nw and nh and (nw < 0 or nh < 0) then bad = w .. ' x ' .. h; break end
  end
  check('un petal bipolar de -0.4 no genera ningun rect de tamano negativo', bad == nil, bad)
  eq('dibujar +0.4 y -0.4 produce EXACTAMENTE la misma pantalla', cap_pos, cap_neg)
end

--------------------------------------------------------------------
section('MOTOR: los defaults siguen siendo el comportamiento de v3.03')
--------------------------------------------------------------------
-- Los defaults viven en la MISMA linea de la cabecera (pBipolar=0, pGate=0).
check('pBipolar=0 y pGate=0 en la cabecera del SynthDef',
      sc:match('%s*pBipolar%s*=%s*0%s*,%s*pGate%s*=%s*0') ~= nil,
      'sin estos defaults el anillo arranca con signo en cada carga')

--------------------------------------------------------------------
section('MOTOR: las 6 ramas por defecto no son una aproximacion')
--------------------------------------------------------------------
check('6 x polaridad: Select.ar(pBipolar, [pN, pN - 0.5])',
      count(sc, 'Select%.ar%(pBipolar, %[p%d, p%d %- 0%.5%]%)') == 6)
check('6 x T&H: Select.ar(pGate, [Latch(pN,tN), Lag(Gate(pN,b_phN>0.5),0.004)])',
      count(sc, 'Select%.ar%(%s*pGate%s*,%s*%[Latch%.ar%(%s*p%d%s*,%s*t%d%s*%),%s*Lag%.ar%(%s*Gate%.ar%(%s*p%d%s*,%s*b_ph%d>0%.5%s*%),%s*0%.004%s*%)%]%)') == 6)
check('el reloj del T&H es la fase del propio petal (50/50 en b_ph > 0.5)',
      count(sc, 'Gate%.ar%(%s*p%d%s*,%s*b_ph%d>0%.5%s*%)') == 6)
check('el par (valor, reloj) del T&H es el MISMO que ya usaba el Latch',
      sc:match('Latch%.ar%(p6,t1%)') ~= nil and sc:match('Gate%.ar%(p6,b_ph1>0%.5%)') ~= nil)

--------------------------------------------------------------------
section('MOTOR: el index se manda como entero')
--------------------------------------------------------------------
check('addCommand("p_bipolar", "i", ...)', sc:match('addCommand%("p_bipolar", "i",') ~= nil)
check('addCommand("p_gate", "i", ...)', sc:match('addCommand%("p_gate", "i",') ~= nil)
check('ninguno se manda como "f" (indice de Select vulnerable)',
      sc:match('addCommand%("p_[gb][a-z]*, "f",') == nil)

H.done()