# ncoco
A cocoquantus inspired instrument for Norns + grid

**Versión: 3.03** — desde v3.01 todos los archivos comparten el mismo número de
versión. `NCOCO_VERSION` en `ncoco.lua` es la fuente autoritativa.

## Documentación

- `docs/NCOCO_ANATOMY.md` — anatomía del instrumento y deuda técnica conocida.
- `docs/NORNS_DEVELOPMENT_GUIDE.md` — trampas de norns/SC y cómo evitarlas.
- `docs/BIT_MODES_FINDINGS.md` — los 4 modos de cuantización, con su nivel de verificación.

## Tests

```sh
lua tools/verify_v302_unified.lua     # versiones unificadas + cleanup() segura
lua tools/verify_p22_grupo_coco.lua   # el grupo COCO declara 17 params
lua tools/verify_p23_grid_freeze.lua  # detectores del congelado del grid
lua tools/verify_p24_sequencer_load.lua # el load conserva referencias
lua tools/verify_p26_snap_taps.lua    # toques seguidos no borran snapshots
lua tools/verify_p27_keys.lua         # K2/K3 por pantalla (rec COCO 1 / 2)
lua tools/verify_p28_heartbeat.lua    # el latido diagnostica y ya no parpadea
lua tools/verify_p12_textfit.lua      # nada se pisa en el inspector de destinos
lua tools/verify_p8_matrix.lua        # la matriz hace 288 llamadas OSC
``` 
