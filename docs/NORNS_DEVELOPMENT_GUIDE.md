---

## 0. TL;DR — las 11 reglas que más caro salen


1. **SC se lee de arriba abajo.** No hay hoisting, no hay `if` en tiempo de ejecución.
   Una `var` usada antes de declararse = fallo de compilación.
2. **En un `SynthDef`, todas las `var` van antes de cualquier statement de audio.**
3. **`Select.ar` evalúa TODAS sus ramas, siempre.** Un "if" en SC no existe.
4. **Lua 5.3, no LuaJIT.** `table.unpack`, no `unpack`. Las closures capturan la
   variable de bucle **por referencia**.
5. **`controlspec.new(min, max, warp, step, default, ...)` — el 4º argumento es
   `step`, NO `default`.**
6. **`params:add_group(name, n)`** — `n` debe ser el conteo **exacto** o los params
   caen fuera del grupo.
7. **`params:default()` restaura los defaults del código.** No carga el PSET.
8. **`g:led()` solo marca sucio; `g:refresh()` es lo único que habla con el grid.**
   Nunca llames `refresh()` por LED.
9. **`include()` tiene caché por ruta.** Incluir dos veces = la **misma** tabla.
10. **El archivo del engine debe llamarse exactamente como `engine.name`.**
    Dos copias = error `DUPLICATE ENGINES` al cargar.
11. **`metro` y `clock` son el MISMO hilo.** Un watchdog que dice «el otro no me
    ha contestado en N s» **no puede** distinguir «el otro se rompió» de «los dos
    nos quedamos sin CPU». Mide **tu propio atraso**: es la única prueba.

---

## 1. Versiones exactas


Extraídas del `Dockerfile` y `wscript` del repo oficial `monome/norns` (no de
memoria, no de blogs). **Verificadas el 2026-10-02** y **re-verificadas al corregir
esta guía en v3.03** contra el mismo checkout: `lua53`, `SUPERCOLLIDER_VERSION=3.13.0`,
`LIBMONOME_VERSION=1.4.9`, `LIBGPIOD_VERSION=1.6.4`, `NNG_VERSION=1.11`. **Todas
siguen igual.**

| Componente | Versión | Dónde se declara |
|---|---|---|
| **norns OS** | **2.9.3** (tag `v2.9.3`, 2025-09-26) | `github.com/monome/norns/releases` |
| norns OS (pre-releases) | `260102`, `260526`, `260616`, `260819` | idem, marcados *Pre-release* |
| **SuperCollider** | **3.13.0** | `Dockerfile` → `SUPERCOLLIDER_VERSION=3.13.0` |
| sc3-plugins | 3.13.0 | `Dockerfile` → `SUPERCOLLIDER_PLUGINS_VERSION` |
| **Lua** | **5.3** (estándar, **no** LuaJIT) | `wscript` → `conf.check_cfg(package='lua53')` |
| libmonome | 1.4.9 | `Dockerfile` → `LIBMONOME_VERSION` |
| libgpiod | 1.6.4 | `Dockerfile` → `LIBGPIOD_VERSION` |
| NNG | 1.11 | `Dockerfile` → `NNG_VERSION` |
| Frecuencia de muestreo | **48000 Hz, fija** | hardware CS4270 |
| Resolución de pantalla | 128 × 64, **16 niveles** (0–15) | norns specs |

### 1.1 Cómo saber qué versión lleva *mi* norns

En `maiden` → REPL:

```lua
print(_VERSION)            -- debe decir Lua 5.3
```

En ssh: `sclang -v`. En el aparato: **SYSTEM → VERSION** muestra la versión de
norns, de sclang y de scsynth.

> No confundas la versión de norns con la de SuperCollider. Son independientes.
> Un norns 2.9.3 **siempre** lleva SC 3.13.0. Si ves otra cosa, estás en un
> entorno de desarrollo o una imagen custom.

### 1.2 El stack de procesos

```
systemd
 ├── norns-jack          ← servidor JACK
 ├── crone               ← backend de audio, softcut, efectos. JACK app.
 ├── sclang              ← lenguaje SC. SPAWnea un scsyn child.
 │    └── scsyn          ← el servidor de audio real
 └── matron              ← el "cerebro": corre los scripts Lua, dibuja,
                           habla con encoders/teclas/grid/midi/OSC
maiden                    ← IDE web (proceso aparte)
```

Consecuencia práctica: **`matron` y `scsyn` son procesos separados.** La comunicación
Lua↔SC pasa por **mensajes OSC**, no por memoria compartida. Por eso cada
`engine.algo(valor)` es un viaje de red (loopback).

