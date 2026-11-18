-- Adapted from Oil Outpost Planner 1.7.0 by Coppermine (MIT).
-- See oil/vendor/LICENSE and oil/README.md.
-- Keep upstream temporary globals inside this module.
local _ENV = setmetatable({}, {__index = _ENV})
local common = require("oil.vendor.common")
local obstacles = require("mpp.obstacles")
local terrain = require("mpp.terrain")

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
  local copy = {}

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
    local spec = {
      name="entity-ghost",inner_name=proto.name,position=position,direction=direction,quality=quality,
    }
    spec.insert_plan = args.module_plan
    args.on_preview(spec)
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
        if not terrain.blocks_entity(entity, args.terrain_choices) then
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
      if not terrain.blocks_entity(entity, args.terrain_choices) then
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
  if new_entity and args.module_plan then new_entity.insert_plan=args.module_plan end
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
  local filled = args.filled

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
      if tile.name == "out-of-map" or terrain.blocks_tile(tile, args.terrain_choices or {})
      then
        goto skip_tile
      end

      local tile_proto = tile.prototype

      while true
      do
        local cover_tile = terrain.cover_tile({name=tile_proto.name,prototype=tile_proto}, args.terrain_choices or {})

        if not Collides(tile_proto, entity_proto)
        then
          break
        end

        if cover_tile == nil then
          if tile_proto.collision_mask.layers.meltable then cover_tile = prototypes.tile["concrete"] end
          if not cover_tile then
            if args.on_blocked then args.on_blocked() end
            break
          end
        end
        local fill_key = tile.position.x..","..tile.position.y..":"..cover_tile.name
        if filled[fill_key] then break end
        filled[fill_key] = true

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

-- Resume from tile coordinates. Per-position queries preserve collision and force filters.
local function scan(job, state)
  local surface, force, settings = state.surface, state.player.force, state.oil_settings
  local bounds = job.bounds
  local layers = prototypes.entity.pipe.collision_mask.layers
  local x1, y1 = job.scan_x or bounds.min_x, job.scan_y or bounds.min_y
  local x2, y2 = math.min(x1+15,bounds.max_x), math.min(y1+15,bounds.max_y)
  local index = obstacles.collect(surface, {{x1-.5,y1-.5},{x2+.5,y2+.5}}, job.ignored, state)
  for x=x1,x2 do
    for y=y1,y2 do
      local pos = {x=x, y=y}
      if obstacles.blocked_bounds(index, x-.49,y-.49,x+.49,y+.49)
        or (not settings.remove_existing and (surface.count_entities_filtered{
          position=pos, collision_mask=layers, force=force} > 0 or surface.count_entities_filtered{
          position=pos, type="entity-ghost", force=force} > 0))
        or (not settings.add_landfill and surface.count_tiles_filtered{
          position=pos, radius=.5, collision_mask=layers} > 0) then
        job.forbidden[Pos2Str(pos)] = true
      end
    end
  end
  job.scan_x, job.scan_y = x1, y2+1
  if job.scan_y>bounds.max_y then job.scan_x,job.scan_y=x2+1,bounds.min_y end
  return job.scan_x>bounds.max_x
end

local function in_bounds(bounds, pos)
  return pos.x >= bounds.min_x and pos.x <= bounds.max_x
     and pos.y >= bounds.min_y and pos.y <= bounds.max_y
end

-- Partition candidate outlets by connectivity. The queue and visited set are
-- part of the task so joining clients resume the same wave of the flood fill.
local function partition_step(tree)
  if not tree.remaining then
    tree.remaining = {}
    for _,target in ipairs(tree.targets) do
      for _,pos in pairs(target) do
        if not tree.forbidden[Pos2Str(pos)] then table.insert(tree.remaining,pos) end
      end
    end
    tree.best_count = 0
  end
  if not tree.queue then
    if #tree.remaining == 0 then return true end
    local origin = tree.remaining[1]
    tree.queue, tree.head, tree.visited = {origin}, 1, {[Pos2Str(origin)]=true}
  end
  for _=1,512 do
    local pos = tree.queue[tree.head]
    if not pos then
      local other = {}
      for _,p in ipairs(tree.remaining) do
        if not tree.visited[Pos2Str(p)] then table.insert(other,p) end
      end
      local count = #tree.remaining-#other
      if count > tree.best_count then tree.best_count,tree.reachable=count,tree.visited end
      tree.remaining, tree.queue, tree.visited = other, nil, nil
      return #other == 0
    end
    tree.head = tree.head+1
    for _,off in ipairs(orthogonal_neighbours) do
      local p = {x=pos.x+off.x, y=pos.y+off.y}
      local key = Pos2Str(p)
      if in_bounds(tree.bounds,p) and not tree.visited[key] and not tree.forbidden[key] then
        tree.visited[key]=true
        table.insert(tree.queue,p)
      end
    end
  end
