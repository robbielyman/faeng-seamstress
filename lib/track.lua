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
  }
  setmetatable(t, {__index = Track})
  for i = 2 * PAGES do
    t.counters_max[i] = Pages[i].counter
  end
end

return Track
