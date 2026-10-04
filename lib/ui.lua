-- lib/ui.lua v3.07
-- CHANGELOG v3.07 (LINEA DE CERO CONTINUA EN LOS DOS SCOPES + ETIQUETA T/H):
-- 1. La linea de cero del scope bipolar pasa de PUNTOS a una linea continua de
--    1 px, y se anade la MISMA linea al inspector de DESTINOS. Mismo nivel (4),
--    mismo tramo y mismo modo de trazo: la misma linea en las dos pantallas.
-- 2. POR QUE FALTABA EN DESTINOS: lo que se veia con nada cableado era la ONDA
--    plana en cero, no una referencia, y se deformaba en cuanto conectabas una
--    fuente. La discontinua del umbral de disparo se queda como estaba: es otra
--    cosa (marca el umbral de FLIP/SKIP/REC).
-- 3. screen.pixel es en realidad screen.rect(x, y, 1, 1) y norns pide enteros;
--    con la caja de 25 px de alto el centro caia en 32.5. Ahora el cero es entero
--    (math.floor) y la onda pivota sobre ese mismo valor. No se toca line_width:
--    matron ya lo fija a 1 px al arrancar.
-- 4. La etiqueta del inspector de petalos pasa de "S&H" a "T/H": el modo S&H ya
--    no existe y la salida retentiva es siempre Track & Hold.
-- v3.06: SOLO la etiqueta de version. El codigo NO se toco. El scope bipolar de
--   v3.05 ya recibia outN por el OSC /update, asi que no se veia nada distinto:
--   lo que se ve y lo que suena ya coinciden.
-- CHANGELOG v3.05 (EL SCOPE DE LOS PETALOS SE CENTRA EN BIPOLAR):
-- 1. draw_scope acepta un 8o argumento OPCIONAL (bipolar). Si no se le pasa,
--    lo deduce solo: fuentes 1..6 (los petalos) con el param global
--    petal_polarity en Bipolar. Asi no hay que tocar NINGUNA de las llamadas,
--    y el menu de patch (que dibuja la fuente que estas cableando) queda
--    coherente con el petalo que muestra.
-- 2. Con bipolar el cero pasa al CENTRO de la caja y la onda recorre -1..+1;
--    ademas se dibuja la linea de cero en puntos al nivel mas tenue. Es el
--    mismo criterio que ya usaba el inspector de destinos (cero centrado,
--    recorte -1..+1, linea al nivel 2 con fill() para no engordar el trazo),
--    para que las dos pantallas se lean igual.
-- 3. MOTIVO: el OSC /update manda los petalos CON SIGNO cuando el bipolar esta
--    activo, y esto recortaba a 0..1. Todo valor negativo se pintaba pegado al
--    borde inferior: media onda no existia y -0.4 daba EXACTAMENTE la misma
--    pantalla que 0. El petalo parecia clavado en su minimo justo cuando mas
--    se movia.
-- 4. SIN EFECTOS COLATERALES: con bipolar=false esta funcion emite
--    exactamente las mismas llamadas de dibujo que antes (zero_y=y+h,
--    half_h=h, lo=0 reproducen py = y + h - val*h), asi que los inspectores de
--    env, yellow y coco no cambian ni un pixel. Verificado en
--    tools/verify_p29_petals.lua comparando el inspector de env con las dos
--    polaridades.
-- CHANGELOG v3.01:
-- 1. FIX: draw_main leia G.sources_val[7] y [8] SIN el `or 0` que usa el resto
--    del archivo. Un nil tumbaba el redraw de pantalla entero.
-- 2. FIX: inspector de DESTINOS, destino SKIP (6/13). El codigo dibujaba
--    "K2/3: MODE" en la fila y=62, que en ese mismo destino ya esta ocupada por
--    "E1:CHS"/"E2:RATE": los textos se SUPERPONIAN. Arreglo final: se ELIMINA la
--    pista "K2/3: MODE" de este inspector (a y=55 seguia tocando el borde de la
--    caja, que acaba en y=50). La caja del scope SUBE 5 px (y=15 -> y=10).
--    Alturas medidas con la fuente real de norns (resources/norns.ttf, cairo
--    size 8.0 -> 5 px sobre la linea base), ver tools/verify_p12_textfit.lua:
--    titulo y=6 ocupa 1..6 | caja 10..50 | controles y=62 ocupan 57..62.
--    (El inspector de COCO conserva su "K2/3: MODE" en y=55: alli la caja acaba
--    en y=45 y no lo toca.)
-- 3. CLEAN: el ancho de la onda (antes el 119 a mano) se deriva de BOX_W-1.
-- FIX v3.00:
-- 1. B7: BIT_NAMES[4] "μ-law" -> "u-law". The norns builtin 6x13 font has NO glyph
--    for U+03BC (GREEK SMALL LETTER MU) — only ASCII 32..126. The UTF-8 bytes
--    (0xCE 0xBC) render as nothing, so the display showed "-law".
--    Commit b7b7240 (v2.05, by the original author) had deliberately used
--    "u-law" here for exactly this reason. Fase 2 reintroduced the mu and
--    unknowingly reverted that fix. Restored.
-- CHANGELOG v2.14:
-- 1. FIX: E4 bits text only visible in NICAM mode (bit_idx==3).
-- CHANGELOG v2.12:
-- 1. RENAME: BIT_NAMES[3] "ADPCM" -> "1bit CVSD".
-- CHANGELOG v2.02:
-- 1. RENAME: BIT_NAMES[2] "12bit" -> "u-law" (the display-safe spelling).

