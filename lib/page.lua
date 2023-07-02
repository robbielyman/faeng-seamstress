return function(ROWS)
  local ACCIDENTAL = { -1, 0, 1 }
  local DURATION = { 1/2, 1/4, 1/6, 1/8, 1/12, 1/16, 1/32 } 
  local INTERP = function(x)
    return util.round(util.linlin(1, ROWS - 1, 1, 127, x))
  end
  CC = INTERP
  MODWHEEL = INTERP
  PRESSURE = INTERP

  local function Play_Note(track)
    Playing[track.id] = 0
    if track:get('trigger') == 0 then return end
    local note = track:get('note') + track:get('alt_note')
    note = Scale(note) + 12 * (track:get('octave') - 3)
    note = note + ACCIDENTAL[track:get('accidental') - 2]
    local velocity = INTERP(track:get('velocity'))
    local duration = DURATION[track:get('trigger')]
    Manage_Polyphony(note, velocity, duration, track.id)
    Playing[track.id] = 1
  end

  local function indicator(datum, check, current, _)
    if current then
      return { { ROWS - datum, 15 } }
    else
      return { { ROWS - datum, check and 9 or 4 } }
    end
  end

  local bar = function(center)
    return function(datum, check, current, _)
      local lights = indicator(datum, check, current, _)
      if datum > center then
        for i = center, datum - 1 do
          table.insert(lights, { ROWS - i, check and 9 or 4 })
        end
      elseif datum < center then
        for i = center - 1, datum + 1, -1 do
          table.insert(lights, { ROWS - i, check and 9 or 4 })
        end
      end
      return lights
    end
  end

  local trigger = {
    data = 0,
    display = function(datum, check, current, _)
      if datum == 0 then
        if current then return { { ROWS - 6, 15 }} end
        return { {ROWS - 6, check and 4 or 1} }
      else
        return bar(7)(datum, check, current, _)
      end
    end,
    key = function (y, current)
      if current == 0 then
        return ROWS - y
      end
      if ROWS - y == current then return 0 end
      return ROWS - y
    end
  }

  local note = {}

  local octave = {
    data = 3,
    min = 3,
    max = 7,
    display = bar(3),
  }

  local accidental = {
    data = 4,
    min = 3,
    max = 5,
  }

  local ratchet = {
    priority = 5,
    data = 4,
    counter = 12,
    min = 4,
    max = 7,
    display = function(datum, check, current, counter)
      local ratchet_amount = datum & 3
      local ratchets = datum >> 2
      local lights = {}
      local j
      if current then
        local out_of_twelve = (counter - 1) % 12 + 1
        j = out_of_twelve // (12 / (ratchet_amount + 1))
      end
      for i = 0, ratchet_amount do
        if ratchets & 2 ^ i == 2 ^ i then
          if i == j then
            table.insert(lights, { 7 - i, 15 })
          else
            table.insert(lights, { 7 - i, check and 9 or 4 })
          end
        end
      end
      return lights
    end,
    key = function(y, current)
      local ratchet_amount = current & 3
      local ratchets = current >> 2
      if 7 - y > ratchet_amount then
        -- add new bits
        for i = ratchet_amount + 1, 7 - y do
          ratchets = ratchets ~ 2 ^ i
        end
        ratchet_amount = 7 - y
      else
        ratchets = ratchets ~ 2 ^ (7 - y)
      end
      if ratchets == 0 then
        -- reset
        ratchets = 1
        ratchet_amount = 0
      end
      return (ratchets << 2) | ratchet_amount
    end,
    action = function(track, name, datum, counter)
      track:set(name, datum)
      local ratchet_div = 12 / ((datum & 3) + 1)
      local ratchets = datum >> 2
      local out_of_twelve = (counter - 1) % 12 + 1
      if counter % ratchet_div == 1 then
        local step = 2 ^ ((out_of_twelve - 1) / ratchet_div)
        if step & ratchets == step then Play_Note(track) end
      end
    end,
  }

  local velocity = {
    data = 5,
    display = bar(5),
  }

  local alt_note = {}
  local cc = {
    display = bar(1),
    action = function(track, name, datum, _)
      track:set(name, datum)
      Midi:cc(71, CC(datum), track.id)
    end
  }
  local mod_wheel = {
    display = bar(1),
    action = function(track, name, datum, _)
      track:set(name, datum)
      Midi:cc(1, MODWHEEL(datum), track.id)
    end,
  }
  local pressure = {
    display = bar(1),
    action = function(track, name, datum, _)
      track:set(name, datum)
      Midi:channel_pressure(PRESSURE(datum), track.id)
    end,
  }

  local default = {
    length = 8,
    division_1 = 1,
    division_2 = 16,
    probability = 4,
    data = 1,
    swing = 8,
    priority = 3,
    min = 1,
    max = ROWS - 1,
    counter = 1,
    action = function(track, name, datum, _)
      track:set(name, datum)
    end,
    key = function(y, _) return ROWS - y end,
    display = indicator,
  }

  local Pages = {
    trigger,
    note,
    octave,
    accidental,
    ratchet,
    velocity,
    alt_note,
    cc,
    mod_wheel,
    pressure,

    pages = {
      'trigger',
      'note',
      'octave',
      'accidental',
      'ratchet',

      'velocity',
      'alt_note',
      'mod_wheel',
      'pressure',
      'cc'

    }
  }
  setmetatable(Pages, { __index = default })
  setmetatable(trigger, { __index = default })
  setmetatable(note, { __index = default })
  setmetatable(octave, { __index = default })
  setmetatable(accidental, { __index = default })
  setmetatable(ratchet, { __index = default })
  setmetatable(velocity, { __index = default })
  setmetatable(alt_note, { __index = default })
  setmetatable(cc, { __index = default })
  setmetatable(mod_wheel, { __index = default })
  setmetatable(pressure, { __index = default })

  return Pages
end
