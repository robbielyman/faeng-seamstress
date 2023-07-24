--- faeng is a sequencer
-- @script faeng

local sequins = require "sequins"
local lattice = require "lattice"
local musicutil = require "musicutil"
local counter = 0

Grid = grid.connect()
Presses = {}
Press_Counter = {}
Playing = {}
TRACKS = 7
ROWS = 8
Tracks = {}
PATTERNS = 16
PAGES = 5
Page = 0
Playing = {}
Alt_Page = false
Pattern = 1
MODS = 3
Mod = 0
SubSequins = 0
Active_Track = 1
Grid_Dirty = true
Scale_Names = {}
Lattice = lattice.new()
for i = 1, #musicutil.SCALES do
  table.insert(Scale_Names, musicutil.SCALES[i].name)
end
Dance_Index = 1
Midi = midi.connect_output()

Scale = nil

local Trackmaker = require 'lib.track'
Track = nil
local Pagemaker = require "lib.page"
Pages = nil
local Notes = {}

local function note_on(note, velocity, duration, id)
  table.insert(Notes[id], note)
  clock.sync(duration / 16)
  Midi:note_on(note, velocity, id)
  clock.sync(duration, duration)
  Midi:note_off(note, 0, id)
  clock.sleep(0.5)
  local key = tab.key(Notes[id], note)
  if key then table.remove(Notes[id], key) end
end

function Manage_Polyphony(note, velocity, duration, id)
  clock.run(note_on, note, velocity, duration, id)
end

local function build_scale()
  local note_nums = musicutil.generate_scale_of_length(params:get('root_note'), params:get('scale'), 127)
  Scale = function(note)
    if note_nums then
      return note_nums[note]
    end
  end
end

local function nav_bar(x, z)
  if x == 1 then
    -- track button
    if z == 0 then
      if SubSequins > 0 then
        SubSequins = 0
      elseif SubSequins == 0 then
        -- enter track view
        Page = 0
        Mod = 0
        Alt_Page = false
      end
    end
    return z
  elseif x == 3 then
    -- scroll left
    if z == 0 then
      Active_Track = Active_Track - 1 < 1 and TRACKS or Active_Track - 1
      redraw()
    end
    return z
  elseif x == 4 then
    -- scroll right
    if z == 0 then
      Active_Track = Active_Track + 1 > TRACKS and 1 or Active_Track + 1
      redraw()
    end
    return z
  elseif x >= 5 + 1 and x <= 5 + PAGES then
    if z ~= 0 then return z end
    if Page == x - 5 then
      -- active page pressed; toggle alt page
      Alt_Page = not Alt_Page
    end
    Page = x - 5
    SubSequins = 0
    return z
  elseif x >= 5 + PAGES + 1 + 1 and x <= 5 + PAGES + 1 + MODS then
    if z ~= 0 then return z end
    if Mod == x - (5 + PAGES + 1) then
      -- active mod pressed
      Mod = 0
    elseif Page ~= 0 then
      Mod = x - (5 + PAGES + 1)
      SubSequins = 0
    end
    return z
  elseif x == 16 then
    -- pattern page pressed
    if z == 0 then
      Mod = 0
      SubSequins = 0
      Page = -1
    end
    return z
  end
end

function loop_mod(x, y, z)
  local track = Tracks[Active_Track]
  local page = Page
  if Page == -1 then
    track = Tracks[TRACKS + 1]
  end
  if Alt_Page then page = page + PAGES end
  if z ~= 0 then return z end
  for i = 1, 16 do
    if Presses[i][y] == 1 and i ~= x then
      -- set new bounds
      if i < x then
        return z, i, x
      else
        return z, x, x
      end
    end
  end
  -- move bounds
  local length
  if track.type == 'track' then
    length = track.bounds[page][Pattern][2] - track.bounds[page][Pattern][1]
  else
    length = track.bounds[2] - track.bounds[1]
  end
  return z, x, math.min(x + length, 16)
end

