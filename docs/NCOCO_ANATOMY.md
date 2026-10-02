---

## 1. Qué es, en términos de sonido


ncoco es un **looper asíncrono de dos cintas** (una por canal) con la señal de entrada
inyectada dentro del bucle. La diferencia con un looper de overdub clásico:

- **La entrada se suma a la lectura de la cinta mientras se graba**, no se "capa"
  encima. El bucle se auto-realimenta: lo que entra vuelve a salir mezclado con lo
  que ya había.
- Eso genera **saturación, acumulación de graves y degradación progresiva** de forma
  orgánica, en vez de un overdub lineal que solo crece.
- Los **3 modos de bits** (8bit / μ-law / SBC) son una capa de **coloración de
  digitalización** aplicada a la señal *dentro* del bucle: el grano y el ruido de
  cuantización se realimentan y se acumulan.

**Perfil sonoro esperado:** cálidas, con deriva de cinta, saturación gradual, y
texturas que se van degradando con el tiempo. Es un instrumento de textura, no de
precisión.

---

## 2. Estructura de archivos


```
ncoco/
├── ncoco.lua                  ← script principal (628 líneas)
├── lib/
│   ├── Engine_Ncoco.sc        ← motor DSP (630 líneas)
│   ├── globals.lua            ← estado global compartido
│   ├── param_set.lua          ← definición de todos los parámetros
│   ├── grid_nav.lua           ← mapeo del grid + secuenciadores
│   ├── ui.lua                 ← dibujo de pantalla
│   ├── quantussy.lua          ← dibujo de los "pétalos" (hexágonos)
│   ├── sc_utils.lua           ← puente Lua → engine
│   ├── storage.lua            ← PSET / total recall
│   └── 16n.lua                ← soporte del Faderfox 16n
└── docs/
    ├── NORNS_DEVELOPMENT_GUIDE.md
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
> `include('ncoco/lib/sc_utils')` (línea 26). Como `include` **tiene caché**, es la
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
- `.abs` al final → **salida siempre positiva** (0..1), nunca bipolar

**La forma (Tri / Castle):**
```supercollider
c1 = Latch.ar(p6, t1);              // S&H: congela p6 cuando t1 dispara
out1 = Select.ar(p1shape, [p1, c1]);
```
- `p1shape = 0` → triángulo suave
- `p1shape = 1` → sample & hold (escalones) → "Castle"

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


# Anatomía de ncoco

> Instrumento tipo *async looper* para **monome norns** + grid, inspirado en
> cocoquantus. Dos cintas de audio en loop, una matriz de modulación 12×24 y tres
> modos de degradación de bits (8bit / μ-law / SBC).
>
> Documento **de proyecto**. Las reglas de la plataforma están en
> [`NORNS_DEVELOPMENT_GUIDE.md`](./NORNS_DEVELOPMENT_GUIDE.md).
>
> Análisis del código: **2026-10-02**, sobre el commit `97f4ec2` (rama `main`).

---

## 6. Los 3 modos de bits


Este es el corazón del color sonoro. **Verificado leyendo el código.**

### 6.1 Cómo se selecciona

El parámetro `bitsL` / `bitsR` (menú: *"Bits 1"* / *"Bits 2"*) mapea a un número:

| Opción del menú | Valor enviado | Qué se activa |
|---|---|---|
| `8bit` | `bitDepth = 8` | cuantización de 8 bits |
| `μ-law` | `bitDepth = 12` | companding μ-law |
| `SBC` | `bitDepth = 14` | Sub-Band Coding |

Y en el motor:
```supercollider
is8L     = bitDepthL < 10;
is12L    = (bitDepthL >= 10) * (bitDepthL < 14);
isAdpcmL = bitDepthL >= 14;
```

### 6.2 Qué hace cada modo

#### 8bit — `Latch.ar(writeL.round(0.5 ** 8), srTrigL)`

- Cuantización a **8 bits** (256 niveles), retenida a la tasa del reloj de muestra.
- `0.5 ** 8` = paso de cuantización de 0.0039.
- `srTrigL` es un reloj derivado de la velocidad de reproducción → **el grano se
  mueve a velocidad de cinta**, como un sampler real.
- Añade `PinkNoise` al 0.008 de amplitud.
- **Color:** el "crunch" de 8 bits clásico. Gruesos, sucios, muy digital. El modo
  más agresivo de los tres.

#### μ-law — `Latch.ar(muLawL, srTrigL)`

- Companding μ-law (G.711): comprime el rango dinámico en una curva logarítmica
  antes de cuantizar.
- `baseSR = 31250 Hz`, filtro de realimentación a 12.8 kHz.
- `PinkNoise` al 0.004 (la mitad que en 8bit — el μ-law es más limpio por diseño).
- **Color:** más suave que 8bit, con menos "siseo" en los niveles bajos. Es el modo
  de voz/telefonía clásico. Más musical, menos sucio.

#### SBC — `dpcmReconL` (Sub-Band Coding, 2 bandas)

- **Divide la señal en dos bandas** con un crossover a 6.8 kHz:
  - **Banda baja: 10 bits** (paso `2^-9`)
  - **Banda alta: 5 bits** (paso `2^-4`)
- Recombina las dos bandas. Da **mucha resolución en el cuerpo** y poca en el brillo.
- **48 kHz nativo** — sin recorte de banda.
- `PinkNoise` al 0.002 (el más limpio).
- **Color:** detalle fino, brillante, "digital-frío". El más sutil de los tres.

### 6.3 Ruido y filtro por modo

| Modo | Ruido | Filtro feedback | Reloj base |
|---|---|---|---|
| 8bit | 0.008 | 7 kHz | 16 kHz |
| μ-law | 0.004 | 12.8 kHz | 31.25 kHz |
| SBC | 0.002 | 16 kHz | 48 kHz |

**Regla general:** cuanto más "digital" es el modo, más limpio. Es un degradado de
8bit → μ-law → SBC, de **saturación a limpieza**.

### 6.4 Detalle del SBC: sin `Latch`

```supercollider
writeL = Select.ar(is8L + (is12L * 2) + (isAdpcmL * 3), [
    Latch.ar(...),          // índice 0 — 8bit
    Latch.ar(muLawL, ...),  // índice 1 — μ-law
    Latch.ar(...),          // índice 2 — 12-bit lineal
    dpcmReconL              // índice 3 — SBC, feedforward puro, sin Latch
]);
```

El SBC **no retiene el valor**: recalcula la cuantización **en cada muestra** a
48 kHz. Por eso es "nativo" y sin grano. Los modos 8bit y μ-law sí usan `Latch`, que
congela el valor entre muestras — de ahí su grano más audible.

> ⚠️ **Punto de atención (verificado en código, requiere prueba de oído).**
> El índice se calcula `is8L + (is12L * 2) + (isAdpcmL * 3)`. Con `bitDepth = 12`
> obtenemos índice **2** (12-bit lineal). El índice **1** (μ-law) solo se alcanzaría
> con `bitDepth = 10` u `11`, que **el menú nunca envía**.
>
> **Lo que probablemente estás escuchando como "μ-law" es en realidad 12-bit lineal.**
> Esto hay que confirmar en el dispositivo. Si el modo "μ-law" te suena a 12-bit plano
> y no a companding de telefonía, el diagnóstico se confirma. La corrección sería
> reindexar el `Select` (p. ej. `is8L + is12L + isAdpcmL * 2`), pero eso **cambia el
> sonido** de ese modo y hay que hacerlo con criterio, no de un vistazo.


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
local size = util.linlin(0, 1, 1, 9, val);
local bright = math.floor(util.linlin(0, 1, 4, 15, val));
```

