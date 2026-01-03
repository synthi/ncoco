-- lib/ui.lua v1027
-- CHANGELOG v1027:
-- 1. LAYOUT: Radars moved down +3px (Y: 35->38).
-- 2. METERS: Max height reduced by 5px (Mult: 36->31).

local Q = include('ncoco/lib/quantussy')
local UI = {}

local SRC_NAMES = {"PETAL 1","PETAL 2","PETAL 3","PETAL 4","PETAL 5","PETAL 6","ENV 1","ENV 2","YEL 1","YEL 2"}
local DST_NAMES = {
  [1]="SPD 1",[2]="AMP 1",[3]="FB 1",[4]="FILT 1",[5]="FLIP 1",[6]="SKIP 1",[7]="REC 1",
  [8]="SPD 2",[9]="AMP 2",[10]="FB 2",[11]="FILT 2",[12]="FLIP 2",[13]="SKIP 2",[14]="REC 2",
  [15]="P1 FRQ",[16]="P2 FRQ",[17]="P3 FRQ",[18]="P4 FRQ",[19]="P5 FRQ",[20]="P6 FRQ"
}
local DLB_NAMES = {
  [1]="OFF", [2]="G-IN", [3]="G-FB", 
  [4]="G-ALL", [5]="PUNCH-IN", [6]="PUNCH-OUT", 
  [7]="GI/PI", [8]="PO/GF", [9]="X-DUCK"
}
local BIT_NAMES = {[1]="8bit", [2]="12bit", [3]="16bit"}

local function get_trail(G, id) if not G.trails[id] then G.trails[id]={} end; return G.trails[id] end

function UI.update_histories(G)
  for i=1, 2 do
    if not G.trail_head[i] then G.trail_head[i]=1 end
    local head=G.trail_head[i]; G.trails[i][head]=G.coco[i].pos or 0
    G.trail_head[i]=(head % G.TRAIL_SIZE)+1
  end
  for i=1, 10 do
    local val = G.sources_val[i] or 0
    local hist = G.scope_history[i]
    if not G.scope_head then G.scope_head=1 end
    hist[G.scope_head] = val
  end
  G.scope_head = (G.scope_head % G.SCOPE_LEN) + 1
end

function UI.draw_scope(G, id, x, y, w, h, scale)
  local hist = G.scope_history[id]
  local head = G.scope_head
  local len = G.SCOPE_LEN
  screen.level(15)
  local last_px, last_py = nil, nil
  for i=0, w-1 do
    if i < len then
      local idx = (head - 1 - i - 1) % len + 1
      local val = util.clamp(hist[idx] * (scale or 1), 0, 1)
      local px = x + w - i
      local py = y + h - (val * h) 
      if last_px then screen.move(last_px, last_py); screen.line(px, py) else screen.pixel(px, py) end
      last_px = px; last_py = py
    end
  end
  screen.stroke()
end

function UI.draw_main(G)
  if (G.sources_val[7] > 0.95) or (G.sources_val[8] > 0.95) then screen.level(15); screen.rect(0,0,128,64); screen.stroke() end

  if G.focus.source then
    if G.focus.last_dest then UI.draw_patch_menu(G); return end
    if G.focus.source <= 6 then UI.draw_petal_inspector(G, G.focus.source)
    elseif G.focus.source <= 8 then UI.draw_env_inspector(G, G.focus.source) 
    else UI.draw_yellow_inspector(G, G.focus.source) end
    return
  end
  
  if G.focus.inspect_dest then UI.draw_dest_inspector(G, G.focus.inspect_dest); return end

  Q.draw(G) 
  -- MOVED DOWN 3px (35 -> 38)
  UI.draw_coco_radar(G, 1, 38, 50, 1)   
  UI.draw_coco_radar(G, 78, 38, 49, 2)  
  
  -- REDUCED METER HEIGHT (Multiplier 36 -> 31)
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
  screen.level(3); screen.move(2, 60); screen.text("E2:SPD "); screen.level(15); screen.text(string.format("%.2f", G.coco[1].real_speed or 1))
  screen.level(3); screen.move(85, 60); screen.text("E3:CHS"); screen.level(15); screen.move(126, 60); screen.text_right(string.format("%.0f%%", params:get("global_chaos")*100))
end

