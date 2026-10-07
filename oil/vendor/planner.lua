-- Adapted from Oil Outpost Planner 1.7.0 by Coppermine (MIT).
-- See oil/vendor/LICENSE and oil/README.md.
-- Keep upstream temporary globals inside this module.
local _ENV = setmetatable({}, {__index = _ENV})
local common = require("oil.vendor.common")
local obstacles = require("mpp.obstacles")

local layout = {}

local orthogonal_neighbours = {
  { x = -1, y = 0 },
  { x = 0, y = 1 },
  { x = 1, y = 0 },
  { x = 0, y = -1 },
}

local function round(x)
  return math.floor(x+0.5)
end

local function IsEmpty(t)
  -- Returns true is a table is empty
  for _, _ in pairs(t)
  do
    return false
  end

  return true
end

local function First(t)
  -- Returns the first value from a table
  for _, v in pairs(t)
  do
    return v
  end

  return nil
end

local function MoreThanOne(t)
  -- Returns true if the given table has more than one value
  local count = 0
  for _, _ in pairs(t)
  do
    count = count + 1
    if count > 1
    then
      return true
    end
  end
  return false
end

local function CopyTable(t)
  copy = {}

  for key, val in pairs(t)
  do
    copy[key] = val
  end

  return copy
end

local function Pos2Str(pos)
  return pos.x..","..pos.y
end

local function Str2Pos(str)
  local a, b = str:find(",")
  assert(a, "Invalid string")
  x = tonumber(str:sub(1, a-1))
  y = tonumber(str:sub(b+1))
  return { x = x, y = y }
end

local function ForceGhostAt(args)
  local surface = args.surface
  local proto = args.proto
  local position = args.position
  local direction = args.direction
  local quality = args.quality
  local player = args.player

  local force = player.force
  local bbox = proto.collision_box
  bbox.left_top.x = bbox.left_top.x + position.x
  bbox.left_top.y = bbox.left_top.y + position.y
  bbox.right_bottom.x = bbox.right_bottom.x + position.x
  bbox.right_bottom.y = bbox.right_bottom.y + position.y
  if args.obstacles then
    bbox = obstacles.entity_box(proto.name,position,direction)
    if obstacles.blocked_box(args.obstacles,bbox) then
      if args.on_blocked then args.on_blocked() end
      return
    end
  end

  if args.preview_only then
    args.on_preview{
      name="entity-ghost",inner_name=proto.name,position=position,direction=direction,quality=quality,
    }
    return {valid=true,surface=surface,ghost_prototype=proto,
      bounding_box=obstacles.entity_box(proto.name,position,direction)}
  end

  -- Remove real entities that would collide
  local existing = surface.find_entities_filtered{
    area=bbox,
    collision_mask=proto.collision_mask.layers,
    force={force, "neutral"},
  }

  for _, entity in pairs(existing)
  do
    if entity ~= new_entity
    then
      -- In editor mode marking a cliff for deconstruction instantly removes
      -- it.  That in turn can cause connected cliff segments to cease to
      -- exist.  Which can make later entities in this loop invalid.
      if entity.valid
      then
        if not args.obstacles and (args.allow_removal or entity.force == game.forces.neutral) then
          if args.on_deconstruction then args.on_deconstruction(entity) end
          entity.order_deconstruction(player.force, player)
        end
      end
    end
  end

  -- Then remove ghosts that would conflict
  local existing = surface.find_entities_filtered{
    area=bbox,
    type="entity-ghost",
    force=force,
  }
  for _, entity in pairs(existing)
  do
    if entity ~= new_entity
    then
      --args.debug("Removing ghost of "..entity.ghost_name.." due to "..proto.name)
      if args.allow_removal and not args.obstacles then
        if args.on_deconstruction then args.on_deconstruction(entity) end
        entity.order_deconstruction(player.force, player)
      end
    end
  end

  -- Create the entity itself
  local new_entity = surface.create_entity{
    name="entity-ghost",
    inner_name=proto.name,
    position=position,
    direction=direction,
    quality=quality,
    raise_built=true,
    force=player.force,
    player=player,
  }

  if new_entity and args.on_created then args.on_created(new_entity) end
  if not new_entity and args.obstacles and args.on_blocked then args.on_blocked() end

  return new_entity
end

local function Collides(proto1, proto2)
  local layers1 = proto1.collision_mask.layers
  local layers2 = proto2.collision_mask.layers

  for name, _ in pairs(layers1)
  do
    if layers2[name]
    then
      return true
    end
  end

  return false
end

local function AddLandfillUnder(args)
  local player = args.player
  local ghosts = args.ghosts

  for _, ghost in pairs(ghosts)
  do
    if not ghost.valid
    then
      args.debug("Invalid ghost. Entities placed overlapping.  Please report this as a bug in OilOutpostPlanner")
      goto skip_ghost
    end

    local surface = ghost.surface
    local entity_proto = ghost.ghost_prototype
    local tiles = surface.find_tiles_filtered{
      area=ghost.bounding_box,
      collision_mask=entity_proto.collision_mask.layers
    }

    for _, tile in pairs(tiles)
    do
      if tile.name == "out-of-map"
      then
        goto skip_tile
      end

      local tile_proto = tile.prototype

      while true
      do
        local cover_tile = tile_proto.default_cover_tile

        if not Collides(tile_proto, entity_proto)
        then
          break
        end

        if cover_tile == nil
        then
          -- Hardcode concrete as the cover for meltable tiles for Aquilo; I
          -- don't know how we're supposed to know that this is the 'correct'
          -- tile for this surface.
          cover_tile = prototypes.tile["concrete"]
        end

        local tile_spec = {
          name="tile-ghost",
          position=tile.position,
          inner_name=cover_tile.name,
          raise_built=true,
          player=player,
          force=player.force
        }
        local tile_ghost
        if args.preview_only then args.on_preview(tile_spec)
        else tile_ghost=surface.create_entity(tile_spec) end
        if tile_ghost and args.on_created then args.on_created(tile_ghost) end

        tile_proto = cover_tile
      end

      ::skip_tile::
    end

    ::skip_ghost::
  end
end

-- Round down to the next odd multiple of 0.5
local function FloorHalf(x)
  return 0.5 + math.floor(x - 0.5)
end

-- Round up to the next odd multiple of 0.5
local function CeilHalf(x)
  return 0.5 + math.ceil(x - 0.5)
end

local function ForbidPointsInBox(args)
  local pos=args.pos
  local cbox = args.collision_box
  local forbidden = args.forbidden

  local min_x = CeilHalf(pos.x + cbox.left_top.x)
  local max_x = FloorHalf(pos.x + cbox.right_bottom.x)
  local min_y = CeilHalf(pos.y + cbox.left_top.y)
  local max_y = FloorHalf(pos.y + cbox.right_bottom.y)

  for x=min_x, max_x
  do
    for y=min_y, max_y
    do
      local pos = { x = x, y = y }
      forbidden[Pos2Str(pos)] = true
    end
  end
end

