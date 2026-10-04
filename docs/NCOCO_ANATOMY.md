# Anatomía de ncoco

> Instrumento tipo *async looper* para **monome norns** + grid, inspirado en
> cocoquantus. Dos cintas de audio en loop, una matriz de modulación 12×24 y
> **cuatro** modos de degradación de bits (8bit / 12bit / SBC / u-law).
>
> Documento **de proyecto**. Las reglas de la plataforma están en
> [`NORNS_DEVELOPMENT_GUIDE.md`](./NORNS_DEVELOPMENT_GUIDE.md). El detalle de
> los modos de bits, con su nivel de verificación, está en
> [`BIT_MODES_FINDINGS.md`](./BIT_MODES_FINDINGS.md).
>
> Análisis del código: **2026-10-02**, revisado contra **v3.03** (`6c6cc02`).

---

## 1. Qué es, en términos de sonido


ncoco es un **looper asíncrono de dos cintas** (una por canal) con la señal de entrada
inyectada dentro del bucle. La diferencia con un looper de overdub clásico:

- **La entrada se suma a la lectura de la cinta mientras se graba**, no se "capa"
  encima. El bucle se auto-realimenta: lo que entra vuelve a salir mezclado con lo
  que ya había.
- Eso genera **saturación, acumulación de graves y degradación progresiva** de forma
  orgánica, en vez de un overdub lineal que solo crece.
- Los **4 modos de bits** (8bit / 12bit / SBC / u-law) son una capa de
  **coloración de digitalización** aplicada a la señal *dentro* del bucle: el grano y
  el ruido de cuantización se realimentan y se acumulan.

**Perfil sonoro esperado:** cálidas, con deriva de cinta, saturación gradual, y
texturas que se van degradando con el tiempo. Es un instrumento de textura, no de
precisión.

---

## 2. Estructura de archivos


```
ncoco/
├── ncoco.lua                  ← script principal (916 líneas)
├── lib/
│   ├── Engine_Ncoco.sc        ← motor DSP (650 líneas)
│   ├── globals.lua            ← estado global compartido
│   ├── param_set.lua          ← definición de todos los parámetros
│   ├── grid_nav.lua           ← mapeo del grid + secuenciadores
│   ├── ui.lua                 ← dibujo de pantalla
│   ├── quantussy.lua          ← dibujo de los "pétalos" (hexágonos)
│   ├── sc_utils.lua           ← puente Lua → engine
│   ├── storage.lua            ← PSET / total recall
│   └── 16n.lua                ← soporte del Faderfox 16n
├── tools/                     ← tests (`lua tools/verify_*.lua`)
└── docs/
    ├── NORNS_DEVELOPMENT_GUIDE.md
    ├── BIT_MODES_FINDINGS.md  ← los 4 modos de bits, con su verificación
    └── NCOCO_ANATOMY.md       ← este documento
```

### 2.1 Orden de carga (importa)

`ncoco.lua` carga sus libs con un wrapper a prueba de fallos:

```lua
local function safe_include(name)
  local ok, result = pcall(include, name)
  if not ok then print("CRITICAL: " .. name .. " - " .. tostring(result)); return nil end
  return result
end
G       = safe_include('ncoco/lib/globals')
SC      = safe_include('ncoco/lib/sc_utils')
GridNav = safe_include('ncoco/lib/grid_nav')
UI      = safe_include('ncoco/lib/ui')
_16n    = safe_include('ncoco/lib/16n')
Params  = safe_include('ncoco/lib/param_set')
Storage = safe_include('ncoco/lib/storage')
```

Si cualquiera falla, `ncoco.lua` hace `return` y no arranca. **Es un acierto**: un
include roto en norns te deja un script a medias y una pantalla en blanco sin
explicación.

> ⚠️ **Acoplamiento oculto:** `grid_nav.lua` hace su propio
> `include('ncoco/lib/sc_utils')` (línea 55). Como `include` **tiene caché**, es la
> misma tabla — no una copia. Funciona, pero `grid_nav` depende de un módulo que no
> recibe como parámetro. Si alguien mueve `sc_utils`, `grid_nav` se rompe sin avisar.

---

## 3. El motor: dos synths, no uno


El engine se divide en **dos `SynthDef` separados**:

```
NcocoCore  ──┬── b_tape     (audio, 2ch)  ──┐
             ├── b_mon      (audio, 2ch)  ──┤
             ├── b_bleed    (audio, 2ch)  ──┼──> NcocoOut ──> out_b
             ├── b_mod_vol  (control, 2ch) ─┤
             └── b_mod_filt (control, 2ch) ─┘
```

**Por qué dos y no uno:** el motor tiene un presupuesto de `var` limitado (ver
`NORNS_DEVELOPMENT_GUIDE.md` §3.3 — ncoco ya lo ha sufrido). Partirlo permite que
cada synth se mantenga bajo el techo. El precio es que **todo lo que `Core` produce
y `Out` necesita tiene que viajar por un bus**, y un bus de control tiene 1 bloque
de latencia (~1.3 ms).

**Consecuencia práctica:** `NcocoOut` no puede calcular la modulación, solo la
recibe. Por eso existen `b_mod_vol` y `b_mod_filt` — son el **puente de la
modulación de volumen y filtro** entre los dos synths.

### 3.1 Buffers

```supercollider
bufL = Buffer.alloc(context.server, 48000 * 60, 1);  // 60 s, mono
bufR = Buffer.alloc(context.server, 48000 * 60, 1);
```

- **60 segundos** de cinta por canal, mono, a 48 kHz.
- Se graban con `BufWr.ar(writeL, bufL, ptrL)` y se leen con
  `BufRd.ar(1, bufL, ptrL, loop:1)`.
- Se vacían con `buf.zero` en el arranque (con barrera `sync` alrededor).

**Coste de RAM:** 60 s × 48000 × 4 bytes × 2 canales ≈ **23 MB**. En una CM3 con
1 GB es perfectamente viable, pero es el mayor consumidor del engine.

### 3.2 El bucle de realimentación

```supercollider
feedback_in = LocalIn.ar(10);   // arriba del todo
...
LocalOut.ar([p1..p6, yellowL, yellowR, src11_ar, src12_ar]);  // al final
```

`LocalIn`/`LocalOut` cierran el bucle con **exactamente 1 bloque de latencia**
(64 muestras @ 48 kHz = **1.33 ms**). Ese retardo es **audible** en el looper: es la
razón por la que el "eco" de la cinta no está perfectamente en fase.

| Canal | Señal | Entra de vuelta al audio |
|---|---|---|
| 0–5 | `p1`..`p6` (los 6 pétalos, pasan por `tanh`) | sí — cadena de pétalos |
| 6–7 | `yellowL`, `yellowR` (posición de lectura) | no — solo telemetría |
| 8–9 | `src11_ar`, `src12_ar` (salidas COCO) | no — solo telemetría |

> **Importante:** solo los 6 pétalos se realimentan de verdad en el grafo de audio.
> Las posiciones y las salidas COCO se devuelven "para medir", no para realimentar.

## 4. Las 12 fuentes de modulación


ncoco tiene 12 "fuentes" (lo que puede modular) y 24 "destinos" (lo que se puede
modular):

