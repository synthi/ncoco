-- lib/quantussy.lua v1033
-- CHANGELOG v1033:
-- 1. LAYOUT: Center moved down +3px (Y: 15->18).
-- 2. ANIMATION: Brightness is now linked to petal size (val). 
--    Small petals are dim, big petals are bright.

local Q = {}
local cx, cy = 64, 18 -- Moved +3px down
local r = 13
Q.coords = {}
Q.history = {} 

for i=1, 6 do
  local angle = (i-1) * 60 - 120 
  local rad = math.rad(angle)
  Q.coords[i] = { x = cx + r * math.cos(rad), y = cy + r * math.sin(rad) }
  Q.history[i] = {}
  for j=1, 6 do Q.history[i][j] = 0 end
end

function Q.draw(G) 
  for i=1, 6 do
    local p = Q.coords[i]
    local val = G.sources_val[i] or 0
    local chaos = params:get("p"..i.."chaos") or 0
    local shape = params:get("p"..i.."shape") or 1
    
    table.remove(Q.history[i], 1)
    table.insert(Q.history[i], val)
    
    local theta = (util.time() * chaos * 8) + (val * math.pi)
    local vib_x = (math.random() - 0.5) * chaos * 3
    local vib_y = (math.random() - 0.5) * chaos * 3
    
    local w_ratio = 1
    if shape == 2 then 
       w_ratio = 1 + (math.sin(util.time()*10) * chaos * 0.5)
    end
    
    -- MATRIX DRAWING FUNCTION
    local function draw_rot_rect(x, y, size, angle, level)
      screen.level(level)
      screen.save() -- Save matrix state
      screen.translate(x, y) -- Move origin to petal center
      screen.rotate(angle)   -- Rotate canvas
      
      -- Squash & Stretch (S&H only)
      local w = size * w_ratio
      local h = size / w_ratio
      
      screen.rect(-w/2, -h/2, w, h) -- Draw centered
      screen.fill()
      
      screen.restore() -- Restore matrix
    end

    -- Draw Trails (Static Rotation for ghost effect)
    for j=1, 4 do
      local h_val = Q.history[i][j]
      local h_size = util.linlin(0, 1, 1, 9, h_val)
      -- Trails drift slightly due to vibration but don't rotate as fast
      draw_rot_rect(p.x + vib_x + (math.random()-0.5)*chaos*5, 
                    p.y + vib_y + (math.random()-0.5)*chaos*5, 
                    h_size, theta - (j*0.5), math.floor(10 / (5-j)))
    end

    -- Draw Main
    local size = util.linlin(0, 1, 1, 9, val)
    
    -- BRIGHTNESS MODULATION (Small = Dim, Big = Bright)
    -- Map value 0.0-1.0 to Brightness 4-15
    local bright = math.floor(util.linlin(0, 1, 4, 15, val))
    
    draw_rot_rect(p.x + vib_x, p.y + vib_y, size, theta, bright)
  end
end
return Q