function handle_subsequins(x, y, z, handler, default)
  if z ~= 0 then return z end
  local track = Tracks[Active_Track]
  local page = Page
  if Page == -1 then
    track = Tracks[TRACKS + 1]
  end
  if Alt_Page then page = page + PAGES end
  local datum
  if track.type == 'track' then
    datum = track.data[page][Pattern][SubSequins]
  else
    datum = track.data[SubSequins]
  end
  if Presses[1][y] == 1 and 1 ~= x then
    -- alter SubSequins length
    if x > #datum then
      for i = #datum, x do
        datum[i] = default
      end
    elseif x < #datum then
      for i = x + 1, #datum do
        datum[i] = nil
      end
    end
    return z
  elseif x == 1 then
    for i = 2, 16 do
      if Presses[i][y] == 1 then
        -- remove SubSequins, exit SubSequins mode
        datum = datum[1]
        SubSequins = 0
        return z
      end
    end
  end
  datum[x] = handler(y, datum[x])
  return z
end

function grid_long_press(x, y)
  clock.sleep(1)
  Press_Counter[x][y] = nil
  if y == 8 or Mod > 0 or SubSequins > 0 then return end
  if Page == -1 and y == 1 then
    -- copy pattern
    for i = 1, TRACKS do
      local track = Tracks[i]
      track:copy(Tracks[TRACKS + 1].data[Tracks[TRACKS + 1].selected], x)
    end
    Grid_Dirty = true
    redraw()
  elseif Page == -1 and y == 4 then
    SubSequins = x
    Grid_Dirty = true
    redraw()
  else
    SubSequins = x
    Grid_Dirty = true
    redraw()
  end
end

local function patterns_key(x, y, z)
  if Mod == 1 and y == 4 then
    local press, left, right = loop_mod(x, y, z)
    if left and right then
      Tracks[TRACKS + 1].bounds[1] = left
      Tracks[TRACKS + 1].bounds[2] = right
    end
    return press
  end
  if SubSequins > 0 and y == 4 then
    return handle_subsequins(x, y, z, function(_, current)
      if x <= #Tracks[TRACKS + 1].data[SubSequins] then
        Tracks[TRACKS + 1].selected = x
      end
      Tracks[TRACKS + 1]:make_sequins()
      return current
    end, 1)
  end
  if SubSequins > 0 and y == 1 then
    if z ~= 0 then return z end
    -- set selection
    Tracks[TRACKS + 1].data[SubSequins][Tracks[TRACKS + 1].selected] = x
    Tracks[TRACKS + 1]:make_sequins()
    return z
  end
  if y == 1 then
    if z ~= 0 then
      Press_Counter[x][y] = clock.run(grid_long_press, x, y)
      return z
    end
    if not Press_Counter[x][y] then return z end
    clock.cancel(Press_Counter[x][y])
    Tracks[TRACKS + 1].data[Tracks[TRACKS + 1].selected] = x
    Tracks[TRACKS + 1]:make_sequins()
    return z
  end
  if y == 4 then
    if z ~= 0 then
      Press_Counter[x][y] = clock.run(grid_long_press, x, y)
      return z
    end
    if not Press_Counter[x][y] then return z end
    clock.cancel(Press_Counter[x][y])
    Tracks[TRACKS + 1].selected = x
    return z
  end
  if y == 6 then
    if z ~= 0 then return z end
    Tracks[TRACKS + 1].lengths[Tracks[TRACKS + 1].selected] = x
    return z
  end
end

local function division_key(x, y, z)
  local track = Tracks[Active_Track]
  local page = Page
  if Alt_Page then page = page + PAGES end
  if y == 2 then
    if z ~= 0 then return z end
    if Page == -1 then
      Tracks[TRACKS + 1].divisions[1] = x
      Tracks[TRACKS + 1]:update()
    else
      track.divisions[page][Pattern][1] = x
      track:update()
    end
    return z
  elseif y == 4 then
    if z ~= 0 then return z end
    if Page == -1 then
      Tracks[TRACKS + 1].divisions[2] = x
      Tracks[TRACKS + 1]:update()
    else
      track.divisions[page][Pattern][2] = x
      track:update()
    end
    return z
  elseif y == 6 then
    if z ~= 0 then return z end
    if Page == -1 then
      Tracks[TRACKS + 1].swings = x
      Tracks[TRACKS + 1]:update()
    else
      track.swings[page][Pattern] = x
      track:update()
    end
    return z
  end
