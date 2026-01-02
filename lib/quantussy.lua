-- lib/quantussy.lua v506
local Q = {}
local cx, cy = 64, 15
local r = 10 
Q.coords = {}
for i=1, 6 do
  local angle = (i-1) * 60 - 90
  local rad = math.rad(angle)
  Q.coords[i] = { x = cx + r * math.cos(rad), y = cy + r * math.sin(rad) }
end

function Q.draw(G) 
  for i=1, 6 do
    local p = Q.coords[i]
    local val = G.sources_val[i] or 0
    local size = util.linlin(-1, 1, 3, 8, val)
    local offset = size/2
    screen.level(math.floor(util.linlin(-1, 1, 3, 15, val)))
    screen.rect(p.x - offset, p.y - offset, size, size)
    screen.fill()
  end
end
return Q