---

## 2. Rutas del sistema


Todo lo que crea un script vive bajo `dust/`, que en el norns real es
`/home/we/dust`.

| Variable | Ruta real | Contenido |
|---|---|---|
| `_path.home` | `/home/we/dust` | raíz del usuario |
| `_path.audio` | `/home/we/dust/audio` | WAV, AIFF |
| `_path.data` | `/home/we/dust/data` | PSETs, datos serializados |
| `_path.user` | `/home/we/dust/user` | datos de usuario |
| `_path.system` | `/home/we/norns/system` | solo lectura |

Estructura de un proyecto:

```
dust/code/miproyecto/
├── miproyecto.lua          ← script principal
└── lib/
    ├── Engine_Mi.sc        ← el engine (renombrado = engine.name)
    ├── helpers.lua
    └── ui.lua
```

**Los engines `.sc` viven en el `lib/` del proyecto**, no en una carpeta global.
Consecuencia: si dos proyectos llevan un `Engine_X.sc` con el mismo nombre, la
segunda vez que cargas cualquiera de los dos **falla**.

### 2.1 `include` vs `require`

```lua
local SC = include('miproyecto/lib/sc_utils')   -- ruta SIN extensión ni .lua
```

- `include` **tiene caché por ruta de módulo**. La segunda llamada devuelve la
  **misma tabla**, no una copia.
- Consecuencia: si A y B incluyen el mismo lib, **comparten estado**. A veces es lo
  que quieres; a veces es un acoplamiento oculto.
- `require` usa la ruta de paquetes de Lua estándar (`package.path`).

## 3. SuperCollider en norns


### 3.1 Se lee de arriba abajo. Punto.

SuperCollider no es un lenguaje imperativo con hoisting. El intérprete **construye el
grafo de audio en el orden exacto en que lee las líneas**. No existe "eleva esta
declaración para después".

```supercollider
// FALLA: x no existe todavía
SynthDef(\mal, { var out; out = SinOsc.ar(x); x = 440; out });

// OK
SynthDef(\bien, { var x, out; x = 440; out = SinOsc.ar(x); out });
```

**Regla dura dentro de un `SynthDef`:** el bloque entero de declaraciones `var` va
primero, y solo después empieza el audio.

También es una **ventaja**: el orden de lectura = orden de ejecución del grafo.

### 3.2 `arg` = entradas del synth

```supercollider
SynthDef(\miSynth, {
    arg bufL, inL, out,        // sin default = obligatorio
    gain = 1.0, loopLen = 8.0, // con default = opcional
});
```

- Los **defaults se evalúan al construir la definición**, no al instanciar.
- Para pasar valores: `Synth.new(\miSynth, [\gain, 0.5, \out, 0])`. El orden sin
  `\nombre` es posicional y **frágil**; usa siempre `\nombre`.
- En caliente: `synth.set(\gain, 0.5)`.

### 3.3 El presupuesto de vars y nodos — límite real y duro

Un `SynthDef` se serializa a un array de bytes con índices de 16 bits. Hay un techo
práctico de **nodos/vars por SynthDef** (del orden de los ~512). Al pasarlo, scsyn
falla al construir la definición.

**Síntomas de haberlo pasado:**
- El SynthDef no se registra → `Synth.new` falla → **no suena nada**.
- O falla *parcialmente*: un control deja de responder sin explicación.
- Un síntoma clásico: "un canal funciona y el otro no". Eso es casi siempre un
  **error de orden de statements** (una `var` usada antes de asignarse), no un
  límite de vars.

**Cómo presupuestarlo:** si te acercas, **inlinea**. Si solo usas
`readL = readL.something`, no necesitas una `var` para `readL_something`; escribe
la expresión. Menos vars = menos riesgo y menos CPU.

> Lección registrada en el changelog de `ncoco` v2.08:
> *"Inlined ~24 vars to stay under SynthDef var limit (fixes rec/feedback bug on ch1)"*.
> Un inline de 24 vars arregló un bug de feedback **solo en el canal 1**. Si un
> canal se comporta distinto al otro, suspecta el `var`/orden antes que el DSP.

### 3.4 `Select.ar` evalúa todas las ramas — el mayor malentendido de SC

```supercollider
writeL = Select.ar(selector, [rama0, rama1, rama2, rama3]);
```

Esto **no** es un `if`. Las cuatro ramas **se calculan siempre**, y el `selector`
solo elige cuál resultado se escucha. Las otras tres se calculan y se tiran.

Implicación: si la rama cara es un `exp`/`log`/filtro, **pagas el filtro aunque el
selector nunca lo elija**. Y en un SynthDef *no hay forma de saltártelo* sin
cambiar el grafo.

