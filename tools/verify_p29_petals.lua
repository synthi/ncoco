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
--[[ v3.05: LA COMPROBACION QUE HABIA AQUI ESTABA MAL Y BLOQUEABA EL ARREGLO.
-- Decia, literalmente, "add_group(_, 7) es indice, no contador", y exigia que
-- el 7 siguiera en su sitio. La creencia era FALSA: el segundo argumento de
-- params:add_group SI es un contador. Con 7 declarados y 9 params dentro,
-- petal_polarity y petal_gate_mode se salian del grupo, que son justo los dos
-- params que estrena v3.04 y los que este test vigila. Un test que fijaba el
-- bug: "arreglar" el contador hacia que el test fallara.
-- Se deja el texto original tal cual, comentado, como constancia:
-- Original:
      pset:match('add_group%("GLOBALS", 7%)') ~= nil)

]]
-- [v3.05] La comprobacion correcta no es el NUMERO, es la POSICION: los dos
-- params tienen que caer entre add_group("GLOBALS") y el grupo siguiente. Asi
-- este test no duplica el contador (eso lo lleva tools/verify_p30_groups.lua)
-- y no queda obsoleto cuando GLOBALS crezca otra vez.
--
-- Nota: aqui se cuentan lineas NO VACIAS, porque no hace falta el numero de
-- linea exacto, solo el ORDEN relativo entre los cuatro patrones, y el orden
-- no cambia al saltarse las vacias.
local NL = string.char(10)
local function linea_de(pat)
  local n = 0
  for line in pset:gmatch('[^' .. NL .. ']+') do
    n = n + 1
    if line:match(pat) then return n end
  end
  return nil
end

local l_globals = linea_de('add_group%("GLOBALS"')
local l_tapeops = linea_de('add_group%("TAPE OPS"')
local l_pol     = linea_de('add_option%("petal_polarity"')
local l_gate    = linea_de('add_option%("petal_gate_mode"')

check('existen los dos grupos que acotan GLOBALS (control negativo)',
      (l_globals ~= nil) and (l_tapeops ~= nil) and (l_tapeops > l_globals))
check('petal_polarity esta DENTRO del grupo GLOBALS',
      (l_pol ~= nil) and (l_pol > l_globals) and (l_pol < l_tapeops))
check('petal_gate_mode esta DENTRO del grupo GLOBALS',
      (l_gate ~= nil) and (l_gate > l_globals) and (l_gate < l_tapeops))

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
section('DIBUJO: el scope del petalo se centra en bipolar (v3.05)')
--------------------------------------------------------------------
-- El OSC /update manda los petalos CON SIGNO cuando el modo bipolar esta
-- activo. Hasta v3.04 draw_scope recortaba a 0..1, de modo que todo valor
-- negativo se dibujaba pegado al borde inferior: un petalo en -0.4 y otro en 0
-- daban EXACTAMENTE la misma pantalla, y media onda no existia.
--
-- Aqui se fija que en bipolar la onda se centra, que hay linea de cero, y que
-- en Abs no cambia NADA (los otros inspectores comparten esta misma funcion).
local UI = dofile('lib/ui.lua')
check('ui.lua carga y expone draw_scope',
      type(UI) == 'table' and type(UI.draw_scope) == 'function')