| # | Nombre | Qué es | Cómo se genera |
|---|---|---|---|
| 1–6 | **PÉTALO 1–6** | 6 LFO / audio-reactivos | `Phasor` + `tanh` + realimentación cruzada |
| 7 | **ENV L** | envolvente de entrada izq. | `Amplitude.kr` sobre la entrada L |
| 8 | **ENV R** | envolvente de entrada der. | `Amplitude.kr` sobre la entrada R |
| 9 | **YEL 1** | posición de lectura izq. | `ptrL / endL` |
| 10 | **YEL 2** | posición de lectura der. | `ptrR / endR` |
| 11 | **COCO 1** | salida del looper 1 | `readL` o su envolvente |
| 12 | **COCO 2** | salida del looper 2 | `readR` o su envolvente |

### 4.1 Los pétalos en detalle

Cada pétalo i es un LFO con **realimentación cruzada** — el pétalo 2 se modula por
el 1, el 3 por el 2, etc.:

```supercollider
b_ph1 = Phasor.ar(0, (p1f + mod_p1).abs * SampleDur.ir, 0, 1);
t1    = Trig1.ar(b_ph1 > 0.05, SampleDur.ir);
p1    = ((b_ph1 + (fb_petals[5] * p1c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
```

- `p_if` = frecuencia base (0.01–20 Hz en modo LFO, 20–2000 Hz en modo Audio)
- `mod_pN` = modulación recibida de la matriz (hasta ±10)
- `pNc` = caos (individual + global), aplicado como `pow(3)` → **el caos solo
  actúa en el extremo del rango**, no de forma lineal
- `fb_petals[n-1]` = realimentación del pétalo anterior
- `.abs` al final → **en modo Abs (por defecto) la salida es 0..1**, y la realimentación
  del anillo es unidireccional. En modo Bipolar ver §4.2.

**La forma (Tri / Castle):**
```supercollider
c1 = Select.ar(pGate,[Latch.ar(p6,t1), Lag.ar(Gate.ar(p6,b_ph1>0.5),0.004)]);
out1 = Select.ar(p1shape, [p1, c1]);
```
- `p1shape = 0` → triángulo suave (la rampa `p1`)
- `p1shape = 1` → escalones → "Castle" (la salida retentida `c1`)

**Shape es un filtro de SALIDA, no parte del oscilador (v3.06).** El anillo de
pétalos es el generador; `outN` decide **qué se manda hacia fuera**. Por eso hay
**dos etapas** de `sources_sig`, y por eso el orden importa tanto como el
contenido:

```supercollider
// etapa A: la rama CRUDA y retrasada (fb_petals) -> la frecuencia de los pétalos
sources_sig = [fb_petals[0..5], …];
mod_p1 = (sources_sig * mod_p1_Amts).sum * …;   // <- se resuelve AQUÍ
…out1..out6 ya existen…
// etapa B: la rama CON SHAPE, del bloque actual -> los destinos de audio
sources_sig = [out1.tanh, …, out6.tanh, …];
mod_val_speedL = (sources_sig * mod_speedL_Amts).sum * …;
```

La etapa A **no puede** ser la B: `mod_pN` alimenta la fase del propio pétalo, así
que si leyera `outN` (valor del bloque actual) habría un lazo algebraico
`pétal → sources_sig → mod_pN → pétal` sin retardo, y SuperCollider no puede
construir eso. El retardo de un bloque de `fb_petals` es lo que rompe el lazo.
Por el mismo motivo el acoplamiento del anillo sigue con la rama cruda: el anillo
es el generador, y `Shape` solo actúa a la salida.

> **Historia: esto estuvo roto desde v2.52.** Entre el commit `7737aaa` y `v3.05`
> las dos etapas se colapsaron en una sola, la cruda. `Shape` solo afectaba al OSC
> `/update`: con Castle el display dibujaba escalones y el sonido seguía siendo el
> triángulo. No se notaba porque con **Tri (el default) `outN == pN`**, y las dos
> ramas coinciden exactamente. El invariante que faltaba —*lo que se dibuja y lo
> que se modula tienen que ser la misma variable*— está ahora en
> `tools/verify_p29_petals.lua`.

### 4.2 Los dos modos globales de los pétalos (v3.04)

Dos opciones globales en el menú, en el grupo **GLOBALS**, que afectan a los 6
pétalos a la vez. **Ambas son opt-in: su valor por defecto es la de v3.03 y la señal
resultante es bit-idéntica.**

**Petal Polarity — `Abs` (por defecto) / `Bipolar`**

Después de la rampa rectificada se re-centra reutilizando la misma variable:

```supercollider
p1 = ((b_ph1 + (fb_petals[5] * p1c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
p1 = Select.ar(pBipolar, [p1, p1 * 2 - 1]);
```

> **v3.05 corrigió el centrado.** Hasta v3.04 era `p1 - 0.5`, o sea un rango de
> −0.5..+0.5 mientras que Abs llega a 1.0. Como la matriz aplica `.tanh`, el pico
> bipolar era `tanh(0.5)=0.46`, el **61%** del pico de Abs (`tanh(1)=0.76`): el
> bipolar se oía más flojo en vez de recorrer lo mismo en las dos direcciones.
> `2*pN-1` pone el cero en el centro exacto de la rampa (`p=0.5 → 0`) y devuelve
> el pico a 0.76, **idéntico al de Abs**.

| | Abs | Bipolar |
|---|---|---|
| Rango | 0..1 | −1..+1 |
| Pico tras el `.tanh` de la matriz | 0.76 | 0.76 |
| Acoplamiento del anillo |unidireccional | **con signo, bidireccional** |
| El "cero" | un pulso | una envolvente 50/50 |

Que `p1` sea negativo significa que `p2`, que se calcula a partir de `p1`, también
puede serlo: la polaridad se propaga sola por toda la cadena, sin código extra.

**La salida retentiva: siempre Track & Hold (v3.07)**

> El modo `Sample & Hold` **se eliminó** en v3.07 (decisión del autor). El parámetro
> global «Petal S&H/T&H» ya no existe y `c1` es siempre un T&H. Con él se fueron el
> `Latch`, el `Select` de elección y los seis relojes `t1..t6`, que solo existían para
> el `Latch`. Ahorro: **−18 ugens** y **−6 vars**. No hace falta migrar los PSET: el
> valor guardado en `petal_gate_mode` simplemente ya no se consulta, y el default del
> motor ahora *es* T&H.

```supercollider
c1 = Lag.ar(Gate.ar(p6, b_ph1 > 0.5), 0.004);
```

| | Qué hace |
|---|---|
| `Gate.ar(p6, b_ph1>0.5)` | deja pasar `p6` mientras `b_ph1 > 0.5` (primera mitad del ciclo) |
| `Lag.ar(…, 0.004)` | congela el último valor y suaviza el borde del gate (segunda mitad) |

El reloj es **exactamente 50/50** y sale de la fase del propio pétalo, que ya se
calculaba para la onda, así que no cuesta nada.

> **Nota sobre el reloj 50/50.** Con `p1f = 0.5` el ciclo dura 2 s: T&H sigue la fuente
> 1 s y la mantiene 1 s. Si subes mucho `p1f` la fase completa un ciclo antes que el
> `Lag` de 4 ms termine de asentarse — con frecuencias de audio el T&H tiende al LFO
> continuo. Es el comportamiento esperado de un T&H real, no un fallo.

