-- Adapted from Oil Outpost Planner 1.7.0 by Coppermine (MIT).
-- See oil/vendor/LICENSE and oil/README.md.
local common = {}

function common.get_visible_qualities()
  local qualities = {}

  for _, quality in pairs(prototypes.quality) do
    if not quality.hidden then
      table.insert(qualities, quality)
    end
  end

  table.sort(qualities, function(a, b)
    return a.level == b.level and a.name < b.name or a.level < b.level
  end)
  return qualities
end

function common.get_unlocked_qualities(force)
  local qualities = {}

  for _, quality in pairs(common.get_visible_qualities()) do
    if force.is_quality_unlocked(quality) then
      table.insert(qualities, quality)
    end
  end

  return qualities
end

function common.get_default_quality()
  return common.get_visible_qualities()[1]
end

-- Check a pipe definition to verify that it is a 'simple'
-- pipe of the type we want to use.
local function is_regular_pipe(entity_proto)
  local fluidboxes = entity_proto.fluidbox_prototypes
  if #fluidboxes ~= 1
  then
    return false
  end

  local pipes = fluidboxes[1].pipe_connections
  if #pipes ~= 4
  then
    return false
  end

  for _, pipe in pairs(pipes)
  do
    if pipe.connection_type ~= "normal"
    then
      return false
    end
  end

  -- We could also check that flow_direction == "input-output", and that the
  -- four connections are in the four cardinal directions, but I doubt
  -- there will be cases where that's relevant.

  return true
end

-- Check an underground pipe definition to verify that it is a 'simple'
-- underground pipe of the type we want to use.
local function is_regular_underground_pipe(entity_proto)
  local fluidboxes = entity_proto.fluidbox_prototypes
  if #fluidboxes ~= 1
  then
    return false
  end

  local pipes = fluidboxes[1].pipe_connections
  if #pipes ~= 2
  then
    return false
  end

  local normal_pipe = nil
  local underground_pipe = nil

  for _, pipe in pairs(pipes)
  do
    if pipe.connection_type == "normal"
    then
      normal_pipe = pipe
    elseif pipe.connection_type == "underground"
    then
      underground_pipe = pipe
    end
  end

  if normal_pipe == nil or underground_pipe == nil
  then
    return false
  end

  if normal_pipe.direction ~= defines.direction.north
  then
    return false
  end

  if underground_pipe.direction ~= defines.direction.south
  then
    return false
  end

  -- We could also check that flow_direction == "input-output", but I doubt
  -- there will be cases where that's relevant.

  return true
end

local function add_beacon_utility_field(flow, player_data)
  local row = flow.add{
    type="flow",
    direction="horizontal",
  }
  local tooltip={"mpp-oil.settings_beacon_utility_tooltip"}
  row.add{
    type="label",
    caption={"mpp-oil.settings_beacon_utility"},
    tooltip=tooltip,
  }
  local utility_field = row.add{
    type="textfield",
    name="oop_min_beacon_utility",
    tooltip=tooltip,
    numeric=true,
    allow_decimal=true,
    lose_focus_on_confirm=true,
  }

  if player_data.min_beacon_utility == nil
  then
    player_data.min_beacon_utility = 2
  end

  local value = player_data.min_beacon_utility
  utility_field.text = tostring(value)
end

common.simple_entity_selections = {
  {
    name="pipe",
    filter_type="pipe",
    default="pipe",
    max_size=1,
    predicate=is_regular_pipe,
    allow_none=false
  },
  {
    name="pipe-to-ground",
    filter_type="pipe-to-ground",
    default="pipe-to-ground",
    max_size=1,
    predicate=is_regular_underground_pipe,
    allow_none=true
  },
  {
    name="pole",
    filter_type="electric-pole",
    default="medium-electric-pole",
    max_size=2,
    allow_none=true
  },
  {
    name="beacon",
    filter_type="beacon",
    default="none",
    extra_fields=add_beacon_utility_field,
    allow_none=true
  },
  {
    name="heat-pipe",
    filter_type="heat-pipe",
    default="heat-pipe",
    max_size=1,
    allow_none=true
  },
}

return common