local function AnySpotForbidden(args)
  local pos = args.position
  local cbox = args.collision_box
  local forbidden = args.forbidden

  local min_x = CeilHalf(pos.x + cbox.left_top.x)
  local max_x = FloorHalf(pos.x + cbox.right_bottom.x)
  local min_y = CeilHalf(pos.y + cbox.left_top.y)
  local max_y = FloorHalf(pos.y + cbox.right_bottom.y)

  for x=min_x, max_x
  do
    for y=min_y, max_y
    do
      local pos = { x = x, y = y }
      if forbidden[Pos2Str(pos)]
      then
        return true
      end
    end
  end

  return false
end

local function AddForbiddenPoints(args)
  local min_x = args.bounds.min_x
  local min_y = args.bounds.min_y
  local max_x = args.bounds.max_x
  local max_y = args.bounds.max_y
  local surface = args.surface
  local force = args.force
  local player_data = args.player_data
  local forbidden = args.forbidden

  local collision_mask = prototypes.entity.pipe.collision_mask.layers

  if args.obstacles then
    for x=min_x,max_x do
      for y=min_y,max_y do
        local box={left_top={x=x-0.49,y=y-0.49},right_bottom={x=x+0.49,y=y+0.49}}
        if obstacles.blocked_box(args.obstacles,box) then forbidden[Pos2Str{x=x,y=y}]=true end
      end
    end
  end

  local function check_for(predicate)
    for x = min_x,max_x
    do
      for y = min_y,max_y
      do
        local pos = {x = x, y = y}
        if predicate(pos)
        then
          forbidden[Pos2Str(pos)] = true
        end
      end
    end
  end

  if not player_data.remove_existing
  then
    check_for(function(pos)
      return surface.count_entities_filtered{
          position=pos,
          collision_mask=collision_mask,
          force=force,
        } > 0 or
        surface.count_entities_filtered{
          position=pos,
          type="entity-ghost",
          force=force,
        } > 0
      end)
  end

  if not player_data.add_landfill
  then
    check_for(function(pos)
      return surface.count_tiles_filtered{
          position=pos,
          radius=0.5,
          collision_mask=collision_mask,
        } > 0
      end)
  end
end

local function FloodFill(args)
  local min_x = args.bounds.min_x
  local min_y = args.bounds.min_y
  local max_x = args.bounds.max_x
  local max_y = args.bounds.max_y
  local origin = args.origin
  local adjacency = args.adjacency
  local forbidden = args.forbidden

  local to_check = {origin}
  local next_to_check = {}
  local reachable = {[Pos2Str(origin)] = true}

  while not IsEmpty(to_check)
  do
    for _, pos in pairs(to_check)
    do
      for _, off in pairs(adjacency)
      do
        local candidate = { x = pos.x + off.x, y = pos.y + off.y }
        local candidate_s = Pos2Str(candidate)

        local valid_and_new = (
          not reachable[candidate_s]
          and candidate.x >= min_x
          and candidate.x <= max_x
          and candidate.y >= min_y
          and candidate.y <= max_y
          and not forbidden[candidate_s])

        if valid_and_new
        then
          table.insert(next_to_check, candidate)
          reachable[candidate_s] = true
        end
      end
    end

    to_check = next_to_check
    next_to_check = {}
  end

  return reachable
end