**Cómo diseñar alrededor de esto:**
- Que el selector sea un **argumento constante por synth**, o
- mover la decisión a **Lua** y crear el synth distinto, o
- usar `Switch.ar` con umbrales (pero eso **introduce clics**).

### 3.5 `LocalIn` / `LocalOut` = 1 bloque de latencia

```supercollider
feedback_in = LocalIn.ar(10);   // SIEMPRE al principio
// ... grafo ...
LocalOut.ar([a, b, c, ...]);    // SIEMPRE al final
```

- `LocalIn.ar(N)` y `LocalOut.ar` con **N canales exactamente**. Si no coinciden,
  error.
- Exactamente **1 bloque** (64 muestras @ 48k = **1.33 ms**) de ida y vuelta. En un
  looper asíncrono eso es un retardo fijo y audible.
- El orden de canales es **índice 0-based**: `feedback_in[0]` es el primero.

### 3.6 Bus de audio vs bus de control

```supercollider
b_tape    = Bus.audio(server, 2);    // 2 canales, audio
b_mod_vol = Bus.control(server, 2);  // 2 canales, control

Out.ar(b_tape.index, [sigL, sigR]);   // escribe audio
Out.kr(b_mod_vol.index, [krL, krR]);  // escribe control

In.ar(b_tape.index, 2);              // lee audio
In.kr(b_mod_vol.index, 2);            // lee control
```

**Mezclarlos es error duro:** `In.ar` sobre un bus de control (o al revés) falla.

**¿Cuándo usar bus y no `cont.kr`?** Cuando el valor lo calcula **otro synth**.
`cont.kr` solo funciona dentro del mismo SynthDef. Si divides el engine en `Core`
(genera) y `Out` (mezcla/filtro), **necesitas buses obligatoriamente**.

### 3.7 Barrieras de sincronía

`context.server.sync` es una **barrera bloqueante**: espera a que el servidor
aplique lo pendiente. Obligatorio alrededor de `Buffer.alloc`, de
`SynthDef(...)...add` y de cualquier cambio de topología.

```supercollider
context.server.sync;   // barrera 1
bufL.zero; bufR.zero;
context.server.sync;

SynthDef(\Core, { ... }).add;
SynthDef(\Out,  { ... }).add;
context.server.sync;   // barrera 2

synth_core = Synth.new(\Core, [...], context.xg, \addToHead);
synth_out  = Synth.new(\Out,  [...], context.xg, \addToTail);
```

`context.xg` es el **grupo**. `addToHead`/`addToTail` deciden el orden *dentro* del
grupo, que afecta al **orden de mezcla**, no al orden del audio.


# Guía de desarrollo para monome norns

> Documento **script-agnostic**. No habla de ningún instrumento concreto: describe la
> plataforma (norns + SuperCollider + Lua) y las trampas que hacen perder días.
>
> Última verificación: **2026-10-02**, contra `monome/norns@main` y `monome/docs@main`.

---

### 3.8 `addCommand` — el contrato de tipos

```supercollider
this.addCommand("cutoff",  "f",            { |msg| synth.set(\cutoff, msg[1]) });
this.addCommand("mod_amp", "ffffffffffff", { |msg| synth.setn(\mod_amp, msg.drop(1)) });
```

| Carácter | Tipo |
|---|---|
| `i` | entero |
| `f` | float |
| `s` | string |
| `a` | array (por **nombre** de control) |
| `t` | toggle (booleano) |
| `b` | blob |

- `"f"` × N = un array de N floats. Un `addCommand` de array **es un solo viaje
  OSC**, no N. Eso es lo que hace viable una matriz de modulación de 12×24.
- **El formato DEBE coincidir con lo que Lua manda.** Si Lua manda 12 floats y el
  formato es `"f"`, el motor lee 1 y el resto se pierde en silencio.
- Desde Lua: `engine.cutoff(440)`, `engine.mod_amp(1, 0, 0, ...)`.

### 3.9 `set` vs `setn` vs `setkr`

```supercollider
synth.set(\gain, 0.5)              // un control
synth.setn(\mod_amp, [1,0,0,...])  // un NamedControl array
synth.set(\x, y, \kr)              // fuerza control-rate
```

Un control que usas para audio **y** para control necesita `set(..., \kr)` explícito.

### 3.10 Telemetría SC → Lua

Hay dos caminos, y el que usa casi todo el mundo es el **peor**.

