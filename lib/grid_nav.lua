-- lib/grid_nav.lua v600 (REVERSE LOOKUP)
local SC = include('ncoco/lib/sc_utils')
local GridNav = {}
GridNav.cache = {}

function GridNav.init_map(G)
  G.grid_map = {}
  for x=1,16 do G.grid_map[x] = {}; GridNav.cache[x] = {}; for y=1,8 do GridNav.cache[x][y] = -1 end end
  local function map(x, y, type, id, meta) G.grid_map[x][y] = {t=type, id=id, m=meta} end

  map(1,1,'edit',1); map(2,1,'edit',1); map(1,2,'edit',1); map(2,2,'edit',1)
  map(15,1,'edit',2); map(16,1,'edit',2); map(15,2,'edit',2); map(16,2,'edit',2)
  map(1,3,'rec',1); map(2,3,'jack',7); map(1,4,'flip',1); map(2,4,'jack',5); map(1,5,'skip',1); map(2,5,'jack',6)
  map(16,3,'rec',2); map(15,3,'jack',14); map(16,4,'flip',2); map(15,4,'jack',12); map(16,5,'skip',2); map(15,5,'jack',13)
  
  map(7,1,'petal',1); map(6,1,'p_jack',15); map(10,1,'petal',2); map(11,1,'p_jack',16)
  map(5,3,'petal',6); map(4,3,'p_jack',20); map(12,3,'petal',3); map(13,3,'p_jack',17)
  map(7,5,'petal',5); map(6,5,'p_jack',19); map(10,5,'petal',4); map(11,5,'p_jack',18)
  
  map(4,6,'env',7); map(13,6,'env',8)
  map(1,7,'jack',2); map(3,7,'jack',3); map(5,7,'jack',4); map(7,7,'jack',1)
  map(10,7,'jack',8); map(12,7,'jack',11); map(14,7,'jack',10); map(16,7,'jack',9)
  
  for x=1,7 do map(x,8,'fader',1, x) end 
  for x=10,16 do map(x,8,'fader',2, 17-x) end
end

function GridNav.key(G, g, x, y, z)
  local obj = G.grid_map[x] and G.grid_map[x][y]
  if not obj then return end
  
  if z == 1 then GridNav.cache[x][y] = 15; if g then g:led(x, y, 15) end end
  if z == 0 and (obj.t == 'skip' or obj.t == 'flip' or obj.t == 'rec') then GridNav.cache[x][y] = -1 end

  if obj.t == 'edit' then if obj.id==1 then G.focus.edit_l=(z==1) end; if obj.id==2 then G.focus.edit_r=(z==1) end; return end
  
  if obj.t == 'petal' or obj.t == 'env' then 
    if z==1 then 
      G.focus.source=obj.id
      G.focus.last_dest=nil 
    elseif G.focus.source==obj.id then 
      G.focus.source=nil 
    end 
    return 
  end
  
  if (obj.t=='jack' or obj.t=='p_jack') then
    if z==1 then
      if G.focus.source then
        G.focus.dest=obj.id; G.focus.last_dest=obj.id; G.focus.dest_timer=util.time()
        clock.run(function() clock.sleep(0.8); if z==1 and G.focus.dest==obj.id then G.patch[G.focus.source][obj.id]=0.0; SC.update_matrix(obj.id,G) end end)
      else
        G.focus.inspect_dest = obj.id -- REVERSE LOOKUP TRIGGER
      end
    else
      if G.focus.source then
        if util.time()-G.focus.dest_timer<0.8 then if G.patch[G.focus.source][obj.id]==0 then G.patch[G.focus.source][obj.id]=0.5; SC.update_matrix(obj.id,G) end end
        G.focus.dest=nil
      else
        G.focus.inspect_dest = nil
      end
    end
    return
  end
  
  if z==1 and not G.focus.source then
    if obj.t=='rec' then local c=G.coco[obj.id]; c.rec=1-c.rec; SC.set_rec(obj.id,c.rec)
    elseif obj.t=='flip' then local c=G.coco[obj.id]; c.flip=c.flip*-1; SC.set_flip(obj.id,c.flip)
    elseif obj.t=='skip' then SC.set_skip(obj.id,1)
    elseif obj.t=='fader' then 
        local c=G.coco[obj.id]
        c.speed = G.SPEED_TABLE[obj.m]
        SC.set_speed(obj.id, math.abs(c.speed)) 
    end
  elseif z==0 then 
    if obj.t=='skip' then SC.set_skip(obj.id,0) end 
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
    if abs_spd > val_btn and abs_spd < val_next then
      local t = (abs_spd - val_btn) / (val_next - val_btn)
      return math.floor(util.linlin(0, 1, 12, 4, t)) 
    end
  end
  if btn_idx > 1 then
    local val_prev = table[btn_idx-1]
    if abs_spd > val_prev and abs_spd < val_btn then
      local t = (abs_spd - val_prev) / (val_btn - val_prev)
      return math.floor(util.linlin(0, 1, 4, 12, t))
    end
  end
  return bg
end

function GridNav.redraw(G, g)
  for x=1,16 do for y=1,8 do
    local obj=G.grid_map[x][y]; local b=0
    if obj then
      if obj.t=='edit' then b=((G.focus.edit_l and obj.id==1) or (G.focus.edit_r and obj.id==2)) and 15 or 4
      elseif obj.t=='petal' or obj.t=='env' then 
        -- REVERSE LOOKUP VISUALS
        if G.focus.inspect_dest then
           b = (G.patch[obj.id][G.focus.inspect_dest] ~= 0) and 15 or 2
        elseif G.focus.source==obj.id then b=15 
        else b=util.round(util.linlin(0,1,6,15,math.abs(G.sources_val[obj.id] or 0))) end
      
      elseif obj.t=='jack' or obj.t=='p_jack' then
        if G.focus.source then b=(G.patch[G.focus.source][obj.id]~=0) and 12 or 3
        elseif G.focus.inspect_dest==obj.id then b=15
        else b=(G.patch[1][obj.id]~=0) and 8 or 1 end 
      elseif obj.t=='rec' then local c=G.coco[obj.id]; b=(c.rec==1 or (c.gate_rec and c.gate_rec>0.5)) and 15 or 4
      elseif obj.t=='flip' then local c=G.coco[obj.id]; b=((c.flip == -1) or (c.gate_flip and c.gate_flip < -0.1)) and 15 or 4
      elseif obj.t=='skip' then local c=G.coco[obj.id]; b=(c.gate_skip and c.gate_skip > 0.5) and 15 or 4
      elseif obj.t=='fader' then
         local c=G.coco[obj.id]
         b = get_fader_bright(G, c.speed, obj.m)
      else b=4 end
    end
    if GridNav.cache[x][y]~=b then g:led(x,y,b); GridNav.cache[x][y]=b end
  end end
  g:refresh()
end
return GridNav