**Por qué se reescriben las variables en vez de crear otras.** El motor ya está al
**72% de `MAX_CONTROL`** por los 24 `NamedControl` de la matriz de modulación, y
`p1..p6` / `c1..c6` ya existen en la declaración de vars. Reutilizarlas cuesta:

| Recurso | v3.03 | v3.04 | Δ |
|---|---|---|---|
| Vars del SynthDef | 208 | 208 | **+0** |
| Slots de control | 312 (+ ~56 sueltos) | 314 | **+2** |
| Canales `LocalIn` / `LocalOut` | 10 / 10 | 10 / 10 | **+0** |
| Paquetes OSC (`/update` a 30 Hz) | — | — | **+0** |
| Unit generators | 210 | 234 | **+24** |

Los +24 eran 6 `Select` (polaridad) + 6 `Select` + 6 `Gate` + 6 `Lag`. **Select no
cortocircuita**: las dos ramas se evalúan siempre, así que en S&H el T&H también se
calculaba. Todos son ugens de una sola muestra. En v3.07 se media mitad: los **12
ugens** del `Select` y el `Latch` se fueron con el modo S&H, y con ellos los 6
`Trig1` (los relojes `t1..t6`).

**Lo que costó v3.06** (la etapa B de `sources_sig`, ver §4.1): **+8 ugens**
(6 `tanh` + 2 `K2A` duplicados), **+0 vars**, **+0 canales `LocalIn`/`LocalOut`**,
**+0 paquetes OSC**. Se reutiliza `sources_sig` en vez de crear una variable
nueva, porque a partir de la etapa B su versión cruda ya no hace falta: se resuelve
antes en las seis `mod_pN`. Total acumulado en v3.06: **242 ugens**.

**Fallo hacia atrás.** Solo el `1` exacto de la opción activa el modo nuevo; cualquier
otro valor (un PSET corrupto, un parámetro eliminado, un `nil`) elige la rama 0, que
es el comportamiento de v3.03. Un dato corrupto no debe dejar el motor en un modo que
el usuario no pidió.

> **Al recompilar.** Añadir controles al SynthDef obliga a `engine.load()`, que
> **re-asigna los buffers de 60 s y corta el audio**. La primera vez que arranques con
> esta versión hay que recargar la cinta del disco.

**Por qué 6 en cadena y no en paralelo:** la cadena hace que el conjunto se comporte
como **un sistema caótico único** en vez de 6 LFO independientes. Es la diferencia
entre "6 osciladores" y "un oscilador complejo". Subir el caos global (E3) hace que
el sistema se vuelva impredecible; bajar el caos de un pétalo individual lo
desacopla de la cadena.

---

## 5. Los 24 destinos de modulación


| # | Destino | Efecto musical |
|---|---|---|
| 1 | SPD 1 | velocidad cinta L |
| 2 | AMP 1 | volumen L |
| 3 | FB 1 | realimentación L |
| 4 | FILT 1 | filtro DJ izq. |
| 5 | FLIP 1 | invertir dirección L |
| 6 | SKIP 1 | salto/stutter L |
| 7 | REC 1 | grabar L |
| 8 | SPD 2 | velocidad cinta R |
| 9 | AMP 2 | volumen R |
| 10 | FB 2 | realimentación R |
| 11 | FILT 2 | filtro DJ der. |
| 12 | FLIP 2 | invertir dirección R |
| 13 | SKIP 2 | salto/stutter R |
| 14 | REC 2 | grabar R |
| 15–20 | P1–P6 FRQ | frecuencia de los pétalos |
| 21 | VOL 1 | volumen final izq. |
| 22 | VOL 2 | volumen final der. |
| 23 | AUD IN 1 | audio de entrada hacia L |
| 24 | AUD IN 2 | audio de entrada hacia R |

**La fuerza de cada modulación la controla `dest_gains[d]`, 0–2×**, ajustable con
E3 en el inspector de destino. 1.0 = normal, 0 = sin efecto, 2 = el doble.

> **Todas las fuentes y destinos son bilaterales:** una fuente puede modular
> cualquier destino, y el grid tiene un "jack" para cada destino. No hay asignaciones
> fijas.


## 6. Los 4 modos de bits


Este es el corazón del color sonoro. **Verificado leyendo el código.**

### 6.1 Cómo se selecciona

El parámetro `bitsL` / `bitsR` (menú: *"Bits 1"* / *"Bits 2"*) es una opción con
**cuatro** valores. El índice del menú (1–4) se convierte a índice de motor (0–3)
en un único sitio, `lib/sc_utils.lua`:

```lua
params:add_option("bits"..s, "Bits "..num, {"8bit", "12bit", "SBC", "u-law"}, 1)
params:set_action("bits"..s, function(x) SC.set_mode(i, x-1) end)
```

| Opción del menú | `modeL` / `modeR` | Qué se activa |
|---|---|---|
| `8bit` | **0** | cuantización de 8 bits |
| `12bit` | **1** | cuantización de 12 bits |
| `SBC` | **2** | Sub-Band Coding |
| `u-law` | **3** | companding μ-law |

Y en el motor ese entero **se usa directamente como índice del `Select`**, sin flags
ni aritmética:

```supercollider
writeL = Select.ar(modeL, [
    Latch.ar(writeL.round(0.5 ** 8),  srTrigL),  // 0: 8-bit
    Latch.ar(writeL.round(0.5 ** 12), srTrigL),  // 1: 12-bit
    dpcmReconL,                                  // 2: SBC (sin Latch)
    Latch.ar(muLawL, srTrigL)                    // 3: mu-law
]);
```

> ⚠️ **Por qué el menú dice `u-law` y no `μ-law`.** La fuente integrada de norns
> (6×13) solo cubre ASCII 32–126: no tiene glifo para U+03BC, así que `μ` se
> renderiza como nada y el modo aparecía como `-law`. Verificado en el historial
> del proyecto, que ya había corregido esto antes y se reintrodujo por error.
> El detalle está en [`BIT_MODES_FINDINGS.md`](./BIT_MODES_FINDINGS.md) §4.

### 6.2 Qué hace cada modo

Los tres modos cuantizadores comparten reloj (`srTrigL`); solo el SBC es
feedforward. El "grano" viene de que `Latch` retiene el valor cuantizado **entre**
muestras, y el reloj va **a la velocidad de reproducción** — como un sampler real.

#### 8bit — `Latch.ar(writeL.round(0.5 ** 8), srTrigL)`

- Cuantización a **8 bits** (256 niveles), retenida a la tasa del reloj.
- `0.5 ** 8` = paso de cuantización de 0.0039.
- `srTrigL` es un reloj derivado de la velocidad de reproducción → **el grano se
  mueve a velocidad de cinta**.
- `PinkNoise` al 0.008 (el más alto), realimentación filtrada a 7 kHz.
- **Color:** el "crunch" de 8 bits clásico. Gruesos, sucios, muy digital. El más
  agresivo de los cuatro.

#### 12bit — `Latch.ar(writeL.round(0.5 ** 12), srTrigL)`

- Cuantización a **12 bits**, mismo esquema de `Latch` que el 8bit pero con paso
  `0.5 ** 12` (≈0.00024).
