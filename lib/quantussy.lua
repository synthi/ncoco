-- lib/quantussy.lua v3002
-- CHANGELOG v3002:
-- 1. CRIT FIX: Restored Q.coords initialization (Fixed "nil value 'p'" crash).
-- 2. LOGIC: Properly switch between Solid Rect (LFO) and Nebula Points (Audio).
-- 3. VISUAL: Improved Nebula rendering using screen.fill() for visibility.

local Q = {}
local cx, cy = 64, 18 -- Center coordinates
local r = 13           -- Base radius
Q.coords = {}
Q.history = {} 

-- 1. Initialize Hexagon Coordinates (CRITICAL FIX)
for i=1, 6 do
  local angle = (i-1) * 60 - 120 
  local rad = math.rad(angle)
  Q.coords[i] = { x = cx + r * math.cos(rad), y = cy + r * math.sin(rad) }
  Q.history[i] = {}
  for j=1, 6 do Q.history[i][j] = 0 end
end

-- 2. Pre-calculate offsets for the "nebula" effect
local NEBULA_POINTS = 12
local NEBULA_OFFSETS = {}
for i = 1, NEBULA_POINTS do
  local angle = math.rad((i-1) * (360 / NEBULA_POINTS))
  -- Randomize slightly to make it less perfect circle, more "cloud"
  local dist = r * (0.5 + (math.random() * 0.4)) 
  local offset_x = math.cos(angle) * dist
  local offset_y = math.sin(angle) * dist
  table.insert(NEBULA_OFFSETS, {x = offset_x, y = offset_y})
end

function Q.draw(G) 
  for i=1, 6 do
    local p = Q.coords[i]
    if not p then return end -- Safety check
    
    local val = G.sources_val[i] or 0
    local chaos = params:get("p"..i.."chaos") or 0
    local shape_idx = params:get("p"..i.."shape") or 1
    local range_idx = params:get("p"..i.."range") or 1
    
    -- Frequency for spin calculation
    local freq_param = (range_idx==1) and "p"..i.."f_lfo" or "p"..i.."f_aud"
    local freq = params:get(freq_param) or 100
    
    local is_audio = (range_idx == 2)
    local shape = shape_idx -- 1=Tri, 2=Castle
    
    -- Update history
    table.remove(Q.history[i], 1)
    table.insert(Q.history[i], val)
    
    -- Base rotation and vibration
    local base_theta = (util.time() * chaos * 8)
    local vib_x = (math.random() - 0.5) * chaos * 3
    local vib_y = (math.random() - 0.5) * chaos * 3
    
    -- Audio Mode Spin
    local freq_spin = 0
    if is_audio then 
      -- Map 20Hz-2000Hz to rotation speed
      freq_spin = util.time() * util.linlin(20, 2000, 1, 20, freq) 
    end
    local total_theta = base_theta + freq_spin
    
    local size = util.linlin(0, 1, 1, 9, val)
    local bright = math.floor(util.linlin(0, 1, 4, 15, val))

    -- DRAWING FUNCTION (Switches logic based on mode)
    local function draw_shape(x, y, sz, angle, level, audio_mode)
      screen.level(level)
      screen.save() 
      screen.translate(x, y) 
      screen.rotate(angle)   
      
      local w_ratio = 1
      if shape == 2 then -- S&H shape modifier (Castle)
         w_ratio = 1 + (math.sin(util.time()*10) * chaos * 0.5)
      end
      
      if audio_mode then
        -- === NEBULA MODE (Points) ===
        for j = 1, NEBULA_POINTS do
           local off = NEBULA_OFFSETS[j]
           -- Scale offset by current size/envelope
           local px = off.x * (sz / r) * w_ratio
           local py = off.y * (sz / r) / w_ratio
           
           -- Add jitter (Electron cloud effect)
           px = px + (math.random()-0.5) * 2
           py = py + (math.random()-0.5) * 2
           
           screen.pixel(px, py)
        end
        screen.fill() -- Render points
      else
        -- === LFO MODE (Solid Rect) ===
        local w = sz * w_ratio
        local h = sz / w_ratio
        screen.rect(-w/2, -h/2, w, h)
        screen.fill() -- Render solid
      end
      
      screen.restore() 
    end

    -- Draw Trails
    for j=1, 4 do
      local h_val = Q.history[i][j]
      local h_size = util.linlin(0, 1, 1, 9, h_val)
      local h_bright = math.floor(10 / (5-j)) 
      -- Trails spin slower in audio mode to create a "blur" effect
      local trail_angle = is_audio and (total_theta - (j*0.2)) or (total_theta - (j*0.5))
      
      draw_shape(p.x + vib_x + (math.random()-0.5)*chaos*5, 
                 p.y + vib_y + (math.random()-0.5)*chaos*5, 
                 h_size, trail_angle, h_bright, is_audio)
    end

    -- Draw Main Element
    draw_shape(p.x + vib_x, p.y + vib_y, size, total_theta, bright, is_audio)
  end
end
return Q