end

local function probability_key(x, y, z)
  local track = Tracks[Active_Track]
  local page = Page
  if Alt_Page then page = page + PAGES end
  if y < 3 then return end
  if z ~= 0 then return z end
  if Page == -1 then
    Track[TRACKS + 1].probabilities[x] = TRACKS - y
  else
    track.probabilities[page][Pattern][x] = TRACKS - y
  end
  return z
end

local function tracks_key(x, y, z)
  if x == 1 then
    -- select track
    if z ~= 0 then return z end
    Active_Track = y
    redraw()
    return z
  elseif x == 2 then
    -- mute / unmute track
    if z ~= 0 then return z end
    Tracks[y].muted = not Tracks[y].muted
    if Tracks[y].muted then
      Midi:cc(123, 127, Tracks[y].id)
      Midi:cc(123, 0, Tracks[y].id)
    end
    return z
  end
end

local function grid_key(x, y, z)
  local press
  if y == ROWS then
    press = nav_bar(x, z)
  elseif Page == 0 then
    press = tracks_key(x, y, z)
  elseif Mod == 2 then
    press = division_key(x, y, z)
  elseif Mod == 3 then
    press = probability_key(x, y, z)
  elseif Page == -1 then
    press = patterns_key(x, y, z)
  else
    local page = Page
    if Alt_Page then page = page + PAGES end
    press = Tracks[Active_Track].keys[page](x, y, z)
  end
  if z == 0 then press = 0 end
  if press then
    Presses[x][y] = press
    redraw()
    Grid_Dirty = true
  end
end

local function nav_bar_view()
  -- track page
  if SubSequins > 0 and Mod == 0 then
    Grid:led(1, ROWS, Dance_Index % 2 == 1 and 15 or 9)
  else
    Grid:led(1, ROWS, Page == 0 and 15 or 9)
  end

  -- track scroll
  for i = 1, 2 do
    Grid:led(2 + i, ROWS, 9)
  end

  -- pages
  for x = 1, PAGES do
    if Alt_Page then
      Grid:led(x + 5, ROWS, x == Page and Dance_Index % 2 == 1 and 15 or 9)
    else
      Grid:led(x + 5, ROWS, x == Page and 15 or 9)
    end
  end

  -- mod
  for x = 1, MODS do
    Grid:led(x + 5 + PAGES + 1, ROWS, x == Mod and Dance_Index % 2 == 1 and 15 or 9)
  end

  Grid:led(16, ROWS, Page == -1 and 15 or 9)
end

local function division_view()
  if Page == 0 then
    Mod = 0
    Grid_Dirty = true
    return
  end
  for i = 1, 16 do
    Grid:led(i, 2, 4)
    Grid:led(i, 4, 4)
  end
  local page = Page
  if Alt_Page then page = page + PAGES end
  if Page ~= -1 then
    Grid:led(Tracks[Active_Track].divisions[page][Pattern][1], 2, 15)
    Grid:led(Tracks[Active_Track].divisions[page][Pattern][2], 4, 15)
    Grid:led(Tracks[Active_Track].swings[page][Pattern], 6, 15)
  else
    Grid:led(Tracks[TRACKS + 1].divisions[1], 2, 15)
    Grid:led(Tracks[TRACKS + 1].divisions[2], 4, 15)
    Grid:led(Tracks[TRACKS + 1].swings, 6, 15)
  end
end

