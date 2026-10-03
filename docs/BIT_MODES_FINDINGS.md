# BIT_MODES_FINDINGS.md

**Proposito**: documentar los 4 modos de cuantizacion de ncoco, de donde salio
cada numero, y que esta VERIFICADO frente a lo que es SUPUESTICION.

> Regla de este documento: si una afirmacion no lleva etiqueta `[VERIFICADO]`,
> no la trates como cierta. Todo lo marcado `[SUPUESTICION]` quedo pendiente de
> comprobar con hardware.

---

## 1. Como se selecciona el modo

`lib/param_set.lua:136`

```lua
params:add_option("bits"..s, "Bits "..num, {"8bit", "12bit", "SBC", "u-law"}, 1)
params:set_action("bits"..s, function(x) SC.set_mode(i, x-1) end)
```

Cadena completa:

```
params (indice 1..4)
  -> SC.set_mode(i, x-1)                    lib/sc_utils.lua:56
  -> engine.modeL / engine.modeR            "i" (entero)
  -> synth_core.set(\modeL, n)              Engine_Ncoco.sc:570
  -> Select.kr(modeL, [...])                index DIRECTO de las tablas
```

`[VERIFICADO]` El menu va 1..4 y el engine va 0..3. La conversion `x-1` esta en
un solo sitio. El `Select` usa el valor crudo como indice, sin flags ni
aritmetica: **es imposible que el menu y el audio se desincronicen.** Ese fue
justo el bug que existia antes de la Fase 2.

---

## 2. Tabla de los 4 modos

Valores extraidos de `lib/Engine_Ncoco.sc` en las lineas indicadas.

| idx | Etiqueta | baseSR (Hz) | Filtro fijo (Hz) | Ruido | Bleed | Jitter SR | Cuantizacion | Linea |
|-----|----------|-------------|------------------|-------|-------|-----------|--------------|-------|
| 0 | `8bit`   | 16000       | 7000             | 0.008 | 0.0025 | 0.020     | `Latch(round(0.5**8))`  | 386 |
| 1 | `12bit`  | 31250       | 12800            | 0.004 | 0.0010 | 0.004     | `Latch(round(0.5**12))` | 387 |
| 2 | `SBC`    | 48000       | 16000            | 0.002 | 0.0030 | 0.010     | 2 bandas, 6.8 kHz      | 388 |
| 3 | `u-law`  | 22000       | 11111            | 0.006 | 0.0011 | 0.011     | companding log 8-bit   | 389 |

Tablas fuente (identicas para L y R, con `baseSR_R * 1.002`):

```supercollider
// Engine_Ncoco.sc:216
noiseL = PinkNoise.ar(Select.kr(modeL, [0.008, 0.004, 0.002, 0.006]));
// Engine_Ncoco.sc:219
baseSR_L = Select.kr(modeL, [16000, 31250, 48000, 22000]);
// Engine_Ncoco.sc:221
fixedFiltFreqL = Select.kr(modeL, [7000, 12800, 16000, 11111]);
// Engine_Ncoco.sc:305
bleedL = ... * Select.kr(modeL, [0.0025, 0.001, 0.003, 0.0011]);
// Engine_Ncoco.sc:369
srTrigL = ... * (1 + WhiteNoise.ar(Select.kr(modeL, [0.02, 0.004, 0.01, 0.011])));
```

### 2.1 Modo 0 `8bit` — el unico con valores de referencia

`[VERIFICADO]` Estos numeros vienen del commit de donacion `2f85646`, donde el
8-bit era el unico modo real y por tanto todo el resto se elegia por defecto.
Los tres valores comparables coinciden EXACTAMENTE:

| Parametro | `2f85646` (original) | Actual idx 0 | |
|-----------|---------------------|--------------|---|
| baseSR 8-bit | `is8L * 16000` | `16000` | coincide |
| Ruido 8-bit  | `is8L * 0.008`  | `0.008`  | coincide |
| Filtro fijo   | `is8L * 7000`  | `7000`   | coincide |

`2f85646:171,174,176` (logica con flags) frente a `Engine_Ncoco.sc:216,219,221`
(logica con Select). Escribi un script que comparara ambas formas y los tres
valores dan el mismo resultado.

