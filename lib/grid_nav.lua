-- lib/grid_nav.lua v3.04
-- v3.03 (LATIDO deja de dar falsas alarmas):
-- 0. NEW: GridNav.heartbeat_step() — la decision del latido, sacada a una
--    funcion PURA para poder testearla sin simular clock ni metro.
-- 1. DIAGNOSTICO: el latido ahora mide TAMBIEN su propio atraso. Verificado en
--    matron/src/events.cc: UN solo event_loop(), UNA sola cola FIFO, y tanto
--    w_handle_metro como w_handle_clock_resume llaman al MISMO estado Lua.
--    Metro y latido estan SERIALIZADOS => un bloqueo de N s para a los dos, y
--    al reanudarse el latido ve N s de "sin redraw" en una rejilla que estaba
--    viva. Esa era la falsa alarma de v3.02.
-- 2. Dos avisos antes de recuperar: una parada transitoria nunca apaga la rejilla.
-- v3.01 (continúa la FASE 4 del congelado del grid):
-- 0. FIX: el clock.run del jack (0.8s) hacia G.patch[G.focus.source][obj.id]
--    al despertar. Si G.focus.source se volvia nil entre medias (soltar la
--    fuente, cargar un snapshot), era G.patch[nil] -> "table index is nil"
--    DENTRO de una corrutina de clock. Ahora captura la fuente al crear el
--    cierre y comprueba antes de indexar.
-- 1. refresh() se llama SIEMPRE, no solo `if changed`. Un error a mitad del
--    bucle podia dejar quads dirty sin que nadie los reenviara (ver el
--    comentario en el propio redraw). refresh() no gasta mas: el C solo manda
--    los quads con la flag dirty.
-- 2. snap_timers es un TIMESTAMP, no un flag: expira solo aunque su corrutina
--    muera. Antes un boton podia quedarse en brillo 15 para siempre.
-- 3. GridNav.last_redraw alimenta el latido de ncoco.
-- 4. NEW: GridNav.find_device_port() — devuelve el vport que SI tiene aparato.
--    Lo usa la recuperacion del latido y grid.add para reenganchar la rejilla
--    cuando g.device queda nil (verificado contra norns grid.lua/vport.lua).
-- CLEANUP v3.00 FASE 1 (no functional change):
-- 1. REMOVED GridNav.is_dirty (written 5x, never read; see note at the field).
-- 2. Grid debounce key is now numeric (x-1)*8+y instead of a "x,y" string.
-- CHANGELOG v2.05:
-- 1. OPT: g:refresh() only called when at least one LED changed (reduces serial traffic).
-- 2. OPT: Cache reset every 75 frames (~5s at 15Hz) to prevent desync.
-- CHANGELOG v2.04:
-- 1. FIX: Sequencer simulated events now set cache=-1 (dirty) instead of 15,
--    allowing GridNav.redraw to illuminate buttons. Previously cache=15 blocked
--    the differential update (cache==b==15 → skip), leaving LEDs dark.
-- CHANGELOG v2.03:
-- 1. FIX: Added 10000 event limit per sequencer to prevent memory leaks.
-- CHANGELOG v2.02:
-- 1. NEW: Snapshots can be recorded/played by sequencers (simulated snaps skip timer).
-- 2. FIX: Removed auto-heal (was ineffective, cause fixed upstream).
-- CHANGELOG v2.01:
-- 1. OPT: Sequencer simulated events skip g:led/g:refresh to reduce USB traffic.
-- CHANGELOG v2.00:
-- 1. FIX: Protected energy calculation with nil guards (sources_val) to prevent grid freeze.
-- 2. OPT: Lowered auto-heal trigger from 60 to 30 frames (~2s) for faster recovery.
-- CHANGELOG v9006:
-- 1. REFRESH: Added auto-heal mechanism (cache reset) to fix frozen LEDs.
-- CHANGELOG v10001 (FINAL AUDIT):
-- 1. REFRESH: Unlocked "is_dirty" block to allow 30Hz fluid animation.
-- 2. OPTIMIZATION: Jacks logic separated (Static Patching vs Dynamic Monitoring).
-- 3. CACHE: Differential update preserved to protect serial bus bandwidth.

