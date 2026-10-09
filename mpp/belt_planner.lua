local builder = require("mpp.builder")
local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local EAST, NORTH, SOUTH, WEST, ROTATION = util.directions()
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local terrain = require("mpp.terrain")
local output_balancer = require("mpp.output_balancer")
local train_station = require("mpp.train_station")
local belt_planner = {}
local blueprint_name = "mpp-blueprint-belt-planner"
local station_cursor_version = 4

---@class BeltinatorState : TaskState
---@field belt_specification BeltPlannerSpecification
---@field belt_target {position: MapPosition, direction: defines.direction}
---@field belt_x number
---@field belt_y number
---@field belt_direction defines.direction
---@field belt_choice string
---@field belt_quality_choice string?
---@field planned GhostSpecification[]?
---@field grid Grid?
---@field _collected_ghosts LuaEntity[]?
---@field _belt_routing boolean

local function key(x, y) return x..","..y end

local function grid_position(state, position)
	local c=state.coords
	local origin=util.revert_world(c.gx,c.gy,state.direction_choice,0,0,c.tw,c.th)
	return util.coord_convert[state.direction_choice](position.x-floor(origin[1])-0.5,
		position.y-floor(origin[2])-0.5,0,0)
end

function belt_planner.clear_belt_planner_stack(data)
	for _, spec in pairs(data.belt_planner_stack) do
		for _, object in pairs(spec._renderables or {}) do
			if object.valid then object.destroy() end
		end
	end
	data.belt_planner_stack = {}
end

function belt_planner.push_belt_planner_step(player, spec)
	local index = type(player) == "number" and player or player.index
	table.insert(storage.players[index].belt_planner_stack, spec)
end

local function orient_cursor_entities(entities, direction)
	local delta = util.direction_coord[direction]
	for i, entity in ipairs(entities) do
		entity.direction = direction
		entity.position = {x=-delta.y*(i-0.5)-delta.x*0.5, y=delta.x*(i-0.5)-delta.y*0.5}
	end
	return entities
end

local function cursor_direction(entities, event)
	local direction = entities[1].direction or NORTH
	if event.flip_horizontal then direction = (-direction) % ROTATION end
	if event.flip_vertical then direction = (SOUTH-direction) % ROTATION end
	return (direction + (event.direction or NORTH)) % ROTATION
end

local function configure_station_grid(stack)
	stack.blueprint_snap_to_grid={x=2,y=2}
	stack.blueprint_absolute_snapping=true
	stack.blueprint_position_relative_to_grid={x=0,y=0}
end

local function station_grid_matches(stack)
	local grid=stack.blueprint_snap_to_grid
	local offset=stack.blueprint_position_relative_to_grid
	return grid and grid.x==2 and grid.y==2 and stack.blueprint_absolute_snapping
		and offset and offset.x==0 and offset.y==0
end

local function queue_station_cursor(data,stack)
	local layout=data.belt_cursor_station_layout
	if not layout then return end
	data.belt_cursor_restore={entities=train_station.cursor_entities(layout,data.belt_cursor_direction,
		data.belt_cursor_mirror),tick=game.tick+1,station=true,label=stack.label}
	stack.set_blueprint_entities({})
	script.on_event(defines.events.on_tick,task_runner_handler)
end

function belt_planner.rotate_cursor(player, event, reverse)
	local stack = player.cursor_stack
	if not stack or not stack.valid_for_read or stack.name ~= blueprint_name then return false end
	local data = storage.players[player.index]
	local entities = stack.get_blueprint_entities() or {}
	local direction = data.belt_cursor_direction
		or ((entities[1] and entities[1].direction or NORTH) + (event.cursor_direction or NORTH)) % ROTATION
	data.belt_cursor_direction = (direction + (reverse and -EAST or EAST)) % ROTATION
	if data.belt_cursor_station_layout then queue_station_cursor(data,stack) end
	return true
end