El resto de modos **no** viene del original: en `2f85646` no existian. Salen de
commits posteriores (ADPCM v2.05, NICAM/SBC v2.13/v2.20, u-law v2.08) y de ahi
se tomaron tal cual. `[VERIFICADO]` que se copiaron sin transformarlos.
---

## 3. El bug estructural que existia antes de la Fase 2

`[VERIFICADO]` reconstruido del historial.

En el codigo previo, el motor no recibia un indice de modo sino tres flags
independientes:

```supercollider
// antes de la Fase 2 (reconstruido)
writeL = Select.ar(is8L + is12L, [ ... ])   // suma de flags como indice
```

`is8L + is12L` da 0, 1, 2 segun cuantos flags esten activos. El problema: **el
indice del `Select` y el nombre del modo no tenian relacion garantizada.** Un
tercer flag (ADPCM) podia empujar la suma a un indice que no correspondia al
modo que el usuario habia elegido en el menu.

`[VERIFICADO]` La Fase 2 lo elimino: ahora hay un unico entero `modeL` que es
a la vez lo que decide el menu y lo que indexa las tablas.

---

## 4. La u en el display: por que NO es la letra griega

`[VERIFICADO]` por el usuario, en hardware, y por el historial de commits.

La fuente integrada de norns (6x13) cubre **solo ASCII 32..126**. No tiene glifo
para U+03BC (mu griega). Sus bytes UTF-8 son `0xCE 0xBC`, que no corresponden a
ningun caracter de la fuente y se renderizan como nada:

```
"μ-law"  ->  se ve "-law"       roto
"u-law"  ->  se ve "u-law"      correcto
```

Esto no es una discusion academica: el commit `b7b7240` (v2.05, del autor
original) cambio el display a `"u-law"` **a proposito** por este motivo:

```diff
-local BIT_NAMES = {[1]="8bit", [2]="μ-law", [3]="16bit"}
+local BIT_NAMES = {[1]="8bit", [2]="u-law", [3]="ADPCM"}
```

La Fase 2 reintrodujo la letra griega y **deshizo sin querer una correccion
previa que ya existia en el historial**. Fue un fallo mio de no haber leido el
`git log -S` de la linea antes de tocarla.

**Corregido**: `"μ-law"` -> `"u-law"` en `lib/ui.lua` (pantalla) y en
`lib/param_set.lua` (menu de params).

### 4.1 Por que renombrar la etiqueta NO rompe los presets

`[VERIFICADO]` `params` guarda el **indice** de la opcion, nunca el string:

```lua
local v = params:get("bitsL")   -- devuelve 1..4 (numero)
params:set("bitsL", (v%4)+1)    -- opera sobre numeros
```

Ningun sitio del proyecto compara contra el texto `"u-law"`. Verificado con grep
sobre todos los `.lua`: las unicas apariciones de la cadena estan en la
declaracion de la opcion y en su etiqueta de pantalla. Renombrar la etiqueta no
puede invalidar un preset guardado.

---

## 5. Estado de verificacion

| Afirmacion | Estado |
|------------|--------|
| Los 4 modos existen y son alcanzables desde el menu | `[VERIFICADO]` leido del codigo |
| `modeL` indexa las tablas directamente (sin desync) | `[VERIFICADO]` leido del codigo |
| Los valores del modo 0 coinciden con `2f85646` | `[VERIFICADO]` comparado con script |
| Los valores de modos 1-3 vienen de commits posteriores | `[VERIFICADO]` traceados en el historial |
| "u-law" renderiza y "μ-law" no | `[VERIFICADO]` por el usuario en hardware |
| Renombrar la etiqueta no afecta a presets | `[VERIFICADO]` grep exhaustivo |
| **Los 4 modos suenan bien y suenan DISTINTOS** | **`[PENDIENTE]`** el usuario los probara |
| **SBC es subjetivamente el mejor de los 4** | **`[SUPUESTICION]`** no medido |
| **El ruido 0.002 de SBC es "correcto"** | **`[SUPUESTICION]`** heredado del codigo viejo |

---

## 6. Lo que NO se toco

- `lib/16n.lua` — **fuera de limites.** Es el unico punto donde un cambio
  razonable puede fallar en silencio. Ningun cambio sin hardware verificado.
- `lib/Engine_Ncoco.sc` — las tablas de la Fase 2 son reorganizacion, no afinacion.
- Los 4 modos — ninguno se ajusto, solo se hizo alcanzable el 4o.