**El habitual (doble salto):**
```supercollider
// en el SynthDef, 30 veces por segundo:
SendReply.kr(Impulse.kr(30), '/update', [ ...24 valores... ]);

// en el engine:
osc_responder = OSCFunc({ |msg| NetAddr("127.0.0.1", 10111).sendMsg("/update", *msg.drop(3)); },
                        '/update', nil);
```

`SendReply` va a **sclang**, que es un proceso **distinto** de matron. Entonces
sclang reenvía a matron por otro socket. Dos procesos, dos saltos, y un `OSCFunc` en
**modo promiscuo** (`recvID = nil`) que captura *cualquier* `/update`.

**El idiomático: `addPoll`**

`addPoll` se registra en `CronePollRegistry` y **matron lo pide directamente**. Un
solo salto, sin `OSCFunc` promiscuo, sin reenvío.

**Cuándo NO cambiar a poll:** si necesitas >30 Hz o muchos canales por mensaje.

**Coste a recordar:** si construyes el `NetAddr` **dentro** del `OSCFunc`, reservas
memoria nueva 30 veces por segundo, para siempre. Reutiliza el `NetAddr` que ya
tienes como atributo del engine.

---

## 4. Lua 5.3 en norns


### 4.1 Es 5.3. NO es LuaJIT.

Esto cambia cosas concretas:

| Escribes | LuaJIT (5.1) | **norns (5.3)** |
|---|---|---|
| `unpack(t)` | funciona | **error**, usa **`table.unpack(t)`** |
| `3/2` | `1.5` | **`1`** (división entera entre enteros) |
| `1/2` | `0.5` | `0.5` (igual) |
| `//` | no existe | división entera |
| `bit32` | disponible | deprecado, presente |
| `math.type(1)` | no existe | existe |

**El caso peligroso:** si mezclas enteros y flotantes sin querer, `/` puede darte
un entero truncado donde esperabas un decimal.

### 4.2 Las closures capturan la variable de bucle por referencia

Este es el bug silencioso más caro de Lua 5.3. **No se arregló hasta Lua 5.4.**

```lua
local fs = {}
for i = 1, 3 do
  fs[i] = function() return i end    -- en 5.3, las 3 devuelven 3
end
```

Solución: crear una `local` **dentro** del cuerpo del bucle.

```lua
for i = 1, 2 do
  local s = (i == 1) and "L" or "R"   -- 's' es nueva en cada iteración
  params:set_action("rec"..s, function(x) SC.set_rec(i, x) end)
  --                                                      ^ error: 'i' es la del bucle
end
```

**Regla práctica:** dentro de un `for`, captura en una `local` *todo* lo que vayas
a usar en una closure. La variable de control del `for` **nunca**.

> Esto importa muchísimo en el patrón `param_set.lua`, donde un `for i=1,2` crea
> decenas de acciones de parámetro. Si todas capturan `i`, todas hablan con el
> canal 2.

### 4.3 `math.random` y el orden de carga

`math.randomseed(t)` afecta a lo que se ejecute **después**. Los módulos que corren
en el `include` (p. ej. precalcular tablas de offsets) se ejecutan **antes** de tu
`init()`. Si quieres variación por sesión, siembra **antes** del `include`.

## 5. `params` — el módulo donde más se tropieza


### 5.1 `controlspec.new` — el 4º argumento NO es el default

```lua
controlspec.new(min, max, warp, step, default, units, quantum, wrap)
--                       ^^^^        ^^^^^^^^^^^^^^^
```

Orden real: `min, max, warp, step, default, units, quantum, wrap`.

```lua
-- "un control de 0 a 2, lineal, redondeo automático, arranca en 1"
controlspec.new(0, 2, "lin", 0, 1)

-- el que todo el mundo escribe por costumbre:
controlspec.new(0, 2, "lin", 1)   -- step = 1 -> cuantiza a enteros
```

`step = 0` significa "sin cuantizar".

**Warps:** `lin`, `exp`, `sq`, `cub`, `sqrt`, `f` (frecuencia).
- `exp` **requiere `min > 0`**. `controlspec.new(0, 100, "exp")` está mal.
- Para un fader de frecuencia usa `f`, no `exp`.

**Presets:** `controlspec.AMP`, `.PAN`, `.DB`, `.FREQ`, `.LOFREQ`, `.MIDFREQ`,
`.WIDEFREQ`, `.DELAY`, `.BEATS`, `.RATE`, `.MIDI`, `.MIDINOTE`, `.MIDIVELOCITY`,
`.PHASE`, `.RQ`, `.DETUNE`, `.UNIPOLAR`, `.BIPOLAR`.