-- CHANGELOG v2.01:
-- 1. META: Version bump to 2.01 (project-wide alignment).
-- CHANGELOG v9004:
-- 1. INSPECTOR: Added E3 Slew visualization to Coco Inspector.

local Q = include('ncoco/lib/quantussy')
local UI = {}

local SRC_NAMES = {
  "PETAL 1","PETAL 2","PETAL 3","PETAL 4","PETAL 5","PETAL 6",
  "ENV 1","ENV 2","YEL 1","YEL 2",
  "COCO 1", "COCO 2"
}
local DST_NAMES = {
  [1]="SPD 1",[2]="AMP 1",[3]="FB 1",[4]="FILT 1",[5]="FLIP 1",[6]="SKIP 1",[7]="REC 1",
  [8]="SPD 2",[9]="AMP 2",[10]="FB 2",[11]="FILT 2",[12]="FLIP 2",[13]="SKIP 2",[14]="REC 2",
  [15]="P1 FRQ",[16]="P2 FRQ",[17]="P3 FRQ",[18]="P4 FRQ",[19]="P5 FRQ",[20]="P6 FRQ",
  [21]="VOL 1", [22]="VOL 2",
  [23]="AUD IN 1", [24]="AUD IN 2"
}
-- v3.00 Fase 2: 4 modes. "8bit" is the ORIGINAL tuning restored (2f85646);
-- "u-law" is the real companding branch, which was unreachable before.
-- NOTE: spelled "u-law", not "μ-law": the norns builtin font has no glyph for
-- U+03BC, so the Greek letter renders as nothing (shows "-law"). See B7.
local BIT_NAMES = {[1]="8bit", [2]="12bit", [3]="SBC", [4]="u-law"}

function UI.update_histories(G)
  for i=1, 2 do
    if not G.trail_head[i] then G.trail_head[i]=1 end
    local head=G.trail_head[i]; G.trails[i][head]=G.coco[i].pos or 0
    G.trail_head[i]=(head % G.TRAIL_SIZE)+1
  end
  for i=1, 12 do
    local val = G.sources_val[i] or 0
    local hist = G.scope_history[i]
    if not G.scope_head then G.scope_head=1 end
    hist[G.scope_head] = val
  end
  G.scope_head = (G.scope_head % G.SCOPE_LEN) + 1
end

