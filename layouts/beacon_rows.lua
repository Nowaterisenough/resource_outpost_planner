local simple = require("layouts.simple")
local compact = require("layouts.compact")
local logistics = require("layouts.logistics")
local common = require("layouts.common")
local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local rows = require("mpp.beacon_rows")
local layout = table.deepcopy(compact)
local floor, min, max = math.floor, math.min, math.max
local N,S = defines.direction.north,defines.direction.south

layout.name = "beacon_rows"
layout.do_power_pole_joiners = false

function layout:initialize(state)
	simple.initialize(self,state)
	state._beacon_rows = true
	state.pole_gap = max(1,state.pole.size)
	state.beacon_pipe_gap = state.miner.supports_fluids and state.pipe_choice~="none"
		and (state.requires_fluid or state.force_pipe_placement_choice or state._mining_layout_choice=="pipe") and 1 or 0
	state.miner_stride = state.miner.size+prototypes.entity[state.beacon_choice].tile_width+2*state.beacon_pipe_gap
end

function layout:_placement_attempt(state,attempt)
	local M,C = state.miner,state.coords
	local miners,postponed,lanes = {},{},{}
	local H = common.init_heuristic_values()
	local sx,sy = attempt[1],attempt[2]
	local bx,by,b2x,b2y = math.huge,math.huge,-math.huge,-math.huge
	local heuristic = self:_get_miner_placement_heuristic(state)
	local line,y = 1,sy
	while y<C.th+M.size do
		lanes[line] = {y=y,row_index=line}
		local column = 1
		for x=sx,C.tw+M.size,state.miner_stride do
			local tile = state.grid:get_tile(x,y)
			local miner = {x=x,y=y,origin_x=x+M.x,origin_y=y+M.y,tile=tile,line=line,column=column,
				direction=line%2==1 and S or N}
			if tile and not tile.forbidden and tile.neighbors_outer>0 then
				if heuristic(tile) then
					miners[#miners+1] = miner
					common.add_heuristic_values(H,M,tile)
					bx,by,b2x,b2y = min(bx,x-1),min(by,y-1),max(b2x,x+M.size-1),max(b2y,y+M.size-1)
				else postponed[#postponed+1] = miner end
			end
			column = column+1
		end
		y = y+M.size+(line%2==1 and 1 or state.pole_gap)
		line = line+1
	end
	local result = {sx=sx,sy=sy,bx=bx,by=by,b2x=b2x,b2y=b2y,miners=miners,postponed=postponed,
		lane_layout=lanes,heuristics=H,price=0,heuristic_score=0}
	common.finalize_heuristic_values(result,H,C)
	return result
end

function layout:prepare_miner_layout(state)
	local next_step = simple.prepare_miner_layout(self,state)
	rows.reserve(state)
	return next_step
end

function layout:_mining_drill_lane_y_provider(state,attempt)
	return function(i) return attempt.lane_layout[i].y+state.miner.size end
end

function layout:prepare_pipe_layout(state)
	if state.beacon_pipe_gap==0 then return simple.prepare_pipe_layout(self,state) end
	state.place_pipes = true
	state.builder_pipes = {}
	local M,attempt,stride = state.miner,state.best_attempt,state.miner_stride
	local specs = {}
	for i=1,state.miner_lane_count do
		local lane = attempt.lane_layout[i]
		local y = lane.y+M.pipe_left[i%2==1 and S or N]
		local present = {}
		for _,miner in ipairs(state.miner_lanes[i] or {}) do present[miner.column]=true end
		for column=1,state.miner_max_column do
			local x = attempt.sx+(column-1)*stride
			if not present[column] then specs[#specs+1]={structure="horizontal",x=x-1,y=y,w=M.size+1} end
			if column<state.miner_max_column then
				specs[#specs+1] = {structure="horizontal",x=x+M.size,y=y,w=stride-M.size-1}
			end
		end
		specs[#specs+1] = {structure="cap_vertical",x=attempt.sx-1,y=y,skip_up=i==1,skip_down=i==state.miner_lane_count}
		if i>1 then
			local previous = attempt.lane_layout[i-1]
			local py = previous.y+M.pipe_left[(i-1)%2==1 and S or N]
			specs[#specs+1] = {structure="joiner_vertical",x=attempt.sx-1,y=py+1,h=y-py-1,belt_y=previous.y+M.size}
		end
	end
	state.pipe_layout_specification = specs
	common.create_pipe_building_environment(state).process_specification(specs)
	return "prepare_pole_layout"
end

function layout:prepare_pole_layout(state)
	state.belts = self:_process_mining_drill_lanes(state)
	state.belt_count = #state.belts
	local proto = prototypes.entity[state.beacon_choice]
	for _,belt in ipairs(state.belts) do
		belt.x_start = state.best_attempt.sx-proto.tile_width-state.beacon_pipe_gap-2
	end
	state.builder_power_poles,state.builder_lamps = {},{}
	if state.pole_choice=="none" or state.pole_choice=="zero_gap" then return "prepare_belt_layout" end
	local M,attempt,G = state.miner,state.best_attempt,state.grid
	local selected
	if obstacles.active(state) then
		selected = obstacles.get(setmetatable({_belt_routing=true},{__index=state}))
	end
	local outputs = {}
	for _,miner in ipairs(attempt.miners) do
		local out = M.output_rotated[miner.direction]
		outputs[(miner.x+out.x)..","..(miner.y+out.y)] = true
	end
	local function free(x,y)
		local tile = G:get_tile(x,y)
		return tile and not tile.built_thing and not outputs[x..","..y]
	end
	local function place(x,y,light)
		local spec = {name=state.pole_choice,quality=state.pole_quality_choice,thing="pole",grid_x=x,grid_y=y}
		local _,box = rows.position(state,spec)
		if free(x,y) and (not selected or not obstacles.blocked_box(selected,box)) then
			state.builder_power_poles[#state.builder_power_poles+1] = spec
			G:build_thing_simple(x,y,"pole")
			if light and state.lamp_choice and free(x-1,y) then
				local lamp = {name="small-lamp",thing="lamp",grid_x=x-1,grid_y=y}
				local _,lb = rows.position(state,lamp)
				if not selected or not obstacles.blocked_box(selected,lb) then
					state.builder_lamps[#state.builder_lamps+1] = lamp
					G:build_thing_simple(x-1,y,"lamp")
				end
			end
		end
	end
	for i=0,state.miner_lane_count do
		local y = i==0 and attempt.sy-1 or attempt.lane_layout[i].y+M.size
		for column=1,state.miner_max_column do
			local x = attempt.sx+(column-1)*state.miner_stride+M.size-1
			if state.beacon_pipe_gap==0 or i%2==0 then place(x,y,i%2==0) end
			if i%2==0 then place(x-M.size+1,y,false) end
		end
	end
	local x = attempt.sx-proto.tile_width-state.beacon_pipe_gap-1
	local step = max(1,floor(min(state.pole.wire,state.pole.radius*2)))
	local last = attempt.lane_layout[state.miner_lane_count].y+M.size
	for py=attempt.sy-1,last,step do
		local y = py
		for _,belt in ipairs(state.belts) do if belt.y==y then y=y-1;break end end
		place(x,y,false)
	end
	if state.beacon_pipe_gap>0 then
		for column=1,state.miner_max_column do
			local px = attempt.sx+(column-1)*state.miner_stride+M.size
			for py=attempt.sy-1,last,step do
				for offset=0,2 do
					local y = py-offset
					local output = false
					for _,belt in ipairs(state.belts) do if belt.y==y then output=true;break end end
					if not output and free(px,y) then place(px,y,false);break end
				end
			end
		end
	end
	return "prepare_belt_layout"
end

function layout:prepare_connections(state)
	local issues = state._preview_issues
	local next_step = simple.prepare_connections(self,state)
	if issues and state._preview_issues~=issues then
		for _,issue in ipairs(issues) do state._preview_issues[#state._preview_issues+1]=issue end
	end
	return next_step
end

function layout:prepare_belt_layout(state)
	if state._beacon_logistics then return logistics.prepare_belt_layout(self,state) end
	return compact.prepare_belt_layout(self,state)
end

function layout:finish(state)
	if state._beacon_logistics then return logistics.finish(self,state) end
	return simple.finish(self,state)
end

function layout:expensive_deconstruct(state)
	if state.preview_error then
		if not state.preview_only then state.player.print(state.preview_error);return false end
		return "prepare_connections"
	end
	return simple.expensive_deconstruct(self,state)
end

return layout
