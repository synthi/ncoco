-- lib/grid_nav.lua v2016
-- CHANGELOG v2016:
-- 1. SPEED BUTTONS: Now update 'base_speed' and trigger recalc (Base + Offset).

local SC = include('ncoco/lib/sc_utils')
local GridNav = {}
GridNav.cache = {}
GridNav.debounce = {} 

function GridNav.init_map(G)
  G.grid_map = {}
  for x=1,16 do 
     G.grid_map[x] = {}
     GridNav.cache[x] = {} 
     for y=1,8 do GridNav.cache[x][y] = -1 end 
  end
  
  local function map(x, y, type, id, meta) G.grid_map[x][y] = {t=type, id=id, m=meta} end

  map(1,1,'edit',1); map(2,1,'edit',1); map(1,2,'edit',1); map(2,2,'edit',1)
  map(15,1,'edit',2); map(16,1,'edit',2); map(15,2,'edit',2); map(16,2,'edit',2)
  map(3,1,'seq',1); map(4,1,'seq',2); map(13,1,'seq',3); map(14,1,'seq',4)

  map(1,3,'rec',1); map(2,3,'jack',7); map(1,4,'flip',1); map(2,4,'jack',5); map(1,5,'skip',1); map(2,5,'jack',6)
  map(16,3,'rec',2); map(15,3,'jack',14); map(16,4,'flip',2); map(15,4,'jack',12); map(16,5,'skip',2); map(15,5,'jack',13)
  map(8,3,'petal',9); map(9,3,'petal',10) 
  map(7,1,'petal',1); map(6,1,'p_jack',15); map(10,1,'petal',2); map(11,1,'p_jack',16)
  map(5,3,'petal',6); map(4,3,'p_jack',20); map(12,3,'petal',3); map(13,3,'p_jack',17)
  map(7,5,'petal',5); map(6,5,'p_jack',19); map(10,5,'petal',4); map(11,5,'p_jack',18)
  map(4,6,'env',7); map(13,6,'env',8)
  
  map(1,7,'jack',2);  map(3,7,'jack',3);  map(5,7,'jack',4);
  map(7,7,'jack',21); map(10,7,'jack',22);
  map(12,7,'jack',11); map(14,7,'jack',10); map(16,7,'jack',9);
  
  for x=1,7 do map(x,8,'fader',1, x) end 
  map(8,8,'jack',1);  map(9,8,'jack',8);  
  for x=10,16 do map(x,8,'fader',2, 17-x) end
end