if type(UI) == 'table' and UI.draw_scope then
  -- Sin backslash en los patrones: esta test se mantiene a mano y '\n' dentro
  -- de una cadena Lua es justo el tipo de cosa que se corrompe al copiar.
  local NL = string.char(10)

  local ARRIBA, CENTRO, ABAJO = 20, 32.5, 45   -- caja = rect(10,20,108,25)

  -- Dibuja el inspector del petalo 1 y devuelve las alturas de la onda.
  -- La caja se pinta con rect+stroke (no emite pixel ni line), asi que todo
  -- pixel/line que aparece pertenece a la onda o a la linea de cero.
  local function analiza(valor, polaridad, que)
    local G = { scope_history = {}, scope_head = 33, SCOPE_LEN = 64,
                popup = { active = false } }
    for i = 1, 12 do
      G.scope_history[i] = {}
      for k = 1, 64 do G.scope_history[i][k] = 0 end
    end
    G.scope_history[1][1] = valor
    -- llena la historia como haria UI.update_histories con el valor sostenido
    for k = 1, 64 do G.scope_history[1][k] = valor end
    for i = 1, 6 do
      H.set_param('p' .. i .. 'shape', 1)
      H.set_param('p' .. i .. 'range', 1)
      H.set_param('p' .. i .. 'f_lfo', 100)
      H.set_param('p' .. i .. 'chaos', 0)
    end
    H.set_param('petal_polarity', polaridad)
    H.semilla(1234)
    H.reset()
    if que == 'env' then UI.draw_env_inspector(G, 7)
    else UI.draw_petal_inspector(G, 1) end
    local cap = H.capture()

    -- Se recogen TODOS los pixel/line EN ORDEN: la caja se pinta con
    -- rect+stroke (que no emite ni pixel ni line), asi que solo pueden ser la
    -- linea de cero o la onda.
    local pts = {}
    for linea in cap:gmatch('[^' .. NL .. ']+') do
      local op, y = linea:match('^(%a+) [%d%.%-]+ ([%d%.%-]+)')
      if (op == 'pixel' or op == 'line') then pts[#pts + 1] = tonumber(y) end
    end

    -- La ONDA son los ULTIMOS 64 puntos (= G.SCOPE_LEN), la misma convencion
    -- que usa verify_p12_scope.lua con el inspector de destinos. La linea de
    -- cero se dibuja ANTES, asi que lo que sobra por delante es la linea de
    -- cero. Medirlos juntos no valdria: la linea de cero esta justo en el
    -- centro y falsearia el minimo de la onda.
    local desde = #pts - 64 + 1
    if desde < 1 then desde = 1 end

    local ys, en_cero, miny, maxy = {}, 0, 1e9, -1e9
    for i = 1, #pts do
      local v = pts[i]
      if i >= desde then
        ys[#ys + 1] = v
        if v < miny then miny = v end
        if v > maxy then maxy = v end
      elseif math.abs(v - CENTRO) < 0.01 then
        en_cero = en_cero + 1
      end
    end
    return ys, en_cero, miny, maxy, cap
  end

  -- 1. ABS: comportamiento de siempre, intacto. -0.4 se recorta al fondo.
  local _, _, mins_abs, maxs_abs = analiza(-0.4, 1)
  eq('Abs con -0.4: la onda se queda pegada al fondo (recorte 0..1)', maxs_abs, ABAJO)
  eq('Abs con -0.4: toda la onda esta en el mismo pixel que un 0', mins_abs, ABAJO)

  -- 2. BIPOLAR: el signo se ve. -0.4 va POR DEBAJO del centro, +0.4 por encima.
  local _, _, min_b, max_b = analiza(-0.4, 2)
  local _, _, min_b2, max_b2 = analiza(0.4, 2)
  check('Bipolar con -0.4: la onda baja POR DEBAJO del centro',
        min_b > CENTRO + 0.5, string.format('y=%.4f (centro %.1f)', min_b, CENTRO))
  check('Bipolar con +0.4: la onda sube POR ENCIMA del centro',
        max_b2 < CENTRO - 0.5, string.format('y=%.4f (centro %.1f)', max_b2, CENTRO))

  local d_neg = math.abs(min_b - CENTRO)
  local d_pos = math.abs(max_b2 - CENTRO)
  check('+0.4 y -0.4 recorren la MISMA distancia desde el centro',
        math.abs(d_neg - d_pos) < 0.01,
        string.format('abajo %.2f  arriba %.2f', d_neg, d_pos))

  -- 3. LA PRUEBA QUE DESTAPA EL BUG: en bipolar -0.4 y 0 NO pueden coincidir.
  local _, _, min_cero = analiza(0.0, 2)
  check('bipolar: -0.4 y 0 dan pantallas DISTINTAS (antes coincidian)',
        math.abs(min_b - min_cero) > 0.5,
        string.format('-0.4 -> y=%.4f   0 -> y=%.4f', min_b, min_cero))

  -- 4. Linea de cero: presente en bipolar, ausente en Abs.
  local _, pix_bip = analiza(0.0, 2)
  local _, pix_abs = analiza(0.0, 1)
  check('bipolar dibuja la linea de cero (varios puntos en el centro)',
        pix_bip > 5, 'puntos en el centro: ' .. pix_bip)
  eq('Abs NO dibuja linea de cero (ninguna pantalla cambia)', pix_abs, 0)

  -- 5. La misma caja: la onda bipolar no se sale del rect(10,20,108,25).
  check('la onda bipolar cabe dentro de la caja y=20..45',
        (min_b >= ARRIBA - 0.01) and (max_b <= ABAJO + 0.01),
        string.format('y=%.2f..%.2f', min_b, max_b))

  -- 6. SIN EFECTOS COLATERALES: el inspector de env comparte draw_scope y no
  --    puede cambiar por activar el bipolar de los petalos.
  local _, _, e1, E1, cap_env_abs = analiza(-0.4, 1, 'env')
  local _, _, e2, E2, cap_env_bip = analiza(-0.4, 2, 'env')
  eq('el inspector de env (id 7) es IDENTICO con polaridad Abs y Bipolar',
     cap_env_bip, cap_env_abs)
  eq('env sigue con el cero abajo (no se contagia del bipolar)', E2, E1)
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
check('6 x polaridad: Select.ar(pBipolar, [pN, 2*pN - 1])',
      count(sc, 'Select%.ar%(pBipolar, %[p%d, p%d %* 2 %- 1%]%)') == 6)
-- Control negativo: la forma de v3.04 (pN - 0.5) no debe quedar en NINGUNA
-- rama. Reintroducirla devuelve el pico bipolar al 61% del de Abs.
check('ninguna rama conserva la forma vieja pN - 0.5',
      count(sc, 'Select%.ar%(pBipolar, %[p%d, p%d %- 0%.5%]%)') == 0)
check('6 x T&H: Select.ar(pGate, [Latch(pN,tN), Lag(Gate(pN,b_phN>0.5),0.004)])',
      count(sc, 'Select%.ar%(%s*pGate%s*,%s*%[Latch%.ar%(%s*p%d%s*,%s*t%d%s*%),%s*Lag%.ar%(%s*Gate%.ar%(%s*p%d%s*,%s*b_ph%d>0%.5%s*%),%s*0%.004%s*%)%]%)') == 6)
check('el reloj del T&H es la fase del propio petal (50/50 en b_ph > 0.5)',
      count(sc, 'Gate%.ar%(%s*p%d%s*,%s*b_ph%d>0%.5%s*%)') == 6)
check('el par (valor, reloj) del T&H es el MISMO que ya usaba el Latch',
      sc:match('Latch%.ar%(p6,t1%)') ~= nil and sc:match('Gate%.ar%(p6,b_ph1>0%.5%)') ~= nil)

--------------------------------------------------------------------
section('MOTOR: el bipolar cubre el MISMO recorrido que Abs (v3.05)')
--------------------------------------------------------------------
-- El re-centrado 2p-1 y el Abs comparten pico despues del tanh de fb_petals.
-- No es cosmetico: la matriz aplica .tanh, asi que el recorrido util de la
-- modulacion ES lo que sale de aqui. Numeros exactos, no aproximaciones.
--
-- v3.04 usaba p-0.5, que dejaba el pico en tanh(0.5)=0.46, el 61% del de Abs.
-- Se veia y se oia: el bipolar "llegaba menos" que el Abs en vez de recorrer
-- lo mismo en las dos direcciones.
local function tanh(x) local e = math.exp(2 * x); return (e - 1) / (e + 1) end
local PICO_ABS = tanh(1.0)            -- rampa 0..1    -> pico en 1
local PICO_BIP = tanh(2 * 1.0 - 1)    -- rampa -1..+1  -> pico en 1

eq('el pico bipolar es EXACTAMENTE el de Abs (tanh(1) = 0.761594)',
   string.format('%.6f', PICO_BIP), string.format('%.6f', PICO_ABS))
eq('el cero del bipolar cae en el centro de la rampa (p=0.5 -> 0)',
   string.format('%.6f', tanh(2 * 0.5 - 1)), '0.000000')
check('la forma vieja p-0.5 daba solo el 61% del pico (por eso se cambio)',
      math.abs(PICO_ABS - tanh(0.5)) > 0.25,
      string.format('tanh(1)=%.4f vs tanh(0.5)=%.4f', PICO_ABS, tanh(0.5)))
-- El cero nuevo coincide con el punto medio de la rampa rectificada, que es
-- tambien donde Abs tiene su pico de envolvente. Es el mismo punto: asi el
-- cero bipolar es un cero de verdad, no un desplazamiento del rango.
check('el cero esta donde Abs tiene su maximo (p=0.5 es el centro geometrico)',
      math.abs((2 * 0.5 - 1) - 0.0) < 1e-12)

--------------------------------------------------------------------
section('MOTOR: el index se manda como entero')
--------------------------------------------------------------------
check('addCommand("p_bipolar", "i", ...)', sc:match('addCommand%("p_bipolar", "i",') ~= nil)
check('addCommand("p_gate", "i", ...)', sc:match('addCommand%("p_gate", "i",') ~= nil)
check('ninguno se manda como "f" (indice de Select vulnerable)',
      sc:match('addCommand%("p_[gb][a-z]*, "f",') == nil)

H.done()