- `baseSR = 31250 Hz`, realimentación a 12.8 kHz, `PinkNoise` al 0.004.
- **Color:** transicion limpia entre el 8bit y el SBC. Es el modo más neutro de
  los cuatro.

#### u-law — `Latch.ar(muLawL, srTrigL)`

- Companding logarítmico μ-law, el de voz/telefonía: una curva
  `sign·log(1+255·|x|)/log(256)` antes de cuantizar a 255 pasos, y la inversa
  después. Da **muchos más niveles donde el oído los nota** (los bajos).
- `baseSR = 22000 Hz`, realimentación a 11.111 kHz, `PinkNoise` al 0.006.
- **Color:** más suave que el 8bit, con menos siseo en niveles bajos. El más
  musical de los cuatro.

#### SBC — `dpcmReconL` (Sub-Band Coding, 2 bandas)

- **Divide la señal en dos bandas** con un crossover a 6.8 kHz:
  - **Banda baja: 10 bits** (paso `2^-9`)
  - **Banda alta: 5 bits** (paso `2^-4`)
- Recombina las dos bandas. Da **mucha resolución en el cuerpo** y poca en el brillo.
- **48 kHz nativo** — sin recorte de banda.
- `PinkNoise` al 0.002 (el más limpio), realimentación a 16 kHz.
- **Color:** detalle fino, brillante, "digital-frío". El más sutil de los cuatro.

### 6.3 Ruido y filtro por modo

| Modo | Ruido | Filtro feedback | Reloj base | Latch |
|---|---|---|---|---|
| 8bit | 0.008 | 7 kHz | 16 kHz | sí |
| 12bit | 0.004 | 12.8 kHz | 31.25 kHz | sí |
| SBC | 0.002 | 16 kHz | 48 kHz | **no** |
| u-law | 0.006 | 11.1 kHz | 22 kHz | sí |

**Regla general:** el ruido baja de 8bit a SBC (0.008 → 0.004 → 0.002). Es un
degradado de **saturación a limpieza**, pero **u-law rompe la monotonicidad**: con
0.006 queda entre 8bit y 12bit en ruido, aunque su companding lo hace más limpio
que un 12bit plano en los rangos que importan.

### 6.4 Detalle del SBC: sin `Latch`

```supercollider
writeL = Select.ar(modeL, [
    Latch.ar(writeL.round(0.5 ** 8),  srTrigL),  // 0: 8-bit
    Latch.ar(writeL.round(0.5 ** 12), srTrigL),  // 1: 12-bit
    dpcmReconL,                                  // 2: SBC (feedforward puro)
    Latch.ar(muLawL, srTrigL)                    // 3: mu-law
]);
```

El SBC **no retiene el valor**: recalcula la cuantización **en cada muestra** a
48 kHz. Por eso es "nativo" y sin grano. Los otros tres sí usan `Latch`, que
congela el valor entre muestras — de ahí su grano más audible.

> **Aviso sobre una afirmación antigua de este documento.** Hasta v2.x este
> capítulo decía que el índice se calculaba con flags (`is8L + is12L*2 +
> isAdpcmL*3`), lo que dejaba el modo u-law **inalcanzable** desde el menú, y
> describía lo que sonabas como u-law como en realidad 12-bit lineal. Eso era
> **una descripción del código de entonces, no del actual**. Hoy el motor recibe un
> único entero `modeL`/`modeR` que indexa la tabla directamente, así que la
> correspondencia menú→audio no puede desincronizarse.
> Ver [`BIT_MODES_FINDINGS.md`](./BIT_MODES_FINDINGS.md) §1 y §3, y la fila
> resuelta en §16.


---

## 7. El looper: transporte


### 7.1 Velocidad y dirección

```supercollider
baseSpeedL = (speedL + mod_val_speedL + driftL).lag(0.01);
finalRateL = Select.ar(flipLogicL > 0.5, [baseSpeedL, baseSpeedL * -1]);
ptrL = Phasor.ar(finalJumpTrigL, finalRateL * BufRateScale.kr(bufL), 0, endL, resetPosL);
```

- `speedL` = velocidad base (0.001–3.0)
- `mod_val_speedL` = modulación de la matriz (con `tanh` y `lag(0.01)`)
- `driftL` = deriva de cinta, `LFDNoise3.ar(0.08, driftAmt)` — **wow and flutter**
- `flipLogicL` = inversión de dirección (`.mod(2)` para que sea toggle con
  modulación)

**El lag de 0.01 s** es esencial: sin él, cada cambio de velocidad genera un click.

### 7.2 Skip / Stutter

Dos modos (`skip_modeL/R`):

**Single Jump** — cada pulsación salta a un punto aleatorio:
```supercollider
resetPosL = TRand.ar(0, endL, finalJumpTrigL);
```

**Auto Repeat** — stutter continuo con velocidad y caos configurables:
```supercollider
lowerL = stutterRateL - (stutterChaosL * (stutterRateL - 0.001));
upperL = stutterRateL + (stutterChaosL * (0.350 - stutterRateL));
autoTrigL = TDuty.ar(Dwhite(lowerL, upperL), reset: K2A.ar(gateSkipL)) * K2A.ar(gateSkipL);
```

El caos **ensancha el rango de velocidad del stutter** — con caos 0 el repeat es
rítmico, con caos 1 es impredecible.

### 7.3 Longitud de loop

```supercollider
endL = (loopLenL.lag(0.1) * 48000).min(BufFrames.kr(bufL));
```

- `loopLenL/R` = longitud en segundos (0.01–60, default 8.0)
- Se limita a la longitud real del buffer → **no hay crash**
- El `lag(0.1)` evita clicks al cambiar

### 7.4 Grabación — la fórmula clave

```supercollider
dryL = inputL_sig * (volInL + mod_val_ampL).clip(0, 2);
feedbackL = readL * (fbL + mod_val_fbL).clip(0, 1.2) * 1.15;
feedbackL = LPF.ar(feedbackL, fixedFiltFreqL).softclip;
writeL = (dryL + mod_val_audioInL) * gateRecL + feedbackL;
```

```
escritura = (señal_entrada + modulación) × gate_rec + realimentación
```

- Con `gateRec = 0`: solo pasa la realimentación → **la cinta se repite a sí misma**
- Con `gateRec = 1`: entra la señal nueva **además** de la realimentación →
  **acumulación**
- `softclip` en la realimentación: **el secreto del sonido**. La saturación suave
  impide la divergencia y crea esa textura cálida.
- `* 1.15` antes del clip: empuja la señal para que la saturación actúe.

`gateRec` es un **toggle con XOR**: `(recL + mod_val_recL).mod(2)`, de modo que la
modulación puede **alternar** la grabación en vez de solo encenderla.

---

## 8. Salida: filtro DJ y mezcla


### 8.1 Filtro DJ (Classic / Analog)

```supercollider
lpfFreqL = (totalFiltL.min(0)+1).linexp(0,1,100,20000);
hpfFreqL = totalFiltL.max(0).linexp(0,1,20,15000);
classicL = HPF.ar(LPF.ar(sigL, lpfFreqL), hpfFreqL);
```