El brillo del hexágono es directamente el valor del pétalo. **Los 6 hexágonos
forman la parte más bonita de la interfaz** y son la referencia visual principal
para entender la modulación.

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


| Control | Acción |
|---|---|
| **E1** (main) | Volumen master |
| **E2** (main) | Nivel de monitor |
| **E3** (main) | Chaos global |
| **E1/E2/E3** (edit L/R) | Filtro / Velocidad / Feedback |
| **K1** (main) | Link estéreo L↔R |
| **K2** (main) | Cambiar bits (8bit/μ-law/SBC) |
| **K2/K3** (pétalo) | Cambiar Range / Shape |
| **E3** (dest) | Ganancia de entrada del destino |

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
| **8bit / μ-law / SBC** | los tres modos de degradación de audio |
| **Flip** | invertir la dirección de reproducción |
| **Skip / Stutter** | salto de posición / repetición rápida |
| **DJ Filter** | filtro de barrido lowpass/highpass en la salida |
| **Bleed** | ruido de clock que se filtra a la salida, con enrutado pre/post |
| **Deriva / Drift** | wow and flutter de la cinta |
| **Chaos** | cuanto se desvía el LFO de su trayectoria |

---

## 16. Deuda técnica conocida

*(Actualizado 2026-10-02. Los puntos marcados RESUELTOS ya no aplican: no los
"arregles" de nuevo — fueron análisis equivocados o bugs ya corregidos.)*

| Severidad | Asunto | Estado |
|---|---|---|
| **Alta** | Índice del `Select` en los modos de bits — el u-law probablemente no se activa (§6.4) | Pendiente |
| ~~Alta~~ | ~~`add_group("COCO "..num, 18)` declaraba 18 con 17 params~~ | **RESUELTO** `1cb521e` → 17. El nombre de grupo NO cuenta. |
| ~~Media~~ | ~~`storage.lua`: `for src=1, 10` con 12 fuentes~~ | **RESUELTO** `1cb521e` → 12. COCO 11/12 ya se restauran. |
| ~~Media~~ | ~~`16n.lua`: byte `0x1f` pedido, `0x0f` comprobado~~ | **FALSO POSITIVO.** `0x0f` es correcto. Ver §7.2 de la guía. |
| **Baja** | `normalize(msg.val, is_bipolar_param(p_name))` — el 2º argumento no se usa dentro de `normalize` | Pendiente |
| **Baja** | `math.randomseed()` y el bucle de semillas de pétalos se anulan con `params:default()` justo después | Pendiente |
| ~~Baja~~ | ~~`GridNav.is_dirty` se escribe en 5 sitios pero nunca se lee~~ | **RESUELTO** `ea40a9a` (eliminado a propósito) |
| **Baja** | `MAX_BRIGHT` / `FADER_BG` y otras constantes sin uso en `globals.lua` | Pendiente |
| ~~Info~~ | ~~`Storage.save` serializa `double_click_timer` (una corrutina)~~ | **FALSO POSITIVO.** `tab.save` la salta sin fallar. Nada roto. |
| **Info** | Secuenciador: grabación seguida de reproducción vacía, esporádica | **BUG REAL ENCONTRADO** `f1b8450`. Ver nota abajo. |

---

### Nota sobre #14 (inspector)

`tools/verify_p14_inspector.lua` da 12 correctos / 4 fallidos. Los 4 fallos son
**solo de dibujo de la forma de onda** (destinos 5, 6 y 9): 1 píxel de más en el
umbral y 4 segmentos de más en el trazo. **No afecta al sonido ni a los datos** —
es geometría del dibujo. Preexistente, no introducido en v3.00.

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
