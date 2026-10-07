local util = require("mpp.mpp_util")
local obstacles = {}
local cache = setmetatable({}, {__mode="k"})
local floor, ceil = math.floor, math.ceil
local ignored_types = {resource=true, character=true, unit=true, corpse=true,
	["item-entity"]=true, ["entity-ghost"]=false, ["tile-ghost"]=true}

local function key(x, y) return x..","..y end

function obstacles.blocked_tile(tile)
	local layers = tile.prototype.collision_mask.layers
	return layers.water_tile or layers.lava_tile or layers.out_of_map
		or layers.empty_space or tile.name:find("lava", 1, true) ~= nil
end

local function overlap(a, b)
	return a.left_top.x < b.right_bottom.x and a.right_bottom.x > b.left_top.x
		and a.left_top.y < b.right_bottom.y and a.right_bottom.y > b.left_top.y
end

function obstacles.collect(surface, area, ignored)
	local index = {tiles={}, cells={}, boxes={}}
	local function cell(x, y) index.cells[key(x,y)] = {x=x, y=y} end
	for _, tile in pairs(surface.find_tiles_filtered{area=area}) do
		if obstacles.blocked_tile(tile) then
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
			if entity.type == "cliff" or layers.object or layers.player or layers.train then
				local box = entity.bounding_box
				index.boxes[#index.boxes + 1] = box
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
	for _, other in ipairs(index.boxes) do if overlap(box, other) then return true end end
	return false
end

function obstacles.entity_box(name, position, direction)
	local proto = prototypes.entity[name]
	local box = proto.collision_box
	local x1,y1,x2,y2 = box.left_top.x,box.left_top.y,box.right_bottom.x,box.right_bottom.y
	if direction == defines.direction.east then x1,y1,x2,y2 = -y2,x1,-y1,x2
	elseif direction == defines.direction.south then x1,y1,x2,y2 = -x2,-y2,-x1,-y1
	elseif direction == defines.direction.west then x1,y1,x2,y2 = y1,-x2,y2,-x1 end
	local px,py = position.x,position.y
	if not proto.has_flag("placeable-off-grid") then
		local width,height = proto.tile_width,proto.tile_height
		if direction == defines.direction.east or direction == defines.direction.west then width,height = height,width end
		-- Ghost creation snaps odd-sized buildings to tile centers and even sizes to edges.
		local ox,oy = (width % 2)/2,(height % 2)/2
		px,py = floor(px+0.5-ox)+ox,floor(py+0.5-oy)+oy
	end
	return {left_top={x=px+x1,y=py+y1},right_bottom={x=px+x2,y=py+y2}}
end

function obstacles.get(state)
	local saved = cache[state]
	if saved and saved.tick == game.tick then return saved.index end
	local c = state.coords
	local margin = (state.miner and state.miner.area or 5) + 32
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
	local index = obstacles.collect(state.surface,
		{{c.x1-margin,c.y1-margin},{c.x2+margin,c.y2+margin}}, ignored)
	cache[state] = {tick=game.tick,index=index}
	return index
end

function obstacles.can_place(state, name, position, direction)
	if not state.avoid_obstacles_choice then return true end
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
				if prev.direction ~= spec.direction then return false end
				first=prev
			end
			while true do
				local next=by_position[key(last.grid_x+delta.x,last.grid_y+delta.y)]
				if not next or safe(state,next) then break end
				if next.direction ~= spec.direction then return false end
				last=next
			end
			local start=by_position[key(first.grid_x-delta.x,first.grid_y-delta.y)]
			local finish=by_position[key(last.grid_x+delta.x,last.grid_y+delta.y)]
			if not start or not finish or start.direction ~= spec.direction then return false end
			local route=path(start,finish,spec)
			if not route then return false end
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
	for _, spec in ipairs(state.builder_pipes or {}) do if not safe(state,spec) then return false end end
	for _, spec in ipairs(state.builder_belts or {}) do
		if prototypes.entity[spec.name].type ~= "transport-belt" and not safe(state,spec) then return false end
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
				if not found then spec.grid_x,spec.grid_y=x,y; return false end
				spec.grid_x,spec.grid_y=found[1],found[2]
				state.grid:build_thing_simple(spec.grid_x,spec.grid_y,spec.thing)
			end
		end
	end
	return true
end

return obstacles