**`quantum`** = cuánto mueve `params:delta`. Por defecto `0.01` = 1/100 del rango.
Si cambias el `maxval` de un control, **cambia el `quantum`** proporcionalmente:

```lua
-- max 10 -> quantum 1/100  -> cada giro mueve 0.1
-- max 60 -> quantum 1/600 -> cada giro mueve 0.1  (si no, mueve 0.6)
```

### 5.2 `add_group` — el conteo debe ser EXACTO

`n` es el número de **huecos que se reservan** para los parámetros que van
detrás. El nombre del grupo **NO cuenta**: es una etiqueta, no un hueco.

```lua
params:add_group("COCO 1", 17)   -- reserva 17 huecos
-- ...y se agregan exactamente 17 params
```

Si sobran huecos, se llenan con lo que venga después (en ncoco, `Volume 2` se
colaba dentro de COCO 1). Si faltan, los últimos params caen fuera del grupo.
Cualquiera de los dos errores **desplaza** el resto del menú.

**Ha pasado tres veces en ncoco:** v2.14 (`16n_orient` se quedó fuera de
GLOBALS), v3.00 (`Volume 2` cayó dentro de COCO 1) y v3.05 (`Petal Polarity` y
`Petal S&H/T&H` se quedaron fuera de GLOBALS). Las tres veces el síntoma fue el
mismo: el param **funciona** perfectamente, solo aparece en el sitio
equivocado. No hay error, no hay aviso, y por eso se coló tres veces.

**Cómo no equivocarse:** cuenta los `params:add_*` entre el `add_group` y el
siguiente `add_group`. Ignora las líneas comentadas. Automatízalo con un test:
`tools/verify_p30_groups.lua` lo hace para los **cuatro** grupos del archivo y,
si no cuadra, te dice la línea y a qué número subir el contador.
`tools/verify_p22_grupo_coco.lua` es el guard histórico del grupo COCO.

**Trampa de segundo orden (aprendida en v3.05).** Un test que *fija el valor*
—`add_group("GLOBALS", 7)`— convierte el bug en algo **imposible de arreglar**:
al corregir el contador, falla el test, y el siguiente que llega se cree el
test. Comprueba la **propiedad** («los params están dentro del grupo»), nunca el
literal. Regla general: si un test te impide arreglar algo, sospecha primero
del test.

### 5.3 `default()` no es cargar el PSET

```lua
params:default()   -- pone cada param en SU default de código
```

**No lee ningún archivo PSET.** Cargar el último PSET guardado es
`params.action_read`, cuando el usuario lo elige en el menú.

> Consecuencia: cualquier valor que pongas a mano justo antes de
> `params:default()` **se pierde**.

### 5.4 `set` dispara la acción, salvo que digas lo contrario

```lua
params:set("gain", 0.5)          -- ejecuta la acción
params:set("gain", 0.5, true)    -- silencioso
```

### 5.5 `get` vs `get_raw` vs `controlspec:map`

```lua
params:get("gain")            -- valor REAL (ej. 4400.0 Hz)
params:get_raw("gain")        -- valor normalizado 0..1
cs:map(0.5)                   -- 0.5 normalizado -> valor real
cs:unmap(4400.0)              -- valor real -> 0.5 normalizado
```

**MIDI learn:** un fader CC da 0..127. Para compararlo contra un parámetro que ya
tiene valor, normaliza **ambos** a 0..1. `unmap` es el puente.

### 5.6 PSET: `action_write` / `action_read`

```lua
params.action_write = function(filename, name, number) ... end  -- guardar
params.action_read  = function(filename, silent, number) ... end -- cargar
params.action_bang  = function() params:bang() end               -- sin archivar
```

Si escribes archivos de audio grandes (wav) desde `action_write`, estás escribiendo
en la SD **cada vez que el usuario guarda**. En una CM3 de 4 GB eso se llena rápido.

### 5.7 `hide`/`show` + `_menu.rebuild_params()`

Cambiar la visibilidad de un parámetro **no refresca el menú** por sí solo. Si
depende de otro parámetro (un toggle que muestra/oculta un grupo), llama a
`_menu.rebuild_params()`. No es API pública documentada, pero es el estándar de facto.

---

## 6. `grid` — modelo de tráfico


### 6.1 El modelo de dos fases

```lua
g:led(x, y, nivel)   -- MARCA SUCIO. No habla con el dispositivo.
g:refresh()          -- ENVÍA los sucios. Esto SÍ habla con el dispositivo.
```

**Nunca llames `refresh()` dentro de un bucle de LEDs.** El patrón correcto es:
marcar todos, un `refresh()` al final.

### 6.2 Nivel = valor, no color

