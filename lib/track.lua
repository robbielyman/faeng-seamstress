return function(ROWS)
  local Pages = require('lib.page')(ROWS)
  local sequins = require('sequins')

  local Track = {}

  function Track.new(id, lattice)
    local t = {
      type = "track",
      id = id,
      data = {},
      probabilities = {},
      divisions = {},
      swings = {},
      bounds = {},
      sprockets = {},
      index = {},
      sequins = {},
      muted = false,
      counters = {},
      counters_max = {},
      values = {},
      reset_flag = {},
      displays = {},
      keys = {}
    }
    setmetatable(t, { __index = Track })
    for i = 1, 2 * PAGES do
      t.counters_max[i] = Pages[i].counter
      t.data[i] = {}
      t.probabilities[i] = {}
      t.bounds[i] = {}
      t.swings[i] = {}
      t.counters[i] = 1
      t.index[i] = 1
      t.divisions[i] = {}
      t.reset_flag[i] = false
      for n = 1, PATTERNS do
        t.bounds[i][n] = { 1, Pages[i].length }
        t.swings[i][n] = Pages[i].swing
        t.divisions[i][n] = {Pages[i].division_1, Pages[i].division_2}
        t.data[i][n] = {}
        t.probabilities[i][n] = {}
        for j = 1, 16 do
          t.data[i][n][j] = Pages[i].data
          t.probabilities[i][n][j] = Pages[i].probability
        end
      end
      t.sequins[i] = sequins(t.data[i][1])
      t.values[i] = t.sequins[i]()
      t.sequins[i]:select(1)
      t.displays[i] = Pages[i].display
      t.keys[i] = function(x, y, z)
        if Mod == 1 then
          local press, left, right = loop_mod(x, y, z)
          if left and right then
            t.bounds[i][Pattern][1] = left
            t.bounds[i][Pattern][2] = right
          end
          return press
        end
        if SubSequins > 0 then
          if y < Pages[i].min or y > Pages[i].max then return end
          return handle_subsequins(x, y, z, Pages[i].key, Pages[i].data)
        end
        if y < Pages[i].min or y > Pages[i].max then return end
        if z ~= 0 then
          Press_Counter[x][y] = clock.run(grid_long_press, x, y)
          return z
        end
        if not Press_Counter[x][y] then return z end
        clock.cancel(Press_Counter[x][y])
        t.data[i][Pattern][x] = Pages[i].key(y, t.data[i][Pattern][x])
        return z
      end
      t.sprockets[i] = lattice:new_sprocket {
        division = t.divisions[i][1][1] / (t.divisions[i][1][2] * t.counters_max[i]),
        order = Pages[i].priority,
        swing = t.swings[i][1] * 100 / 16,
        action = function()
          t.counters[i] = t.counters[i] % t.counters_max[i] + 1
          if t.counters[i] == 1 then
            t:increment(i)
          end
          local cond = (i <= PAGES and Page == i) or Page == i - PAGES
          if cond and Active_Track == t.id then Grid_Dirty = true end
          if Page == 0 then Grid_Dirty = true end
          local r = math.random()
          if r > t.probabilities[i][Pattern][t.index[i]] / 4 then return end
          Pages[i].action(t, Pages.pages[i], t.sequins[i](), t.counters[i])
        end
      }
    end
    return t
  end

  function Track.pattern_new(lattice)
    local t = {
      type = "pattern",
      id = TRACKS + 1,
      data = {},
      probabilities = {},
      divisions = {
        Pages.division_1,
        Pages.division_2
      },
      bounds = { 1, 1 },
      index = 1,
      swings = Pages.swing,
      counters = 1,
      selected = 1,
      lengths = {},
      sequins = nil,
      reset_flag = false,
    }
    setmetatable(t, { __index = Track })
    for n = 1, PATTERNS do
      t.data[n] = 1
      t.probabilities[n] = Pages.probability
    end
    for n = 1, 16 do
      t.lengths[n] = Pages.length
    end
    t.sequins = sequins.new(t.data)
    t.sprockets = lattice:new_sprocket {
      division = t.divisions[1] / t.divisions[2],
      order = 1,
      swing = 100 * t.swings / 16,
      action = function()
        t.counters = t.counters + 1
        if Page == -1 then
          Grid_Dirty = true
        end
        if t.counters > t.lengths[t.index] then
          t:increment()
          t.counters = 1
        end
        if t.counters == 1 then
          local r = math.random()
          if r > t.probabilities[Pattern] / 4 then return end
          Pattern = t.sequins()
          for i = 1, TRACKS do
            Tracks[i]:update()
            for j = 1, 2 * PAGES do
              Tracks[i].reset_flag[j] = true
              local sprocket = Tracks[i].sprockets[j]
              sprocket.phase = sprocket.division * lattice.ppqn * 4
              sprocket.downbeat = false
              Tracks[i]:make_sequins(j)
            end
          end
        end
      end
    }
    return t
  end

  function Track:update()
    if self.type ~= 'track' then
      self.sprockets:set_division(self.divisions[1] / self.divisions[2])
      self.sprockets:set_swing(self.swings / 16 * 100)
    else
      for i = 1, 2 * PAGES do
        self.sprockets[i]:set_division(self.divisions[i][Pattern][1] /
        (self.counters_max[i] * self.divisions[i][Pattern][2]))
        self.sprockets[i]:set_swing(self.swings[i][Pattern] / 16 * 100)
      end
    end
  end

  function Track:make_sequins(i)
    local s = {}
    if self.type == 'pattern' then
      for j = 1, 16 do
        if type(self.data[j]) ~= "number" then
          s[j] = sequins(self.data[j])
        else
          s[j] = self.data[j]
        end
      end
      self.sequins:settable(s)
    else
      for j = 1, 16 do
        if type(self.data[i][Pattern][j]) ~= "number" then
          s[j] = sequins(self.data[i][Pattern][j])
        else
          s[j] = self.data[i][Pattern][j]
        end
      end
      self.sequins[i]:settable(s)
    end
  end

  function Track:increment(i)
    if self.type == 'pattern' then
      if self.reset_flag == true then
        self.index = self.bounds[1]
        self.reset_flag = false
      elseif self.index + 1 > self.bounds[2] or self.index + 1 < self.bounds[1] then
        self.index = self.bounds[1]
      else
        self.index = self.index + 1
      end
      self.sequins:select(self.index)
    else
      if self.reset_flag[i] == true then
        self.index[i] = self.bounds[i][Pattern][1]
        self.reset_flag[i] = false
      elseif self.index[i] + 1 < self.bounds[i][Pattern][1] or self.index[i] + 1 > self.bounds[i][Pattern][2] then
        self.index[i] = self.bounds[i][Pattern][1]
      else
        self.index[i] = self.index[i] + 1
      end
      self.sequins[i]:select(self.index[i])
    end
  end

  function Track:get(name)
    local list = Pages.pages
    for k, v in ipairs(list) do
      if v == name then return self.values[k] end
    end
  end

  function Track:set(name, datum)
    local list = Pages.pages
    for k, v in ipairs(list) do
      if v == name then
        self.values[k] = datum
        return
      end
    end
  end

  function Track:copy(source, target)
    for i = 1, 2 * PAGES do
      self.divisions[i][target][1] = self.divisions[i][source][1]
      self.divisions[i][target][2] = self.divisions[i][source][2]
      for j = 1, 16 do
        self.probabilities[i][target][j] = self.probabilities[i][source][j]
        if type(self.data[i][target][j]) ~= "number" then
          self.data[i][target][j] = {}
          for k = 1, #self.data[i][source][j] do
            self.data[i][target][j][k] = self.data[i][source][j][k]
          end
        else
          self.data[i][target][j] = self.data[i][source][j]
        end
      end
      for k = 1, 2 do
        self.bounds[i][target][k] = self.bounds[i][source][k]
      end
      if Pattern == target then
        self:make_sequins(i)
      end
    end
  end

  return Track
end