function belt_planner.flip_cursor(player, horizontal)
	local stack = player.cursor_stack
	if not stack or not stack.valid_for_read or stack.name ~= blueprint_name then return end
	local data = storage.players[player.index]
	local entities = stack.get_blueprint_entities() or {}
	local direction = data.belt_cursor_direction or (entities[1] and entities[1].direction) or NORTH
	data.belt_cursor_direction = ((horizontal and 0 or SOUTH)-direction) % ROTATION
	if data.belt_cursor_station_layout then
		data.belt_cursor_mirror=not data.belt_cursor_mirror
		queue_station_cursor(data,stack)
	end
	return true
end

function belt_planner.update_blueprint(player, spec)
	local stack = player.cursor_stack
	if not stack or not stack.valid_for_read or stack.name ~= blueprint_name then return end
	local entities = stack.get_blueprint_entities() or {}
	local data = storage.players[player.index]
	if spec.station_choices then
		local layout,err=train_station.geometry(spec.count,spec.station_choices,spec.belt_choice)
		if not layout then player.print(err);return end
		local direction=data.belt_cursor_direction or NORTH
		local signature=table.concat({station_cursor_version,spec.count,layout.locomotives,layout.wagons,layout.outputs,spec.belt_choice,
			direction,tostring(data.belt_cursor_mirror)},":")
		if data.belt_cursor_station_signature==signature and #entities==#layout.specs and station_grid_matches(stack) then return stack end
		data.belt_cursor_station_signature=signature
		data.belt_cursor_station_layout=layout
		data.belt_cursor_restore=nil
		stack.set_blueprint_entities({})
		stack.set_blueprint_entities(train_station.cursor_entities(layout,direction,data.belt_cursor_mirror))
		configure_station_grid(stack)
		stack.label=layout.locomotives.." [item=locomotive] + "..layout.wagons.." [item=cargo-wagon] | "..layout.outputs.." [item="..spec.belt_choice.."]"
		return stack
	end
	if data.belt_cursor_station_layout then
		stack.set_blueprint_entities({});entities={}
		stack.blueprint_snap_to_grid=nil
		stack.blueprint_absolute_snapping=false
		data.belt_cursor_station_layout=nil;data.belt_cursor_station_signature=nil
	end
	local quality = spec.belt_quality_choice or "normal"
	local count = spec.output_count or spec.count
	if #entities == count and entities[1].name == spec.belt_choice
		and (entities[1].quality or "normal") == quality then return stack end
	local direction = data.belt_cursor_direction or (entities[1] and entities[1].direction) or NORTH
	entities = {}
	for i=1,count do
		entities[i] = {entity_number=i, name=spec.belt_choice, quality=quality,
			position={x=i-0.5,y=0.5}, direction=NORTH,
			tags={mpp_belt_planner=i==1 and "main" or "delete"}}
	end
	data.belt_cursor_restore = nil
	data.belt_cursor_direction = direction
	stack.set_blueprint_entities(orient_cursor_entities(entities, direction))
	stack.label = count.." x [item="..spec.belt_choice.."]"
	return stack
end

function belt_planner.give_blueprint(state, spec)
	local player = state.player
	if spec.station_choices then
		local layout,err=train_station.geometry(spec.count,spec.station_choices,spec.belt_choice)
		if not layout then return nil,err end
	end
	local stack = player.cursor_stack
	if not stack or not stack.valid_for_read or stack.name ~= blueprint_name then
		if not player.clear_cursor() then return end
		player.cursor_stack.set_stack(blueprint_name)
		local data = storage.players[player.index]
		data.belt_cursor_direction = data.belt_cursor_direction
			or (data.preview and data.preview.belt_target and data.preview.belt_target.direction)
			or data.belt_planner_direction or NORTH
	end
	player.cursor_stack_temporary = true
	return belt_planner.update_blueprint(player, spec)
end