function GridNav.key(G, g, x, y, z, simulated)
  local obj = G.grid_map[x] and G.grid_map[x][y]
  if not obj then return end
  
  if z == 1 and not simulated then
     local id_key = x..","..y
     local last_time = GridNav.debounce[id_key] or 0
     local now = util.time()
     if (now - last_time) < 0.05 then return end
     GridNav.debounce[id_key] = now
  end
  
  if not simulated and obj.t ~= 'seq' and G.sequencers then
    if obj.t == 'rec' or obj.t == 'flip' or obj.t == 'skip' or obj.t == 'fader' then
        local now = util.time()
        for i=1, 4 do
          local s = G.sequencers[i]
          if s and (s.state == 1 or s.state == 4) then 
             local dt = now - s.start_time
             if s.state == 4 and s.duration > 0 then dt = dt % s.duration end
             table.insert(s.data, {x=x, y=y, z=z, dt=dt})
             if s.state == 4 then table.sort(s.data, function(a,b) return a.dt < b.dt end) end
          end
        end
    end
  end

  if z == 1 then 
    GridNav.cache[x][y] = 15
    if g then g:led(x, y, 15); g:refresh() end 
  end
  
  if z == 0 and (obj.t == 'skip' or obj.t == 'flip' or obj.t == 'rec' or obj.t == 'seq' or obj.t == 'fader') then 
    GridNav.cache[x][y] = -1
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
  if obj.t == 'petal' or obj.t == 'env' then 
    if z==1 then G.focus.source=obj.id; G.focus.last_dest=nil elseif G.focus.source==obj.id then G.focus.source=nil end 
    return 
  end
  if (obj.t=='jack' or obj.t=='p_jack') then
    if z==1 then
      if G.focus.source then
        G.focus.dest=obj.id; G.focus.last_dest=obj.id; G.focus.dest_timer=util.time()
        clock.run(function() clock.sleep(0.8); if z==1 and G.focus.dest==obj.id then G.patch[G.focus.source][obj.id]=0.0; SC.update_matrix(obj.id,G) end end)
      else G.focus.inspect_dest = obj.id end
    else
      if G.focus.source then
        if util.time()-G.focus.dest_timer<0.8 then if G.patch[G.focus.source][obj.id]==0 then G.patch[G.focus.source][obj.id]=0.5; SC.update_matrix(obj.id,G) end end
        G.focus.dest=nil
      else G.focus.inspect_dest = nil end
    end
    return
  end
  
  if z==1 and not G.focus.source then
    local side = (obj.id==1) and "L" or "R"
    if obj.t=='rec' then params:set("rec"..side, 1 - params:get("rec"..side))
    elseif obj.t=='flip' then params:set("flip"..side, 1 - params:get("flip"..side))
    elseif obj.t=='skip' then params:set("skip"..side, 1)
    
    elseif obj.t=='fader' then 
        -- SPEED LOGIC UPDATE
        local base = G.SPEED_TABLE[obj.m]
        local c_idx = obj.id
        -- Update Base Speed
        G.coco[c_idx].base_speed = base
        
        -- Recalculate Final: Base + Offset
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

function GridNav.redraw(G, g)
  for x=1,16 do for y=1,8 do
    local obj=G.grid_map[x][y]; local b=0
    
    if obj then
      if obj.t=='edit' then b=((G.focus.edit_l and obj.id==1) or (G.focus.edit_r and obj.id==2)) and 15 or 4
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
         
      elseif obj.t=='petal' or obj.t=='env' then 
        if G.focus.inspect_dest then 
           if G.patch[obj.id] and G.patch[obj.id][G.focus.inspect_dest] then
              b = (G.patch[obj.id][G.focus.inspect_dest] ~= 0) and 15 or 2
           else b=2 end
        elseif G.focus.source==obj.id then b=15 
        else b=util.round(util.linlin(0,1,6,15,math.abs(G.sources_val[obj.id] or 0))) end
      elseif obj.t=='jack' or obj.t=='p_jack' then
        if G.focus.source then 
           if G.patch[G.focus.source] and G.patch[G.focus.source][obj.id] then
              b=(G.patch[G.focus.source][obj.id]~=0) and 12 or 3
           else b=3 end
        elseif G.focus.inspect_dest==obj.id then b=15
        else 
          local energy = 0
          for src=1, 10 do
             if G.patch[src] and G.patch[src][obj.id] then
                local amt = G.patch[src][obj.id]
                if amt ~= 0 then energy = energy + math.abs(G.sources_val[src] * amt) end
             end
          end
          local alive = math.floor(energy * 5)
          b = util.clamp(1 + alive, 1, 7)
          if G.patch[1] and G.patch[1][obj.id] and G.patch[1][obj.id]~=0 then b=math.max(b, 8) end 
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
        if GridNav.cache[x][y] == 15 then b=15 else b=4 end

      elseif obj.t=='fader' then 
        local c=G.coco[obj.id]
        if GridNav.cache[x][y] == 15 then b=15 
        else b = get_fader_bright(G, c.real_speed or 1.0, obj.m) end
      end
    
    else
      b = 0
    end
    
    if GridNav.cache[x][y] ~= b then 
       g:led(x,y,b)
       GridNav.cache[x][y] = b 
    end
  end end
  g:refresh()
end
return GridNav
