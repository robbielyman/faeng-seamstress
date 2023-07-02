return function(ROWS)

  local ACCIDENTAL = { -1, -0.5, -0.25, 0, 0.25, 0.5, 1 }
  local DURATION = { 1/32, 1/16, 1/12, 1/8, 1/4, 1/2}
  local INTERP = function(x)
    return util.round(util.linlin(1, ROWS-1, 1, 127, x))
  end
  CC = INTERP
  MODWHEEL = INTERP
  PRESSURE = INTERP

  local function Play_Note(track)
    Playing[track.id] = 0
    if track:get('trigger') == 0 then return end
    local note = track:get('note') + track:get('alt_note')
    note = Scale(note) + 12 * (track:get('octave') - 3)
    note = note + ACCIDENTAL[track:get('accidental')]
    local velocity = track:get('velocity')
    local duration = DURATION[track:get('trigger')]
    Manage_Polyphony(note, velocity, duration, track.id)
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
    data = 6,
    display = bar(6)
  }

  local note = {}

  local octave = {
    min = 3,
    max = 7,
    display = bar(3),
  }

  local accidental = {
    min = 3,
    max = 7,
    display = bar(3),
  }

  local ratchet = {
    priority = 5,
    data = 4,
    counter = 12,
    min = 3,
    max = 7,
    display = function (datum, check, current, counter)
      local ratchet_amount = datum & 3
      local ratchets = datum >> 2
      local lights = {}
      local j
      if current then
        local out_of_twelve = (counter - 1) % 12 + 1
        j = out_of_twelve // (12 / (ratchet_amount + 1))
      end
      for i = 0, ratchet_amount do
        if ratchets & 2^i == 2^i then
          if i == j then
            table.insert(lights, {7-i, 15})
          else
            table.insert(lights, {7-i, check and 9 or 4})
          end
        end
      end
      return lights
    end,
    key = function (y, current)
      local ratchet_amount = current & 3
      local ratchets = current >> 2
      if 7 - y > ratchet_amount then
        -- add new bits
        for i = ratchet_amount + 1, 7 - y do
          ratchets = ratchets ~ 2^i
        end
        ratchet_amount = 7 - y
      else
        ratchets = ratchets ~ 2^(7 - y)
      end
      if ratchets == 0 then
        -- reset
        ratchets = 1
        ratchet_amount = 0
      end
      return (ratchets << 2) | ratchet_amount
    end,
    action = function (track, name, datum, counter)
      track:set(name, datum)
      local ratchet_div = 12 / ((datum & 3) + 1)
      local ratchets = datum >> 2
      local out_of_twelve = (counter - 1) % 12 + 1
      if counter % ratchet_div == 1 then
        local step = 2^((out_of_twelve - 1) / ratchet_div)
        if step & ratchets == step then Play_Note(track) end
      end
    end,
  }

  local velocity = {
    data = 5,
    min = 2,
    max = 7,
    display = bar(5),
  }

  local alt_note = {}
  local cc = {
    display = bar(1),
    action = function (track, name, datum, _)
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

  local Pages = {
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
    },
    length = 8,
    division = { 1, 16 },
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
    key = function (y, _) return ROWS - y end,
    display = indicator,

    trigger = trigger,
    note = note,
    ocatve = octave,
    accidental = accidental,
    ratchet = ratchet,
    velocity = velocity,
    alt_note = alt_note,
    cc = cc,
    mod_wheel = mod_wheel,
    pressure = pressure,
  }
  Pages.__index = function(key)
    if type(key) == 'number' and 1 <= key and key <= 10 then
      return Pages[Pages.pages[key]]
    end
  end
  trigger.__index = Pages
  note.__index = Pages
  octave.__index = Pages
  accidental.__index = Pages
  ratchet.__index = Pages
  velocity.__index = Pages
  alt_note.__index = Pages
  cc.__index = Pages
  mod_wheel.__index = Pages
  pressure.__index = Pages

  return Pages
end