local function probability_view()
  if Page == 0 then
    Mod = 0
    Grid_Dirty = true
    return
  end
  local page = Page
  if Alt_Page then page = page + PAGES end
  local track = Tracks[Active_Track]
  if Page ~= -1 then
    for x = 1, 16 do
      local value = track.probabilities[page][Pattern][x]
      local left = track.bounds[page][Pattern][1]
      local right = track.bounds[page][Pattern][2]
      local check = x >= left and x <= right
      for i = 4, value, -1 do
        Grid:led(x, TRACKS - i, check and 9 or 4)
      end
      if track.index[page] == x then
        Grid:led(x, TRACKS - value, 15)
      end
    end
  else
    for x = 1, 16 do
      local value = Tracks[TRACKS + 1].probabilities[x]
      local left = Tracks[TRACKS + 1].bounds[1]
      local right = Tracks[TRACKS + 1].bounds[2]
      local check = x >= left and x <= right
      for i = 4, value, -1 do
        Grid:led(x, TRACKS - i, check and 9 or 4)
      end
      if Tracks[TRACKS + 1].index == x then
        Grid:led(x, TRACKS - value, 15)
      end
    end
  end
end

local function tracks_view()
  for y = 1, TRACKS do
    Grid:led(2, y, Tracks[y].muted and 4 or 9)
    if Active_Track == y then
      Grid:led(1, y, Playing[y] == 1 and 15 or 12)
    else
      Grid:led(1, y, Playing[y] == 1 and 9 or 4)
    end
  end
end