function UI.draw_scope(G, id, x, y, w, h, scale, bipolar)
  local hist = G.scope_history[id]
  local head = G.scope_head
  local len = G.SCOPE_LEN

  -- [v3.05] Modo bipolar para los 6 petalos. Se decide por el id de la fuente
  -- (1..6 son petalos) y el param GLOBAL petal_polarity, asi que no hay que
  -- tocar ninguna de las llamadas: los otros inspectores (env 7-8, yellow 9-10,
  -- coco 11-12) no entran nunca aqui porque su id es > 6, y el menu de patch
  -- (que dibuja la fuente que estas cableando) queda coherente con el petalo
  -- que muestra. El 8o argumento permite forzarlo desde fuera.
  --
  -- POR QUE HACE FALTA: el OSC /update manda los petalos CON SIGNO cuando el
  -- modo bipolar esta activo. Antes de v3.05 esta funcion recortaba a 0..1, de
  -- modo que todo valor negativo se dibujaba pegado al borde inferior: media
  -- onda desaparecia y el petalo parecia clavado en su minimo. El rango del
  -- bipolar es -1..+1 con el cero en el centro, que es exactamente el criterio
  -- que ya usa el inspector de destinos.
  --
  -- INVARIANTE: con bipolar=false esta funcion emite EXACTAMENTE las mismas
  -- llamadas de dibujo que antes de v3.05 (zero_y = y+h, half_h = h, lo = 0
  -- reproducen py = y + h - val*h), asi que las pantallas no bipolares no
  -- cambian ni un pixel.
  if bipolar == nil then
    bipolar = (id <= 6) and ((params:get("petal_polarity") or 1) == 2)
  end

  local zero_y, half_h, lo
  if bipolar then
    -- [v3.07] El cero se dibuja como una linea CONTINUA de 1 px, no a puntos.
    -- Dos motivos. (a) screen.pixel es en realidad screen.rect(x, y, 1, 1) y
    -- norns pide coordenadas ENTERAS; con h impar el centro caia en 32.5 y la
    -- linea de puntos salia descentrada. (b) Una linea de puntos se engorda al
    -- cruzarse con la onda, porque se dibuja por su borde (la trampa de v3.00
    -- Fase 3 en el inspector de destinos).
    --
    -- El grosor ya es 1 px de serie: matron llama a screen_line_width(1) al
    -- arrancar (hello.cc), asi que NO hay que tocar line_width, cuyo FIXME
    -- desaconseja hacerlo. Mismo nivel (4) y mismo tramo que el inspector de
    -- destinos: la misma linea en las dos pantallas.
    --
    -- zero_y es ENTERO (math.floor) para que la linea caiga en una fila de pixel
    -- entera y quede nitida, y la onda pivota sobre ese MISMO valor.
    zero_y, half_h, lo = y + math.floor(h / 2), h / 2, -1
    screen.level(4)
    screen.move(x + 1, zero_y); screen.line(x + w - 1, zero_y)
    screen.stroke()
  else
    zero_y, half_h, lo = y + h, h, 0
  end

  screen.level(15)
  local last_px, last_py = nil, nil
  for i=0, w-1 do
    if i < len then
      local idx = (head - 1 - i - 1) % len + 1
      local val = util.clamp(hist[idx] * (scale or 1), lo, 1)
      local px = x + w - i
      local py = util.clamp(zero_y - (val * half_h), y, y + h) 
      if last_px then screen.move(last_px, last_py); screen.line(px, py) else screen.pixel(px, py) end
      last_px = px; last_py = py
    end
  end
  screen.stroke()
end

function UI.draw_popup(G)
  if G.popup.active then
    if util.time() > G.popup.deadline then 
       G.popup.active = false
    else 
      screen.level(0); screen.rect(10, 50, 108, 12); screen.fill()
      screen.level(15); screen.rect(10, 50, 108, 12); screen.stroke()
      screen.move(64, 58); screen.text_center(G.popup.name .. ": " .. G.popup.value) 
    end
  end
end