local SC = include('ncoco/lib/sc_utils')
local GridNav = {}
GridNav.cache = {}
GridNav.debounce = {} 
GridNav.snap_timers = {}
-- NOTE (v3.00): `GridNav.is_dirty` was removed ON PURPOSE. It was written in 5
-- places but never read: the flag was meant to gate the redraw, but that check
-- was intentionally disabled (see CHANGELOG v10001) to allow fluid animation —
-- the sequencer/REC blink uses math.sin(util.time()), which changes every frame
-- with no user input. Re-adding the gate would freeze those LEDs.
-- [v3.00] Marca de tiempo del ultimo redraw completado. La usa el latido
-- (heartbeat) de ncoco para detectar si el metro del grid dejo de disparar.
GridNav.refresh_counter = 0
GridNav.last_redraw = 0

function GridNav.init_map(G)
  G.grid_map = {}
  for x=1,16 do 
     G.grid_map[x] = {}
     GridNav.cache[x] = {} 
     for y=1,8 do GridNav.cache[x][y] = -1 end 
  end
  
  local function map(x, y, type, id, meta) G.grid_map[x][y] = {t=type, id=id, m=meta} end

  for x=1,4 do map(x, 1, 'snap', x) end
  for x=13,16 do map(x, 1, 'seq', x-12) end

  map(1,2,'edit',1); map(2,2,'edit',1); map(3,2,'edit',1)
  map(14,2,'edit',2); map(15,2,'edit',2); map(16,2,'edit',2)

  map(1,3,'rec',1); map(2,3,'jack',7); map(1,4,'flip',1); map(2,4,'jack',5); map(1,5,'skip',1); map(2,5,'jack',6)
  map(16,3,'rec',2); map(15,3,'jack',14); map(16,4,'flip',2); map(15,4,'jack',12); map(16,5,'skip',2); map(15,5,'jack',13)
  map(8,3,'petal',9); map(9,3,'petal',10) 
  map(7,1,'petal',1); map(6,1,'p_jack',15); map(10,1,'petal',2); map(11,1,'p_jack',16)
  map(5,3,'petal',6); map(4,3,'p_jack',20); map(12,3,'petal',3); map(13,3,'p_jack',17)
  map(7,5,'petal',5); map(6,5,'p_jack',19); map(10,5,'petal',4); map(11,5,'p_jack',18)
  
  map(3,6,'jack',23); map(4,6,'env',7); map(13,6,'env',8); map(14,6,'jack',24);
  
  -- SOURCES 11 & 12 (Coco Outputs)
  map(5,6,'coco_out',11); map(12,6,'coco_out',12);

  map(1,7,'jack',2);  map(3,7,'jack',3);  map(5,7,'jack',4);
  map(7,7,'jack',21); map(10,7,'jack',22);
  map(12,7,'jack',11); map(14,7,'jack',10); map(16,7,'jack',9);
  
  for x=1,7 do map(x,8,'fader',1, x) end 
  map(8,8,'jack',1);  map(9,8,'jack',8);  
  for x=10,16 do map(x,8,'fader',2, 17-x) end
end

-- [FIX] Function to force full redraw (cache reset)
function GridNav.reset_cache()
  for x=1,16 do 
     for y=1,8 do 
        GridNav.cache[x][y] = -1 
     end 
  end
end

-- [v3.03] UMBRALES del latido (segundos).
GridNav.HEART_STALL   = 3.0   -- sin redraw durante esto => hay congelacion
GridNav.HEART_LATE    = 1.0   -- atraso del PROPIO latido => el bucle se bloqueo
GridNav.HEART_CONFIRM = 2.0   -- un ciclo de latido entre aviso y recuperacion

