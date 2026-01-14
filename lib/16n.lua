-- lib/16n.lua v3007
-- CHANGELOG v3007:
-- 1. ROLLBACK: Removed "Smart Wake-Up" filter completely.
--    Reason: The filter was blocking smooth 1-step movements, turning them into steps/zipper noise.
--    Resolution (128 steps) is restored. Audio should be smooth.

local _16n = {}
_16n.last_values = {}

_16n.request_sysex_config_dump = function(midi_dev) 
  if midi_dev then 
     print("16n: Requesting config dump...")
     midi.send(midi_dev, {0xf0, 0x7d, 0x00, 0x00, 0x1f, 0xf7}) 
  end
end

_16n.is_sysex_config_dump = function(sysex_payload) return (sysex_payload[2] == 0x7d and sysex_payload[3] == 0x00 and sysex_payload[4] == 0x00 and sysex_payload[5] == 0x0f) end

_16n.parse_sysex_config_dump = function(sysex_payload)
  local i = 6 + 4; local usb_cc_list = {}
  for fader_i=0, 16-1 do table.insert(usb_cc_list, sysex_payload[i+64+fader_i]) end
  return { usb_cc = usb_cc_list }
end

local dev_16n, midi_16n, conf_16n = nil, nil, nil

_16n.init = function(cc_cb_fn)
  for _,dev in pairs(midi.devices) do
    if dev.name~=nil and (string.find(string.lower(dev.name), "16n") or string.find(string.lower(dev.name), "fade")) then
      print("16n: Found device: " .. dev.name)
      dev_16n = dev; midi_16n = midi.connect(dev.port)
      
      local is_sysex_dump_on = false; local sysex_payload = {}
      
      midi_16n.event=function(data)
        local d=midi.to_msg(data)
        if is_sysex_dump_on then
          for _, b in pairs(data) do table.insert(sysex_payload, b)
            if b == 0xf7 then 
                is_sysex_dump_on = false
                if _16n.is_sysex_config_dump(sysex_payload) then 
                   print("16n: Config dump received!")
                   conf_16n = _16n.parse_sysex_config_dump(sysex_payload) 
                end 
            end
          end
        elseif d.type == 'sysex' then 
            is_sysex_dump_on = true
            sysex_payload = {}
            for _, b in pairs(d.raw) do table.insert(sysex_payload, b) end
        elseif d.type == 'cc' and cc_cb_fn ~= nil then 
           local last = _16n.last_values[d.cc] or -1
           
           -- RESTORED ORIGINAL LOGIC: Pass every single change
           if d.val ~= last then
             _16n.last_values[d.cc] = d.val
             cc_cb_fn(d) 
           end
        end
      end
      _16n.request_sysex_config_dump(dev_16n)
      break
    end
  end
end

_16n.cc_2_slider_id = function(cc) 
  local id = nil
  
  -- 1. Try Config from SysEx first
  if conf_16n ~= nil then
     for i, slider_cc in pairs(conf_16n.usb_cc) do 
        if slider_cc == cc then 
            id = i
            break
        end 
     end
  end
  
  -- 2. CASCADE FALLBACK
  if id == nil then
     if cc >= 32 and cc <= 47 then
        id = (cc - 32) + 1
     end
  end
  
  return id 
end

return _16n