- `filtL` bipolar −1..+1: **negativo = LOWPASS** (cierra graves), **positivo =
  HIGHPASS** (cierra agudos)
- **Classic**: LPF + HPF en cascada, 12 dB/oct cada uno
- **Analog** (DFM1): dos etapas `DFM1` + pre-atenuación 0.7 + ganancia 0.32

El bypass cuando `totalFiltL.abs < 0.05` evita procesar cuando el filtro está en
centro — ahorro de CPU y sonido más limpio en posición neutra.

### 8.2 Mezcla final

```supercollider
master_out = Pan2.ar(sigL*finalVolL, panL) + Pan2.ar(sigR*finalVolR, panR);
Out.ar(out, Limiter.ar(master_out + [monL*monitorLevel, monR*monitorLevel], 0.95));
```

- Dos `Pan2` sumados = **mezcla estéreo con paneo independiente**
- `Limiter.ar(..., 0.95)` — **el limitador final es imprescindible** con la
  realimentación. Sin él, un loop runaway satura el output digital.
- El monitor de entrada se mezcla antes del limitador → también limitado.

### 8.3 Envoltura COCO (salida 11/12)

Cada salida COCO puede ser **audio directo** o **envolvente**:

```supercollider
src11_ar = Select.ar(coco1OutMode, [
    K2A.ar(Amplitude.kr(LeakDC.ar(readL), ...slew...)),  // envolvente
    readL                                                       // audio
]);
```

- Modo **Envelope**: una envolvente controlable por slew
- Modo **Audio**: la señal cruda

Esto te da un **LFO de audio-rate** que puedes modular con la matriz — muy útil para
generar movimiento percussivo desde la propia cinta.


---

## 9. El contrato OSC (SC → Lua)


El motor envía 24 valores a 30 Hz a Lua. **Este es el punto más frágil del sistema.**

```
scsyn --SendReply--> sclang --OSCFunc--> matron (puerto 10111) --> osc.event
```

```supercollider
SendReply.kr(osc_trigger, '/update', [
    ptrL_norm, ptrR_norm,          -- 1,2   = posiciones
    gateRecL, gateRecR,            -- 3,4   = gates de grabación
    flipStateL, flipStateR,        -- 5,6   = gates de inversión
    skipL, skipR,                  -- 7,8   = gates de skip
    out1..out6,                    -- 9-14  = los 6 pétalos
    envL, envR,                    -- 15,16 = envolventes
    yellowL, yellowR,              -- 17,18 = posiciones (otra vez)
    finalRateL, finalRateR,        -- 19,20 = velocidades
    out_level_L, out_level_R,      -- 21,22 = niveles de salida
    src11_ar, src12_ar             -- 23,24 = salidas COCO
]);
```

Y Lua los recibe:
```lua
G.sources_val[1..6]  = args[9..14]   -- pétalos
G.sources_val[7]     = args[15]      -- env L
G.sources_val[8]     = args[16]      -- env R
G.sources_val[9]     = args[17]      -- yel 1
G.sources_val[10]    = args[18]      -- yel 2
G.sources_val[11]    = args[23]      -- coco 1
G.sources_val[12]    = args[24]      -- coco 2
```

> ⚠️ **Las posiciones (YEL) se envían dos veces:** en los args 1–2 y en los 17–18.
> La UI usa `G.coco[i].pos` (args 1–2) para el radar, y `sources_val[9,10]`
> (args 17–18) para las fuentes de modulación. **Son el mismo dato duplicado.**
> No es un bug, pero es una tentación de bug futuro si alguien cambia el orden.

> ⚠️ **`out1..out6` (args 9–14) pueden llegar NEGATIVOS desde v3.04.** En modo
> Petal Polarity = Bipolar el pétalo es una señal con signo (−1..+1). Los tres
> consumidores de `sources_val[1..6]` están protegidos:
> - `grid_nav.lua` — usa `math.abs()` en sus dos usos
> - `ui.lua` — `draw_scope` recorta a −1..+1 en bipolar y dibuja la línea de cero
>   en el centro de la caja (v3.05). **Hasta v3.05 recortaba a 0..1, y eso no
>   era estar protegido**: era justo el bug de que el pétalo bipolar se dibujara
>   siempre pegado a su mínimo, con media onda invisible y −0.4 dando la misma
>   pantalla que 0.
> - `quantussy.lua` — normaliza con `math.abs()` en su única lectura (los
>   hexágonos se dimensionan por magnitud; un tamaño negativo no existe)
>
> `sources_val[7]` y `[8]` (envolventes, args 15–16) **no** son pétalos: no les
> afecta el modo bipolar. Por eso el aviso de nivel de `ui.lua` sigue usando 0.95.

**Latencia total del enlace:** 1 bloque de SC (1.33 ms) + 1/30 s del reloj (33 ms)
+ OSC. **La telemetría visual va ~35 ms por detrás del audio.** Irrelevante para lo
que hace, pero explica por qué los visualizadores "se retrasan" un poco.

---

## 10. El grid: mapa de 16×8


Cada botón del grid tiene un **tipo** y un **id**. El mapa está en
`GridNav.init_map(G)` y es puramente declarativo:

```lua
for x=1,4  do map(x, 1,  'snap', x) end      -- 4 snapshots
for x=13,16 do map(x, 1, 'seq', x-12) end    -- 4 secuenciadores
map(1,2,'edit',1); map(2,2,'edit',1); map(3,2,'edit',1)   -- editar L
map(14,2,'edit',2); ...                                    -- editar R
```

### 10.1 Tipos de botón

| Tipo | Función |
|---|---|
| `snap` | Grabar/cargar/limpiar snapshot (toque corto = ciclo, toque largo = limpiar) |
| `seq` | 4 secuenciadores (grabación con press, playback con doble toque) |
| `edit` | Entrar al menú de edición del canal (L o R) |
| `rec` | Grabar cinta |
| `flip` | Invertir dirección |
| `skip` | Stutter |
| `fader` | 7 faders de velocidad (0.002 → 3.0) |
| `petal` / `env` / `coco_out` | Seleccionar fuente de modulación |
| `jack` / `p_jack` | Conectar fuente a destino (jack = general, p_jack = pétalos) |

### 10.2 El brillo codifica información

El nivel de cada LED (0–15) es una **codificación de estado**, no decoración:

- **Fuente seleccionada**: 15 (máximo)
- **Jack conectado**: 12
- **Fuente "viva"** (con energía): 4–7, escalado por su valor
- **Secuencer grabando**: pulsa 5–15 con seno
- **Secuencer reproduciendo**: 12 fijo
- **Botón pulsado (latch)**: 15 fijo hasta soltar

> **Regla de oro:** el grid de ncoco es **más denso en información** que un grid
> secuenciador clásico. No es decorativo: cada LED te dice el estado real de la
> matriz. Cuando no entiendes qué hace un cable, mira el brillo del jack destino.

---

## 11. La interfaz: pétalos, radar, scope


### 11.1 Los hexágonos (`quantussy.lua`)

Cada pétalo se dibuja como un hexágono de 6 lados, con un "trail" de 4 posiciones
pasadas que crea un efecto de movimiento:

- **Modo LFO** → rectángulo sólido que gira (triángulo visual)
- **Modo Audio** → 12 puntos dispersos que "nubean" (electron cloud)
- **Chaos** → añade vibración aleatoria a la posición + rotación