local function SolveSteinerTree(args)
  local min_x = args.bounds.min_x
  local min_y = args.bounds.min_y
  local max_x = args.bounds.max_x
  local max_y = args.bounds.max_y
  local targets = args.targets
  local adjacency = args.adjacency
  local forbidden = args.forbidden
  local forbid_adjacency = args.forbid_adjacency or {}
  local skip_flood_fill = args.skip_flood_fill
  local choose_subtarget = args.choose_subtarget
  local debug_viz_surface = args.debug_viz_surface

  -- Sanity check args
  assert(min_x < max_x, "Invalid x range")
  assert(min_y < max_y, "Invalid y range")
  assert(#targets, "Must have at least one target")

  if debug_viz_surface ~= nil
  then
    for _, target in pairs(targets)
    do
      for i, subtarget in pairs(target)
      do
        local debug_pos = { x = subtarget.x + 0.25, y = subtarget.y }
        local color = {1,1,1}
        if forbidden[Pos2Str(subtarget)]
        then
          color = {1, 0, 0}
        end
        rendering.draw_text{
          text="s",
          surface=debug_viz_surface,
          target=debug_pos,
          color=color,
        }
      end
    end
  end

  local reachable = {}

  if args.skip_flood_fill
  then
    -- If we're asked to skip the flood fill then we instead build a reachable
    -- array that's simply all the non-forbidden points within bounds
    for x = min_x,max_x
    do
      for y = min_y,max_y
      do
        local pos = {x = x, y = y}
        local pos_s = Pos2Str(pos)
        if not forbidden[pos_s]
        then
          reachable[pos_s] = true
        end
      end
    end
  else
    -- First, we want to partition the subtargets into connected components.
    -- This avoids the issue where we pick a subtarget for a particular target
    -- and it turns out to not be able to connect to other ones.  Do this by
    -- flood filling from an arbitrary subtarget and seeing which others we
    -- reach.  Then repeat until we've covered all of them.
    local all_subtargets = {}
    local unreachable_targets = {}

    -- Remove forbidden points from the targets whilst adding the others to the
    -- big list
    for target_idx, target in pairs(targets)
    do
      for i, subtarget in pairs(target)
      do
        if forbidden[Pos2Str(subtarget)]
        then
          target[i] = nil
        else
          table.insert(all_subtargets, subtarget)
        end
      end

      if IsEmpty(target)
      then
        table.insert(unreachable_targets, target_idx)
      end
    end

    if #unreachable_targets > 0
    then
      return {failed=true, unreachable_targets=unreachable_targets}
    end

    local partitions = {}
    while not IsEmpty(all_subtargets)
    do
      local start_point
      for _, subtarget in pairs(all_subtargets)
      do
        start_point = subtarget
        break
      end

      assert(start_point ~= nil)

      local filled = FloodFill{
        origin=start_point,
        bounds=args.bounds,
        adjacency=adjacency,
        forbidden=forbidden,
      }

      local this_part = {}
      local remaining_subtargets = {}

      for _, subtarget in pairs(all_subtargets)
      do
        if filled[Pos2Str(subtarget)]
        then
          table.insert(this_part, subtarget)
        else
          table.insert(remaining_subtargets, subtarget)
        end
      end

      table.insert(partitions, {subtargets=this_part, all_points=filled})

      all_subtargets = remaining_subtargets
    end

    -- Now pick the largest partition to be the one we stick with
    table.sort(partitions, function(l, r)
      return #l.subtargets > #r.subtargets
    end)

    local chosen_partition = partitions[1]
    reachable = chosen_partition.all_points
  end

  -- Eliminate all the subtargets that aren't in the largest partition
  local unreachable_targets = {}
  for target_idx, target in pairs(targets)
  do
    for i, subtarget in pairs(target)
    do
      if not reachable[Pos2Str(subtarget)]
      then
        target[i] = nil
      end
    end

    if IsEmpty(target)
    then
      table.insert(unreachable_targets, target_idx)
    end
  end

  if #unreachable_targets > 0
  then
    return {failed=true, unreachable_targets=unreachable_targets}
  end

  -- Special case for a single target
  if #targets == 1
  then
    path_node = First(targets[1])
    choose_subtarget(1, 1, path_node)
    return {
      paths = { [Pos2Str(path_node)] = path_node },
    }
  end

  -- We spread out from each target in parallel until two collide, then join
  -- those two along the shortest path.  As soon as we join two, they become
  -- one combined target which we reset and spread out from once more.
  -- Once all targets have combined into one large set, we are done.

  -- For each i:
  --   target_neighbourhoods[i] is an array of points in that neighbourhood,
  --     sorted in increasing order of disance from the target
  --   target_neighbourhood_index[i] is an index into target_neighbourhoods[i]
  --     of the next entry to examine
  local nearest_target_to = {}
  local target_neighbourhoods = {}
  local target_neighbourhood_index = {}

  local paths = {}
  -- Sometimes placing an item should forbid some nearby items.  We track these
  -- extra forbidden locations here
  local extra_forbidden = {}

  local function AddExtraForbidden(pos)
    for _, offset in pairs(forbid_adjacency)
    do
      local forbid = { x = pos.x + offset.x, y = pos.y + offset.y }
      extra_forbidden[Pos2Str(forbid)] = true
    end
  end

  local function ClearNeighbourhood(target_idx)
    for _, n in pairs(target_neighbourhoods[target_idx])
    do
      nearest_target_to[Pos2Str(n.pos)] = nil
    end
    target_neighbourhoods[target_idx] = nil
    target_neighbourhood_index[target_idx] = nil
  end

  for target_idx, target_set in pairs(targets)
  do
    target_neighbourhoods[target_idx] = {}
    target_neighbourhood_index[target_idx] = 1

    for subtarget_idx, subtarget in pairs(target_set)
    do
      subtarget_str = Pos2Str(subtarget)
      if not extra_forbidden[subtarget_str]
      then
        if nearest_target_to[subtarget_str] ~= nil
        then
          -- Two targets share a square where a path could start.
          -- Immediately pick the subtarget for both and merge their
          -- target_neighbournoods accordingly
          choose_subtarget(target_idx, subtarget_idx, subtarget)
          ClearNeighbourhood(target_idx)

          other_target_info = nearest_target_to[subtarget_str]
          other_target = other_target_info.target
          other_subtarget_idx = other_target_info.subtarget_idx
          if other_subtarget_idx ~= nil
          then
            choose_subtarget(other_target, other_subtarget_idx, subtarget)
            ClearNeighbourhood(other_target)
            nearest_target_to[subtarget_str] = {target=other_target}
            target_neighbourhoods[other_target] = {}
            target_neighbourhood_index[other_target] = 1
            table.insert(
              target_neighbourhoods[other_target],
              {pos=subtarget, distance=1}
            )
            paths[subtarget_str] = subtarget
            AddExtraForbidden(subtarget)
            if debug_viz_surface ~= nil
            then
              rendering.draw_text{
                text="x",
                surface=debug_viz_surface,
                target=subtarget,
                color={1,1,1}
              }
            end
          end
          break
        else
          nearest_target_to[subtarget_str] = {
            target=target_idx, subtarget_idx=subtarget_idx
          }
          table.insert(
            target_neighbourhoods[target_idx],
            {pos=subtarget, distance=1}
          )
        end
      end
    end
  end

  --print(serpent.block({ min_x=min_x, max_x=max_x, min_y=min_y, max_y=max_y}))
  --print("forbidden = "..serpent.block(forbidden))

  local function FindMergeTarget()
    local process_distance = 1
    while true
    do
      for i, target_neighbourhood in pairs(target_neighbourhoods)
      do
        local idx = target_neighbourhood_index[i]
        assert(idx ~= nil, "idx == nil")

        while true
        do
          local next_neighbour = target_neighbourhood[idx]

          if next_neighbour == nil
          then
            --print("next_neighbour was nil")
            --print("idx = "..idx)
            --print("#target_neighbourhood = "..#target_neighbourhood)
            return nil
          end

          --print("next_neighbour = "..serpent.line(next_neighbour))
          assert(next_neighbour.distance >= process_distance,
            "Values out of order")

          if next_neighbour.distance > process_distance
          then
            break
          end

          local pos = next_neighbour.pos
          --print("idx = "..idx..", pos ("..pos.x..","..pos.y..")")

          for _, off in pairs(adjacency)
          do
            local candidate = { x = pos.x + off.x, y = pos.y + off.y }
            local candidate_s = Pos2Str(candidate)
            --print("Considering candidate ("..candidate.x..","..candidate.y.."), forbidden="..serpent.block(forbidden[candidate_s])..", valid="..serpent.block(valid))
            if reachable[candidate_s] and not extra_forbidden[candidate_s]
            then
              --print("Candidate valid position")
              local nearest_target_info = nearest_target_to[candidate_s]
              if nearest_target_info == nil
              then
                --print("Candidate is a new position")
                nearest_target_to[candidate_s] = { target=i, next_pos=pos }
                --print("nearest_target_to = "..serpent.block(nearest_target_to))
                table.insert(target_neighbourhood, {pos=candidate, distance=process_distance+1})
              else
                local other_target = nearest_target_info.target
                if other_target == i
                then
                  --print("Candidate a self reference")
                else
                  return {
                    t1 = i,
                    t2 = other_target,
                    pos1 = pos,
                    pos2 = candidate
                  }
                end
              end
            end
          end

          idx = idx + 1

          if idx > 10000
          then
            args.debug({"mpp-oil.msg_too_big"})
            return nil
          end
        end

        target_neighbourhood_index[i] = idx
      end

      process_distance = process_distance + 1
    end
  end

  local path_index = 0

  while MoreThanOne(target_neighbourhoods)
  do
    local merge_target = FindMergeTarget()

    if merge_target == nil
    then
      return {failed=true}
    end
    --print("Got a merge target "..serpent.line(merge_target))

    -- We have found a pair of targets to be merged.  We construct the path
    -- connecting them and set the subtarget
    local pos1 = merge_target.pos1
    local pos2 = merge_target.pos2
    local this_path = {}
    local chosen_subtargets = {}

    for _, pos in pairs({pos1, pos2})
    do
      while true
      do
        assert(pos ~= nil, "Expected real pos")
        --print("Adding path node at "..serpent.line(pos))
        table.insert(this_path, pos)

        if #this_path > 500
        then
          args.debug("Generated path was too long")
          return {failed=true}
        end

        local n = nearest_target_to[Pos2Str(pos)]
        assert(n ~= nil, "Expected neighbour")
        local next_pos = n.next_pos
        if next_pos ~= nil
        then
          pos = next_pos
        else
          local subtarget_idx = n.subtarget_idx
          if subtarget_idx ~= nil
          then
            local target = n.target
            assert(target ~= nil, "Expected target")
            choose_subtarget(target, subtarget_idx, pos)
            chosen_subtargets[target] = subtarget_idx
          else
            --print("No subtarget_idx in "..serpent.line(n))
          end
          break
        end
      end
    end

    local t1 = merge_target.t1
    local t2 = merge_target.t2

    -- Gather old distance-1 neighbourhoods for each marged target (but only
    -- for the chosen subtarget, when applicable)
    local old_neighbourhoods = {}
    for _, t in pairs({t1, t2})
    do
      local t_neighbourhood = target_neighbourhoods[t]
      for _, neighbour in pairs(t_neighbourhood)
      do
        if neighbour.distance > 1
        then
          break
        end

        local pos = neighbour.pos
        local n = nearest_target_to[Pos2Str(pos)]
        local subtarget = n.subtarget_idx

        if subtarget == nil or subtarget == chosen_subtargets[t]
        then
          table.insert(old_neighbourhoods, { pos=neighbour.pos, distance=1 })
        end
      end
    end

    ClearNeighbourhood(t1)
    ClearNeighbourhood(t2)

    -- Initialize the new neighbourhood as the union of the two old distance-1
    -- neighbourhoods and the path between them
    target_neighbourhoods[t1] = old_neighbourhoods
    target_neighbourhood_index[t1] = 1
    local t1_neighbourhood = target_neighbourhoods[t1]

    for _, neighbour in pairs(t1_neighbourhood)
    do
      pos_str = Pos2Str(neighbour.pos)
      nearest_target_to[pos_str] = { target=t1 }
    end

    for _, path_node in pairs(this_path)
    do
      path_node_str = Pos2Str(path_node)
      paths[path_node_str] = path_node
      AddExtraForbidden(path_node)

      if nearest_target_to[path_node_str] == nil
      then
        table.insert(t1_neighbourhood, { pos=path_node, distance=1 })
        nearest_target_to[path_node_str] = { target=t1 }
      else
        assert(
          nearest_target_to[path_node_str].target == t1,
          "target = "..t1..", nearest_target_to[path_node_str] = "
            ..serpent.line(nearest_target_to[path_node_str]))
      end

      if debug_viz_surface ~= nil
      then
        local debug_pos = { x = path_node.x, y = path_node.y - path_index/8 }
        rendering.draw_text{
          text=tostring(path_index),
          surface=debug_viz_surface,
          target=debug_pos,
          color={1,1,1}
        }
      end
    end

    path_index = path_index + 1
  end

  return {
    paths=paths
  }
end

local function ReportSteinerTreeFailure(tree_result, debug, debug_entity_name)
  assert(tree_result.failed, "Should have passed a failing result object")

  if tree_result.unreachable_targets ~= nil
  then
    debug({
      "mpp-oil.msg_all_subtargets_invalid",
      {"entity-name."..debug_entity_name},
    })
  end
end

local function FindPipePaths(args)
  local bounds = args.bounds
  local targets = args.targets
  local forbidden = args.forbidden
  local min_underground_distance = args.min_underground_distance
  local max_underground_distance = args.max_underground_distance
  local debug_viz_surface = args.debug_viz_surface

  local directions = {}
  local directional_pipes = {}

  local function ChooseSubtarget(target_idx, subtarget_idx, pos)
    --print("ChooseSubtarget("..target_idx..", "..subtarget_idx..", "..serpent.line(pos)..")")
    directions[target_idx] = subtarget_idx
    pos_str = Pos2Str(pos)
    if directional_pipes[pos_str] == nil
    then
      directional_pipes[pos_str] = subtarget_idx
    else
      directional_pipes[pos_str] = 0
    end
  end

  local tree_result = SolveSteinerTree{
    targets=targets,
    adjacency=orthogonal_neighbours,
    bounds=bounds,
    forbidden=forbidden,
    choose_subtarget=ChooseSubtarget,
    debug=args.debug,
    debug_viz_surface=debug_viz_surface
  }

  if tree_result.failed
  then
    ReportSteinerTreeFailure(tree_result, args.debug, args.debug_entity_name)
    return nil
  end

  local pipes = tree_result.paths
  local undergrounds = {}

  -- Now we have placed all the pipes, we want to search for places where we
  -- might be able to replace a sequence of pipes with an underground pipe.
  local function ReplacePipes(args)
    local outer_name = args.outer
    local min_outer = args.min_outer
    local max_outer = args.max_outer
    local inner_name = args.inner
    local min_inner = args.min_inner
    local max_inner = args.max_inner
    local lower_direction = args.lower_direction
    local upper_direction = args.upper_direction
    local valid_directions = args.valid_directions

    for outer = min_outer, max_outer
    do
      local start_of_run = nil

      for inner = min_inner, max_inner+1
      do
        local pos = { [outer_name] = outer, [inner_name] = inner }
        local existing_direction = directional_pipes[Pos2Str(pos)]
        local has_pipe = (
          pipes[Pos2Str(pos)] ~= nil and
          (existing_direction == nil or valid_directions[existing_direction]))
        if has_pipe
        then
          for _, offset in pairs({-1, 1})
          do
            offset_pos = { [outer_name] = outer, [inner_name] = inner }
            offset_pos[outer_name] = offset_pos[outer_name] + offset
            offset_pos_str = Pos2Str(offset_pos)
            if (pipes[offset_pos_str] ~= nil or
              undergrounds[offset_pos_str] ~= nil)
            then
              has_pipe = false
              break
            end
          end
        end

        -- At this point has_pipe tells us whether we have a pipe with no
        -- problem neighbours
        --print("pipe conversion - has_pipe="..serpent.line(has_pipe)..", "..outer_name.."="..outer..", "..inner_name.."="..inner..", existing_direction="..serpent.line(existing_direction))
        if has_pipe and start_of_run == nil
        then
          start_of_run = inner
        end

        if not has_pipe and start_of_run ~= nil
        then
          length_of_run = inner - start_of_run
          assert(length_of_run ~= nil, "Bad length")
          assert(min_underground_distance ~= nil, "Bad min_underground_distance")
          --print("Doing pipe conversion of length "..length_of_run)
          if length_of_run >= min_underground_distance
          then
            -- We have a range which we can change into an underground (or
            -- sequence of undergrounds)!
            for run_inner = start_of_run, inner - 1
            do
              pipes[Pos2Str({[outer_name]=outer, [inner_name]=run_inner})] = nil
            end

            num_sections_needed = math.ceil(
              (length_of_run+1)/(max_underground_distance+1)
            )
            for i = 0, num_sections_needed-1
            do
              section_start = start_of_run + round(
                length_of_run*i/num_sections_needed)
              section_end = start_of_run + round(
                length_of_run*(i+1)/num_sections_needed) - 1
              start_pos = { [outer_name]=outer, [inner_name]=section_start }
              end_pos = { [outer_name]=outer, [inner_name]=section_end }
              undergrounds[Pos2Str(start_pos)] = {
                pos=start_pos, direction=lower_direction
              }
              undergrounds[Pos2Str(end_pos)] = {
                pos=end_pos, direction=upper_direction
              }
            end
          end
          start_of_run = nil
        end
      end
    end
  end

  local valid_directions = {}
  valid_directions[1] = true
  valid_directions[3] = true
  ReplacePipes{
    outer="x",
    min_outer=bounds.min_x,
    max_outer=bounds.max_x,
    inner="y",
    min_inner=bounds.min_y,
    max_inner=bounds.max_y,
    valid_directions=valid_directions,
    lower_direction=defines.direction.north,
    upper_direction=defines.direction.south,
  }
  local valid_directions = {}
  valid_directions[2] = true
  valid_directions[4] = true
  ReplacePipes{
    outer="y",
    min_outer=bounds.min_y,
    max_outer=bounds.max_y,
    inner="x",
    min_inner=bounds.min_x,
    max_inner=bounds.max_x,
    valid_directions=valid_directions,
    lower_direction=defines.direction.west,
    upper_direction=defines.direction.east,
  }

  return {
    directions = directions,
    pipes = pipes,
    undergrounds = undergrounds,
  }
end

local function FindHeatPipePaths(args)
  local bounds = args.bounds
  local entities = args.entities
  local forbidden = args.forbidden

  local targets = {}

  for _, entity in pairs(entities)
  do
    local entity_pos = entity.position
    local entity_proto = entity.prototype
    local entity_radius = entity_proto.selection_box.right_bottom.x
    local heat_pipe_range = entity_radius + 0.5

    local subtargets = {}
    for x = -heat_pipe_range,heat_pipe_range
    do
      local pos = { x = entity_pos.x + x, y = entity_pos.y + heat_pipe_range }
      table.insert(subtargets, pos)
      local pos2 = { x = entity_pos.x + x, y = entity_pos.y - heat_pipe_range }
      table.insert(subtargets, pos2)
    end
    for y = 1-heat_pipe_range,heat_pipe_range-1
    do
      local pos = { x = entity_pos.x + heat_pipe_range, y = entity_pos.y + y }
      table.insert(subtargets, pos)
      local pos2 = { x = entity_pos.x - heat_pipe_range, y = entity_pos.y + y }
      table.insert(subtargets, pos2)
    end
    table.insert(targets, subtargets)
  end

  local function ChooseSubtarget(target_idx, subtarget_idx, pos)
    -- no implementation needed
  end

  local tree_result = SolveSteinerTree{
    targets=targets,
    adjacency=orthogonal_neighbours,
    bounds=bounds,
    forbidden=forbidden,
    choose_subtarget=ChooseSubtarget,
    debug=args.debug,
  }

  if tree_result.failed
  then
    return tree_result
  end

  return {
    heat_pipe_poss = tree_result.paths
  }
end

local function FindBeaconLocations(args)
  local surface = args.surface
  local bounds = args.bounds
  local beacon_name = args.beacon_name
  local quality = args.quality
  local target_entities = args.entities
  local forbidden = args.forbidden
  local entity_radius = args.entity_radius
  local score_threshold = args.min_beacon_utility

  --args.debug("score_threshold = "..score_threshold)

  local beacon_proto = prototypes.entity[beacon_name]
  local beacon_radius = beacon_proto.selection_box.right_bottom.x
  local beacon_to_entity_max = (
    beacon_proto.get_supply_area_distance(quality)
    + beacon_radius + entity_radius - 1)
  local profile = beacon_proto.profile
  if profile == nil
  then
    profile = {1}
  end

  -- We do a simple greedy search, choosing the best beacon position first and
  -- working down to the worst.

  -- Step 1: Assemble a list of potential positions, together with the set of
  -- entities they touch

  beacon_candidates = {}
  for x = bounds.min_x,bounds.max_x
  do
    for y = bounds.min_y,bounds.max_y
    do
      local pos = {x = x, y = y}
      if AnySpotForbidden{
        collision_box=beacon_proto.collision_box,
        position=pos,
        forbidden=forbidden,
      }
      then
        goto skip_pos
      end

      matching_targets = {}
      for _, target_pos in pairs(target_entities)
      do
        local max_dist = math.max(
          math.abs(x - target_pos.x), math.abs(y - target_pos.y)
        )
        if max_dist <= beacon_to_entity_max
        then
          table.insert(matching_targets, target_pos)
        end
      end

      if #matching_targets > 0
      then
        table.insert(
          beacon_candidates,
          { pos=pos, targets=matching_targets }
        )
      end

      ::skip_pos::
    end
  end

  -- Step 2: Keep track of how many beacons currently placed affect each
  -- target
  local target_counts = {}
  for _, target in pairs(target_entities)
  do
    target_counts[target] = 0
  end

  -- Step 3: Sort the candidates by their effect
  local function beacon_effect(count)
    if count == 0
    then
      return 0
    end
    local result = profile[count]
    -- If we go past the end of the profile, just use the last element
    if result == nil
    then
      result = profile[#profile]
    end
    return result * count
  end

  local function score_candidate(candidate)
    local tally = 0
    for _, target in pairs(candidate.targets)
    do
      local target_count = target_counts[target]
      local current = beacon_effect(target_count)
      local new = beacon_effect(target_count + 1)
      local add = new - current
      tally = tally + add
    end
    return tally
  end

  local function compare_candidates(l, r)
    return score_candidate(l) > score_candidate(r)
  end

  -- Step 4: Grab candidates until their score falls below some threshold
  local beacon_poss = {}
  local last_added_pos = nil

  while true
  do
    -- Filter out anything where the score is below the threshold or it's too
    -- close the the one we last added
    local new_candidates = {}
    for _, candidate in pairs(beacon_candidates)
    do
      if score_candidate(candidate) < score_threshold
      then
        goto skip_candidate
      end

      if last_added_pos ~= nil
      then
        local this_pos = candidate.pos
        local max_dist = math.max(
          math.abs(this_pos.x - last_added_pos.x),
          math.abs(this_pos.y - last_added_pos.y)
        )
        if max_dist < 2 * beacon_radius
        then
          goto skip_candidate
        end
      end

      table.insert(new_candidates, candidate)

      ::skip_candidate::
    end
    beacon_candidates = new_candidates

    table.sort(beacon_candidates, compare_candidates)

    if #beacon_candidates == 0
    then
      break
    end

    local chosen = beacon_candidates[1]
    last_added_pos = chosen.pos
    --args.debug("Adding beacon at "..serpent.line(last_added_pos).." with "..#chosen.targets.." neighbours and score "..score_candidate(chosen))
    table.insert(beacon_poss, last_added_pos)

    -- Increment the counts for all the relevant targets
    for _, target in pairs(chosen.targets)
    do
      target_counts[target] = target_counts[target] + 1
    end
  end

  return {
    beacon_poss=beacon_poss
  }
end

local function FindPowerPolePositions(args)
  local bounds = args.bounds
  local entity_sets = args.targets
  local forbidden = args.forbidden
  local wire_reach = args.wire_reach
  local supply_distance = args.supply_distance
  local size = args.size
  local debug_viz_surface = args.debug_viz_surface

  local targets = {}

  for _, entity_set in pairs(entity_sets)
  do
    if #entity_set.poss == 0
    then
      goto skip_entity_set
    end

    local radius = entity_set.radius
    assert(radius ~= nil, "Bad entity set "..serpent.line(entity_set))
    local entity_to_pole_max = supply_distance + radius - 1
    local subtarget_offsets = {}
    for x = -entity_to_pole_max,entity_to_pole_max
    do
      for y = -entity_to_pole_max,entity_to_pole_max
      do
        local pos = { x = x, y = y }
        table.insert(subtarget_offsets, pos)
      end
    end
    table.sort(subtarget_offsets, function(l, r)
      return l.x * l.x + l.y * l.y < r.x * r.x + r.y * r.y
    end)

    for _, entity_pos in pairs(entity_set.poss)
    do
      local subtargets = {}
      for _, offset in pairs(subtarget_offsets)
      do
        local pos = { x = entity_pos.x + offset.x, y = entity_pos.y + offset.y }
        table.insert(subtargets, pos)
      end
      table.insert(targets, subtargets)
    end

    ::skip_entity_set::
  end

  local squared_wire_reach = wire_reach * wire_reach
  local wire_reach_int = math.floor(wire_reach)
  local pole_adjacency = {}

  for x = -wire_reach_int,wire_reach_int
  do
    for y = -wire_reach_int,wire_reach_int
    do
      local square_distance = x * x + y * y
      local max_distance = math.max(math.abs(x), math.abs(y))
      if square_distance <= squared_wire_reach and max_distance > size
      then
        local pos = { x = x, y = y }
        table.insert(pole_adjacency, pos)
      end
    end
  end

  local function ChooseSubtarget(target_idx, subtarget_idx, pos)
    -- Nothing to do
  end

  local offset_forbidden = forbidden
  local offset_bounds = bounds
  local forbid_adjacency = {}
  -- When the power pole size is 2, we need to replace every entry in forbidden
  -- with four neighbours offset by a half unit in each direction
  if size == 2
  then
    offset_forbidden = {}
    local offsets = {
      { x = 0.5, y = 0.5 },
      { x = 0.5, y = -0.5 },
      { x = -0.5, y = 0.5 },
      { x = -0.5, y = -0.5 },
    }
    for pos_str, _ in pairs(forbidden)
    do
      pos = Str2Pos(pos_str)

      for _, offset in pairs(offsets)
      do
        local offset_pos = { x = pos.x + offset.x, y = pos.y + offset.y }
        offset_forbidden[Pos2Str(offset_pos)] = true
      end
    end

    offset_bounds = {
      min_x = bounds.min_x + 0.5,
      max_x = bounds.max_x - 0.5,
      min_y = bounds.min_y + 0.5,
      max_y = bounds.max_y - 0.5,
    }

    forbid_adjacency = {
      { x = 1, y = 1 },
      { x = 1, y = -1 },
      { x = -1, y = 1 },
      { x = -1, y = -1 },
      { x = 1, y = 0 },
      { x = -1, y = 0 },
      { x = 0, y = 1 },
      { x = 0, y = -1 },
    }
  end

  tree_result = SolveSteinerTree{
    targets=targets,
    bounds=offset_bounds,
    adjacency=pole_adjacency,
    forbidden=offset_forbidden,
    forbid_adjacency=forbid_adjacency,
    skip_flood_fill=true,
    choose_subtarget=ChooseSubtarget,
    debug=args.debug,
    --debug_viz_surface=debug_viz_surface,
  }

  if tree_result.failed
  then
    ReportSteinerTreeFailure(tree_result, args.debug, args.debug_entity_name)
    return nil
  end

  local poles = tree_result.paths

  return {
    pole_poss = poles
  }
end

local function TryPipesAndHeatPipes(args)
  local bounds = args.bounds
  local forbidden = args.forbidden
  local out_pipe_sets = args.out_pipe_sets
  local pumpjack_type = args.pumpjack_type
  local pipe_type = args.pipe_type
  local underground_pipe_type = args.underground_pipe_type
  local entities_require_heating = args.entities_require_heating
  local heat_pipe_type = args.heat_pipe_type
  local oil_patches = args.oil_patches

  -- Figure out other properties of the chosen entities
  local underground_proto
  local min_underground_distance
  local max_underground_distance
  if underground_pipe_type == "none"
  then
    min_underground_distance = 1e10
  else
    underground_proto = prototypes.entity[underground_pipe_type]
    max_underground_distance = underground_proto.max_underground_distance
    min_underground_distance = 3
  end

  local forbidden_for_pipes = CopyTable(forbidden)

  ::try_pipes_again::

  local my_result = {heat_pipe_poss={}}

  local pipe_result = FindPipePaths{
    bounds=bounds,
    targets=out_pipe_sets,
    forbidden=forbidden_for_pipes,
    min_underground_distance=min_underground_distance,
    max_underground_distance=max_underground_distance,
    debug=args.debug,
    debug_entity_name=pipe_type,
    --debug_viz_surface=args.debug_viz_surface
  }

  if pipe_result == nil
  then
    my_result.failed_pipe_layout = true
    return my_result
  end

  local directions = pipe_result.directions
  my_result.directions = directions
  my_result.pipes = pipe_result.pipes
  my_result.undergrounds = pipe_result.undergrounds

  -- Next step is to add heat pipes, but only if the surface requires them
  if entities_require_heating and heat_pipe_type ~= "none"
  then
    -- Construct a list of entities which need heating
    local entities = {}
    local forbidden_for_heat_pipes = CopyTable(forbidden)

    local pipe_proto = prototypes.entity[pipe_type]
    assert(pipe_proto ~= nil)
    for _, pipe_pos in pairs(pipe_result.pipes)
    do
      table.insert(entities, {position=pipe_pos, prototype=pipe_proto})
      forbidden_for_heat_pipes[Pos2Str(pipe_pos)] = true
    end

    local underground_pipe_proto = prototypes.entity[underground_pipe_type]
    assert(underground_pipe_proto ~= nil)
    for _, underground_info in pairs(pipe_result.undergrounds)
    do
      local pos = underground_info.pos
      table.insert(entities, {position=pos, prototype=underground_proto})
      forbidden_for_heat_pipes[Pos2Str(pos)] = true
    end

    local pumpjack_proto = prototypes.entity[pumpjack_type]
    assert(pumpjack_proto ~= nil)
    for i, patch in pairs(oil_patches)
    do
      table.insert(entities, {position=patch.position, prototype=pumpjack_proto})
    end

    local heat_pipe_result = FindHeatPipePaths{
      bounds=bounds,
      entities=entities,
      forbidden=forbidden_for_heat_pipes,
      debug=args.debug,
    }

    if heat_pipe_result.failed
    then
      if heat_pipe_result.unreachable_targets == nil
      then
        ReportSteinerTreeFailure(heat_pipe_result, args.debug, heat_pipe_type)
        my_result.failed_heat_pipe_layout = true
        return my_result
      end

      -- We can hope to try again.  If some pipe was unreachable, then we
      -- forbid that specific spot and loop back.  We need to construct a list
      -- of the positions of all the pipes and undergrounds we originally
      -- passed in so that we can convert the unreachable target indices back
      -- into useful positions
      local entity_poss = {}
      for _, pipe_pos in pairs(pipe_result.pipes)
      do
        table.insert(entity_poss, pipe_pos)
      end

      for _, underground_info in pairs(pipe_result.undergrounds)
      do
        table.insert(entity_poss, underground_info.pos)
      end
      local num_entity_poss = #entity_poss

      for _, target_idx in pairs(heat_pipe_result.unreachable_targets)
      do
        if target_idx > num_entity_poss
        then
          -- This was a pumpjack.  We can't help with that.
          my_result.failed_heat_pipe_layout = true
          return my_result
        end

        local orig_pos = entity_poss[target_idx]
        local orig_pos_str = Pos2Str(orig_pos)
        assert(
          not forbidden_for_pipes[orig_pos_str],
          "Pipe in forbidden location?"
        )
        forbidden_for_pipes[orig_pos_str] = true
      end

      goto try_pipes_again
    end

    my_result.heat_pipe_poss = heat_pipe_result.heat_pipe_poss
  end

  return my_result
end

function layout.Plan(player, player_data, entities, selected_surface, observers)
  observers = observers or {}
  local function debug(message)
    if observers.preview_only then
      if observers.on_message and type(message)=="table" and message[1]~="mpp-oil.msg_count_patches" then
        observers.on_message(message)
      end
    else player.print(message) end
  end
  local function PlaceGhost(args)
    args.allow_removal = player_data.remove_existing
    args.on_created = observers.on_created
    args.on_deconstruction = observers.on_deconstruction
    args.on_blocked = observers.on_blocked
    args.obstacles = observers.obstacles
    args.preview_only = observers.preview_only
    args.on_preview = observers.on_preview
    return ForceGhostAt(args)
  end
  local oil_patches = {}
  local chosen_entity_name
  local resource_category
  local choice_key
  local quality_key

  for _, entity in ipairs(entities)
  do
    local entity_proto = entity.prototype

    if chosen_entity_name == nil
    then
      if entity.valid
      and entity.type == "resource"
      then
        resource_category = entity_proto.resource_category
        choice_key = resource_category.."_pumpjack_choice"
        quality_key = resource_category.."_pumpjack"
        if player_data.choices[choice_key]
        then
          --debug("Found oil!")
          table.insert(oil_patches, entity)
          chosen_entity_name = entity.name
        end
      end
    else
      if entity.name == chosen_entity_name
      then
        table.insert(oil_patches, entity)
      end
    end
  end

  if #oil_patches == 0
  then
    debug({"mpp-oil.msg_no_patches"})
    return
  end

  assert(resource_category ~= nil, "Failed to get category")
  assert(choice_key ~= nil, "Failed to get choice key")

  debug({
    "mpp-oil.msg_count_patches",
    {"entity-name."..chosen_entity_name},
    #oil_patches
  })

  local direction_array = {
    defines.direction.north,
    defines.direction.east,
    defines.direction.south,
    defines.direction.west,
  }

  -- Offsets corresponding to the respective directions in direction_array
  local direction_offset_array = {
    { x = 0, y = -1 },
    { x = 1, y = 0 },
    { x = 0, y = 1 },
    { x = -1, y = 0 },
  }

  local surface = selected_surface or player.surface
  local planet = surface.planet
  local entities_require_heating = false
  if planet ~= nil
  then
    entities_require_heating = planet.prototype.entities_require_heating
  end

  -- Fetch all the player's choices for entities
  local pumpjack_type = player_data.choices[choice_key]
  local pipe_type = player_data.choices["pipe_choice"]
  local underground_pipe_type = player_data.choices["pipe-to-ground_choice"]
  local heat_pipe_type = player_data.choices["heat-pipe_choice"]
  local beacon_type = player_data.choices.beacon_choice
  local power_pole_type = player_data.choices.pole_choice

  local default_quality_proto = common.get_default_quality()
  local default_quality = nil
  if default_quality_proto ~= nil
  then
    default_quality = default_quality_proto.name
  end
  local pumpjack_quality = player_data.qualities[quality_key] or default_quality
  local pipe_quality = player_data.qualities["pipe"] or default_quality
  local underground_pipe_quality = player_data.qualities["pipe-to-ground"] or default_quality
  local heat_pipe_quality = player_data.qualities["heat-pipe"] or default_quality
  local beacon_quality = player_data.qualities["beacon"] or default_quality
  local power_pole_quality = player_data.qualities["pole"] or default_quality

  -- Figure out other properties of the chosen entities
  local underground_proto
  if underground_pipe_type ~= "none"
  then
    underground_proto = prototypes.entity[underground_pipe_type]
  end

  local pumpjack_proto = prototypes.entity[pumpjack_type]
  local pumpjack_radius = pumpjack_proto.selection_box.right_bottom.x
  local pumpjack_radius_int = math.floor(pumpjack_radius)

  local beacon_proto = prototypes.entity[beacon_type]
  local beacon_radius = 0
  if beacon_type ~= "none"
  then
    beacon_radius = beacon_proto.selection_box.right_bottom.x
  end

  -- Worst case padding requries 1 tile for a pipe, 1 tile for a heat pipe, 3
  -- tiles for beacon and 2 tiles for a power pole, so 7 more than pumpjack
  -- radius
  local padding = pumpjack_radius_int + 4 + 2*beacon_radius

  local output_fluidboxes = {}
  for _, fluidbox in pairs(pumpjack_proto.fluidbox_prototypes)
  do
    if fluidbox.production_type == "output"
    then
      table.insert(output_fluidboxes, fluidbox)
    end
  end

  if #output_fluidboxes == 0
  then
    debug({"mpp-oil.msg_no_fluidbox"})
    return
  end

  if #output_fluidboxes > 1
  then
    debug({"mpp-oil.msg_multiple_fluidboxes"})
    return
  end
  local output_fluidbox = output_fluidboxes[1]

  if #output_fluidbox.pipe_connections == 0
  then
    debug({"mpp-oil.msg_no_fluidbox"})
    return
  end

  if #output_fluidbox.pipe_connections > 1
  then
    debug({"mpp-oil.msg_multiple_fluidboxes"})
    return
  end
  local pipe_connection = output_fluidbox.pipe_connections[1]

  local out_pipe_sets = {}
  local forbidden_points = {}
  local min_x = 1e10
  local min_y = min_x
  local max_x = -min_x
  local max_y = max_x

  for _, patch in pairs(oil_patches)
  do
    local pos = patch.position
    local subtargets = {}
    for i, offset in pairs(pipe_connection.positions)
    do
      direction_offset = direction_offset_array[i]
      table.insert(
        subtargets,
        {
          x = pos.x + offset.x + direction_offset.x,
          y = pos.y + offset.y + direction_offset.y,
        }
      )
    end
    table.insert(out_pipe_sets, subtargets)

    ForbidPointsInBox{
      pos=pos,
      collision_box=pumpjack_proto.collision_box,
      forbidden=forbidden_points,
    }

    min_x = math.min(min_x, pos.x - padding)
    min_y = math.min(min_y, pos.y - padding)
    max_x = math.max(max_x, pos.x + padding)
    max_y = math.max(max_y, pos.y + padding)
  end

  local bounds = {
    min_x=min_x,
    min_y=min_y,
    max_x=max_x,
    max_y=max_y,
  }

  AddForbiddenPoints{
    forbidden=forbidden_points,
    force=player.force,
    surface=surface,
    player_data=player_data,
    obstacles=observers.obstacles,
    bounds=bounds,
    debug=debug,
  }

  local pipe_result = TryPipesAndHeatPipes{
    bounds=bounds,
    forbidden=forbidden_points,
    out_pipe_sets=out_pipe_sets,
    pumpjack_type=pumpjack_type,
    pipe_type=pipe_type,
    underground_pipe_type=underground_pipe_type,
    heat_pipe_type=heat_pipe_type,
    entities_require_heating=entities_require_heating,
    oil_patches=oil_patches,
    debug=debug,
    --debug_viz_surface=surface
  }

  if pipe_result.failed_pipe_layout
  then
    debug({"mpp-oil.msg_pipe_layout_failed"})
    return
  end

  if pipe_result.failed_heat_pipe_layout then
    debug({"mpp-oil.msg_heat_pipe_layout_failed"})
    return
  end

  local directions = pipe_result.directions
  local pipes = pipe_result.pipes
  local undergrounds = pipe_result.undergrounds

  --print("Got directions "..serpent.line(directions))
  assert(#oil_patches == #directions, "Did not get one direction per patch\n"
  ..serpent.line(oil_patches).."\n"..serpent.line(directions))

  pumpjack_positions = {}
  ghosts = {}

  for i, patch in pairs(oil_patches)
  do
    local position = patch.position
    table.insert(pumpjack_positions, position)
    local dir_index = directions[i]
    local direction = direction_array[dir_index]
    --print("Using direction "..direction.." for patch at "..serpent.line(position))
    local ghost = PlaceGhost{
      surface=surface,
      proto=pumpjack_proto,
      position=position,
      direction=direction,
      quality=pumpjack_quality,
      player=player,
      debug=debug,
    }
    table.insert(ghosts, ghost)
  end

  local pipe_proto = prototypes.entity[pipe_type]
  for _, pipe_pos in pairs(pipe_result.pipes)
  do
    local ghost = PlaceGhost{
      surface=surface,
      proto=pipe_proto,
      position=pipe_pos,
      quality=pipe_quality,
      player=player,
      debug=debug,
    }
    forbidden_points[Pos2Str(pipe_pos)] = true
    table.insert(ghosts, ghost)
  end

  for _, underground_info in pairs(pipe_result.undergrounds)
  do
    local pos = underground_info.pos
    local direction = underground_info.direction

    local ghost = PlaceGhost{
      surface=surface,
      proto=underground_proto,
      position=pos,
      direction=direction,
      quality=underground_pipe_quality,
      player=player,
    }
    forbidden_points[Pos2Str(pos)] = true
    table.insert(ghosts, ghost)
  end

  local heat_pipe_poss = pipe_result.heat_pipe_poss
  local heat_pipe_proto = prototypes.entity[heat_pipe_type]
  for _, pos in pairs(heat_pipe_poss)
  do
    local ghost = PlaceGhost{
      surface=surface,
      proto=heat_pipe_proto,
      position=pos,
      quality=heat_pipe_quality,
      player=player,
    }
    forbidden_points[Pos2Str(pos)] = true
    table.insert(ghosts, ghost)
  end

  -- Next we add beacons (if requested).  This happens after heat pipes, so we
  -- might end up with unheated beacons, but that is a problem for another day.
  local beacon_poss = {}
  if beacon_type ~= "none"
  then
    assert(beacon_radius ~= nil, "Nil radius")
    assert(beacon_radius ~= 0, "Zero radius")

    local min_beacon_utility = player_data.min_beacon_utility
    if min_beacon_utility == nil
    then
      min_beacon_utility = 2
    end

    local result = FindBeaconLocations{
      surface=surface,
      bounds=bounds,
      beacon_name=beacon_type,
      quality=beacon_quality,
      entities=pumpjack_positions,
      entity_radius=pumpjack_radius,
      min_beacon_utility=min_beacon_utility,
      forbidden=forbidden_points,
      debug=debug
    }

    beacon_poss = result.beacon_poss
    for _, pos in pairs(beacon_poss)
    do
      local ghost = PlaceGhost{
        surface=surface,
        proto=beacon_proto,
        position=pos,
        quality=beacon_quality,
        player=player,
        debug=debug,
      }

      ForbidPointsInBox{
        pos=pos,
        collision_box=beacon_proto.collision_box,
        forbidden=forbidden_points,
      }
      table.insert(ghosts, ghost)
    end
  end

  -- Now pumpjacks, pipes, and beacons are complete, the final step is to add
  -- power poles
  if power_pole_type ~= "none"
  then
    local power_pole_proto = prototypes.entity[power_pole_type]
    local wire_reach = power_pole_proto.get_max_wire_distance(power_pole_quality)
    local supply_distance = power_pole_proto.get_supply_area_distance(power_pole_quality)
    local power_pole_cbox = power_pole_proto.collision_box
    local power_pole_size = math.ceil(
      power_pole_cbox.right_bottom.x - power_pole_cbox.left_top.x)

    result = FindPowerPolePositions{
      bounds=bounds,
      targets={
        {
          poss=pumpjack_positions,
          radius=pumpjack_radius
        },
        {
          poss=beacon_poss,
          radius=beacon_radius
        },
      },
      forbidden=forbidden_points,
      wire_reach=wire_reach,
      supply_distance=supply_distance,
      size=power_pole_size,
      debug=debug,
      debug_entity_name=power_pole_type,
      --debug_viz_surface=surface,
    }

    if result == nil
    then
      debug({"mpp-oil.msg_pole_layout_failed"})
      return
    end

    pole_poss = result.pole_poss

    for _, pole_pos in pairs(pole_poss)
    do
      local ghost = PlaceGhost{
        surface=surface,
        proto=power_pole_proto,
        position=pole_pos,
        quality=power_pole_quality,
        player=player,
        debug=debug,
      }
      table.insert(ghosts, ghost)
    end
  end

  local setting = player.mod_settings["mpp-oil-interface-with-module-inserter-ex"]
  if not observers.preview_only and setting and setting.value and remote.interfaces["ModuleInserterEx"] then
    remote.call(
      "ModuleInserterEx",
      "apply_module_config_to_entities",
      player.index,
      ghosts
    )
  end

  if player_data.add_landfill then
    AddLandfillUnder{
      player=player,
      ghosts=ghosts,
      debug=debug,
      on_created=observers.on_created,
      preview_only=observers.preview_only,
      on_preview=observers.on_preview,
    }
  end
  return ghosts
end

return layout