--- [v3.03] Decision del latido. FUNCION PURA: entra medicion, sale que hacer.
-- No toca la rejilla, no imprime, no usa reloj. Asi el test fabrica cada caso
-- sin tener que simular clock ni metro.
--
-- POR QUE HACE FALTA (verificado en norns, no supuesto):
--   matron/src/events.cc tiene UN SOLO event_loop() que drena UNA cola FIFO, y
--   w_handle_metro() y w_handle_clock_resume() llaman al MISMO estado Lua
--   (lvm). Metro y latido estan, por tanto, SERIALIZADOS: si cualquier
--   manejador de Lua tarda N segundos se paran LOS DOS a la vez. Al
--   reanudarse, el latido mide util.time() (reloj de pared) frente a
--   last_redraw de ANTES del bloqueo y ve N segundos, aunque la rejilla se vaya
--   a recuperar sola en el siguiente tick de metro.
--   Recuperar ahi era la falsa alarma de v3.02: "GRID RECOVERY" mandaba
--   g:all(0) y apagaba una rejilla que estaba perfectamente viva (el parpadeo
--   que delato el problema).
--
-- La prueba que separa los dos casos es el ATRASO PROPIO del latido, que NO
-- depende del metro:
--   late >= HEART_LATE  => el bucle ENTERO se bloqueo => informar, NO tocar.
--                          Se cura solo y tocarlo solo genera el parpadeo.
--   late pequeño + stall grande => el metro si murio => 2 avisos y recuperar.
--
-- @tparam number stall  segundos desde el ultimo redraw terminado
-- @tparam number late   atraso real de ESTE despertar (>=0)
-- @tparam number ticks  ticks de metro vistos desde el ciclo anterior
-- @tparam number|nil pending  instante del aviso 1/2 (nil si no lo hay)
-- @tparam number now    instante actual
-- @treturn string  "ok" | "block" | "warn" | "recover"
-- @treturn string|nil mensaje para maiden (nil cuando la accion es "ok")
function GridNav.heartbeat_step(stall, late, ticks, pending, now)
   if stall <= GridNav.HEART_STALL then
      return "ok"                        -- la rejilla esta latiendo: nada que ver
   end
   if late >= GridNav.HEART_LATE then
      -- El latido NO depende del metro y aun asi llego tarde: el cuello es el
      -- bucle de Lua entero, no la rejilla. Recuperar aqui solo la apagaria.
      return "block", string.format(
         "GRID HEARTBEAT: sin redraw %.1fs PERO el latido llego %.1fs tarde"
         .. " => el bucle de Lua se bloqueo (metro y latido parados juntos,"
         .. " metro +%d ticks). Se recupera solo; NO se toca la rejilla.",
         stall, late, ticks or 0)
   end
   -- Latido puntual: el metro concreto es el que no dispara. Dos avisos.
   if pending and (now - pending) >= GridNav.HEART_CONFIRM then
      return "recover", string.format(
         "GRID HEARTBEAT: sin redraw %.1fs tras 2 avisos con el latido puntual"
         .. " (metro +%d ticks) => recuperando",
         stall, ticks or 0)
   end
   return "warn", string.format(
      "GRID HEARTBEAT: sin redraw %.1fs, latido puntual, metro +%d ticks"
      .. " -> aviso 1/2 (NO recupero aun)",
      stall, ticks or 0)
end


-- [v3.01] Devuelve el indice del vport (1..4) que SI tiene un dispositivo
-- fisico enganchado, o nil si ninguno. Sirve para RECUPERAR la rejilla cuando
-- g.device queda nil.
-- VERIFICADO en norns lua/core/grid.lua + lua/core/vport.lua (no es una
-- suposicion):
--   - grid.connect(n) NO devuelve el aparato, devuelve Grid.vports[n], una tabla
--     cuyo campo .device la rellena Grid.update_devices() al conectar y la pone
--     a nil al desconectar.
--   - vport.wrap_method envuelve led/all/refresh asi:
--         if self.device then self.device[method](self.device, ...) end
--     => con .device nil esas llamadas son NO-OPS SILENCIOSOS (no dan error).
-- Leer .device es, por tanto, la unica forma publica de saber si los LEDs van a
-- llegar realmente al hardware. Si el aparato se reengancha con OTRO nombre, el
-- autofill de Grid.new lo manda a otro vport y el vport 1 se queda sin .device:
-- por eso hay que ESCANEAR, no asumir el 1.
function GridNav.find_device_port()
   for n = 1, 4 do
      local vp = grid.connect(n)
      if vp and vp.device then return n end
   end
   return nil