end

-- Returns nil while a search is in progress, or its final tree/failure.
local function SolveSteinerTree(args, debug)
  local targets, adjacency = args.targets, args.adjacency
  local forbid_adjacency = args.forbid_adjacency or {}
  if not args.paths then
    if not args.skip_flood_fill and not partition_step(args) then return end
    local unreachable = {}
    for i,target in ipairs(targets) do
      for k,pos in pairs(target) do
        local key = Pos2Str(pos)
        if args.forbidden[key] or not in_bounds(args.bounds,pos)
          or (not args.skip_flood_fill and not (args.reachable and args.reachable[key])) then target[k]=nil end
      end
      if not next(target) then table.insert(unreachable,i) end
    end
    if #unreachable>0 then return {failed=true,unreachable_targets=unreachable} end
    args.remaining, args.reachable = nil, nil
    args.nearest, args.neighbourhoods, args.indices = {}, {}, {}
    args.paths, args.extra_forbidden, args.choices = {}, {}, {}
  end
  local nearest_target_to = args.nearest
  local target_neighbourhoods = args.neighbourhoods
  local target_neighbourhood_index = args.indices
  local paths,extra_forbidden = args.paths,args.extra_forbidden
  local function choose_subtarget(i,k,pos)
    args.choices[i]={index=k,pos=pos}
  end
  if #targets==1 then
    local k,pos=next(targets[1])
    choose_subtarget(1,k,pos)
    return {paths={[Pos2Str(pos)]=pos},choices=args.choices}
  end
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

  if not args.seeded then
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

    args.seeded = true
  end

  local function FindMergeTarget()
    local process_distance = args.distance or 1
    local i = args.search_target or next(target_neighbourhoods)
    local budget = math.max(1, math.floor(4096/#adjacency))
    while true do
      while i do
        local target_neighbourhood = target_neighbourhoods[i]
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

          if budget == 0 then
            target_neighbourhood_index[i] = idx
            args.search_target, args.distance = i, process_distance
            return false
          end
          budget = budget-1
          local pos = next_neighbour.pos
          --print("idx = "..idx..", pos ("..pos.x..","..pos.y..")")

          for _, off in pairs(adjacency)
          do
            local candidate = { x = pos.x + off.x, y = pos.y + off.y }
            local candidate_s = Pos2Str(candidate)
            --print("Considering candidate ("..candidate.x..","..candidate.y.."), forbidden="..serpent.block(forbidden[candidate_s])..", valid="..serpent.block(valid))
            if in_bounds(args.bounds,candidate) and not args.forbidden[candidate_s] and not extra_forbidden[candidate_s]
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
                  args.search_target, args.distance = nil, nil
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
            debug({"mpp-oil.msg_too_big"})
            return nil
          end
        end

        target_neighbourhood_index[i] = idx
        i = next(target_neighbourhoods,i)
      end
      i = next(target_neighbourhoods)
      process_distance = process_distance + 1
    end
  end


  if MoreThanOne(target_neighbourhoods) then
    local merge_target = FindMergeTarget()

    if merge_target == false then return end
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
          debug("Generated path was too long")
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

    end

    return
  end

  return {
    paths=paths, choices=args.choices
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

local function convert_pipes(tree_result, underground_proto)
  local directions, directional_pipes = {}, {}
  for i,choice in pairs(tree_result.choices) do
    directions[i]=choice.index
    local key=Pos2Str(choice.pos)
    directional_pipes[key]=directional_pipes[key] and 0 or choice.index
  end
  local pipes = tree_result.paths
  local undergrounds = {}

  if not underground_proto then return {directions=directions,pipes=pipes,undergrounds=undergrounds} end
  local min_underground_distance = 3
  local max_underground_distance = underground_proto.max_underground_distance
  -- Only scan occupied rows and columns. Long empty spans do not participate in conversion.
  local spans = {x={},y={}}
  for _,p in pairs(pipes) do
    for _,axis in ipairs{"x","y"} do
      local key = p[axis]
      local inner = axis=="x" and p.y or p.x
      local span = spans[axis][key]
      if not span then spans[axis][key]={inner,inner}
      else span[1],span[2]=math.min(span[1],inner),math.max(span[2],inner) end
    end
  end
  -- Now we have placed all the pipes, we want to search for places where we
  -- might be able to replace a sequence of pipes with an underground pipe.
  local function ReplacePipes(args)
    local outer_name = args.outer
    local inner_name = args.inner
    local lower_direction = args.lower_direction
    local upper_direction = args.upper_direction
    local valid_directions = args.valid_directions

    local lines = {}
    for outer in pairs(spans[outer_name]) do table.insert(lines,outer) end
    table.sort(lines)
    for _,outer in ipairs(lines) do
      local span=spans[outer_name][outer]
      local min_inner,max_inner=span[1],span[2]
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
    inner="y",
    valid_directions=valid_directions,
    lower_direction=defines.direction.north,
    upper_direction=defines.direction.south,
  }
  local valid_directions = {}
  valid_directions[2] = true
  valid_directions[4] = true
  ReplacePipes{
    outer="y",
    inner="x",
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

local function heat_targets(entities)
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

  return targets
end

-- Build candidates and make one greedy choice in bounded passes. Candidate order
-- is also the tie breaker, so saving between passes cannot change the result.
local function beacon_step(job, settings)
  local b = job.beacon_search
  local bounds = job.bounds
  local proto = prototypes.entity[job.names.beacon]
  local reach = proto.get_supply_area_distance(job.qualities.beacon)+job.beacon_radius+job.radius-1
  local profile = proto.profile or {1}
  if not b then
    b={x=bounds.min_x,y=bounds.min_y,candidates={},counts={},index=1}
    job.beacon_search=b
  end
  if b.x then
    local budget=math.max(1,math.floor(1024/#job.positions))
    for _=1,budget do
      local x,y=b.x,b.y
      local pos={x=x,y=y}
      if not AnySpotForbidden{position=pos,collision_box=proto.collision_box,forbidden=job.forbidden} then
        local matches={}
        for i,target in ipairs(job.positions) do
          if math.max(math.abs(x-target.x), math.abs(y-target.y)) <= reach then table.insert(matches,i) end
        end
        if #matches>0 then table.insert(b.candidates,{pos=pos,targets=matches}) end
      end
      b.y=y+1
      if b.y>bounds.max_y then b.y=bounds.min_y; b.x=x+1 end
      if b.x>bounds.max_x then b.x=nil; break end
    end
    return
  end
  local last=job.beacons[#job.beacons]
  local function effect(n) return n*(profile[n] or profile[#profile]) end
  for i=b.index,math.min(#b.candidates,b.index+255) do
    local c=b.candidates[i]
    if not c.discarded then
      local score=0
      for _,target in ipairs(c.targets) do
        local count=b.counts[target] or 0
        score=score+effect(count+1)-effect(count)
      end
      if score<(settings.min_beacon_utility or 2) or (last and math.max(
        math.abs(last.x-c.pos.x),math.abs(last.y-c.pos.y))<2*job.beacon_radius) then c.discarded=true
      elseif not b.best or score>b.score then b.best,b.score=i,score end
    end
    b.index=i+1
  end
  if b.index<=#b.candidates then return end
  if not b.best then job.beacon_search=nil; return true end
  local chosen=b.candidates[b.best]
  table.insert(job.beacons,chosen.pos)
  for _,target in ipairs(chosen.targets) do b.counts[target]=(b.counts[target] or 0)+1 end
  b.best,b.score,b.index=nil,nil,1
end

local function pole_tree(args)
  local bounds = args.bounds
  local entity_sets = args.targets
  local forbidden = args.forbidden
  local wire_reach = args.wire_reach
  local supply_distance = args.supply_distance
  local size = args.size

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

  return {targets=targets, bounds=offset_bounds, adjacency=pole_adjacency,
    forbidden=offset_forbidden, forbid_adjacency=forbid_adjacency, skip_flood_fill=true}
end

local function begin(state,debug)
  local player_data,entities,surface = state.oil_settings,state.resources,state.surface
  local oil_patches = {}
  local chosen_entity_name
  local resource_category
  local choice_key
  local quality_key

  for _, entity in ipairs(entities)
  do
    if not entity.valid then debug({"mpp-oil.msg_no_patches"}); return end
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

  -- Native fluidbox positions use north, east, south, west order.
  local direction_offset_array = {
    { x = 0, y = -1 },
    { x = 1, y = 0 },
    { x = 0, y = 1 },
    { x = -1, y = 0 },
  }

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

  local positions={}
  for _, patch in ipairs(oil_patches)
  do
    local pos = patch.position
    table.insert(positions,pos)
    local subtargets = {}
    for i, offset in ipairs(pipe_connection.positions)
    do
      local direction_offset = direction_offset_array[i]
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

  return {phase="scan",bounds=bounds,positions=positions,outlets=out_pipe_sets,forbidden=forbidden_points,
    patches=oil_patches,needs_heat=entities_require_heating and heat_pipe_type~="none",radius=pumpjack_radius,beacon_radius=beacon_radius,
    names={pump=pumpjack_type,pipe=pipe_type,underground=underground_pipe_type,heat=heat_pipe_type,
      beacon=beacon_type,pole=power_pole_type},
    qualities={pump=pumpjack_quality,pipe=pipe_quality,underground=underground_pipe_quality,heat=heat_pipe_quality,
      beacon=beacon_quality,pole=power_pole_quality},beacons={},placements={},ignored=obstacles.ignored_entities(state)}
end

local function begin_pipes(job)
  job.tree={bounds=job.bounds,targets=table.deepcopy(job.outlets),adjacency=orthogonal_neighbours,
    forbidden=job.pipe_forbidden or job.forbidden}
  job.phase="pipes"
end

local function begin_heat(job)
  local entities={}
  local forbidden=CopyTable(job.forbidden)
  local function add(pos,kind)
    table.insert(entities,{position=pos,prototype=prototypes.entity[job.names[kind]]})
    forbidden[Pos2Str(pos)]=true
  end
  for _,pos in pairs(job.route.pipes) do add(pos,"pipe") end
  for _,pair in pairs(job.route.undergrounds) do add(pair.pos,"underground") end
  job.pipe_positions={}
  for _,e in ipairs(entities) do table.insert(job.pipe_positions,e.position) end
  for _,pos in ipairs(job.positions) do add(pos,"pump") end
  job.tree={targets=heat_targets(entities),bounds=job.bounds,adjacency=orthogonal_neighbours,forbidden=forbidden}
  job.phase="heat"
end

local function add_placement(job,kind,pos,direction)
  table.insert(job.placements,{kind=kind,position=pos,direction=direction})
end

local function finish_route(job,heat)
  local directions={defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west}
  for i,pos in ipairs(job.positions) do
    add_placement(job,"pump",pos,directions[assert(job.route.directions[i])])
  end
  local function add_pipe(kind,pos,direction)
    add_placement(job,kind,pos,direction)
    job.forbidden[Pos2Str(pos)]=true
  end
  for _,pos in pairs(job.route.pipes) do add_pipe("pipe",pos) end
  for _,pair in pairs(job.route.undergrounds) do add_pipe("underground",pair.pos,pair.direction) end
  for _,pos in pairs(heat or {}) do add_pipe("heat",pos) end
  job.route,job.pipe_positions,job.pipe_forbidden,job.tree,job.outlets=nil,nil,nil,nil,nil
  job.phase="beacons"
end

local function place_batch(job,state,observers)
  local player=state.player
  local first=job.next_placement or 1
  local ghosts={}
  for i=first,math.min(first+63,#job.placements) do
    local place=job.placements[i]
    -- Pumpjacks are the first placements, in patch order. A patch can be
    -- depleted or removed while a multi-tick route is still being planned.
    if place.kind=="pump" and not job.patches[i].valid then
      observers.message({"mpp-oil.msg_no_patches"}); return false
    end
    local proto=prototypes.entity[job.names[place.kind]]
    local quality=job.qualities[place.kind]
    local box=obstacles.entity_box(proto.name,place.position,place.direction)
    local index=obstacles.collect(state.surface,box,job.ignored,state)
    local ghost=ForceGhostAt{surface=state.surface,player=player,proto=proto,position=place.position,
      direction=place.direction,quality=quality,terrain_choices=state,obstacles=index,
      module_plan=observers.module_plan(proto,quality),on_created=observers.on_created,
      on_deconstruction=observers.on_deconstruction,on_blocked=observers.on_blocked,
      preview_only=state.preview_only,on_preview=observers.on_preview}
    if ghost then
      if not state.preview_only and ghost.valid and ghost.unit_number then job.ignored[ghost.unit_number]=true end
      table.insert(ghosts,ghost)
      if job.module_ghosts then table.insert(job.module_ghosts,ghost) end
    end
  end
  if state.oil_settings.add_landfill then
    AddLandfillUnder{player=player,ghosts=ghosts,filled=job.filled,debug=observers.message,
      on_created=observers.on_created,preview_only=state.preview_only,on_preview=observers.on_preview,
      terrain_choices=state,on_blocked=observers.on_blocked}
  end
  job.next_placement=first+64
  if job.next_placement<=#job.placements then return end
  if job.module_ghosts and remote.interfaces.ModuleInserterEx then
    remote.call("ModuleInserterEx","apply_module_config_to_entities",player.index,job.module_ghosts)
  end
  return true
end

-- nil means continue next tick, true means built, false means planning failed.
-- Only data lives in oil_job. Engine callbacks are rebound at every invocation.
function layout.step(state,observers)
  local job=state.oil_job
  local message=observers.message
  if not job then
    state.oil_job=begin(state,message)
    if not state.oil_job then return false end
    return
  end
  if job.phase=="scan" then
    if scan(job,state) then begin_pipes(job) end
  elseif job.phase=="pipes" then
    local tree=SolveSteinerTree(job.tree,message)
    if not tree then return end
    if tree.failed then
      ReportSteinerTreeFailure(tree,message,job.names.pipe)
      message({"mpp-oil.msg_pipe_layout_failed"}); return false
    end
    job.route=convert_pipes(tree,job.names.underground~="none" and prototypes.entity[job.names.underground])
    if job.needs_heat then begin_heat(job) else finish_route(job) end
  elseif job.phase=="heat" then
    local tree=SolveSteinerTree(job.tree,message)
    if not tree then return end
    if tree.failed then
      if tree.unreachable_targets then
        job.pipe_forbidden=job.pipe_forbidden or CopyTable(job.forbidden)
        for _,i in ipairs(tree.unreachable_targets) do
          local pos=job.pipe_positions[i]
          if not pos then message({"mpp-oil.msg_heat_pipe_layout_failed"}); return false end
          job.pipe_forbidden[Pos2Str(pos)]=true
        end
        begin_pipes(job)
      else message({"mpp-oil.msg_heat_pipe_layout_failed"}); return false end
    else finish_route(job,tree.paths) end
  elseif job.phase=="beacons" then
    if job.names.beacon~="none" then
      if not beacon_step(job,state.oil_settings) then return end
      local box=prototypes.entity[job.names.beacon].collision_box
      for _,pos in ipairs(job.beacons) do
        add_placement(job,"beacon",pos)
        ForbidPointsInBox{pos=pos,collision_box=box,forbidden=job.forbidden}
      end
    end
    job.phase="poles"
  elseif job.phase=="poles" then
    if job.names.pole~="none" then
      if not job.tree then
        local proto=prototypes.entity[job.names.pole]
        local q=job.qualities.pole
        local box=proto.collision_box
        job.tree=pole_tree{bounds=job.bounds,forbidden=job.forbidden,
          targets={{poss=job.positions,radius=job.radius},{poss=job.beacons,radius=job.beacon_radius}},
          wire_reach=proto.get_max_wire_distance(q),supply_distance=proto.get_supply_area_distance(q),
          size=math.ceil(box.right_bottom.x-box.left_top.x)}
      end
      local tree=SolveSteinerTree(job.tree,message)
      if not tree then return end
      if tree.failed then
        ReportSteinerTreeFailure(tree,message,job.names.pole)
        message({"mpp-oil.msg_pole_layout_failed"}); return false
      end
      for _,pos in pairs(tree.paths) do add_placement(job,"pole",pos) end
    end
    local setting=state.player.mod_settings["mpp-oil-interface-with-module-inserter-ex"]
    if not state.preview_only and setting and setting.value and remote.interfaces.ModuleInserterEx then job.module_ghosts={} end
    job.tree,job.forbidden,job.filled,job.phase=nil,nil,{},"place"
  elseif job.phase=="place" then
    return place_batch(job,state,observers)
  else error("Unknown oil planning phase: "..tostring(job.phase)) end
end

return layout
