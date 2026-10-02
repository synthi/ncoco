-- Group was declared 18 but only 17 params follow it: "Volume 2" landed
-- inside COCO 1 and COCO 2's params ended up ungrouped.
-- v3.00: count corrected to 17. This test guards the number.
local f = io.open('lib/param_set.lua', 'r')
local src = f:read('*a'); f:close()

local lines = {}
for line in src:gmatch('[^\n]+') do lines[#lines+1] = line end

-- Find the add_group("COCO ...") line, then count params:add_* until the next
-- add_group (the following PETAL group).
local start_i
for i, line in ipairs(lines) do
  if line:match('add_group%("COCO "%s*%.%.%s*num, (%d+)') then
    declared = tonumber(line:match('add_group%("COCO "%s*%.%.%s*num, (%d+)'))
    start_i = i
    break
  end
end
assert(start_i, "no se encontro el grupo COCO")

local count = 0
for i = start_i + 1, #lines do
  if lines[i]:match('add_group') then break end
  local t = lines[i]:gsub('^%s+', '')
  if t:match('^%-%-') then goto continue end          -- commented-out duplicate
  if t:match('^params:add') then count = count + 1 end
  ::continue::
end

print(("declarado: %d   real: %d"):format(declared, count))
if declared ~= count then
  print("FALLA: el conteo no coincide")
  os.exit(1)
end
print("PASA  el grupo COCO declara exactamente los params que tiene")