function UI.draw_main(G)
  if ((G.sources_val[7] or 0) > 0.95) or ((G.sources_val[8] or 0) > 0.95) then screen.level(15); screen.rect(0,0,128,64); screen.stroke() end

  if G.focus.source then
    if G.focus.last_dest then UI.draw_patch_menu(G); return end
    if G.focus.source <= 6 then UI.draw_petal_inspector(G, G.focus.source)
    elseif G.focus.source <= 8 then UI.draw_env_inspector(G, G.focus.source)
    elseif G.focus.source <= 10 then UI.draw_yellow_inspector(G, G.focus.source)
    else UI.draw_coco_inspector(G, G.focus.source) 
    end
    return
  end
  
  if G.focus.inspect_dest then UI.draw_dest_inspector(G, G.focus.inspect_dest); return end

  Q.draw(G) 
  UI.draw_coco_radar(G, 1, 38, 50, 1)   
  UI.draw_coco_radar(G, 78, 38, 49, 2)  
  
  local el = math.pow(G.sources_val[7] or 0, 0.25)
  local er = math.pow(G.sources_val[8] or 0, 0.25)
  screen.level(15)
  screen.rect(60, 64, 3, -(el * 31)); screen.fill() 
  screen.rect(65, 64, 3, -(er * 31)); screen.fill() 
  
  local ol = math.pow(G.coco[1].out_level or 0, 0.25)
  local or_ = math.pow(G.coco[2].out_level or 0, 0.25)
  screen.level(8) 
  screen.rect(57, 64, 1, -(ol * 31)); screen.fill() 
  screen.rect(70, 64, 1, -(or_ * 31)); screen.fill() 
  
  screen.level(3); screen.move(2, 8); screen.text("E1:VOL "); screen.level(15); screen.text(string.format("%.1f", params:get("global_vol") or 1))
  screen.level(3); screen.move(2, 60); screen.text("E2:MON "); screen.level(15); screen.text(string.format("%.2f", params:get("monitor_vol") or 0))
  
  screen.level(3); screen.move(85, 60); screen.text("E3:CHS"); screen.level(15); screen.move(126, 60); screen.text_right(string.format("%.0f%%", params:get("global_chaos")*100))
  
  UI.draw_popup(G)
end