function belt_planner.take_cursor_target(player, event)
	local stack = player.cursor_stack
	if not stack or not stack.valid_for_read or stack.name ~= blueprint_name then return end
	local entities = stack.get_blueprint_entities()
	if not entities or #entities == 0 then return end
	local data = storage.players[player.index]
	if data.belt_cursor_station_layout then
		local direction=((data.belt_cursor_direction or NORTH)+(event.direction or NORTH))%ROTATION
		data.belt_cursor_direction=direction
		data.belt_planner_direction=direction
		queue_station_cursor(data,stack)
		return {position={x=floor(event.position.x/2)*2+1,y=floor(event.position.y/2)*2+1},
			direction=direction,mirror=data.belt_cursor_mirror==true}
	end
	local direction = cursor_direction(entities, event)
	local delta = util.direction_coord[direction]
	if not delta then return end
	local half_width = (#entities-1)/2
	local position = {x=floor(event.position.x+delta.y*half_width)+0.5,
		y=floor(event.position.y-delta.x*half_width)+0.5}
	-- Empty the blueprint before construction so blocked clicks also select a target without issuing orders.
	data.belt_cursor_direction = direction
	data.belt_planner_direction = direction
	-- Clearing resets the engine's held rotation, so bake the visible direction into the restored entities.
	data.belt_cursor_restore = {entities=orient_cursor_entities(entities, direction), tick=game.tick+1}
	stack.set_blueprint_entities({})
	return {position=position, direction=direction}
end

function belt_planner.has_pending_cursor()
	for _, data in pairs(storage.players or {}) do
		if data.belt_cursor_restore then return true end
	end
	return false
end

function belt_planner.restore_cursors()
	for index, data in pairs(storage.players) do
		local pending = data.belt_cursor_restore
		if pending and game.tick >= pending.tick then
			data.belt_cursor_restore = nil
			local player = game.get_player(index)
			local stack = player and player.cursor_stack
			if stack and stack.valid_for_read and stack.name == blueprint_name
				and not stack.get_blueprint_entities() then
				local station=pending.station or data.belt_cursor_station_layout
				stack.set_blueprint_entities(pending.entities)
				if station then
					-- Clearing entities also clears the blueprint's absolute rail grid.
					configure_station_grid(stack)
					if pending.label then stack.label=pending.label end
					player.cursor_stack_temporary=true
				end
			end
		end
	end
end

function belt_planner.release_cursor(data, player)
	data.belt_cursor_restore = nil
	player = player or data.preview and game.get_player(data.preview.player_index)
		or data.last_state and data.last_state.player
	if not player then return end
	local stack = player.cursor_stack
	if stack and stack.valid_for_read and (stack.name == blueprint_name or stack.name == "mpp-belt-planner") then
		player.clear_cursor()
	end
end

---@return BeltinatorState?, LocalisedString?
function belt_planner.create_state(spec, target, choices)
	local c, pos = spec.coords, target.position
	local range = (choices.output_balance_choice or choices.output_station_choice) and 512 or 100
	if abs(c.gx + c.w/2 - pos.x) > range or abs(c.gy + c.h/2 - pos.y) > range then
		return nil, {"mpp.msg_belt_planner_err_too_far"}
	end
	local x,y = grid_position(spec,pos)
	local direction = util.clamped_rotation(-defines.direction[spec.direction_choice]-EAST, target.direction)
	return {
		type="belt_planner", player=spec.player, surface=spec.surface, coords=c,
		direction_choice=spec.direction_choice, belt_specification=spec,
		belt_x=floor(x+0.5), belt_y=floor(y+0.5), belt_direction=direction,
		belt_choice=spec.belt_choice, belt_quality_choice=spec.belt_quality_choice,
		belt_target=target, _belt_routing=true,
		output_balance_choice=choices.output_balance_choice==true,
		output_belt_count_choice=choices.output_belt_count_choice or output_balancer.default_count,
		output_station_choice=choices.output_station_choice==true,
		output_locomotive_count_choice=choices.output_locomotive_count_choice or 2,
		output_wagon_count_choice=choices.output_wagon_count_choice or 4,
		output_loading_side_choice=choices.output_loading_side_choice or "double",
		cliff_mode_choice=choices.cliff_mode_choice, terrain_mode_choice=choices.terrain_mode_choice,
		space_landfill_choice=choices.space_landfill_choice,
		avoid_obstacles_choice=choices.avoid_obstacles_choice,
		avoid_cliffs_choice=choices.avoid_cliffs_choice, avoid_water_choice=choices.avoid_water_choice,
		deconstruction_choice=choices.deconstruction_choice, landfill_choice=choices.landfill_choice,
		_previous_state=choices._previous_state, _collected_ghosts=choices._collected_ghosts,
		_deconstruction_orders=choices._deconstruction_orders,
	}
end

local function world(state, x, y)
	local c = state.coords
	local pos = util.revert_world(c.gx,c.gy,state.direction_choice,x,y,c.tw,c.th)
	return {x=pos[1], y=pos[2]}
end

-- Track arrival direction and penalize turns so equal-length routes use long straight runs.
local function path(start, finish, finish_direction, allowed, bounds, penalty, budget)
	local heap, best = {}, {}
	local turn_cost = 8
	local sequence = 0
	local function node_key(node) return key(node.x,node.y)..","..node.direction end
	local function before(a,b)
		if a.score~=b.score then return a.score<b.score end
		if a.turns~=b.turns then return a.turns<b.turns end
		if a.distance~=b.distance then return a.distance<b.distance end
		return a.sequence<b.sequence
	end
	local function push(node)
		sequence=sequence+1
		node.sequence=sequence
		local i = #heap+1
		while i>1 and before(node,heap[floor(i/2)]) do
			heap[i]=heap[floor(i/2)]; i=floor(i/2)
		end
		heap[i]=node
	end
	local function pop()
		local node, tail = heap[1], table.remove(heap)
		if #heap>0 then
			local i=1
			while i*2<=#heap do
				local child=i*2
				if child<#heap and before(heap[child+1],heap[child]) then child=child+1 end
				if not before(heap[child],tail) then break end
				heap[i]=heap[child]; i=child
			end
			heap[i]=tail
		end
		return node
	end
	start.direction=WEST
	if start.x==finish.x and start.y==finish.y and start.direction==(finish_direction+SOUTH)%ROTATION then return end
	start.turns=0
	start.distance=abs(start.x-finish.x)+abs(start.y-finish.y)
	start.cost=start.distance==0 and start.direction~=finish_direction and turn_cost or 0
	start.score=start.cost+start.distance
	best[node_key(start)]=start.cost
	push(start)
	local visits=0
	while #heap>0 and visits<131072 and (not budget or budget.remaining>0) do
		local node=pop()
		if node.cost==best[node_key(node)] then
			visits=visits+1
			if budget then budget.remaining=budget.remaining-1 end
			if node.x==finish.x and node.y==finish.y then
				local result={}
				while node do result[#result+1]=node; node=node.previous end
				local ordered={}
				for i=#result,1,-1 do ordered[#ordered+1]=result[i] end
				return ordered
			end
			for _, dir in ipairs{WEST,NORTH,SOUTH,EAST} do
				if dir==(node.direction+SOUTH)%ROTATION then goto continue end
				local delta=util.direction_coord[dir]
				local x,y=node.x+delta.x,node.y+delta.y
				if x==finish.x and y==finish.y and dir==(finish_direction+SOUTH)%ROTATION then goto continue end
				local k=key(x,y)..","..dir
				local turns=node.turns+(dir~=node.direction and 1 or 0)
				local cost=node.cost+1+(dir~=node.direction and turn_cost or 0)+(penalty and penalty(x,y) or 0)
				if x==finish.x and y==finish.y and dir~=finish_direction then
					cost=cost+turn_cost
					turns=turns+1
				end
				local distance=abs(x-finish.x)+abs(y-finish.y)
				if x>=bounds.x1 and x<=bounds.x2 and y>=bounds.y1 and y<=bounds.y2
					and (not best[k] or cost<best[k]) and allowed(x,y) then
					best[k]=cost
					push{x=x,y=y,direction=dir,turns=turns,cost=cost,score=cost+distance,distance=distance,previous=node}
				end
				::continue::
			end
		end
	end
end

local function straight_segments(points, allowed)
	local route, seen = {}, {}
	local function append(x,y)
		local k=key(x,y)
		if seen[k] or not allowed(x,y) then return false end
		seen[k]=true
		route[#route+1]={x=x,y=y}
		return true
	end
	if not append(points[1].x,points[1].y) then return end
	for i=2,#points do
		local previous,finish=points[i-1],points[i]
		local dx,dy=finish.x-previous.x,finish.y-previous.y
		if dx~=0 and dy~=0 then return end
		local distance=abs(dx)+abs(dy)
		if distance>0 then
			local sx,sy=dx/distance,dy/distance
			for step=1,distance do
				if not append(previous.x+sx*step,previous.y+sy*step) then return end
			end
		end
	end
	return route
end

local function route_bundle(state, reverse, negotiate)
	local spec, dir = state.belt_specification, state.belt_direction
	local occupied, reserved, sources, outputs, result = {}, {}, {}, {}, {}
	local x1,y1,x2,y2 = state.belt_x,state.belt_y,state.belt_x,state.belt_y
	local source_left=math.huge
	local function reserve(x,y,lane)
		local k=key(x,y)
		if reserved[k] and reserved[k]~=lane then return false end
		reserved[k]=lane
		return true
	end
	local function occupy(box)
		for x=floor(box.left_top.x+0.001),math.ceil(box.right_bottom.x-0.001)-1 do
			for y=floor(box.left_top.y+0.001),math.ceil(box.right_bottom.y-0.001)-1 do
				local gx,gy=grid_position(state,{x=x+0.5,y=y+0.5})
				gx,gy=floor(gx+0.5),floor(gy+0.5)
				occupied[key(gx,gy)]=true
				-- Allow ingress to go around the full station, even when its ports sit inside its bounds.
				x1,y1=min(x1,gx),min(y1,gy)
				x2,y2=max(x2,gx),max(y2,gy)
			end
		end
	end
	for _, entity in ipairs(state.planned or {}) do
		if prototypes.entity[entity.name] then
			local pos=world(state,entity.grid_x,entity.grid_y)
			occupy(obstacles.entity_box(entity.name,pos,util.bp_direction[state.direction_choice][entity.direction or NORTH]))
		end
	end
	for _, ghost in pairs(state._collected_ghosts or {}) do
		if ghost.valid and ghost.type=="entity-ghost" then occupy(ghost.bounding_box) end
	end
	for i, belt in ipairs(spec) do
		local start={x=belt.x_start-1, y=belt.y}
		local finish={x=state.belt_x, y=state.belt_y}
		if state.belt_input_targets then finish=state.belt_input_targets[i]
		elseif dir==WEST then finish.y=finish.y+i-spec.count
		-- Reversing the output direction also reverses row order, keeping the bundle uncrossed.
		elseif dir==EAST then finish.y=finish.y+spec.count-i
		elseif dir==NORTH then finish.x=finish.x+spec.count-i
		else finish.x=finish.x-spec.count+i end
		sources[i],outputs[i]=start,finish
		source_left=min(source_left,start.x)
		if not negotiate and start.x==finish.x and start.y==finish.y then
			return false,{"mpp.msg_obstacle_route_failed"},{routes=result,failed_lane=i,reason="overlap"}
		end
		if not reserve(start.x,start.y,i) or (not negotiate and not reserve(start.x-1,start.y,i)) then
			return false,{"mpp.msg_obstacle_route_failed"},{routes=result,failed_lane=i,reason="overlap"}
		end
		local delta=util.direction_coord[dir]
		for step=-1,1 do
			if negotiate and step==-1 then goto next_reservation end
			if not reserve(finish.x+delta.x*step,finish.y+delta.y*step,step==1 and -i or i) then
				return false,{"mpp.msg_obstacle_route_failed"},{routes=result,failed_lane=i,reason="overlap"}
			end
			::next_reservation::
		end
		x1,y1=min(x1,start.x,finish.x),min(y1,start.y,finish.y)
		x2,y2=max(x2,start.x,finish.x),max(y2,start.y,finish.y)
	end
	local padding=max(negotiate and 48 or 16,spec.count+4)
	local bounds={x1=x1-padding,y1=y1-padding,x2=x2+padding,y2=y2+padding}
	state._belt_search_margin=padding+max(0,-x1,-y1,x2-state.coords.tw,y2-state.coords.th)+2
	local safe_cache={}
	local function safe(x,y)
		local k=key(x,y)
		if safe_cache[k]==nil then
			safe_cache[k]=obstacles.can_place(state,state.belt_choice,world(state,x,y),NORTH)
		end
		return safe_cache[k]
	end
	local order={}
	for i=1,spec.count do order[i]=i end
	if dir==SOUTH or (dir==EAST and state.belt_y>=spec[spec.count].y) then
		for i=1,floor(spec.count/2) do order[i],order[spec.count-i+1]=order[spec.count-i+1],order[i] end
	end
	if reverse then
		for i=1,floor(spec.count/2) do order[i],order[spec.count-i+1]=order[spec.count-i+1],order[i] end
	end
	local completed={}
	local lane_routes, usage, history = {}, {}, {}
	local budget=negotiate and {remaining=262144} or nil
	for pass=1,negotiate and 32 or 1 do
		result,completed={},{}
		for _, i in ipairs(order) do
			local start,finish=sources[i],outputs[i]
			local delta=util.direction_coord[dir]
			local approach={x=finish.x-delta.x,y=finish.y-delta.y}
			local routing=false
			local function allowed(x,y)
				local k=key(x,y)
				local own_start=x==start.x and y==start.y
				local tile=state.grid and state.grid:get_tile(x,y)
				return (not reserved[k] or reserved[k]==i) and ((own_start and not routing) or not occupied[k])
					and (own_start or not tile or not tile.built_thing) and safe(x,y)
			end
			if not allowed(start.x,start.y) or not allowed(finish.x,finish.y)
				or (not negotiate and (not allowed(start.x-1,start.y) or not allowed(approach.x,approach.y))) then
				return false,{"mpp.msg_obstacle_route_failed"},{routes=result,completed=completed,failed_lane=i,reason="blocked"}
			end
			-- The fast pass uses straight endpoints; replanning also permits endpoint corners.
			occupied[key(start.x,start.y)]=true
			if not negotiate then occupied[key(finish.x,finish.y)]=true end
			routing=true
			local route
			-- Outputs behind the mine need nested U-shaped corridors rather than one lane enclosing the others.
			local top=state.belt_y-spec.count+1
			if not negotiate and dir==WEST and state.belt_x>=source_left and (state.belt_y<spec[1].y or top>spec[spec.count].y) then
				local above=state.belt_y<spec[1].y
				local rank=above and i or spec.count-i+1
				local column=source_left-rank-1
				local outer_top=state.belt_input_targets and y1 or top
				local outer_bottom=state.belt_input_targets and y2 or state.belt_y
				local row=above and min(top,spec[1].y,outer_top)-rank or max(state.belt_y,spec[spec.count].y,outer_bottom)+rank
				local far_column=max(state.belt_x+1,source_left,state.belt_input_targets and x2+1 or state.belt_x+1)+rank
				route=straight_segments({{x=start.x-1,y=start.y},{x=column,y=start.y},
					{x=column,y=row},{x=far_column,y=row},{x=far_column,y=approach.y},approach},allowed)
			end
			-- Opposite-facing exits use nested, parallel corridors when the output band is outside the rows.
			if not negotiate and dir==EAST and (state.belt_y+spec.count-1<spec[1].y or state.belt_y>spec[spec.count].y) then
				local column=source_left-(state.belt_y<spec[1].y and i or spec.count-i+1)
				if approach.x>=column then
					route=straight_segments({{x=start.x-1,y=start.y},{x=column,y=start.y},
						{x=column,y=approach.y},approach},allowed)
				end
			end
			-- A perpendicular outlet needs nested bends; the nearest lane must leave room for the outer lanes.
			if not negotiate and state.belt_x>=source_left and
				((dir==SOUTH and state.belt_y-spec.count>spec[spec.count].y)
				or (dir==NORTH and state.belt_y+spec.count<spec[1].y)) then
				local rank=dir==SOUTH and spec.count-i+1 or i
				local column=source_left-rank
				local row=dir==SOUTH and state.belt_y-i or state.belt_y+spec.count-i+1
				route=straight_segments({{x=start.x-1,y=start.y},{x=column,y=start.y},
					{x=column,y=row},{x=approach.x,y=row},approach},allowed)
			end
			if negotiate then
				for _,node in ipairs(lane_routes[i] or {}) do
					local k=key(node.x,node.y)
					usage[k]=usage[k]-1
				end
				-- Temporarily permit shared cells while replanning, then price congested corridors out of the bundle.
				route=path({x=start.x,y=start.y},finish,dir,allowed,bounds,function(x,y)
					local k=key(x,y)
					return (history[k] or 0)+(usage[k] or 0)*(8+pass*4)
				end,budget)
			else
				route=route or path({x=start.x-1,y=start.y},approach,dir,allowed,bounds)
			end
			if not route then
				return false,{"mpp.msg_obstacle_route_failed"},{routes=result,completed=completed,failed_lane=i,reason="route"}
			end
			if not negotiate then
				table.insert(route,1,start)
				route[#route+1]=finish
			else
				lane_routes[i]=route
			end
			for index, node in ipairs(route) do
				local direction=dir
				local next=route[index+1]
				if next then
					for candidate,step in pairs(util.direction_coord) do
						if next.x-node.x==step.x and next.y-node.y==step.y then direction=candidate; break end
					end
				end
				local k=key(node.x,node.y)
				if negotiate then usage[k]=(usage[k] or 0)+1 else occupied[k]=true end
				result[#result+1]={name=state.belt_choice,quality=state.belt_quality_choice,
					thing="belt",grid_x=node.x,grid_y=node.y,direction=direction}
			end
			completed[i]=true
		end
		local conflicts=false
		for k,count in pairs(usage) do
			if count>1 then
				conflicts=true
				history[k]=(history[k] or 0)+8*(count-1)
			end
		end
		if not conflicts then return true,result end
		if budget and budget.remaining<=0 then break end
	end
	-- Tentative shared routes must never reach the builder or appear as valid preview entities.
	return false,{"mpp.msg_obstacle_route_failed"},{routes={},failed_lane=1,reason="route"}
end

local function plan_routes(state)
	local ok, result, diagnostic = route_bundle(state, false)
	if ok then return ok, result end
	-- A greedy lane can close a corridor needed by the next lane; try the opposite order before failing.
	if state.belt_specification.count>1 and diagnostic.reason~="overlap" then
		local reversed, routes, other = route_bundle(state, true)
		if reversed then return true, routes end
		if #other.routes>#diagnostic.routes then diagnostic=other end
	end
	local rerouted, routes = route_bundle(state, false, true)
	if rerouted then return true, routes end
	if not state.preview_only then return false, result end
	local spec, dir = state.belt_specification, state.belt_direction
	local delta=util.direction_coord[dir]
	diagnostic.issues={}
	for i, belt in ipairs(spec) do
		if not (diagnostic.completed and diagnostic.completed[i]) then
			local start={x=belt.x_start-1,y=belt.y}
			local finish={x=state.belt_x,y=state.belt_y}
			if state.belt_input_targets then finish=state.belt_input_targets[i]
			elseif dir==WEST then finish.y=finish.y+i-spec.count
			elseif dir==EAST then finish.y=finish.y+spec.count-i
			elseif dir==NORTH then finish.x=finish.x+spec.count-i
			else finish.x=finish.x-spec.count+i end
			local approach={x=finish.x-delta.x,y=finish.y-delta.y}
			local padding=max(16,spec.count+4)
			local bounds={x1=min(start.x,finish.x)-padding,y1=min(start.y,finish.y)-padding,
				x2=max(start.x,finish.x)+padding,y2=max(start.y,finish.y)+padding}
			-- This relaxed route is explanatory only; every segment stays red and Apply remains disabled.
			local route=path({x=start.x-1,y=start.y},approach,dir,function(x,y)
				return x~=finish.x or y~=finish.y
			end,bounds) or {approach}
			table.insert(route,1,start)
			route[#route+1]=finish
			for index,node in ipairs(route) do
				local direction=dir
				local next=route[index+1]
				if next then for candidate,step in pairs(util.direction_coord) do
					if next.x-node.x==step.x and next.y-node.y==step.y then direction=candidate; break end
				end end
				diagnostic.routes[#diagnostic.routes+1]={name=state.belt_choice,quality=state.belt_quality_choice,
					grid_x=node.x,grid_y=node.y,direction=direction,preview_blocked=true}
			end
			local reason="mpp.preview_issue_connection"
			if diagnostic.reason=="overlap" then reason="mpp.preview_issue_overlap"
			elseif not obstacles.can_place(state,state.belt_choice,world(state,finish.x,finish.y),NORTH)
				or not obstacles.can_place(state,state.belt_choice,world(state,approach.x,approach.y),NORTH) then
				reason="mpp.preview_issue_output"
			end
			local box=obstacles.entity_box(state.belt_choice,world(state,finish.x,finish.y),NORTH)
			diagnostic.issues[#diagnostic.issues+1]={position={x=(box.left_top.x+box.right_bottom.x)/2,
				y=(box.left_top.y+box.right_bottom.y)/2},reason={reason,i}}
		end
	end
	return false, result, diagnostic
end

function belt_planner.plan(state)
	if state.output_station_choice then return train_station.plan(state,plan_routes) end
	if state.output_balance_choice then return output_balancer.plan(state,plan_routes) end
	return plan_routes(state)
end

function belt_planner.layout(state)
	local ok, specs=belt_planner.plan(state)
	if not ok then state.player.print(specs); return false end
	local create=builder.create_entity_builder(state,{do_deconstruction=true})
	for _, spec in ipairs(specs) do create(spec) end
	belt_planner.place_landfill(state,specs)
	return true
end

function belt_planner.place_landfill(state, specs)
	if terrain.avoid_tiles(state) then return end
	state._belt_landfill = state._belt_landfill or {}
	for _, spec in ipairs(specs or {}) do
		local pos=spec.position or world(state,spec.grid_x,spec.grid_y)
		pos={x=pos.x or pos[1],y=pos.y or pos[2]}
		local dir=spec.inner_name and spec.direction or util.bp_direction[state.direction_choice][spec.direction or NORTH]
		local box=obstacles.entity_box(spec.inner_name or spec.name,pos,dir)
		for x=floor(box.left_top.x+0.001),math.ceil(box.right_bottom.x-0.001)-1 do
		for y=floor(box.left_top.y+0.001),math.ceil(box.right_bottom.y-0.001)-1 do
		local tile=state.surface.get_tile{x=x,y=y}
		local pos=tile.position
		local k=key(pos.x,pos.y)
		local cover=terrain.cover_tile(tile,state)
		if not state._belt_landfill[k] and terrain.blocked_tile(tile) and cover then
			state._belt_landfill[k]=true
			local ghost={name="tile-ghost",inner_name=cover.name,position=pos,force=state.player.force,
				player=state.player,raise_built=true}
			if state.preview_only then builder.record_preview(state,ghost)
			else
				local entity=state.surface.create_entity(ghost)
				if entity and state._collected_ghosts then table.insert(state._collected_ghosts,entity) end
			end
		end
		end end
	end
end

return belt_planner