```lua
local val = math.abs(G.sources_val[i] or 0);   -- [v3.04] bipolar puede llegar negativo
local size = util.linlin(0, 1, 1, 9, val);
local bright = math.floor(util.linlin(0, 1, 4, 15, val));
```

El brillo del hexágono es directamente el valor del pétalo. **Los 6 hexágonos
forman la parte más bonita de la interfaz** y son la referencia visual principal
para entender la modulación.

> El `math.abs` de la primera línea es lo que permite que el mismo dibujo funcione en
> Abs y en Bipolar: en bipolar el pétalo oscila entre −0.5 y +0.5, y sin normalizar
> `size` saldría negativo y el hexágono desaparecería de la pantalla.

### 11.2 Radar de cinta

Dos barras horizontales muestran la **posición de lectura** de cada cinta, con un
trail de las últimas 10 posiciones. Cuando la cinta da vueltas, ves la estela.

### 11.3 Scope

- `draw_scope` — osciloscopio simple, 128 muestras de historial
- `draw_dest_inspector` — muestra la **suma modulada** de un destino específico,
  visualizando qué fuentes lo están moviendo

---

## 12. Secuenciadores


4 secuenciadores, cada uno graba eventos del grid y los reproduce.

**Estados:** 0 = vacío · 1 = grabando · 2 = reproduciendo · 3 = parado (listo) ·
4 = grabando en loop

- **Grabar**: mantén pulsado. Los eventos (con su timestamp `dt`) se guardan.
- **Doble toque**: alterna entre estado 2 (una pasada) y 4 (loop continuo).
- Límite de 10000 eventos por secuenciador.

**Comportamiento de simulación:** cuando un secuenciador reproduce un evento, llama
a `GridNav.key(..., simulated=true)`. Eso **omite el LED** para no gastar tráfico
USB, y salta el grabador para no auto-grabarse.

**Orden de carga de un PSET** (el "total recall"):
1. Restaura patch, gains, longitudes, snapshots
2. `clock.sleep(0.1)`
3. Aplica el snapshot activo
4. `clock.sleep(0.1)`
5. Reinicia los secuenciadores que estaban sonando

Los sleeps escalonados evitan que matron se atasque al cargar todo de golpe.

---

## 13. Snapshots y PSET


**Snapshot** (4, en memoria, se pierden al apagar): patch + pétalos + transporte.
Se guardan con toque corto, se limpian con toque largo (>1.6 s).

**PSET** (en disco, sobreviven): todo lo anterior + las **cintas de audio** como
WAV + los secuenciadores.

**Total recall** al cargar un PSET:
- Escribe 2 WAV (uno por canal) en `_path.audio/ncoco/`
- Guarda un `.lua` serializado con `tab.save` en `_path.data/ncoco/`


---

## 14. Referencia rápida de controles


**K2/K3 dependen de la pantalla activa.** Hasta v3.02 K2 cambiaba los modos de bits
y K2/K3 no distinguían canal; hoy cada uno hace una cosa por contexto:

| Control | Pantalla | Acción |
|---|---|---|
| **E1** | main | Volumen master |
| **E2** | main | Nivel de monitor |
| **E3** | main | Chaos global |
| **K1** | main | Link estéreo L↔R |
| **K2** | main | **REC COCO 1** (toggle `recL`) |
| **K3** | main | **REC COCO 2** (toggle `recR`) |
| **E1/E2/E3** | edit L/R | Filtro / Velocidad / Feedback |
| **K3** | edit L (o link) | Cicla los **4 modos de bits** de L (y R si hay link) |
| **K3** | edit R | Cicla los modos de bits de R |
| **K2** | popup de fuente (pétalo) | Cambiar **Range** del pétalo |
| **K3** | popup de fuente (pétalo) | Cambiar **Shape** del pétalo |
| **K2/K3** | popup destino SKIP (6 / 13) | Cambiar modo skip (jump ↔ repeat) |
| **E1** | inspector, destino SKIP | Chaos del stutter |
| **E2** | inspector, destino SKIP | Rate del stutter |
| **E3** | inspector de destino | Ganancia de la modulación de ese destino (`dest_gains`) |
| **E3** | fuente + destino conectados | Mueve la conexión de la matriz (`patch[s][d]`) |

Tres reglas que evitan sorpresas:

- **K2/K3 no disparan grabación dentro de un popup.** Si hay un popup de fuente o
  de destino abierto, son la función de esa pantalla, no REC. Es el mismo criterio
  que usa el dibujo.
- **Los modos de bits se ciclan con K3 en la pantalla de edición**, no en la main.
  Hay cuatro: 8bit → 12bit → SBC → u-law.
- **E3 hace dos cosas distintas** según el contexto: ganancia del destino en el
  inspector, o intensidad de la conexión cuando ya hay fuente y destino elegidos.

**Faders del 16n** (si está conectado):
- Faders 1–6: frecuencia de los 6 pétalos
- Faders 7–8: offset de velocidad L/R
- Faders 9–10: preamp L/R
- Faders 11–12: feedback L/R
- Faders 13–14: volumen L/R
- Faders 15–16: filtro L/R

---

## 15. Glosario para el ingeniero de sonido


| Término | Significado en ncoco |
|---|---|
| **COCO** | cada cinta / canal del looper (de "cocoquantus") |
| **Pétalo** | cada LFO de modulación (6 en total) |
| **Jack** | un punto de conexión de la matriz |
| **Modulación** | una fuente controlando un destino, con fuerza -1..+1 |
| **Realimentación** | el feedback del looper: lo que sale vuelve a entrar |
| **8bit / 12bit / SBC / u-law** | los cuatro modos de degradación de audio |
| **Flip** | invertir la dirección de reproducción |
| **Skip / Stutter** | salto de posición / repetición rápida |
| **DJ Filter** | filtro de barrido lowpass/highpass en la salida |
| **Bleed** | ruido de clock que se filtra a la salida, con enrutado pre/post |
| **Deriva / Drift** | wow and flutter de la cinta |
| **Chaos** | cuanto se desvía el LFO de su trayectoria |

---

## 16. Deuda técnica conocida

*(Actualizado para v3.03. Los puntos marcados RESUELTOS ya no aplican: no los
"arregles" de nuevo — fueron análisis equivocados o bugs ya corregidos.)*

