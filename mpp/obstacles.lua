local util = require("mpp.mpp_util")
local terrain = require("mpp.terrain")
local obstacles = {}
local cache = setmetatable({}, {__mode="k"})
local floor, ceil = math.floor, math.ceil
local ignored_types = {"resource", "character", "unit", "corpse", "item-entity", "tile-ghost"}
local hazard_tiles
local geometry_cache={}
local shared_shapes={}
local shared_cache=setmetatable({}, {__mode="k"})
local owned_ids=setmetatable({}, {__mode="k"})

local function key(x, y) return x..","..y end

obstacles.blocked_tile = terrain.blocked_tile

function obstacles.active(state)
	for _, setting in ipairs(terrain.tile_choices) do if state[setting] ~= nil then return true end end
	return state.cliff_mode_choice ~= nil or state.terrain_mode_choice ~= nil
		or state.avoid_obstacles_choice or state.avoid_water_choice or state.avoid_cliffs_choice
		or state.remove_entities_choice ~= nil or state.remove_trees_choice ~= nil or state.remove_rocks_choice ~= nil
		or state.deconstruction_choice or state.landfill_choice
end

function obstacles.collect(surface, area, ignored, choices)
	local index = {tiles={}, underground_tiles={}, cells={}, boxes={}, boxes_by_cell={}}
	local function cell(x, y) index.cells[key(x,y)] = {x=x, y=y} end
	if not hazard_tiles and prototypes.tile then
		local names={}
		for name,proto in pairs(prototypes.tile) do
			if terrain.blocked_tile{name=name,prototype=proto} then names[#names+1]=name end
		end
		if #names>0 then table.sort(names);hazard_tiles=names end
	end
	-- Filter in the engine instead of materializing every grass tile in Lua.
	for _, tile in pairs(surface.find_tiles_filtered{area=area,name=hazard_tiles}) do
		local layers=tile.prototype.collision_mask.layers
		if layers.lava_tile or layers.empty_space or layers.out_of_map then
			index.underground_tiles[key(tile.position.x,tile.position.y)]=true
		end
		if (not choices and terrain.blocked_tile(tile)) or (choices and terrain.blocks_tile(tile, choices)) then
			local pos = tile.position
			index.tiles[key(pos.x,pos.y)] = true
			cell(pos.x,pos.y)
		end
	end
	-- Explicit output forcing delegates entity conflicts to native blueprints,
	-- but it must still route around terrain whose filling is disabled.
	if choices and choices._force_build_mode and choices._belt_routing then return index end
	-- Ore patches can contain thousands of resources that never obstruct placement.
	for _, entity in pairs(surface.find_entities_filtered{area=area,type=ignored_types,invert=true}) do
		if entity.valid and not (entity.unit_number and ignored and ignored[entity.unit_number]) then
			local proto = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
			local layers = proto.collision_mask.layers
			local selected = not choices or terrain.blocks_entity(entity, choices)
			if selected and (entity.type == "cliff" or layers.object or layers.player or layers.train) then
				local box = entity.bounding_box
				index.boxes[#index.boxes + 1] = box
				for x=floor(box.left_top.x),ceil(box.right_bottom.x)-1 do
					for y=floor(box.left_top.y),ceil(box.right_bottom.y)-1 do
						local k=key(x,y)
						local bucket=index.boxes_by_cell[k] or {}
						index.boxes_by_cell[k]=bucket;bucket[#bucket+1]=box
					end
				end
				for x=floor(box.left_top.x + 0.001),ceil(box.right_bottom.x - 0.001)-1 do
					for y=floor(box.left_top.y + 0.001),ceil(box.right_bottom.y - 0.001)-1 do cell(x,y) end
				end
			end
		end
	end
	return index
end

function obstacles.blocked_bounds(index, x1,y1,x2,y2)
	for x=floor(x1 + 0.001),ceil(x2 - 0.001)-1 do
		for y=floor(y1 + 0.001),ceil(y2 - 0.001)-1 do
			if index.tiles[key(x,y)] then return true end
		end
	end
	if index.boxes_by_cell then
		for x=floor(x1),ceil(x2)-1 do
			for y=floor(y1),ceil(y2)-1 do
				local bucket=index.boxes_by_cell[key(x,y)]
				if bucket then for _,other in ipairs(bucket) do if x1<other.right_bottom.x and x2>other.left_top.x and y1<other.right_bottom.y and y2>other.left_top.y then return true end end end
			end
		end
	else
		for _, other in ipairs(index.boxes) do if x1<other.right_bottom.x and x2>other.left_top.x and y1<other.right_bottom.y and y2>other.left_top.y then return true end end
	end
	return false
end

function obstacles.blocked_box(index, box)
 return obstacles.blocked_bounds(index,box.left_top.x,box.left_top.y,box.right_bottom.x,box.right_bottom.y)
end

function obstacles.entity_bounds(name, px, py, direction)
 local proto=prototypes.entity[name]
 local shapes=geometry_cache[name]
 if not shapes or shapes.prototype~=proto then shapes={prototype=proto};geometry_cache[name]=shapes end
 local k=direction or false
 local shape=shapes[k]
 if not shape then
		local box=proto.collision_box
		local x1,y1,x2,y2=box.left_top.x,box.left_top.y,box.right_bottom.x,box.right_bottom.y
		local width,height=proto.tile_width,proto.tile_height
		if direction==defines.direction.east then x1,y1,x2,y2=-y2,x1,-y1,x2
		elseif direction==defines.direction.south then x1,y1,x2,y2=-x2,-y2,-x1,-y1
		elseif direction==defines.direction.west then x1,y1,x2,y2=y1,-x2,y2,-x1 end
		if direction==defines.direction.east or direction==defines.direction.west then width,height=height,width end
		shape={prototype=proto,x1=x1,y1=y1,x2=x2,y2=y2,ox=(width%2)/2,oy=(height%2)/2,
			off_grid=proto.has_flag("placeable-off-grid")}
		shapes[k]=shape
	end
	if not shape.off_grid then
		-- Ghost creation snaps odd-sized buildings to tile centers and even sizes to edges.
		px,py = floor(px+0.5-shape.ox)+shape.ox,floor(py+0.5-shape.oy)+shape.oy
	end
 return px+shape.x1,py+shape.y1,px+shape.x2,py+shape.y2
end

function obstacles.entity_box(name, position, direction)
 local x1,y1,x2,y2=obstacles.entity_bounds(name,position.x,position.y,direction)
 return {left_top={x=x1,y=y1},right_bottom={x=x2,y=y2}}
end

function obstacles.get(state)
	local saved = cache[state]
	local search_area=state._belt_search_area
	if saved and saved.tick == game.tick then
		if search_area then
			local area=saved.area
			if area[1][1]<=search_area[1][1] and area[1][2]<=search_area[1][2]
				and area[2][1]>=search_area[2][1] and area[2][2]>=search_area[2][2] then return saved.index end
		elseif not saved.explicit_area and saved.margin >= (state._belt_search_margin or 0) then return saved.index end
	end
	local c = state.coords
	local margin = (state.miner and state.miner.area or 5) + 32
	local x1,y1,x2,y2 = c.x1,c.y1,c.x2,c.y2
	if state.belt_target then
		local pos = state.belt_target.position
		x1,y1 = math.min(x1,pos.x),math.min(y1,pos.y)
		x2,y2 = math.max(x2,pos.x),math.max(y2,pos.y)
		margin = math.max(margin, (state.belt_specification and state.belt_specification.count or 0) + 16,
			state._belt_search_margin or 0)
	end
	local ignored = {}
	local previous = state._previous_state
	if not previous and state.player then
		local data = storage.players[state.player.index]
		local last = data and data.last_state
		if last and last.surface == state.surface and util.coords_overlap(c, last.coords) then previous = last end
	end
	local seen_lists={}
	for _, list in pairs{state._collected_ghosts or {}, previous and previous._collected_ghosts or {}} do
		if not seen_lists[list] then
			seen_lists[list]=true
			for _, entity in pairs(list) do
				-- Ownership is reread each time. An entity's unit number is immutable;
				-- retaining the number of a destroyed entity cannot hide a new one.
				local id=owned_ids[entity]
				if not id and entity.valid then id=entity.unit_number;owned_ids[entity]=id end
				if id then ignored[id]=true end
			end
		end
	end
	local area=search_area or {{x1-margin,y1-margin},{x2+margin,y2+margin}}
	local index = obstacles.collect(state.surface,area,ignored,state)
	cache[state] = {tick=game.tick,index=index,margin=margin,area=area,explicit_area=search_area~=nil}
	return index
end

local function shared_match(entity,name,x,y,direction,quality)
 if not entity.valid or not (entity.name==name or entity.type=="entity-ghost" and entity.ghost_name==name)
  or entity.direction~=direction then return end
 local q=entity.quality
 if q and q.name~=quality then return end
 local p=entity.position
 if math.abs(p.x-x)<.001 and math.abs(p.y-y)<.001 then return entity end
end

function obstacles.shared_entity(state,name,position,direction,quality)
 if not state.output_only then return end
 local proto=prototypes.entity[name]
 if not proto then return end
 local shape=shared_shapes[name]
 if not shape or shape.prototype~=proto then
  local kind=proto.type
  shape={prototype=proto,reusable=kind=="transport-belt" or kind=="straight-rail"};shared_shapes[name]=shape
 end
 if not shape.reusable then return end
 local px,py=position.x,position.y
 quality=quality or "normal"
 if state.preview_only then
  -- Numeric rows avoid per-belt string keys and candidate arrays. Buckets are
  -- still tick-scoped: construction and subsequent ticks observe world changes.
  local saved=shared_cache[state]
  if not saved or saved.tick~=game.tick then saved={tick=game.tick,chunks={}};shared_cache[state]=saved end
  local cx,cy=floor(px/32),floor(py/32)
  local row=saved.chunks[cy]
  if not row then row={};saved.chunks[cy]=row end
  local buckets=row[cx]
  if buckets==nil then
   local query=state.surface.find_entities_filtered
   if not query then return end
   local entities=query{
    area={{cx*32-.05,cy*32-.05},{(cx+1)*32+.05,(cy+1)*32+.05}},
    type={"transport-belt","straight-rail","entity-ghost"},force=state.player.force}
   buckets=false
   for _,entity in pairs(entities) do
    if not buckets then buckets={} end
    local p=entity.position
    local x,y=floor(p.x),floor(p.y)
    local cells=buckets[x]
    if not cells then cells={};buckets[x]=cells end
    local list=cells[y]
    if not list then list={};cells[y]=list end
    list[#list+1]=entity
   end
   row[cx]=buckets
  end
  if not buckets then return end
  for x=floor(px-.001),floor(px+.001) do
   local cells=buckets[x]
   if cells then for y=floor(py-.001),floor(py+.001) do
    local list=cells[y]
    if list then for _,entity in ipairs(list) do
     local result=shared_match(entity,name,px,py,direction,quality)
     if result then return result end
    end end
   end end
  end
 else
  local query=state.surface.find_entities_filtered
  if not query then return end
  for _,entity in pairs(query{position=position,radius=.05,force=state.player.force}) do
   local result=shared_match(entity,name,px,py,direction,quality)
   if result then return result end
  end
 end
end

-- A routing attempt is synchronous and cannot change the world. Resolve its
-- obstacle snapshot once, outside the potentially large path-search loop.
function obstacles.placement_checker(state,name,direction)
	if not obstacles.active(state) then return function() return true end end
	local index=obstacles.get(state)
	if not next(index.tiles) and #index.boxes==0 then return function() return true end end
	return function(position)
		return not obstacles.blocked_bounds(index,obstacles.entity_bounds(name,position.x,position.y,direction))
			or not (state._force_build_mode and state._belt_routing) and obstacles.shared_entity(state,name,position,direction,state.belt_quality_choice)~=nil
	end
end

function obstacles.can_place(state, name, position, direction)
	if not obstacles.active(state) then return true end
	-- Most route probes are empty ground. Only query the engine for a reusable
	-- entity when the broad phase actually found an obstruction at this position.
	if not obstacles.blocked_bounds(obstacles.get(state),obstacles.entity_bounds(name,position.x,position.y,direction)) then return true end
	return not (state._force_build_mode and state._belt_routing) and obstacles.shared_entity(state,name,position,direction,state.belt_quality_choice)~=nil
end

function obstacles.mark_grid(state)
	local c, grid, size = state.coords, state.grid, state.miner.size
	local convert = util.coord_convert[state.direction_choice]
	local index=obstacles.get(state)
	for _, pos in pairs(index.cells) do
		-- Invert revert_world at the tile center, including its half-tile offset.
		local x,y = convert(pos.x+0.5-c.gx,pos.y+0.5-c.gy,c.w,c.h)
		x,y = floor(x+0.5),floor(y+0.5)
		local tile = grid:get_tile(x,y)
		if tile then tile.avoid = true end
		-- Dense big drills need dry shoreline space for their receiving belts
		-- and detours; a clear footprint alone can strand the drop on lava.
		local margin=state._capacity_tight_big and index.tiles[key(pos.x,pos.y)] and (state._shore_margin or 2) or 0
		grid:forbid(x-size+1-margin,y-size+1-margin,size+margin*2)
	end
end

local function world(state, spec)
	local c = state.coords
	local pos = util.revert_world(c.gx,c.gy,state.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
	return {x=pos[1],y=pos[2]}, util.bp_direction[state.direction_choice][spec.direction or defines.direction.north]
end

local function safe(state, spec)
	if not spec.name or not prototypes.entity[spec.name] then return true end
	local pos,dir = world(state,spec)
	return obstacles.can_place(state,spec.name,pos,dir)
end

local function failure(state, spec, reason)
	if state.preview_only then
		local pos,dir=world(state,spec)
		local box=obstacles.entity_box(spec.name,pos,dir)
		pos={x=(box.left_top.x+box.right_bottom.x)/2,y=(box.left_top.y+box.right_bottom.y)/2}
		state._preview_issues=state._preview_issues or {}
		state._preview_issues[#state._preview_issues+1]={position=pos,reason={reason}}
	end
	return false
end

local directions = {defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west}

function obstacles.route_belts(state, specs)
 state._underground_fill=nil
 local index=obstacles.get(state)
 if not next(index.tiles) and #index.boxes==0 and not next(index.underground_tiles or {}) then return true,specs end
 local by_position, occupied, removed, added = {}, {}, {}, {}
 local work={}
 local function register(spec)
  local k=key(spec.grid_x,spec.grid_y)
  occupied[k]=spec;by_position[k]=spec;work[#work+1]=spec
 end
 for _,spec in ipairs(specs or {}) do
  local kind=prototypes.entity[spec.name].type
  occupied[key(spec.grid_x,spec.grid_y)]=spec
  if kind=="transport-belt" or kind=="underground-belt" then by_position[key(spec.grid_x,spec.grid_y)]=spec end
  work[#work+1]=spec
 end
 local underground_tiles=index.underground_tiles or {}
 local function underground_blocked(x,y)
  -- Space Age also checks tiles below the tunnel, independently of whether
  -- filling is allowed. These masks are not exposed by runtime prototypes.
  local pos=world(state,{grid_x=x,grid_y=y})
  local k=key(floor(pos.x),floor(pos.y))
  return underground_tiles[k] and k
 end
 local function partner(spec)
  local delta=util.direction_coord[spec.direction]
  local sign=spec.type=="input" and 1 or -1
  for distance=1,state.belt.underground_reach or 0 do
   local candidate=by_position[key(spec.grid_x+delta.x*sign*distance,spec.grid_y+delta.y*sign*distance)]
   if candidate and candidate.name==spec.name and candidate.direction==spec.direction and candidate.type~=spec.type then return candidate end
  end
 end
 local function crosses_lava(spec)
  local other=partner(spec)
  if not other then return false end
  local d=util.direction_coord[spec.direction];local sign=spec.type=="input" and 1 or -1
  local distance=math.abs(other.grid_x-spec.grid_x)+math.abs(other.grid_y-spec.grid_y)
  for offset=1,distance-1 do
   local k=underground_blocked(spec.grid_x+d.x*sign*offset,spec.grid_y+d.y*sign*offset)
   if k and index.tiles[k] then return true end
  end
  return false
 end
 local function clear(spec)
  removed[spec]=true
  local k=key(spec.grid_x,spec.grid_y)
  if occupied[k]==spec then occupied[k]=nil end
  if by_position[k]==spec then by_position[k]=occupied[k] end
 end
 local function blocked(spec)
  local tile=state.grid and state.grid:get_tile(floor(spec.grid_x),floor(spec.grid_y))
  return spec._route_crossing or tile and tile.built_thing and tile.built_thing~="belt" or not safe(state,spec)
 end
 -- A shoreline can cut through a previously chosen tunnel endpoint. Expand
 -- the whole pair before repairing its surface run, including reserved poles.
 local function expand(spec)
  if prototypes.entity[spec.name].type~="underground-belt" then return true end
  local delta=util.direction_coord[spec.direction]
  local sign=spec.type=="input" and 1 or -1
  local other=partner(spec)
  if not other then return false end
  local distance=math.abs(other.grid_x-spec.grid_x)+math.abs(other.grid_y-spec.grid_y)
  clear(spec);clear(other)
  for offset=0,distance do
   local replacement={name=state.belt_choice,quality=spec.quality,thing="belt",
    grid_x=spec.grid_x+delta.x*sign*offset,grid_y=spec.grid_y+delta.y*sign*offset,direction=spec.direction}
   local k=key(replacement.grid_x,replacement.grid_y)
   if occupied[k] then
    -- Keep the crossing's surface belt. This virtual cell belongs only to
    -- the expanded tunnel chain and must be routed around (or underneath).
    replacement._route_crossing=true;by_position[k]=replacement;work[#work+1]=replacement
   else register(replacement) end
   added[#added+1]=replacement
  end
  return true
 end
 for _,spec in ipairs(specs or {}) do
  if not removed[spec] and prototypes.entity[spec.name].type=="underground-belt" and (not safe(state,spec) or crosses_lava(spec)) then
   if not expand(spec) then return failure(state,spec,"mpp.preview_issue_belt") end
  end
 end
 local receiving={}
 for _,miner in ipairs(state.best_attempt and state.best_attempt.miners or {}) do
  local offset=state.miner.output_rotated[miner.direction]
  if offset then receiving[key(miner.x+offset.x,miner.y+offset.y)]=true end
 end
 local incoming={}
 local function refresh_incoming()
 incoming={}
 for _,spec in pairs(by_position) do
  if prototypes.entity[spec.name].type=="transport-belt" or spec.type=="output" then
   local d=util.direction_coord[spec.direction or defines.direction.north]
   local k=key(spec.grid_x+d.x,spec.grid_y+d.y);local target=by_position[k]
   if target and target.direction~=(spec.direction+defines.direction.south)%16 then
    incoming[k]=incoming[k] or {};incoming[k][#incoming[k]+1]=spec
    if target.direction~=spec.direction then receiving[k]=true end
   end
  end
 end
 end
 local function path(start,finish,model,margin)
  local reach=state.belt and state.belt.underground_reach or 0
  local underground=state.belt and state.belt.related_underground_belt
  local function node_key(x,y,dir,tunnel) return key(x,y)..":"..dir..(tunnel and "u" or "s") end
  local queue,head,visited={{grid_x=start.grid_x,grid_y=start.grid_y,direction=start.direction,tunnel=start.type=="output"}},1,{}
  visited[node_key(start.grid_x,start.grid_y,start.direction)]=true
  local min_x,max_x=math.min(start.grid_x,finish.grid_x)-margin,math.max(start.grid_x,finish.grid_x)+margin
  local min_y,max_y=math.min(start.grid_y,finish.grid_y)-margin,math.max(start.grid_y,finish.grid_y)+margin
  local passable_cache,tunnel_cache={},{}
  local function passable(x,y,dir)
   local k=key(x,y);local free=passable_cache[k]
   if free==nil then
    free=(x==finish.grid_x and y==finish.grid_y or not occupied[k]) and not blocked{name=model.name,grid_x=x,grid_y=y,direction=dir}
    passable_cache[k]=not not free
   end
   return free
  end
  local function tunnel_clear(x,y,dir)
   local k=node_key(x,y,dir);local free=tunnel_cache[k]
   if free==nil then
    free=not receiving[key(x,y)]
    local d=util.direction_coord[dir]
    if free then
     local behind,ahead
     for offset=1,reach do
      local back=occupied[key(x-d.x*offset,y-d.y*offset)]
      local front=occupied[key(x+d.x*offset,y+d.y*offset)]
      if not behind and back and back.name==underground and back.direction%8==dir%8 then behind=back end
      if not ahead and front and front.name==underground and front.direction%8==dir%8 then ahead=front end
     end
     if behind and ahead and partner(behind)==ahead then free=false end
    end
    if free then free=safe(state,{name=underground,grid_x=x,grid_y=y,direction=dir}) end
    tunnel_cache[k]=not not free
   end
   return free
  end
  local function enqueue(node,x,y,dir,tunnel)
   local endpoint=x==finish.grid_x and y==finish.grid_y
   local k=node_key(x,y,dir,tunnel)
   if not visited[k] and x>=min_x and x<=max_x and y>=min_y and y<=max_y
    and not (endpoint and (tunnel and (dir~=finish.direction or finish.type) or finish.type and dir~=finish.direction or dir==(finish.direction+defines.direction.south)%16))
    and passable(x,y,dir) then
    local previous=node
    while previous do
     if previous.grid_x==x and previous.grid_y==y then return end
     if tunnel and previous.tunnel and previous.previous and previous.direction%8==dir%8 then
      local a,b=previous,previous.previous
      if dir%8==0 and x==a.grid_x and math.min(y,node.grid_y)<math.max(a.grid_y,b.grid_y)
       and math.max(y,node.grid_y)>math.min(a.grid_y,b.grid_y) then return end
      if dir%8==4 and y==a.grid_y and math.min(x,node.grid_x)<math.max(a.grid_x,b.grid_x)
       and math.max(x,node.grid_x)>math.min(a.grid_x,b.grid_x) then return end
     end
     previous=previous.previous
    end
    visited[k]=true
    queue[#queue+1]={grid_x=x,grid_y=y,direction=dir,tunnel=tunnel,previous=node}
   end
  end
  while head<=#queue and head<=65536 do
   local node=queue[head];head=head+1
   if node.grid_x==finish.grid_x and node.grid_y==finish.grid_y then
    local result={}
    while node do table.insert(result,1,node);node=node.previous end
    return result
   end
   for _,dir in ipairs(directions) do
    local accepts=true
    if not node.previous then for _,source in ipairs(incoming[key(node.grid_x,node.grid_y)] or {}) do
     if not removed[source] and dir==(source.direction+defines.direction.south)%16 then accepts=false;break end
    end end
    if accepts and dir~=(node.direction+defines.direction.south)%16 and (not node.tunnel or dir==node.direction) then
     local delta=util.direction_coord[dir]
     local x,y=node.grid_x+delta.x,node.grid_y+delta.y
     enqueue(node,x,y,dir)
     -- A tunnel must enter and leave straight, with both endpoints on dry
     -- unoccupied tiles. Never hide a mining drop or steal an existing pair.
     if underground and not node.tunnel and dir==node.direction and not passable(x,y,dir)
      and tunnel_clear(node.grid_x,node.grid_y,dir) then
      for distance=2,reach do
       if underground_blocked(node.grid_x+delta.x*(distance-1),node.grid_y+delta.y*(distance-1)) then break end
       local tx,ty=node.grid_x+delta.x*distance,node.grid_y+delta.y*distance
       local existing=occupied[key(tx,ty)]
       if existing and existing.name==underground and existing.direction%8==dir%8 then break end
       if tunnel_clear(tx,ty,dir) then enqueue(node,tx,ty,dir,true) end
      end
     end
    end
   end
  end
 end
 local i=1
 while work[i] do
  local spec=work[i];i=i+1
  if not removed[spec] and prototypes.entity[spec.name].type=="transport-belt" and blocked(spec) then
   local delta=util.direction_coord[spec.direction or defines.direction.north]
   local first,last=spec,spec
   local function neighbor(node,sign)
    local x,y=node.grid_x+delta.x*sign,node.grid_y+delta.y*sign
    local found=by_position[key(x,y)]
    if found and prototypes.entity[found.name].type=="underground-belt" then
     if not expand(found) then return end
     found=by_position[key(x,y)]
    end
    return found
   end
   while true do
    local prev=neighbor(first,-1)
    if not prev or not blocked(prev) then break end
    if prev.direction~=spec.direction then return failure(state,spec,"mpp.preview_issue_belt") end
    first=prev
   end
   while true do
    local next=neighbor(last,1)
    if not next or not blocked(next) then break end
    if next.direction~=spec.direction then return failure(state,spec,"mpp.preview_issue_belt") end
    last=next
   end
   local start,finish=neighbor(first,-1),neighbor(last,1)
   if not start or not finish or start.direction~=spec.direction then return failure(state,spec,"mpp.preview_issue_belt") end
   refresh_incoming()
   local route=path(start,finish,spec,16)
   -- The first dry tile can be trapped between lava and a parallel belt.
   -- Move the turn back over unused surface tiles, keeping every drill drop.
   for _=1,12 do
    if route then break end
    local changed=false
    if not start.type and not receiving[key(start.grid_x,start.grid_y)] then
     local prev=neighbor(start,-1)
     if prev and prev.direction==spec.direction and not blocked(prev) then
      occupied[key(start.grid_x,start.grid_y)]=nil;first=start;start=prev;changed=true
     end
    end
    if not finish.type and not receiving[key(finish.grid_x,finish.grid_y)] then
     local next=neighbor(finish,1)
     if next and next.direction==spec.direction and not blocked(next) then
      occupied[key(finish.grid_x,finish.grid_y)]=nil;last=finish;finish=next;changed=true
     end
    end
    if not changed then break end
    route=path(start,finish,spec,16)
   end
   route=route or path(start,finish,spec,64)
   if not route then return failure(state,spec,"mpp.preview_issue_belt") end
   local x,y=first.grid_x,first.grid_y
   repeat
    clear(by_position[key(x,y)])
    if x==last.grid_x and y==last.grid_y then break end
    x,y=x+delta.x,y+delta.y
   until false
   for index=1,#route-(route[#route].tunnel and 0 or 1) do
    local node,next=route[index],route[index+1]
    local kind=node.tunnel and "output" or next and next.tunnel and "input" or nil
    local replacement={name=kind and state.belt.related_underground_belt or spec.name,
     quality=spec.quality,thing="belt",grid_x=node.grid_x,grid_y=node.grid_y,direction=next and next.direction or finish.direction,type=kind}
    if index==1 then clear(start) elseif index==#route then clear(finish) end
    added[#added+1]=replacement;register(replacement)
   end
  end
 end
 local result={}
 for _,spec in ipairs(specs or {}) do if not removed[spec] then result[#result+1]=spec end end
 for _,spec in ipairs(added) do if not removed[spec] then result[#result+1]=spec end end
 -- Lava beneath retained tunnels needs foundation even where there is no
 -- surface entity. Placement collects these cells along with its footprints.
 for _,spec in ipairs(result) do if spec.type=="input" then
  local other=partner(spec)
  if other then
   local d=util.direction_coord[spec.direction]
   local distance=math.abs(other.grid_x-spec.grid_x)+math.abs(other.grid_y-spec.grid_y)
   for offset=1,distance-1 do
    local k=underground_blocked(spec.grid_x+d.x*offset,spec.grid_y+d.y*offset)
    if k and not index.tiles[k] then
     state._underground_fill=state._underground_fill or {};state._underground_fill[k]=true
    end
   end
  end
 end end
 return true,result
end

-- Removing poles on internal lava can split an otherwise covered mine into
-- islands. Join those components using dry, free pole sites after belt repair.
function obstacles.reconnect_poles(state)
 local poles=state.builder_power_poles or {}
 if not state._capacity_tight_big or #poles<2 then return true end
 local index=obstacles.get(state)
 if not next(index.tiles) and #index.boxes==0 then return true end
 local reach=state.pole.wire;local reach2=reach*reach
 local function nearby(a,b) return (a.grid_x-b.grid_x)^2+(a.grid_y-b.grid_y)^2<=reach2 end
 local offsets={}
 for dx=-floor(reach),floor(reach) do for dy=-floor(reach),floor(reach) do
  if dx*dx+dy*dy>0 and dx*dx+dy*dy<=reach2 then offsets[#offsets+1]={dx,dy} end
 end end
 table.sort(offsets,function(a,b) return a[1]^2+a[2]^2>b[1]^2+b[2]^2 end)
 local free={}
 local function site(x,y)
  local k=key(x,y);local value=free[k]
  if value==nil then
   local tile=state.grid:get_tile(x,y)
   value=tile and not tile.built_thing and safe(state,{name=state.pole_choice,grid_x=x,grid_y=y})
   free[k]=not not value
  end
  return value
 end
 while true do
  local connected,queue={[1]=true},{poles[1]};local head=1
  while queue[head] do
   local node=queue[head];head=head+1
   for i,pole in ipairs(poles) do if not connected[i] and nearby(node,pole) then connected[i]=true;queue[#queue+1]=pole end end
  end
  if #queue==#poles then return true end
  local targets={}
  for i,pole in ipairs(poles) do if not connected[i] then targets[#targets+1]=pole end end
  local visited={}
  for _,pole in ipairs(queue) do visited[key(pole.grid_x,pole.grid_y)]=true end
  head=1;local found
  while queue[head] and head<=16384 and not found do
   local node=queue[head];head=head+1
   if node.previous then for _,target in ipairs(targets) do if nearby(node,target) then found=node;break end end end
   if not found then for _,offset in ipairs(offsets) do
    local x,y=node.grid_x+offset[1],node.grid_y+offset[2]
    local k=key(x,y)
    if not visited[k] then
     visited[k]=true
     if site(x,y) then queue[#queue+1]={grid_x=x,grid_y=y,previous=node} end
    end
   end end
  end
  if not found then return failure(state,targets[1],"mpp.preview_issue_power") end
  while found.previous do
   local pole={name=state.pole_choice,quality=state.pole_quality_choice,thing="pole",grid_x=found.grid_x,grid_y=found.grid_y}
   poles[#poles+1]=pole;state.grid:build_thing_simple(pole.grid_x,pole.grid_y,"pole");free[key(pole.grid_x,pole.grid_y)]=false
   found=found.previous
  end
 end
end

function obstacles.prepare(state)
	for _, spec in ipairs(state.builder_pipes or {}) do
		if not safe(state,spec) then return failure(state,spec,"mpp.preview_issue_pipe") end
	end
	for _, spec in ipairs(state.builder_belts or {}) do
		if prototypes.entity[spec.name].type ~= "transport-belt" and prototypes.entity[spec.name].type ~= "underground-belt" and not safe(state,spec) then
			return failure(state,spec,"mpp.preview_issue_entity")
		end
	end
	local ok,belts=obstacles.route_belts(state,state.builder_belts)
	if not ok then return false end
	if state.grid then for _,spec in ipairs(state.builder_belts or {}) do
		local tile=state.grid:get_tile(spec.grid_x,spec.grid_y)
		if tile and tile.built_thing=="belt" then tile.built_thing=nil end
	end end
	state.builder_belts=belts
	if state.grid then
		for _, spec in ipairs(belts) do state.grid:build_thing_simple(spec.grid_x,spec.grid_y,"belt") end
	end
	for _, list in pairs{state.builder_power_poles or {},state.builder_lamps or {}} do
		for _, spec in ipairs(list) do
			if not safe(state,spec) then
				local x,y=spec.grid_x,spec.grid_y
				local found
				local proto=prototypes.entity[spec.name]
				local function preserves_coverage()
					if proto.type ~= "electric-pole" then return true end
					local reach=proto.get_max_wire_distance(spec.quality or "normal")
					local supply=proto.get_supply_area_distance(spec.quality or "normal")
					local radius=supply+(state.miner and state.miner.size/2 or 0)-1
					for _, miner in ipairs(state.best_attempt and state.best_attempt.miners or {}) do
						if math.abs(miner.origin_x-x)<=radius and math.abs(miner.origin_y-y)<=radius
							and (math.abs(miner.origin_x-spec.grid_x)>radius or math.abs(miner.origin_y-spec.grid_y)>radius) then return false end
					end
					for _, other in ipairs(state.builder_power_poles or {}) do
						if other ~= spec and (other.grid_x-x)^2+(other.grid_y-y)^2 <= reach^2
							and (other.grid_x-spec.grid_x)^2+(other.grid_y-spec.grid_y)^2 > reach^2 then return false end
					end
					return true
				end
				for radius=1,3 do
					for dx=-radius,radius do for dy=-radius,radius do
						if math.max(math.abs(dx),math.abs(dy))==radius then
							spec.grid_x,spec.grid_y=x+dx,y+dy
							local tile=state.grid:get_tile(floor(spec.grid_x),floor(spec.grid_y))
							if not found and tile and not tile.built_thing and safe(state,spec) and preserves_coverage() then found={spec.grid_x,spec.grid_y} end
						end
					end end
					if found then break end
				end
				if not found then
					spec.grid_x,spec.grid_y=x,y
					return failure(state,spec,proto.type=="electric-pole" and "mpp.preview_issue_power" or "mpp.preview_issue_entity")
				end
				spec.grid_x,spec.grid_y=found[1],found[2]
				state.grid:build_thing_simple(spec.grid_x,spec.grid_y,spec.thing)
			end
		end
	end
	return obstacles.reconnect_poles(state)
end

return obstacles