function UI.draw_dest_inspector(G, id)
  local title = DST_NAMES[id] or "DEST"

  -- [v3.02] El titulo es SIEMPRE la etiqueta de la pagina (DST_NAMES), sin el
  -- modo. Antes decia "SKIP 1: SINGLE"; el autor lo quiere como en la pagina:
  -- "SKIP 1", con el modo aparte como "K2/K3: SINGLE".
  local is_skip = (id == 6 or id == 13)
  local mode_txt = nil
  if is_skip then
     local side = (id==6) and "L" or "R"
     local mode = params:get("skip_mode"..side)
     mode_txt = "K2/K3: " .. ((mode==1) and "SINGLE" or "AUTO")
  end

  -- v3.00 Fase 3: caja del scope ampliada y cabecera compacta en UNA fila.
  -- Antes 108x25 en (10,30), con la cabecera en tres filas: "IN GAIN:" en
  -- y=10, su valor en y=18 y el titulo en y=20.
  -- Ahora: titulo a la izquierda y "E3 GAIN IN: valor" a la derecha, en la
  -- misma fila de y=6. Se elimina la pista de abajo "E3: IN GAIN", que era
  -- redundante con el control ya visible en la cabecera.
  -- Caja: de 108x25 a 120x40, area x1.78. El cero sigue en el CENTRO, que es
  -- lo correcto porque la modulacion puede ir a mas o a menos.
  -- v3.01: la caja sube 5 px (y=15 -> y=10) al eliminar la pista "K2/3: MODE"
  -- de este inspector, que ya no ocupa la fila de abajo (y=62).
  -- Comprobado con la fuente real (norns.ttf@8: 5 px de alto sobre la base):
  -- titulo y=6 -> 1..6 | caja 10..50 | controles y=62 -> 57..62. Sin solapes.
  local BOX_X, BOX_Y, BOX_W, BOX_H = 4, 10, 120, 40

  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(3, 6); screen.text(title)

  -- cabecera en UNA sola fila: titulo izquierda, "E3 GAIN IN: valor" derecha
  -- etiqueta a nivel 6 (antes 3, se perdia contra el fondo) y valor a nivel 12
  -- (antes 8, se leia apagado; 12 es brillante sin competir con el 15 de los
  -- valores principales).
  -- El titulo mas largo es el de SKIP ("AUD IN 2", 37 px) y la etiqueta
  -- "E3 GAIN IN:" (47 px) con text_right en x=90 empieza en x=43: el titulo
  -- acaba en x=40, asi que quedan 3 px. SKIP no lleva esa etiqueta porque en su
  -- lugar muestra "K2/K3: <modo>" (ver abajo). Anchos medidos con norns.ttf@8.
  local gain_txt = string.format("%.2fx", G.dest_gains[id])
  if is_skip then
     -- SKIP: etiqueta de pagina + modo que cambian K2/K3 + gain, en UNA fila.
     -- Anchos medidos con norns.ttf@8: "SKIP 1"=31, "K2/K3: SINGLE"=59,
     -- "2.00x"=21. Titulo en x=3 (3..34); K2/K3 con text_right en x=99
     -- (40..99) y gain en x=126 (105..126): 6 px de hueco a cada lado.
     screen.level(6); screen.move(99, 6); screen.text_right(mode_txt)
     screen.level(12); screen.move(126, 6); screen.text_right(gain_txt)
  else
     screen.level(6); screen.move(90, 6); screen.text_right("E3 GAIN IN:")
     screen.level(12); screen.move(126, 6); screen.text_right(gain_txt)
  end
  screen.level(15)
  screen.rect(BOX_X, BOX_Y, BOX_W, BOX_H); screen.stroke()

  -- [v3.07] Linea de cero CONTINUA de 1 px: la MISMA que dibuja UI.draw_scope en
  -- los petalos, mismo nivel (4), mismo tramo y mismo modo de trazo.
  --
  -- POR QUE FALTABA: aqui no habia ninguna linea de referencia. Lo que se veia
  -- con nada cableado era la ONDA plana en cero (sum sale 0 en todos los pixeles,
  -- asi que los 119 puntos caen todos en el centro y forman una linea), y en
  -- cuanto conectabas una fuente la curva se deformaba y la linea desaparecia.
  -- No era una referencia: era el valor. Con esto el cero ya no depende de lo que
  -- haya cableado, y las dos pantallas se leen igual.
  --
  -- OJO: esto NO es la linea discontinua de mas abajo. Aquella marca el umbral
  -- de disparo de los destinos con Schmidt (FLIP/SKIP/REC) y esa se queda como
  -- estaba: es informacion distinta.
  local zc_y = BOX_Y + math.floor(BOX_H / 2)
  screen.level(4)
  screen.move(BOX_X + 1, zc_y); screen.line(BOX_X + BOX_W - 1, zc_y)
  screen.stroke()
  
  if id==5 or id==6 or id==7 or id==12 or id==13 or id==14 then
     local thresh_y = BOX_Y + 11
     screen.level(2)
     for tx=BOX_X+1, BOX_X+BOX_W-1, 4 do screen.pixel(tx, thresh_y) end
     -- v3.00 Fase 3: FILL explicito. Antes el primer fill() del scope
     -- (dentro del bucle) venia a rellenar estos puntos por casualidad.
     -- Al pasar la onda a una sola linea con un unico stroke(), estos puntos
     -- se acumulaban en el trazo y se dibujaban por su BORDE, quedando
     -- visiblemente mas gruesos. Hay que cerrarlos aqui.
     screen.fill()
  end

  local head = G.scope_head; local len = G.SCOPE_LEN
  -- w = ancho util de la onda = BOX_W - 1 (antes el 119 estaba a mano; mismo
  -- valor, pero ahora se deriva de la caja y no puede desincronizarse).
  local w, h = BOX_W - 1, BOX_H; local center_y = BOX_Y + h/2

  -- v3.00 Fase 3 (#14): precalcular que fuentes tienen cableado a este destino.
  -- Antes se recorrian las 12 fuentes para cada uno de los 108 pixeles
  -- (~1300 busquedas por cuadro). Con la lista precalculada solo se suman las
  -- que NO son cero, que normalmente son 3 o 4.
  -- VERIFICADO con tools/verify_p14_inspector.lua: el scope resultante es
  -- identico en los 108 pixeles con matriz vacia, dispersa y completa.
  local activos = {}
  for src=1, 12 do
    if G.patch[src][id] ~= 0 then activos[#activos+1] = src end
  end

  -- v3.00 Fase 3 (#12): dibujar una linea continua en vez de 108 puntos
  -- sueltos. Los inspectores de fuentes (UI.draw_scope) ya lo hacian asi;
  -- aqui se dibujaba cada punto suelto con su propio screen.fill(), lo que
  -- dejaba huecos visibles cuando el valor saltaba (parecia "saltarse
  -- lineas") y costaba 108 rellenos por fotograma.
  -- Ahora: una sola llamada a screen.stroke() para toda la onda.
  -- NO se cambia el calculo: mismo py, mismo rango bipolar -1..+1 con el
  -- cero en el centro, mismo recorte 30..54.
  -- VERIFICADO con tools/verify_p12_scope.lua: los 108 valores son
  -- identicos al calculo de referencia en los 4 escenarios probados.
  screen.level(15)
  local last_px, last_py = nil, nil
  for x=0, w-1 do
    local sum = 0
    local hist_idx = (head - 1 - x - 1) % len + 1
    for _, src in ipairs(activos) do
      sum = sum + (G.scope_history[src][hist_idx] * G.patch[src][id])
    end
    sum = sum * G.dest_gains[id]
    local py = center_y - (util.clamp(sum, -1, 1) * (h/2))
    py = util.clamp(py, BOX_Y, BOX_Y + BOX_H)
    local px = BOX_X + w - x
    if last_px then
      screen.move(last_px, last_py); screen.line(px, py)
    else
      screen.pixel(px, py)
    end
    last_px = px; last_py = py
  end
  screen.stroke()
  
  -- v3.00 Fase 3: la pista "E3: IN GAIN" de abajo se ha eliminado. El
  -- control ya aparece en la cabecera ("E3 GAIN IN: <valor>"), asi que aqui
  -- era redundante. Solo SKIP mantiene su pista, que informa de otra cosa.
  if id == 6 or id == 13 then
     local side = (id==6) and "L" or "R"
     local ch = params:get("stutter_chaos"..side)
     local rt = params:get("stutter_rate"..side)
     screen.level(4); screen.move(2, 62); screen.text("E1:CHS"); screen.level(15); screen.text(string.format("%.2f", ch or 0))
     screen.level(4); screen.move(60, 62); screen.text("E2:RATE"); screen.level(15); screen.text(string.format("%.3fs", rt or 0.1))
  end
  
  UI.draw_popup(G)
end

function UI.draw_petal_inspector(G, id)
  local p_range = params:get("p"..id.."range") or 1
  local p_id = (p_range==1) and "p"..id.."f_lfo" or "p"..id.."f_aud"
  local p = params:get(p_id) or 0
  local ch=params:get("p"..id.."chaos") or 0
  local shp_idx=params:get("p"..id.."shape") or 1
  local rng_idx=params:get("p"..id.."range") or 1
  local shp = shp_idx==1 and "TRI" or "T/H"
  local rng = rng_idx==1 and "LFO" or "AUD"

  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.move(120,10); screen.text_right(string.format("%.2f Hz", p))
  screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); 
  screen.level(4); screen.move(10,55); screen.text("E2:FREQ"); 
  screen.move(64,55); screen.text("E3:CHAOS"); screen.level(15); screen.move(126,55); screen.text_right(string.format("%.2f", ch))
  screen.level(4); screen.move(10,62); screen.text("K2:"..rng); 
  screen.move(64,62); screen.text("K3:"); screen.level(15); screen.move(126,62); screen.text_right(shp)
  UI.draw_popup(G)
end

function UI.draw_env_inspector(G, id)
  local side = (id==7) and "L" or "R"
  local val_pre = params:get("preamp"..side) or 1
  local val_slew = params:get("envSlew"..side) or 0.05
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); 
  screen.level(4)
  screen.move(2, 55); screen.text("E2:PREAMP"); screen.level(15); screen.text(string.format(" %.1fx", val_pre))
  screen.level(4)
  screen.move(126, 55); screen.text_right(string.format("E3:SLEW %.2f", val_slew))
  UI.draw_popup(G)
end

function UI.draw_yellow_inspector(G, id)
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); screen.level(4)
  screen.move(64,55); screen.text_center("ADDRESS NOISE")
  UI.draw_popup(G)
end

function UI.draw_coco_inspector(G, id)
  local side = (id==11) and "1" or "2"
  local param_name = "coco"..side.."_out_mode"
  local mode = params:get(param_name) 
  local mode_str = (mode==1) and "ENVELOPE" or "AUDIO"
  local slew = params:get("coco"..side.."_slew")
  
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); 
  screen.move(120,10); screen.text_right(mode_str)
  
  screen.rect(10,20,108,25); screen.stroke(); 
  UI.draw_scope(G,id,10,20,108,25,1); 
  
  screen.level(4)
  screen.move(2,55); screen.text("K2/3: MODE")
  -- NEW: Slew Display
  screen.move(126,55); screen.text_right(string.format("E3:SLEW %.2f", slew))
  UI.draw_popup(G)