| Severidad | Asunto | Estado |
|---|---|---|
| ~~Alta~~ | ~~Índice del `Select` en los modos de bits — el u-law probablemente no se activa~~ | **RESUELTO.** Ya no aplica: el motor usa un entero `modeL`/`modeR` (0–3) como índice directo del `Select`, sin flags. El §6.4 de este documento estaba **desactualizado** al respecto. Ver [`BIT_MODES_FINDINGS.md`](./BIT_MODES_FINDINGS.md) §1 y §3. |
| ~~Alta~~ | ~~`add_group("COCO "..num, 18)` declaraba 18 con 17 params~~ | **RESUELTO** `1cb521e` → 17. El nombre de grupo NO cuenta. |
| ~~Media~~ | ~~`storage.lua`: `for src=1, 10` con 12 fuentes~~ | **RESUELTO** `1cb521e` → 12. COCO 11/12 ya se restauran. |
| ~~Media~~ | ~~`16n.lua`: byte `0x1f` pedido, `0x0f` comprobado~~ | **FALSO POSITIVO.** `0x0f` es correcto. Ver §7.2 de la guía. |
| **Baja** | `normalize(msg.val, is_bipolar_param(p_name))` — el 2º argumento no se usa dentro de `normalize` (`lib/16n.lua:29`). La función devuelve siempre 0..1, así que el ajuste bipolar/a polar **no tiene efecto**. Verificado: el cuerpo de la función nunca lee `bipolar`. | Pendiente |
| **Baja** | `math.randomseed(os.time())` (`ncoco.lua:439`) es inútil para lo que dice su comentario: las semillas aleatorias de los pétalos (488–491) las sobrescribe `params:default()` en la línea 496. Solo afecta al jitter visual de `quantussy.lua`, que no es lo que el comentario promete. | Pendiente |
| ~~Baja~~ | ~~`GridNav.is_dirty` se escribe en 5 sitios pero nunca se lee~~ | **RESUELTO** `ea40a9a` (eliminado a propósito) |
| **Baja** | `FADER_BG` en `lib/globals.lua:24` no se usa en ningún sitio. Medido sobre las 4 constantes del módulo: `SPEED_TABLE` 2 usos, `TRAIL_SIZE` 4, `SCOPE_LEN` 18, `FADER_BG` **0**. (La versión antigua de esta fila citaba un `MAX_BRIGHT` que no existe en el código.) | Pendiente |
| ~~Info~~ | ~~`Storage.save` serializa `double_click_timer` (una corrutina)~~ | **FALSO POSITIVO.** `tab.save` la salta sin fallar. Nada roto. |
| **Info** | Secuenciador: grabación seguida de reproducción vacía, esporádica | **BUG REAL ENCONTRADO** `f1b8450`. Ver nota abajo. |

---

### Inspector de destinos: nota obsoleta retirada

Este documento decía que `tools/verify_p14_inspector.lua` daba **12 correctos /
4 fallidos** (1 píxel de más en el umbral y 4 segmentos de más en el trazo, en los
destinos 5, 6 y 9), y lo merchantaba como deuda preexistente.

**Medido hoy: 17 correctos, 0 fallidos.** La nota estaba desactualizada, así que
ya no procede tratarlo como problema abierto.

Lo que sí se puede afirmar sin especular: el inspector solo **dibuja** esas
formas de onda a partir de los valores de la matriz. Un fallo ahí no puede alterar
ni el audio ni los datos; como mucho, muestra mal un valor que ya era correcto.

### Nota sobre el secuenciador (v3.01)

Se encontró un **bug real de referencias**, no una hipótesis:

`run_sequencer()` captura `local s = G.sequencers[id]` **una sola vez** al
arrancar. `Storage.load` hacía `G.sequencers = data.sequencers`, es decir
**reemplazaba la tabla**. A partir de ahí:

- `GridNav.key` grababa en la tabla **nueva**;
- la corrutina de reproducción leía la tabla **vieja**.

Resultado: grabar parece funcionar y la reproducción sale **vacía** o con datos
rancios. Corregido mutando campo a campo (`f1b8450`), de modo que toda
referencia viva sigue apuntando a la misma tabla.

`[NO DEMOSTRADO]` **No está probado que este sea el fallo esporádico original.**
Encaja con "grabo y suena vacío", pero se desconoce cuándo ocurre exactamente.
Se deja anotado como candidato, no como causa cerrada.

---

## 17. Congelado del grid (v3.01) — REVISION HONESTA

**Síntoma:** la rejilla se queda fija con el brillo del último valor recibido
(al máximo), los LFOs no se mueven, pero **sigue respondiendo a las
pulsaciones**. Ocurre de repente, a veces sin tocar nada.

### La repro en directo (2026-02) — lo que cambió el diagnóstico

El grid volvió a congelarse **en plena sesión**. Datos duros de ese fallo:

- **Maiden no imprimió NADA**: ni `OSC STALLED`, ni `GRID HEARTBEAT`, ni
  `g.device = nil`, ni `GRID_REDRAW_ERROR`.
- Cargar un PSET **no** lo recuperó; hubo que **reiniciar ncoco**.

Eso **descarta** las tres causas que Lua puede ver:

- el latido solo calla si el redraw de Lua **sigue latiendo** → no es el metro;
- sin aviso de `g.device` → no es el vport;
- sin error de Lua → no es el `pcall`.

Y **descarta la teoría del caché diferencial**: `dev_monome_grid_set_led` marca
`dirty` **sin comparar el valor** (ver punto 3 abajo), así que el
`reset_cache()` cada ~5 s ya forzaría un reenvío completo. Si fuera
desincronización de caché, **se auto-curaría**.

**Conclusión honesta (sin especular):** el corte está **por debajo de Lua**
(capa serial/USB de monome, o el binding dispositivo↔vport). No hay invariante
de Lua que lo vea — por eso los detectores callaron. Por eso, además de
detectar, ahora se **recupera** (abajo).

### Lo que SÍ es verificable (leído del código oficial de norns)

Del código C de monome (norns `matron/src/device/device_monome.cc`,
`lua/core/grid.lua`, `lua/core/vport.lua`):

1. **`grid.connect()` devuelve un "vport", no el dispositivo.** Sus métodos
   `led`/`all`/`refresh` se envuelven así:
   ```lua
   if self.device then self.device[method](self.device, ...) end
   ```
   **Si `g.device` es `nil`, esas llamadas son no-ops SILENCIOSOS**: no dan
   error. Este es un candidato tan válido como el OSC, y hasta ahora no se
   vigilaba. Un `g.device` nil congela los LEDs exactamente igual.

2. **`g:refresh()` solo envía los quads marcados "dirty"** (`dev_monome_refresh`
   recorre `md->dirty[]`). Llamarlo de más no gasta ancho de banda.

3. **`g:led()` marca el quad dirty SIEMPRE, sin comparar el valor.**
   `dev_monome_grid_set_led` hace `md->data[q][...] = val; md->dirty[q] = true;`
   sin ningún `if (data != val)`. Y en `dev_monome_refresh` la flag se limpia
   **después** de escribir, **sin comprobar el error de escritura**. Consecuencia
   verificable: un fallo de escritura **transitorio se auto-recupera** (la
   siguiente pasada re-marca dirty). Un congelado que **no** se recupera solo,
   por tanto, **no es de caché**.

### Lo que sí se corrigió (verificado)

1. **`refresh()` ahora se llama siempre**, no solo `if changed`. Antes, un error
   a mitad del bucle podía dejar quads marcados dirty sin que ninguna pasada
   posterior los reenviara (porque el cache Lua ya creía haberlos pintado).
   Esto es un fallo real de desincronización, independiente del OSC.
2. **`snap_timers` expira por tiempo.** Un botón de snapshot se quedaba en 15
   para siempre si moría su corrutina; `reset_cache` no lo limpiaba.
3. **`ui.lua:89`** leía `G.sources_val[7]` sin el `or 0` que usa el resto.
4. **El caso "el OSC nunca arrancó" (`last_osc_time == 0`)** antes era invisible:
   el guardia exigía `> 0`. Ahora se registra (`OSC NEVER STARTED`).
