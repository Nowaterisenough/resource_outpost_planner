local util = require("mpp.mpp_util")
local terrain = require("mpp.terrain")
local obstacles = {}
local cache = setmetatable({}, {__mode="k"})
local floor, ceil = math.floor, math.ceil
local ignored_types = {resource=true, character=true, unit=true, corpse=true,
	["item-entity"]=true, ["entity-ghost"]=false, ["tile-ghost"]=true}
local hazard_tiles
local geometry_cache={}

local function key(x, y) return x..","..y end

obstacles.blocked_tile = terrain.blocked_tile

function obstacles.active(state)
	return state.cliff_mode_choice ~= nil or state.terrain_mode_choice ~= nil
		or state.avoid_obstacles_choice or state.avoid_water_choice or state.avoid_cliffs_choice
		or state.deconstruction_choice or state.landfill_choice
end

local function overlap(a, b)
	return a.left_top.x < b.right_bottom.x and a.right_bottom.x > b.left_top.x
		and a.left_top.y < b.right_bottom.y and a.right_bottom.y > b.left_top.y
end

function obstacles.collect(surface, area, ignored, choices)
	local index = {tiles={}, cells={}, boxes={}, boxes_by_cell={}}
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
		if (not choices and terrain.blocked_tile(tile)) or (choices and terrain.blocks_tile(tile, choices)) then
			local pos = tile.position
			index.tiles[key(pos.x,pos.y)] = true
			cell(pos.x,pos.y)
		end
	end
	for _, entity in pairs(surface.find_entities_filtered{area=area}) do
		if entity.valid and not ignored_types[entity.type]
			and not (entity.unit_number and ignored and ignored[entity.unit_number]) then
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

function obstacles.blocked_box(index, box)
	for x=floor(box.left_top.x + 0.001),ceil(box.right_bottom.x - 0.001)-1 do
		for y=floor(box.left_top.y + 0.001),ceil(box.right_bottom.y - 0.001)-1 do
			if index.tiles[key(x,y)] then return true end
		end
	end
	if index.boxes_by_cell then
		for x=floor(box.left_top.x),ceil(box.right_bottom.x)-1 do
			for y=floor(box.left_top.y),ceil(box.right_bottom.y)-1 do
				local bucket=index.boxes_by_cell[key(x,y)]
				if bucket then for _,other in ipairs(bucket) do if overlap(box,other) then return true end end end
			end
		end
	else
		for _, other in ipairs(index.boxes) do if overlap(box, other) then return true end end
	end
	return false
end

function obstacles.entity_box(name, position, direction)
	local proto = prototypes.entity[name]
	local k=name..":"..tostring(direction)
	local shape=geometry_cache[k]
	if not shape or shape.prototype~=proto then
		local box=proto.collision_box
		local x1,y1,x2,y2=box.left_top.x,box.left_top.y,box.right_bottom.x,box.right_bottom.y
		local width,height=proto.tile_width,proto.tile_height
		if direction==defines.direction.east then x1,y1,x2,y2=-y2,x1,-y1,x2
		elseif direction==defines.direction.south then x1,y1,x2,y2=-x2,-y2,-x1,-y1
		elseif direction==defines.direction.west then x1,y1,x2,y2=y1,-x2,y2,-x1 end
		if direction==defines.direction.east or direction==defines.direction.west then width,height=height,width end
		shape={prototype=proto,x1=x1,y1=y1,x2=x2,y2=y2,ox=(width%2)/2,oy=(height%2)/2,
			off_grid=proto.has_flag("placeable-off-grid")}
		geometry_cache[k]=shape
	end
	local px,py = position.x,position.y
	if not shape.off_grid then
		-- Ghost creation snaps odd-sized buildings to tile centers and even sizes to edges.
		px,py = floor(px+0.5-shape.ox)+shape.ox,floor(py+0.5-shape.oy)+shape.oy
	end
	return {left_top={x=px+shape.x1,y=py+shape.y1},right_bottom={x=px+shape.x2,y=py+shape.y2}}
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
	for _, list in pairs{state._collected_ghosts or {}, previous and previous._collected_ghosts or {}} do
		for _, entity in pairs(list) do
			if entity.valid and entity.unit_number then ignored[entity.unit_number] = true end
		end
	end
	local area=search_area or {{x1-margin,y1-margin},{x2+margin,y2+margin}}
	local index = obstacles.collect(state.surface,area,ignored,state)
	cache[state] = {tick=game.tick,index=index,margin=margin,area=area,explicit_area=search_area~=nil}
	return index
end

function obstacles.shared_entity(state,name,position,direction,quality)
	if not state.output_only or not state.surface.find_entities_filtered then return end
	local proto=prototypes.entity[name]
	if not proto or (proto.type~="transport-belt" and proto.type~="straight-rail") then return end
	for _,entity in pairs(state.surface.find_entities_filtered{position=position,radius=.05,force=state.player.force}) do
		local matches=entity.name==name or entity.type=="entity-ghost" and entity.ghost_name==name
		if matches and entity.direction==direction and (not entity.quality or entity.quality.name==(quality or "normal"))
			and math.abs(entity.position.x-position.x)<.001 and math.abs(entity.position.y-position.y)<.001 then return entity end
	end
end

