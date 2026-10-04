# ncoco
A cocoquantus inspired instrument for Norns + grid

**Versión: 3.04** — desde v3.01 todos los archivos comparten el mismo número de
versión. `NCOCO_VERSION` en `ncoco.lua` es la fuente autoritativa.

## Documentación

- `docs/NCOCO_ANATOMY.md` — anatomía del instrumento y deuda técnica conocida.
- `docs/NORNS_DEVELOPMENT_GUIDE.md` — trampas de norns/SC y cómo evitarlas.
- `docs/BIT_MODES_FINDINGS.md` — los 4 modos de cuantización, con su nivel de verificación.

## Tests

Se ejecutan con `lua` pelado, sin norns: cada uno monta su propio stub.

```sh
# Documento / estructura
lua tools/verify_v302_unified.lua     # versiones unificadas + cleanup() segura
lua tools/verify_p22_grupo_coco.lua   # el grupo COCO declara 17 params
lua tools/verify_p8_matrix.lua        # la matriz hace 288 llamadas OSC

# Grid y congelado
lua tools/verify_p23_grid_freeze.lua  # detectores del congelado del grid
lua tools/verify_p28_heartbeat.lua    # el latido diagnostica y ya no parpadea
lua tools/verify_p26_snap_taps.lua    # toques seguidos no borran snapshots

# Controles
lua tools/verify_p27_keys.lua         # K2/K3 por pantalla (rec COCO 1 / 2)
lua tools/verify_p13_order.lua        # orden de los destinos
lua tools/verify_p13_speed.lua        # rango de velocidad
lua tools/verify_p29_petals.lua       # bipolar + T&H: defaults, presupuesto y dibujo

# Interfaz
lua tools/verify_p14_inspector.lua    # dibujo del inspector de destinos
lua tools/verify_p14_pixels.lua       # píxeles del inspector
lua tools/verify_p12_textfit.lua      # nada se pisa en pantalla
lua tools/verify_p12_umbral.lua       # dibujo de los umbrales
lua tools/verify_p12_scope.lua        # dibujo del scope

# Secuenciadores
lua tools/verify_p24_sequencer_load.lua # el load conserva referencias
```

`verify_p12_otros.lua` **no** se ejecuta suelto: necesita una referencia anterior
para comparar (`lua tools/verify_p12_otros.lua --old <ruta>`). Es una limitación
del propio test, no un fallo del proyecto. 