end

function GridNav.key(G, g, x, y, z, simulated)
  local obj = G.grid_map[x] and G.grid_map[x][y]
  if not obj then return end
  
    
  if z == 1 and not simulated then
     -- Numeric key (x-1)*8+y instead of a "x,y" string: avoids a string
     -- allocation on every button press. 1..128 maps to a 1D array.
     local id_key = (x-1)*8 + y
     local last_time = GridNav.debounce[id_key] or 0
     local now = util.time()
     if (now - last_time) < 0.05 then return end
     GridNav.debounce[id_key] = now
  end
  
  if not simulated and obj.t ~= 'seq' and G.sequencers then
    if obj.t == 'rec' or obj.t == 'flip' or obj.t == 'skip' or obj.t == 'fader' or obj.t == 'snap' then
        local now = util.time()
        for i=1, 4 do
          local s = G.sequencers[i]
          if s and (s.state == 1 or s.state == 4) then 
             local dt = now - s.start_time
             if s.state == 4 and s.duration > 0 then dt = dt % s.duration end
             if #s.data < 10000 then
               table.insert(s.data, {x=x, y=y, z=z, dt=dt})
            end
             if s.state == 4 then table.sort(s.data, function(a,b) return a.dt < b.dt end) end
          end
        end
    end
  end

  if z == 1 then 
    if not simulated then
      GridNav.cache[x][y] = 15
      if g then g:led(x, y, 15); g:refresh() end
    else
      GridNav.cache[x][y] = -1
    end
  end
  
  if z == 0 and (obj.t == 'skip' or obj.t == 'flip' or obj.t == 'rec' or obj.t == 'seq' or obj.t == 'fader' or obj.t == 'snap') then 
    GridNav.cache[x][y] = -1
  end

  if obj.t == 'snap' then
     -- SECUENCIADOR: accion inmediata (sin timer, no puede borrar snapshots)
     if simulated then
        if z == 1 then
           if G.snapshots[obj.id] == nil then
              G.snap_save(obj.id)
           else
              G.snap_load(obj.id)
           end
        end
        return
     end
     
     if z == 1 then
        -- [v3.01] La corrutina lleva capturado SU PROPIO sello de tiempo.
        -- ANTES comparaba "snap_timers[id] ~= 0": eso es un valor COMPARTIDO por
        -- todos los toques. Al despertar, la corrutina de un toque VIEJO veia el
        -- sello de un toque NUEVO (distinto de 0) y BORRABA el snapshot aunque
        -- ese toque nuevo fuera corto. Con toques muy seguidos eso pasaba antes o
        -- despues -> "de pronto dice cleared" sin que nadie mantuviera pulsado.
        -- Ahora solo actua si el sello sigue siendo EXACTAMENTE el suyo: si hubo
        -- release (pasa a 0) o un toque nuevo (sello distinto), deja de coincidir.
        -- Mantener >1.6s sigue borrando igual.
        local pressed_at = util.time()
        GridNav.snap_timers[obj.id] = pressed_at
        clock.run(function()
           clock.sleep(1.6) 
           if GridNav.snap_timers[obj.id] == pressed_at then
              G.snap_clear(obj.id)
              GridNav.snap_timers[obj.id] = -1 
                         end
        end)
     elseif z == 0 then
        if GridNav.snap_timers[obj.id] == -1 then
           GridNav.snap_timers[obj.id] = 0
        elseif GridNav.snap_timers[obj.id] then   -- nil = release sin press: no hacer nada
           local t = util.time() - GridNav.snap_timers[obj.id]
           GridNav.snap_timers[obj.id] = 0
           if t < 1.6 then
              if G.snapshots[obj.id] == nil then
                 G.snap_save(obj.id)
              elseif G.active_snapshot == obj.id then
                 G.snap_update(obj.id)
              else
                 G.snap_load(obj.id)
              end
           end
        end
             end
     return
  end

  if obj.t == 'seq' and G.sequencers then
     local s = G.sequencers[obj.id]
     if s then 
         if z == 1 then
            s.press_time = util.time()
            if s.state == 0 then
               s.state = 1; s.data = {}; s.start_time = util.time(); s.step = 1
            elseif s.state == 1 then
               s.duration = util.time() - s.start_time
               if s.duration < 0.1 then s.duration = 0.1 end 
               s.state = 2; s.start_time = util.time()
            elseif s.state == 2 or s.state == 4 then
               if s.double_click_timer then
                  s.state = 3; s.double_click_timer = nil 
               else
                  s.double_click_timer = clock.run(function()
                     clock.sleep(0.25)
                     if s.state == 3 then return end
                     if s.state == 2 then s.state = 4 else s.state = 2 end
                     s.double_click_timer = nil
                                       end)
               end
            elseif s.state == 3 then
               s.state = 2; s.start_time = util.time(); s.step = 1
            end
         elseif z == 0 then
            if util.time() - s.press_time > 1.0 then
               s.state = 0; s.data = {};
            end
         end
     end
     return
  end

  if obj.t == 'edit' then if obj.id==1 then G.focus.edit_l=(z==1) end; if obj.id==2 then G.focus.edit_r=(z==1) end; return end
  
  if obj.t == 'petal' or obj.t == 'env' or obj.t == 'coco_out' then 
    if z==1 then 
        if G.focus.inspect_dest then
            G.focus.source = obj.id; G.focus.dest = G.focus.inspect_dest
            G.focus.last_dest = G.focus.inspect_dest; G.focus.dest_timer = util.time()
            local current = G.patch[obj.id][G.focus.dest]
            local next_val = 0
            if current == 0 then next_val = 0.5 elseif math.abs(current) < 0.9 then next_val = 1.0 else next_val = 0 end
            G.patch[obj.id][G.focus.dest] = next_val; SC.update_matrix(G.focus.dest, G)
        else
            G.focus.source=obj.id; G.focus.last_dest=nil 
        end
    elseif z==0 then
        if G.focus.source==obj.id and not G.focus.inspect_dest then G.focus.source=nil end 
    end 
    return 
  end
  
  if (obj.t=='jack' or obj.t=='p_jack') then
    if z==1 then
      if G.focus.source then
        if G.focus.last_dest == obj.id then
           local current = G.patch[G.focus.source][obj.id]
           local next_val = 0
           if current == 0 then next_val = 0.5 elseif math.abs(current) < 0.9 then next_val = 1.0 else next_val = 0 end
           G.patch[G.focus.source][obj.id] = next_val; SC.update_matrix(obj.id,G)
        else
           G.focus.dest=obj.id; G.focus.last_dest=obj.id; G.focus.dest_timer=util.time()
           -- [v3.01] Capturar la fuente AHORA, no leerla dentro de 0.8s.
           -- Antes el cierre hacia `G.patch[G.focus.source][obj.id]` al despertar.
           -- Si entre medias `G.focus.source` se volvia nil (soltar la fuente,
           -- cargar un snapshot), eso era `G.patch[nil]` -> "table index is nil"
           -- DENTRO de una corrutina de clock: un error que norns imprime pero
           -- que aborta la corrutina. Ahora se fija el valor y se comprueba.
           local focus_src = G.focus.source
           clock.run(function() 
               clock.sleep(0.8)
               if focus_src and G.patch[focus_src] and G.focus.dest == obj.id then
                  G.patch[focus_src][obj.id] = 0.0
                  SC.update_matrix(obj.id, G)
               end 
           end)
        end
      else G.focus.inspect_dest = obj.id end
    else
      if G.focus.inspect_dest == obj.id then G.focus.inspect_dest = nil; G.focus.source = nil
      elseif G.focus.source then
        if util.time()-G.focus.dest_timer<0.8 then 
            if G.patch[G.focus.source][obj.id]==0 then G.patch[G.focus.source][obj.id]=0.5; SC.update_matrix(obj.id,G) end 
        end
        G.focus.dest=nil
      end
    end
    return
  end
  
  if z==1 and not G.focus.source then
    local side = (obj.id==1) and "L" or "R"
    if obj.t=='rec' then params:set("rec"..side, 1 - params:get("rec"..side))
    elseif obj.t=='flip' then params:set("flip"..side, 1 - params:get("flip"..side))
    elseif obj.t=='skip' then params:set("skip"..side, 1)
    
    elseif obj.t=='fader' then 
        local base = G.SPEED_TABLE[obj.m]
        local c_idx = obj.id
        G.coco[c_idx].base_speed = base
        
        local suffix = (c_idx==1) and "L" or "R"
        local offset = params:get("speed_offset"..suffix)
        params:set("speed"..suffix, base + offset)
    end
  elseif z==0 then 
    if obj.t=='skip' then 
      local side = (obj.id==1) and "L" or "R"
      params:set("skip"..side, 0)
    end 
  end