function obstacles.can_place(state, name, position, direction)
	if not obstacles.active(state) then return true end
	if obstacles.shared_entity(state,name,position,direction,state.belt_quality_choice) then return true end
	return not obstacles.blocked_box(obstacles.get(state), obstacles.entity_box(name,position,direction))
end

function obstacles.mark_grid(state)
	local c, grid, size = state.coords, state.grid, state.miner.size
	local convert = util.coord_convert[state.direction_choice]
	for _, pos in pairs(obstacles.get(state).cells) do
		-- Invert revert_world at the tile center, including its half-tile offset.
		local x,y = convert(pos.x+0.5-c.gx,pos.y+0.5-c.gy,c.w,c.h)
		x,y = floor(x+0.5),floor(y+0.5)
		local tile = grid:get_tile(x,y)
		if tile then tile.avoid = true end
		grid:forbid(x-size+1,y-size+1,size)
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
	local by_position, occupied, removed, added = {}, {}, {}, {}
	for _, spec in ipairs(specs or {}) do
		local k = key(spec.grid_x,spec.grid_y)
		occupied[k] = spec
		if prototypes.entity[spec.name].type == "transport-belt" then by_position[k] = spec end
	end
	local function path(start, finish, model)
		local queue, head, visited = {start}, 1, {[key(start.grid_x,start.grid_y)]=true}
		local min_x,max_x = math.min(start.grid_x,finish.grid_x)-12,math.max(start.grid_x,finish.grid_x)+12
		local min_y,max_y = math.min(start.grid_y,finish.grid_y)-12,math.max(start.grid_y,finish.grid_y)+12
		while head <= #queue and head <= 4096 do
			local node = queue[head]; head = head + 1
			if node.grid_x == finish.grid_x and node.grid_y == finish.grid_y then
				local result = {}
				while node do table.insert(result,1,node); node=node.previous end
				return result
			end
			for _, dir in ipairs(directions) do
				local delta = util.direction_coord[dir]
				local x,y = node.grid_x+delta.x,node.grid_y+delta.y
				local k = key(x,y)
				local endpoint = x == finish.grid_x and y == finish.grid_y
				if not visited[k] and x>=min_x and x<=max_x and y>=min_y and y<=max_y then
					visited[k] = true
					local probe = {name=model.name,grid_x=x,grid_y=y,direction=dir}
					local tile = state.grid and state.grid:get_tile(floor(x),floor(y))
					if (endpoint or not occupied[k] and not (tile and tile.built_thing)) and safe(state,probe) then
						probe.previous=node; queue[#queue+1]=probe
					end
				end
			end
		end
	end
	for _, spec in ipairs(specs or {}) do
		if by_position[key(spec.grid_x,spec.grid_y)] == spec and not removed[spec] and not safe(state,spec) then
			local delta = util.direction_coord[spec.direction or defines.direction.north]
			local first,last = spec,spec
			while true do
				local prev=by_position[key(first.grid_x-delta.x,first.grid_y-delta.y)]
				if not prev or safe(state,prev) then break end
				if prev.direction ~= spec.direction then return failure(state,spec,"mpp.preview_issue_belt") end
				first=prev
			end
			while true do
				local next=by_position[key(last.grid_x+delta.x,last.grid_y+delta.y)]
				if not next or safe(state,next) then break end
				if next.direction ~= spec.direction then return failure(state,spec,"mpp.preview_issue_belt") end
				last=next
			end
			local start=by_position[key(first.grid_x-delta.x,first.grid_y-delta.y)]
			local finish=by_position[key(last.grid_x+delta.x,last.grid_y+delta.y)]
			if not start or not finish or start.direction ~= spec.direction then return failure(state,spec,"mpp.preview_issue_belt") end
			local route=path(start,finish,spec)
			if not route then return failure(state,spec,"mpp.preview_issue_belt") end
			local x,y=first.grid_x,first.grid_y
			repeat
				removed[by_position[key(x,y)]]=true
				if x==last.grid_x and y==last.grid_y then break end
				x,y=x+delta.x,y+delta.y
			until false
			for index=1,#route-1 do
				local node,next=route[index],route[index+1]
				local dir
				for _, candidate in ipairs(directions) do
					local step=util.direction_coord[candidate]
					if next.grid_x-node.grid_x==step.x and next.grid_y-node.grid_y==step.y then dir=candidate break end
				end
				if index==1 then start.direction=dir else
					local replacement={name=spec.name,quality=spec.quality,thing="belt",grid_x=node.grid_x,grid_y=node.grid_y,direction=dir}
					added[#added+1]=replacement; occupied[key(node.grid_x,node.grid_y)]=replacement
				end
			end
		end
	end
	local result={}
	for _, spec in ipairs(specs or {}) do if not removed[spec] then result[#result+1]=spec end end
	for _, spec in ipairs(added) do result[#result+1]=spec end
	return true,result
end

function obstacles.prepare(state)
	for _, spec in ipairs(state.builder_pipes or {}) do
		if not safe(state,spec) then return failure(state,spec,"mpp.preview_issue_pipe") end
	end
	for _, spec in ipairs(state.builder_belts or {}) do
		if prototypes.entity[spec.name].type ~= "transport-belt" and not safe(state,spec) then
			return failure(state,spec,"mpp.preview_issue_entity")
		end
	end
	local ok,belts=obstacles.route_belts(state,state.builder_belts)
	if not ok then return false end
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
	return true
end

return obstacles
