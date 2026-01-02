-- lib/ui.lua v600 (CLEANED)
local Q = include('ncoco/lib/quantussy')
local UI = {}

local SRC_NAMES = {"PETAL 1","PETAL 2","PETAL 3","PETAL 4","PETAL 5","PETAL 6","ENV L","ENV R"}
local DST_NAMES = {
  [1]="SPD L",[2]="AMP L",[3]="FB L",[4]="FILT L",[5]="FLIP L",[6]="SKIP L",[7]="REC L",
  [8]="SPD R",[9]="AMP R",[10]="FB R",[11]="FILT R",[12]="FLIP R",[13]="SKIP R",[14]="REC R",
  [15]="P1 FRQ",[16]="P2 FRQ",[17]="P3 FRQ",[18]="P4 FRQ",[19]="P5 FRQ",[20]="P6 FRQ"
}

local function get_trail(G, id) if not G.trails[id] then G.trails[id]={} end; return G.trails[id] end

function UI.update_histories(G)
  for i=1, 2 do
    if not G.trail_head[i] then G.trail_head[i]=1 end
    local head=G.trail_head[i]; G.trails[i][head]=G.coco[i].pos or 0
    G.trail_head[i]=(head % G.TRAIL_SIZE)+1
  end
  for i=1, 8 do
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
      local val = hist[idx] * (scale or 1)
      local px = x + w - i
      local py = y + (h/2) - (val * (h/2))
      if last_px then screen.move(last_px, last_py); screen.line(px, py) else screen.pixel(px, py) end
      last_px = px; last_py = py
    end
  end
  screen.stroke()
end

function UI.draw_main(G)
  -- NOT calling update_histories here.
  if (G.sources_val[7] > 0.95) or (G.sources_val[8] > 0.95) then screen.level(15); screen.rect(0,0,128,64); screen.stroke() end

  if G.focus.source then
    if G.focus.last_dest then UI.draw_patch_menu(G); return end
    if G.focus.source <= 6 then UI.draw_petal_inspector(G, G.focus.source)
    elseif G.focus.source <= 8 then UI.draw_env_inspector(G, G.focus.source) end
    return
  end
  
  if G.focus.inspect_dest then UI.draw_dest_inspector(G, G.focus.inspect_dest); return end

  Q.draw(G) 
  UI.draw_coco_radar(G, 10, 35, 40, 1)
  UI.draw_coco_radar(G, 78, 35, 40, 2)
  
  local el = math.pow(G.sources_val[7] or 0, 0.25)
  local er = math.pow(G.sources_val[8] or 0, 0.25)
  screen.level(15)
  screen.rect(58, 64, 3, -(el * 45)); screen.fill()
  screen.rect(68, 64, 3, -(er * 45)); screen.fill()
  
  screen.level(2)
  screen.move(2, 8); screen.text("E1:VOL " .. string.format("%.1f", params:get("global_vol") or 1))
  screen.move(2, 60); screen.text("E2:SPD " .. string.format("%.2f", G.coco[1].speed))
  screen.move(126, 60); screen.text_right("E3:CHS " .. string.format("%.0f%%", (G.petals[1].chaos)*100))
end

function UI.draw_dest_inspector(G, id)
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(64, 20); screen.text_center(DST_NAMES[id] or "DEST")
  screen.rect(10, 30, 108, 25); screen.stroke()
  local head = G.scope_head; local len = G.SCOPE_LEN; local w, h = 108, 25; local center_y = 30 + h/2
  screen.level(15)
  for x=0, w-1 do
    local sum = 0
    local hist_idx = (head - 1 - x - 1) % len + 1
    for src=1, 8 do
      local amt = G.patch[src][id]
      if amt ~= 0 then sum = sum + (G.scope_history[src][hist_idx] * amt) end
    end
    local py = center_y - (util.clamp(sum, -1, 1) * (h/2))
    screen.pixel(10 + w - x, py); screen.fill()
  end
  screen.level(4); screen.move(64, 62); screen.text_center("INCOMING SIGNAL")
end

function UI.draw_petal_inspector(G, id)
  local p=G.petals[id]; screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.move(120,10); screen.text_right(string.format("%.2f Hz", p.freq))
  screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); screen.level(4)
  screen.move(10,55); screen.text("E2:FREQ E3:CHAOS"); screen.move(10,62); screen.text("K2:"..(p.range==0 and "LFO" or "AUD").." K3:"..(p.shape==0 and "TRI" or "S&H"))
end
function UI.draw_env_inspector(G, id)
  local p=G.input[id-6]; screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(SRC_NAMES[id]); screen.rect(10,20,108,25); screen.stroke(); UI.draw_scope(G,id,10,20,108,25,1); screen.level(4)
  screen.move(10,55); screen.text("E2:PREAMP "..string.format("%.1fx",p.preamp)); screen.move(120,55); screen.text_right("E3:SLEW "..string.format("%.2f",p.slew))
end
function UI.draw_coco_radar(G, x, y, w, id)
  local c=G.coco[id]; if not c then return end; screen.level(1); screen.rect(x,y,w,10); screen.stroke()
  local trail=G.trails[id]; local head=G.trail_head[id]
  for i=0, G.TRAIL_SIZE-1 do local idx=(head-1-i-1)%G.TRAIL_SIZE+1; local b=math.floor(15*(0.6^i)); if b>0 then screen.level(b); screen.rect(x+(trail[idx]*w),y+1,2,8); screen.fill() end end
  if c.rec==1 or (c.gate_rec and c.gate_rec>0.5) then screen.level(15); screen.rect(x+(c.pos*w),y-3,2,2); screen.fill() end
end
function UI.draw_edit_menu(G, id)
  local c=G.coco[id]; if not c then return end; local l=G.focus.edit_l and G.focus.edit_r
  screen.level(0); screen.rect(0,0,128,64); screen.fill(); screen.level(15)
  screen.move(5,10); screen.text(l and "[ LINK ]" or (id==1 and "COCO L" or "COCO R")); screen.move(120,10); screen.text_right("K3: "..(c.bits or 8).." BIT")
  screen.move(10,30); screen.text("E1: FILT "..string.format("%.2f",c.filt)); screen.move(10,45); screen.text("E2: SPD "..string.format("%.2f",c.speed))
  screen.move(10,60); screen.text("E3: FB "..math.floor((c.vol_fb or 0)*100).."%")
end
function UI.draw_patch_menu(G)
  local src,dst=G.focus.source,G.focus.last_dest; if not src or not dst then return end
  local val=G.patch[src][dst] or 0; screen.level(0); screen.rect(10,10,108,44); screen.fill(); screen.level(15); screen.rect(10,10,108,44); screen.stroke()
  screen.move(64,25); screen.text_center("PATCHING..."); screen.move(64,35); screen.text_center(SRC_NAMES[src].." > "..DST_NAMES[dst])
  screen.move(64,40); screen.level(2); screen.line_rel(40,0); screen.move(64,40); screen.line_rel(-40,0); screen.stroke(); screen.level(15); screen.move(64,40); screen.line_rel(val*40,0); screen.stroke(); screen.circle(64+(val*40),40,2); screen.fill()
  screen.level(4); screen.move(10,55); screen.text("E3: AMT "..string.format("%.0f%%",val*100))
  UI.draw_scope(G,src,30,45,68,10,math.abs(val))
end
return UI