0 = apagado · 1-3 = muy tenue · 4-6 = tenue · 8-10 = medio · 12-14 = brillante ·
15 = máximo. **No hay color.** Un grid monochrome muestra 16 niveles de brillo
(gris), no 16 colores.

```lua
g:all(0)        -- apagar todo
g:refresh()     -- obligatorio
g:intensity(i)  -- multiplicador GLOBAL de brillo de ese grid (0-15)
```

`intensity()` es un escalón por dispositivo, independiente del nivel por LED.

### 6.3 El patrón de caché diferencial

Para no reenviar los 128 LEDs 15 veces por segundo, guarda lo que *crees* que está
puesto y solo manda la diferencia:

```lua
if cache[x][y] ~= b then
  g:led(x, y, b)
  cache[x][y] = b
  changed = true
end
-- ... al final del bucle:
if changed then g:refresh() end
```

**Dos centinelas distintos y por qué importa:**

| Valor | Significado |
|---|---|
| `-1` | "no sé qué hay" -> fuerza reenvío (dirty) |
| `15` | "latch: este botón está pulsado, no lo toques" |

Confundirlos produce el bug clásico: pones `15` como marca de "forzar redibujo" y
el update diferencial ve `cache == b == 15`, **omite el LED**, y el botón se queda
apagado. Usa `-1` para "sucio", `15` para "pulsado".

### 6.4 `grid.add` es GLOBAL, no del dispositivo

```lua
function grid.add(new_grid)      -- obligatorio que sea 'grid'
  g = grid.connect(new_grid.port)
end
-- g.add = ...                    -- NO existe
```

Se dispara cuando se conecta *cualquier* grid. También existe `grid.remove`.

En el callback **re-conecta** y **resetea la caché**, o te queda la pantalla
congelada mostrando el estado anterior.

### 6.5 Anti-congelamiento

Los grids se desincronizan del sistema (al dormir, al cambiar de hub USB, o por un
glitch USB). El remedio barato y probado: **cada N segundos, tirar la caché** para
forzar el reenvío completo.

```lua
contador = contador + 1
if contador >= 75 then       -- 75 frames @ 15 Hz = 5 s
  reset_cache()              -- todo a -1
  contador = 0
end
```

No es elegante, pero es infinitamente más robusto que intentar detectar la
desincronización. Coste: 128 escrituras cada 5 s. Irrelevante.

### 6.6 Recuperación en caliente (lo que hace un reinicio, sin reiniciar)

Un reinicio de script, en lo que a la rejilla toca, ejecuta `Script.clear()`
(`lua/core/script.lua`) → `grid.cleanup()` (por dispositivo: `dev:all(0)` +
`dev:refresh()`) y `metro.free_all()`. Eso **se puede hacer en vivo**:

```lua
local port = GridNav.find_device_port()      -- escanea Grid.vports[1..4].device
if port and g ~= grid.connect(port) then g = grid.connect(port) end
GridNav.reset_cache()                         -- reenvío forzado, SIN apagar (ver abajo)
grid_metro:stop(); grid_metro:start()        -- start() REUSA el id: sin fuga
```

- `grid.connect(n)` devuelve `Grid.vports[n]`; su campo `.device` lo rellena
  `Grid.update_devices()`. **Hay que ESCANEAR los 4 vports**: si el aparato
  reengancha con otro nombre queda en otro vport y el 1 se queda sin `.device`
  (y entonces `g:led`/`g:refresh` son **no-ops silenciosos**, `vport.lua`).
- `g:led()` marca su quad dirty **sin comparar el valor** (`device_monome.cc`), así
  que poner la caché a `-1` hace que el siguiente redraw **reescriba las 128
  celdas** y deje los 4 quads sucios. `reset_cache()` **basta** para un reenvío
  completo.
- **No uses `g:all(0)` para "forzar" el reenvío.** Sí marca todo dirty, pero
  también **manda los 128 LEDs a 0**: la rejilla se apaga hasta el siguiente
  tick (67 ms a 15 Hz). Ese es el **destello**. Es redundante *y* destructivo.
- Ncoco expone `>> recover_grid()` a maiden para el congelado que **no** se puede
  detectar desde Lua (capa serial/USB de monome).

### 6.7 `metro` y `clock` son el MISMO hilo — el watchdog que miente

Verificado en `matron/src/events.cc`:

- hay **un solo `event_loop()`**, que drena **una sola cola FIFO**;
- `w_handle_metro()` (ticks de `metro`) y `w_handle_clock_resume()` (despertares
  de `clock`) llaman **al mismo estado Lua** (`lvm`).