end

local function get_fader_bright(G, current_speed, btn_idx)
  local table = G.SPEED_TABLE
  local val_btn = table[btn_idx]
  local abs_spd = math.abs(current_speed)
  local bg = (btn_idx == 4) and 4 or math.floor(util.linlin(1, 7, 2, 5, btn_idx))
  if math.abs(abs_spd - val_btn) < 0.05 then return 12 end
  if btn_idx < 7 then
    local val_next = table[btn_idx+1]
    if abs_spd > val_btn and abs_spd < val_next then local t = (abs_spd - val_btn) / (val_next - val_btn); return math.floor(util.linlin(0, 1, 12, 4, t)) end
  end
  if btn_idx > 1 then
    local val_prev = table[btn_idx-1]
    if abs_spd > val_prev and abs_spd < val_btn then local t = (abs_spd - val_prev) / (val_btn - val_prev); return math.floor(util.linlin(0, 1, 4, 12, t)) end
  end
  return bg
end

-- SMART-REFRESH IMPLEMENTATION (~15Hz)
function GridNav.redraw(G, g)
  if not g then return end
  
  -- Periodic cache reset (~5s / 75 frames) to prevent LED desync
  GridNav.refresh_counter = (GridNav.refresh_counter or 0) + 1
  if GridNav.refresh_counter >= 75 then
     GridNav.reset_cache()
     GridNav.refresh_counter = 0
  end

  for x=1,16 do for y=1,8 do
    local obj=G.grid_map[x][y]; local b=0
    
    if obj then
      if obj.t=='snap' then
         -- [v3.00] snap_timers[id] guarda un TIMESTAMP (util.time()), no un flag.
         -- Antes se comprobaba "> 0", es decir "hay un flash en curso", y solo lo
         -- apagaba la corrutina de clock.run. Si esa corrutina moria, el flag se
         -- quedaba en positivo para siempre y ese boton quedaba en brillo 15
         -- permanentemente -- reset_cache NO lo limpia, porque no es el cache.
         -- Comparando contra el tiempo, expira solo: ningun estado puede colgar.
         local flash = GridNav.snap_timers[obj.id]
         if flash and flash > 0 and (util.time() - flash) < 1.6 then b = 15
         elseif G.active_snapshot == obj.id then b = 10
         elseif G.snapshots[obj.id] ~= nil then b = 6
         else b = 2 end
         
      elseif obj.t=='edit' then b=((G.focus.edit_l and obj.id==1) or (G.focus.edit_r and obj.id==2)) and 15 or 4
      elseif obj.t=='seq' then
         if G.sequencers then
             local s = G.sequencers[obj.id]
             if s then
                 if GridNav.cache[x][y] == 15 then b=15
                 elseif s.state == 0 then b=2 
                 elseif s.state == 1 then b = math.floor(util.linlin(-1, 1, 5, 15, math.sin(util.time() * 5)))
                 elseif s.state == 2 then b=12
                 elseif s.state == 3 then b=5
                 elseif s.state == 4 then b = math.floor(util.linlin(-1, 1, 5, 15, math.sin(util.time() * 15)))
                 end
             else b=0 end
         else b=0 end
         
      elseif obj.t=='petal' or obj.t=='env' or obj.t=='coco_out' then 
        if G.focus.inspect_dest then 
           if G.patch[obj.id] and G.patch[obj.id][G.focus.inspect_dest] then
              b = (G.patch[obj.id][G.focus.inspect_dest] ~= 0) and 15 or 2
           else b=2 end
        elseif G.focus.source==obj.id then b=15 
        else 
           b=util.round(util.linlin(0,1,6,15,math.abs(G.sources_val[obj.id] or 0))) 
        end
      elseif obj.t=='jack' or obj.t=='p_jack' then
        if G.focus.source then
           if G.patch[G.focus.source] and G.patch[G.focus.source][obj.id] then
              b=(G.patch[G.focus.source][obj.id]~=0) and 12 or 3
           else b=3 end
        elseif G.focus.inspect_dest==obj.id then b=15
        else 
          local energy = 0
          for src=1, 12 do
             if G.patch[src] and G.patch[src][obj.id] then
                local amt = G.patch[src][obj.id] or 0
                if amt ~= 0 then energy = energy + math.abs((G.sources_val[src] or 0) * amt) end
             end
          end
          local alive = math.floor(energy * 5)
          b = util.clamp(1 + alive, 1, 7)
        end 
      
      elseif obj.t=='rec' then 
        local id = obj.id
        local side = (id==1) and "L" or "R"
        local p_val = params:get("rec"..side)
        local c = G.coco[id]
        local mod_val = (c.gate_rec and c.gate_rec > 0.5)
        
        if GridNav.cache[x][y] == 15 then b=15
        elseif (p_val == 1) or mod_val then 
           b = math.floor(util.linlin(-1, 1, 10, 14, math.sin(util.time() * 15)))
        else b=4 end
      
      elseif obj.t=='flip' then 
        local id = obj.id
        local side = (id==1) and "L" or "R"
        local p_val = params:get("flip"..side)
        local c = G.coco[id]
        if GridNav.cache[x][y] == 15 then b=15
        elseif (p_val == 1) or (c.gate_flip and c.gate_flip > 0.5) then b = 10 
        else b=4 end
        
      elseif obj.t=='skip' then 
        local c=G.coco[obj.id]
        if GridNav.cache[x][y] == 15 then b=15 
        elseif (c.gate_skip and c.gate_skip > 0.5) then b=10
        else b=4 end

      elseif obj.t=='fader' then 
        local c=G.coco[obj.id]
        if GridNav.cache[x][y] == 15 then b=15 
        else b = get_fader_bright(G, c.real_speed or 1.0, obj.m) end
      end
    
    else
      b = 0
    end
    
    -- DIFFERENTIAL UPDATE: only send LEDs that changed
    if GridNav.cache[x][y] ~= b then 
       g:led(x,y,b)
       GridNav.cache[x][y] = b 
    end
  end end
  -- [v3.00] refresh() se llama SIEMPRE, no solo si cambió algo.
  -- Antes: "if changed then g:refresh() end". Riesgo real: si un error a mitad
  -- del bucle abortaba el redraw, los g:led ya emitidos dejaban su quad DIRTY
  -- en el C, pero el refresh que los enviaba no llegaba a llamarse; y como el
  -- cache ya se había actualizado, ninguna pasada posterior los reenviaba.
  -- (Los cuadros sucios quedaban varados sin que nadie los vaciara.)
  -- refresh() cuesta lo mismo con la lista limpia: el C solo manda los quads
  -- cuya flag dirty está puesta. Llamarlo siempre no gasta ancho de banda y
  -- garantiza que ningún cuadro quede pendiente.
  g:refresh()
  -- Latido: constancia de que este ciclo llego al final. El heartbeat
  -- de ncoco vigila este valor para detectar que el metro murio.
  GridNav.last_redraw = util.time()
end
return GridNav