end

function UI.draw_coco_radar(G, x, y, w, id)
  local c=G.coco[id]; if not c then return end; screen.level(1); screen.rect(x,y,w,8); screen.stroke()
  local trail=G.trails[id]; local head=G.trail_head[id]
  for i=0, G.TRAIL_SIZE-1 do local idx=(head-1-i-1)%G.TRAIL_SIZE+1; local b=math.floor(15*(0.6^i)); if b>0 then screen.level(b); screen.rect(x+(trail[idx]*w),y+1,2,6); screen.fill() end end
  
  local rec = params:get("rec"..(id==1 and "L" or "R"))
  if rec==1 or (c.gate_rec and c.gate_rec>0.5) then screen.level(15); screen.rect(x+(c.pos*w),y-2,2,2); screen.fill() end
end

function UI.draw_edit_menu(G, id)
  local side = (id==1) and "L" or "R"
  local speed = params:get("speed"..side)
  local filt = params:get("filt"..side)
  local fb = params:get("fb"..side)
  local bit_idx = params:get("bits"..side)
  local is_link = G.focus.edit_l and G.focus.edit_r
  local title = is_link and "[ < STEREO LINK > ]" or ("COCO "..id) 
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(title); screen.move(120,10); screen.text_right("K3: "..(BIT_NAMES[bit_idx]))
  screen.move(10,30); screen.text("E1: FILT "..string.format("%.2f",filt)); screen.move(10,45); screen.text("E2: SPD "..string.format("%.2f",speed))
  screen.move(10,60); screen.text("E3: FB "..math.floor(fb*100).."%")
  UI.draw_popup(G)
end

function UI.draw_patch_menu(G)
  local src,dst=G.focus.source,G.focus.last_dest; if not src or not dst then return end
  local val=G.patch[src][dst] or 0; 
  screen.level(0); screen.rect(10,10,108,50); screen.fill(); screen.level(15); screen.rect(10,10,108,50); screen.stroke()
  screen.move(64,25); screen.text_center("PATCHING..."); screen.move(64,35); screen.text_center(SRC_NAMES[src].." > "..DST_NAMES[dst])
  screen.move(64,40); screen.level(2); screen.line_rel(40,0); screen.move(64,40); screen.line_rel(-40,0); screen.stroke(); screen.level(15); screen.move(64,40); screen.line_rel(val*40,0); screen.stroke(); screen.circle(64+(val*40),40,2); screen.fill()
  screen.level(15); screen.move(115, 20); screen.text_right(string.format("%.0f%%",val*100))
  UI.draw_scope(G,src,30,48,68,10,math.abs(val))
  UI.draw_popup(G)
end
return UI