Consecuencia práctica: **están serializados.** Si un manejador de Lua tarda N
segundos, se paran los dos a la vez; al reanudarse, todos los eventos pendientes
se procesan de golpe.

Por eso este patrón —tan natural como falso— **miente**:

```lua
-- MAL: parece que vigila el metro, pero en realidad vigila "el reloj".
local last = mi_metronometro          -- lo escribe el evento del metro
clock.run(function()                 -- un watchdog "independiente"...
  while true do
    clock.sleep(2.0)
    if util.time() - last > 3.0 then recover() end   -- ...que no lo es
  end
end)
```

Si el bucle se bloquea 5 s, el watchdog ve 5 s y "recupera" algo que no estaba
roto. Y si la recuperación **apaga** la rejilla (como `g:all(0)`), el propio
watchdog **falla en abierto**: el destructivo es su propia acción correctora.

**La prueba que sí funciona: mide tu propio atraso.**

```lua
local t0 = util.time()
while true do
  clock.sleep(2.0)
  local now = util.time()
  local late = (now - t0) - 2.0        -- ~0 si el bucle está sano
  t0 = now
  if late >= 1.0 then
    -- el bucle ENTERO se bloqueó: el otro sistema tampoco corría.
    report("se bloqueó Lua %.1fs; no toco nada") late
  elseif (now - last) > 3.0 then
    -- el latido fue puntual y aun así no hay redraw: ahí sí es el otro.
    report("el metro no dispara; recuperando")
  end
end
```

`late` grande **prueba** el bloqueo global (un watchdog que no depende del metro
no puede llegar tarde si no se paró todo); `late` pequeño con el otro sistema
muerto **prueba** que el fallo es del otro. Y aun así, exige **dos detecciones
seguidas** antes de actuar: una parada transitoria no debe costar un destello.

ncoco lo tiene en `lib/grid_nav.lua` → `GridNav.heartbeat_step()` (función pura,
testeable sin reloj) y `tools/verify_p28_heartbeat.lua`.

---

## 7. `midi`


```lua
m = midi.connect()             -- puerto 1 por defecto
m:note_on(60, 100, 1)
m.event = function(data)       -- SIEMPRE recibe el array crudo
  local msg = midi.to_msg(data)
  if msg.type == 'cc' then ... end
end
```

### 7.1 SysEx: reensamblar en orden — pero `pairs`, NO `ipairs`

⚠️ **Esta sección cambió el 2026-10. La versión anterior decía `ipairs` y era
FALSA. No repitas el consejo viejo.**

```lua
-- MAL: midi.devices puede tener HUECOS. ipairs() se detiene en el primer
-- hueco y nunca ve el dispositivo que está conectado.
for _, dev in ipairs(midi.devices) do ... end

-- BIEN: pairs() recorre TODAS las claves, tenga huecos o no.
for _, dev in pairs(midi.devices) do ... end
```

**Lo que pasó de verdad:** `midi.devices` no es un array contiguo. Si el
dispositivo aparece en la posición 2 y no en la 1, `ipairs` se detiene en el
primer hueco y **nunca lo encuentra**. El 16n se connectaba y el script no lo
veía: sin faders, sin MIDI. Esto costó una regresión real (`b914b75` la revirtió).

**Para arrays 1..n contiguos, `ipairs` sí es lo correcto.** La regla es: si
puede haber huecos, `pairs`. No hay una regla única.

### 7.2 El handshake de config de un 16n

El 16n (Faderfox) expone un dump de configuración por SysEx no estándar.

**En ncoco el byte `0x0f` es el CORRECTO.** Se pide y se comprueba el mismo.
Antes esta guía afirmaba que había una discrepancia (`0x1f` pedido, `0x0f`
comprobado) y que por eso la config nunca se leía. **Era un análisis
equivocado**: se下定a como bug algo que funciona. No lo "arregles" sin hardware.

### 7.3 Puertos virtuales

Por defecto norns solo acepta MIDI del **puerto 1**. Si usas un hub o un
dispositivo que se registra en el puerto 2, tu script no lo ve. Reasigna el
dispositivo al puerto 1 o añade la conexión explícita.


---

## 8. `audio` y buses del sistema


```lua
audio.level_dry(0.8)      -- volumen de la salida principal
audio.level_wet(1.0)      -- de los buses de efecto
audio.pan(x)              -- balance izq/der
```

`context.in_b` / `context.out_b` en un engine son las **entradas y salidas físicas**
de la máquina. Asumir 48 kHz y 2 canales es seguro: están fijos por hardware.

---

## 9. `util`, `tab`, `poll` — los otros que vas a usar