5. **`grid.add` engancha el vport del dispositivo** (`dev.port`), no el 1 a
   ciegas. Antes, si el aparato reenganchaba en otro vport, el 1 quedaba sin
   `.device` y todos los LEDs eran no-ops silenciosos (bug latente).
6. **Recuperación en caliente (`recover_grid`)** — ver abajo.

### Recuperación en caliente: `recover_grid`

Se rehace **en vivo**, sin re-seleccionar el script, lo que un reinicio de norns
le hace a la rejilla (verificado en `lua/core/script.lua`: `Script.clear()` llama
a `grid.cleanup()` —que por dispositivo hace `dev:all(0); dev:refresh()`— y a
`metro.free_all()`):

1. **Reengancha el vport con dispositivo.** `GridNav.find_device_port()` escanea
   los 4 vports (`grid.lua`) y devuelve el que tiene `.device`.
2. **Fuerza reenvío completo** con `GridNav.reset_cache()`, y **ya sin apagar**
   (esto cambió en v3.03, ver §17.1). Poner la caché a `-1` fuerza a que las 128
   celdas se reescriban; y como `g:led()` marca dirty **sin comparar el valor**,
   los 4 quads quedan sucios y el `refresh()` que cierra `redraw()` los manda
   todos. Mismo reenvío garantizado que daba `g:all(0)`, sin el frame en negro.
3. **Reinicia el metro** (`grid_metro:stop(); grid_metro:start()`). `Metro:start()`
   reusa el mismo id (solo `metro.init()` consume de `Metro.available`): **sin
   fuga de ids**. Se hace fuera del propio callback, en el sistema `clock`.

**Cuándo se dispara SOLA** (v3.03: con diagnóstico y **dos avisos**, ya no a la
primera — ver §17.1):

- `sin redraw > 3 s` **dos ciclos seguidos con el latido puntual** → el metro dejó
  de disparar de verdad.
- `g.device = nil` **dos ciclos seguidos** → los `g:led`/`g:refresh` son no-ops
  silenciosos.

**Cuándo a MANO.** Para el congelado que **no se ve desde Lua** (por debajo,
capa serial/USB), no hay señal que disparar, así que se expone a maiden:

```lua
>> recover_grid()
```

**Lo que NO se toca.** El caso "el `/update` de SC se para" solo lo rearmaría
`engine.load()`, que re-ejecuta `init` y **re-asigna los buffers de 60 s** →
cortaría el audio en directo. Ese caso se **registra**, no se "arregla" a ciegas.

**Lección:** la función de un diagnóstico no es adivinar la causa, es hacer que
el fallo sea observable — y, cuando el coste de equivocarse es nulo, **actuar**.
### 17.1 La falsa alarma que destapó el problema (v3.03)

**Síntoma, en maiden, con el instrumento funcionando:**

```lua
GRID HEARTBEAT: sin redraw desde hace 4.7 seconds -> recuperando
GRID RECOVERY (sin redraw)
   ...unos segundos después...
GRID HEARTBEAT: sin redraw desde hace 3.2 seconds -> recuperando
GRID RECOVERY (sin redraw)
```

La rejilla **parpadeó** (un frame en negro) pero siguió respondiendo: no estaba
congelada. El watchdog que en v3.01 se describía como «sin falsos positivos
posibles» era justo el que mentía.

**Causa — VERIFICADA, no supuesta.** En `matron/src/events.cc`:

- hay **un solo `event_loop()`**, que drena **una sola cola FIFO**;
- `w_handle_metro()` (los ticks de `metro`) y `w_handle_clock_resume()` (los
  despertares de `clock`) llaman **al mismo estado Lua** (`lvm`).

O sea: **`metro` y `clock` están serializados.** Si cualquier manejador de Lua se
bloquea N segundos, **se paran los dos a la vez**. Al reanudarse, el latido mide
con `util.time()` (reloj de pared) frente a un `last_redraw` de **antes** del
bloqueo → ve N segundos y concluye «congelado», cuando en realidad lo que se
detuvo fue el bucle entero, y la rejilla se iba a recuperar sola en el siguiente
tick de metro.

`[NO DEMOSTRADO]` **Qué manejador bloqueó esos 4.7 s no se ha identificado.** Se
sabe que no fue la rejilla; el culpable está en la cola de eventos. No se especula.

**El parpadeo era nuestro, no del hardware.** `recover_grid()` empezaba con
`g:all(0); g:refresh()`: mandaba los 128 LEDs a 0 y el siguiente tick de metro
(67 ms) los repintaba. Ese frame en negro **es** el destello. Y `all(0)` era
redundante: `dev_monome_grid_set_led()` marca dirty **sin comparar el valor**, así
que `reset_cache()` ya fuerza el reenvío completo de los 4 quads (punto 3 de §17).
Prueba empírica: `reset_cache()` **solo** ya se dispara cada 75 frames (5 s) desde
v2.04 y nunca ha parpadeado.

**Qué hace v3.03:**

1. El latido mide **su propio atraso** (`late = (now - t0) - 2.0`). El latido vive
   en `clock` y **no depende del metro**, así que si llega tarde es **prueba**,
   no conjetura, de que se bloqueó el bucle entero. Con `late >= 1 s`: informa y
   **no toca la rejilla**.
2. Con el latido puntual, la decisión exige **dos avisos separados por un ciclo
   entero**. Una parada transitoria nunca apaga nada; una congelación real se
   recupera 2 s después — y `>> recover_grid()` sigue ahí para hacerlo al momento.
3. El mensaje lleva **la prueba, no la sospecha**: `metro +0 ticks` = el metro no
   disparó; `metro +31 ticks` = el metro corría pero el `redraw` no llegaba a
   terminar.

**Cómo leer un aviso de maiden a partir de ahora:**

| Mensaje | Qué pasó | ¿Se toca la rejilla? |
|---|---|---|
| `...PERO el latido llegó Ns tarde => el bucle de Lua se bloqueó` | se paró el bucle entero | **No** — se cura solo |
| `...latido puntual, metro +0 ticks -> aviso 1/2` | el metro se murió | Todavía no |
| `...tras 2 avisos con el latido puntual -> recuperando` | congelación real | Sí |
| `g.device = nil -> aviso 1/2` | los LEDs no llegan | Todavía no |
| `g.device = nil tras 2 avisos -> recuperando` | persiste | Sí |

**Lección (ampliada):** la v3.01 decía «cuando el coste de equivocarse es nulo,
actuar». Eso era **falso**: apagar la rejilla que funcionaba es un coste real (un
flash en pleno concierto) y se estaba pagando. La regla correcta es: **antes de
actuar, comprobar que el coste de equivocarse es de verdad nulo**. Y cuando hay
ambigüedad entre «el otro falló» y «los dos nos quedamos sin CPU», la prueba es
medir **el atraso del propio watchdog** — es el único dato que separa los dos
casos. La lógica quedó aislada en `GridNav.heartbeat_step()` (función pura) y
cubierta por `tools/verify_p28_heartbeat.lua`, con control negativo que
reproduce la regla de v3.02 y confirma que **sí** disparaba la recuperación
equivocada.



### Ojo: esto no arregla el fallo del secuenciador

Son dos cosas distintas.

---

---

---