local function patterns_view()
  for x = 1, 16 do
    Grid:led(x, 1, 4)
  end
  local track = Tracks[TRACKS + 1]
  local left = track.bounds[1]
  local right = track.bounds[2]
  if SubSequins > 0 then
    if type(track.data[SubSequins]) == "number" then
      track.data[SubSequins] = { track.data[SubSequins] }
      track:make_sequins()
    end
    local datum = track.data[SubSequins]
    for x = 1, #datum do
      Grid:led(x, 4, 9)
    end
    if track.selected > #datum then
      track.selected = #datum
      Grid_Dirty = true
      return
    end
    Grid:led(track.selected, 4, 12)
    Grid:led(datum[track.selected], 1, 12)
  else
    local datum = track.data[track.selected]
    if type(datum) == "number" then
      Grid:led(datum, 1, 12)
    else
      Grid:led(datum[Dance_Index % #datum + 1], 1, 12)
    end
    Grid:led(Pattern, 1, 15)
    for x = 1, 16 do
      local check = x >= left and x <= right
      Grid:led(x, 4, check and 9 or 4)
    end
    Grid:led(track.selected, 4, 12)
    Grid:led(track.index, 4, Dance_Index % 2 == 1 and 15 or 0)

    for x = 1, track.lengths[track.index] do
      Grid:led(x, 6, 4)
    end

    Grid:led(track.lengths[track.index], 6, 9)
    Grid:led(track.lengths[track.selected], 6, 12)
    Grid:led(track.counters, 6, 15)
  end
end

local function page_view()
  if Page == 0 then
    tracks_view()
    return
  elseif Page == -1 then
    patterns_view()
    return
  end
  local page = Page
  if Alt_Page then page = page + PAGES end
  local track = Tracks[Active_Track]
  local left = track.bounds[page][Pattern][1]
  local right = track.bounds[page][Pattern][2]
  if SubSequins > 0 then
    if type(track.data[page][Pattern][SubSequins]) == 'number' then
      track.data[page][Pattern][SubSequins] = { track.data[page][Pattern][SubSequins] }
      track:make_sequins(page)
    end
    local datum = track.data[page][Pattern][SubSequins]
    for x = 1, #datum do
      local lights = Pages[page].display(datum[x], true, false, nil)
      for _, light in ipairs(lights) do
        Grid:led(x, light[1], light[2])
      end
    end
    return
  end
  for x = 1, 16 do
    local datum = track.data[page][Pattern][x]
    datum = type(datum) == "number" and datum or datum[Dance_Index % #datum + 1]
    local check = x >= left and x <= right
    local lights = Pages[page].display(datum, check, x == track.index[page], track.counters[page])
    for _, light in ipairs(lights) do
      Grid:led(x, light[1], light[2])
    end
  end
end

local function grid_redraw()
  Grid_Dirty = false
  Grid:all(0)
  nav_bar_view()
  if Mod == 1 and Page == 0 then
    Mod = 0
    Grid_Dirty = true
  end
  if Mod == 2 then
    division_view()
  elseif Mod == 3 then
    probability_view()
  else
    page_view()
  end
  for x = 1, 16 do
    for y = 1, TRACKS + 1 do
      if Presses[x][y] == 1 then
        if Press_Counter[x][y] then
          Grid:led(x, y, 15)
        else
          Grid:led(x, y, Dance_Index % 2 == 1 and 15 or 9)
        end
      end
    end
  end
  Grid:refresh()
end

function init()
  if counter == 0 then
    counter = counter + 1
    params:add {
      type = 'number',
      id = 'root_note',
      name = 'root note',
      min = 0,
      max = 127,
      default = 60,
      formatter = function(param)
        return musicutil.note_num_to_name(param:get(), true)
      end,
    }
    params:set_action("root_note", build_scale)
    params:add {
      type = 'option',
      id = 'scale',
      name = 'scale',
      options = Scale_Names,
      default = 5,
    }
    params:set_action("scale", build_scale)
    params:bang()
  end
  build_scale()
  if Grid.device == nil then
    redraw()
    return
  end
  Pages = Pagemaker(Grid.rows)
  Track = Trackmaker(Grid.rows)
  TRACKS = Grid.rows - 1
  ROWS = Grid.rows
  for i = 1, 16 do
    Presses[i] = {}
    Press_Counter[i] = {}
    for j = 1, ROWS do
      Presses[i][j] = 0
    end
  end
  for i = 1, TRACKS do
    Notes[i] = {}
    Tracks[i] = Track.new(i, Lattice)
  end
  Tracks[TRACKS + 1] = Track.pattern_new(Lattice)
  Grid.key = grid_key
  local grid_redraw_metro = metro.init()
  grid_redraw_metro.event = function()
    if Grid.device and Grid_Dirty then grid_redraw() end
  end
  local screen_redraw_metro = metro.init()
  screen_redraw_metro.event = function ()
    redraw()
  end

  Lattice:new_sprocket {
    division = 1 / 8,
    order = 1,
    action = function()
      Dance_Index = Dance_Index % 16 + 1
      Grid_Dirty = true
    end
  }

  if grid_redraw_metro then
    grid_redraw_metro:start(1 / 25)
  end
  if screen_redraw_metro then
    screen_redraw_metro:start(1 / 15)
  end
  Lattice:start()
  redraw()
end

local colors = {
  {200, 50, 50},
  {233, 100, 50},
  {244, 150, 50},
  {225, 200, 50},
  {150, 224, 50},
  {100, 233, 50},
  {50, 200, 50},
  {50, 233, 100},
  {50, 244, 150},
  {50, 225, 200},
  {50, 150, 225},
  {50, 100, 233},
  {50, 50, 200},
  {100, 50, 225},
  {200, 50, 200},
}

function redraw()
  screen.set(1)
  screen.clear()
  if Grid.device == nil then
    local w, h = screen.get_size()
    screen.move(w / 2, h / 2 - 8)
    screen.color(0, 155, 155)
    screen.text_center("connect a grid!")
    screen.refresh()
    screen.reset()
    return
  end
  screen.move(10, 20)
  for i = 1, TRACKS do
    screen.move_rel(0, 10)
    screen.color(table.unpack(colors[i]))
    screen.text("TRACK " .. i)
    local pos = 40
    screen.move_rel(pos, 0)
    for _, value in ipairs(Notes[i]) do
      screen.move_rel(10, 0)
      pos = pos + 10
      screen.text(musicutil.note_num_to_name(value))
    end
    screen.move_rel(-pos, 0)
  end
  screen.refresh()
  screen.reset()
end

screen.resized = redraw

grid.add = function(dev)
  init()
end

cleanup = function ()
  Grid:all(0)
  Grid:refresh()
  for i = 1, TRACKS do
    Midi:cc(123, 0, i)
  end
end