function UI.draw_dest_inspector(G, id)
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(64, 20); screen.text_center(DST_NAMES[id] or "DEST")
  
  screen.level(3); screen.move(126, 10); screen.text_right("IN GAIN:"); screen.level(15)
  screen.move(126, 18); screen.text_right(string.format("%.2fx", G.dest_gains[id]))
  
  screen.rect(10, 30, 108, 25); screen.stroke()
  
  if id==5 or id==6 or id==7 or id==12 or id==13 or id==14 then
     -- THRESHOLD 0.6 of 25px = 15px from bottom. Y = 55 - 15 = 40.
     local thresh_y = 40
     screen.level(2)
     for tx=10, 118, 4 do screen.pixel(tx, thresh_y) end
  end

  local head = G.scope_head; local len = G.SCOPE_LEN; local w, h = 108, 25; local center_y = 30 + h/2
  screen.level(15)
  for x=0, w-1 do
    local sum = 0
    local hist_idx = (head - 1 - x - 1) % len + 1
    for src=1, 10 do
      local amt = G.patch[src][id]
      if amt ~= 0 then sum = sum + (G.scope_history[src][hist_idx] * amt) end
    end
    sum = sum * G.dest_gains[id]
    local py = center_y - (util.clamp(sum, -1, 1) * (h/2))
    screen.pixel(10 + w - x, py); screen.fill()
  end
  screen.level(4); screen.move(10, 62); screen.text("E3: IN GAIN")
end

function UI.draw_petal_inspector(G, id)
  local p_range = params:get("p"..id.."range") or 1
  local p_id = (p_range==1) and "p"..id.."f_lfo" or "p"..id.."f_aud"
  local p = params:get(p_id) or 0
  
  local ch=params:get("p"..id.."chaos") or 0
  local shp_idx=params:get("p"..id.."shape") or 1
  local rng_idx=params:get("p"..id.."range") or 1
  local shp = shp_idx==1 and "TRI" or "S&H"
  local rng = rng_idx==1 and "LFO" or "AUD"

  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.move(120,10); screen.text_right(string.format("%.2f Hz", p))
  screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); 
  
  screen.level(4); screen.move(10,55); screen.text("E2:FREQ"); 
  screen.move(64,55); screen.text("E3:CHAOS"); screen.level(15); screen.move(126,55); screen.text_right(string.format("%.2f", ch))
  
  screen.level(4); screen.move(10,62); screen.text("K2:"..rng); 
  screen.move(64,62); screen.text("K3:"); screen.level(15); screen.move(126,62); screen.text_right(shp)
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
end

function UI.draw_yellow_inspector(G, id)
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); screen.level(4)
  screen.move(64,55); screen.text_center("ADDRESS NOISE")
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
  local dlb_idx = params:get("dolby"..side)

  local is_link = G.focus.edit_l and G.focus.edit_r
  local title = is_link and "[ < STEREO LINK > ]" or ("COCO "..id) 

  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(title); screen.move(120,10); screen.text_right("K3: "..(BIT_NAMES[bit_idx]))
  screen.move(10,30); screen.text("E1: FILT "..string.format("%.2f",filt)); screen.move(10,45); screen.text("E2: SPD "..string.format("%.2f",speed))
  screen.move(10,60); screen.text("E3: FB "..math.floor(fb*100).."%")
  screen.move(120,60); screen.text_right("K2: "..(DLB_NAMES[dlb_idx]))
end
function UI.draw_patch_menu(G)
  local src,dst=G.focus.source,G.focus.last_dest; if not src or not dst then return end
  local val=G.patch[src][dst] or 0; screen.level(0); screen.rect(10,10,108,44); screen.fill(); screen.level(15); screen.rect(10,10,108,44); screen.stroke()
  screen.move(64,25); screen.text_center("PATCHING..."); screen.move(64,35); screen.text_center(SRC_NAMES[src].." > "..DST_NAMES[dst])
  screen.move(64,40); screen.level(2); screen.line_rel(40,0); screen.move(64,40); screen.line_rel(-40,0); screen.stroke(); screen.level(15); screen.move(64,40); screen.line_rel(val*40,0); screen.stroke(); screen.circle(64+(val*40),40,2); screen.fill()
  
  -- LAYOUT FIX: Remove label, show only value
  screen.level(15); screen.move(115, 20); screen.text_right(string.format("%.0f%%",val*100))
  
  UI.draw_scope(G,src,30,45,68,10,math.abs(val))
end
return UI