| Módulo | Para qué | Trampa |
|---|---|---|
| `util.linlin` | remapeo lineal | es `(x, inMin, inMax, outMin, outMax, x)` — **el valor va al final** |
| `util.clamp` | recorte | `util.clamp(x, 0, 1)` |
| `util.wrap` | envolvente 1..n | |
| `util.time()` | reloj monotónico en segundos | **no** es `os.clock`; no retrocede |
| `util.file_exists` | existe el archivo | |
| `util.make_dir` | crea directorio (recursivo) | |
| `tab.save` / `tab.load` | serializa una tabla Lua a archivo | **no sabe serializar corrutinas** |
| `poll` | **telemetría del engine, la forma idiomática** | ver §3.10 |
| `screen` | dibujo | `screen.update()` es OBLIGATORIO |
| `string.format` | formateo | `%d` con flotante en 5.3 **lanza error** |

### 9.1 `string.format("%d", 3.7)` en Lua 5.3

```lua
string.format("%d", 3.7)                 -- ERROR: number has no integer representation
string.format("%d", math.floor(3.7))     -- OK
```

Esto **rompió** muchos scripts al migrar de LuaJIT (5.1, donde sí se truncaba).

### 9.2 `tab.save` y las corrutinas

`tab.save` serializa tablas, números, strings, booleanos. **Una corrutina no es
ninguna de esas cosas.** Si guardas una tabla que contiene un `thread`, falla o
escribe basura. Si tu estado tiene un `clock.run()` guardado, **sácalo antes de
serializar**.

---

## 10. Tabla de errores ya pagados


| Síntoma | Causa raíz | Dónde mirar |
|---|---|---|
| Un canal suena, el otro no | `var` usada antes de asignarse, o límite de vars | orden de statements |
| El engine no carga | Nombre de archivo ≠ `engine.name`, o dos copias | nombre del `.sc` |
| `DUPLICATE ENGINES` al arrancar | Dos proyectos con el mismo `Engine_X.sc` | renombra |
| Grid congelado con LEDs apagados | Caché en `15` en vez de `-1` como "sucio" | caché diferencial |
| Un parámetro no aparece en el menú | Conteo de `add_group` incorrecto | `add_group` |
| Todo el MIDI-CC va al canal equivocado | Closure capturando la variable del `for` | `param_set` style |
| Un control salta en vez de moverse fino | `step`/`quantum` mal puestos | `controlspec.new` |
| El PSET no carga al arrancar | `params:default()` no lee archivos | `action_read` |
| Error de formato `%d` | Lua 5.3 es estricto con enteros | `string.format` |
| `unpack` es nil | Lua 5.3, usa `table.unpack` | global |
| Ruido/click al cambiar un parámetro | Falta `.lag` o `.slew` en el control | SC, no Lua |
| El engine se siente "lento" | Barato de datos o demasiado trabajo por frame | §3.10 y caché del grid |
| La rejilla **parpadea y sigue funcionando bien** | Un watchdog que "recuperaba" sin medir su propio atraso: vio el tiempo de un bloqueo de Lua como si fuera fallo del grid | §6.7 |

---

## 11. Checklist antes de publicar un script


- [ ] ¿Probado en el **norns real**, no solo en desktop?
- [ ] ¿El `.sc` está en `lib/` y se llama exactamente como `engine.name`?
- [ ] ¿`cleanup()` cancela **todos** los `clock.run` y para **todos** los `metro`?
- [ ] ¿`grid.add` (no `g.add`) reconecta y resetea caché?
- [ ] ¿`g:refresh()` se llama **una vez** por frame, no por LED?
- [ ] ¿Todos los `add_group` con el conteo exacto?
- [ ] ¿Ningún `for` captura su propia variable de control en una closure?
- [ ] ¿`table.unpack` en vez de `unpack`?
- [ ] ¿Ningún `%d` con un flotante?
- [ ] ¿Ningún estado serializado contiene una corrutina?
- [ ] ¿Los controles que se mueven en caliente llevan `.lag`?
- [ ] ¿Probado con **todos** los modos/bits del engine, no solo el default?
- [ ] ¿Consumo de CPU y memoria siguen bien tras una hora de uso?

---

## 12. Referencias


- Docs: <https://monome.org/docs/norns/>
- Referencia del API: <https://monome.org/docs/norns/reference/>
- Engine studies 1-3: *rude mechanicals*, *skilled labor*, *transit authority*
- Código fuente (autoritativo para versiones): `monome/norns@main` ->
  `Dockerfile`, `wscript`, `sc/core/CroneEngine.sc`
- Releases: <https://github.com/monome/norns/releases>


---
