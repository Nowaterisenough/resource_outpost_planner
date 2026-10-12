local simple=require("layouts.simple")
local common=require("layouts.common")
local capacity=require("mpp.belt_capacity")
local beacons=require("mpp.beacons")
local rows=require("mpp.beacon_rows")
local obstacles=require("mpp.obstacles")
local util=require("mpp.mpp_util")
local layout=table.deepcopy(simple)
local floor,min,max=math.floor,math.min,math.max
local N,S,W=defines.direction.north,defines.direction.south,defines.direction.west
layout.name="capacity_rows"
layout.do_power_pole_joiners=false

function layout:initialize_capacity_layout(state)
	state._capacity_rows=true
	state._capacity_gap=state._capacity_gap or 1
	state._capacity_pass=(state._capacity_pass or 0)+1
	state.preview_error=nil
	state.preview_warning=nil
	for _,field in ipairs{"resource_tiles","resource_iter","saved_attempts","best_attempt","_preview_issues",
		"_beacons_prepared","_beacon_counts","_beacon_merges","_beacon_planning","power_grid","_capacity_checked",
		"builder_belt_connections","balanced_output_count","fill_tiles","fill_tile_progress"} do state[field]=nil end
	state.builder_beacons={}
	self:initialize(state)
	state._beacon_rows=beacons.enabled(state) and true or nil
	state.beacon_pipe_gap=state.miner.supports_fluids and state.pipe_choice~="none"
		and (state.requires_fluid or state.force_pipe_placement_choice or state._mining_layout_choice=="pipe") and 1 or 0
	local proto=state._beacon_rows and prototypes.entity[state.beacon_choice]
	state._capacity_beacon_width=proto and proto.tile_width or 0
	state.miner_stride=state.miner.size+state._capacity_beacon_width+2*state.beacon_pipe_gap
	return "initialize_grid"
end

function layout:_placement_attempt(state,attempt)
	local M,C=state.miner,state.coords
	local miners,postponed,lanes={},{},{}
	local H=common.init_heuristic_values()
	local sx,sy=attempt[1],attempt[2]
	local bx,by,b2x,b2y=math.huge,math.huge,-math.huge,-math.huge
	local heuristic=self:_get_miner_placement_heuristic(state)
	local line,price=1,0
	-- One spare tile behind each row carries power without occupying drill drop positions.
	for y=sy,C.th+M.size-1,M.size+state._capacity_gap+1 do
		lanes[line]={y=y,row_index=line}
		local column=1
		for x=sx,C.tw+M.size,state.miner_stride do
			local tile=state.grid:get_tile(x,y)
			local miner={x=x,y=y,origin_x=x+M.x,origin_y=y+M.y,tile=tile,line=line,column=column,direction=S}
			price=price+M.area
			if tile and not tile.forbidden and tile.neighbors_outer>0 then
				if heuristic(tile) then
					miners[#miners+1]=miner
					common.add_heuristic_values(H,M,tile)
					bx,by,b2x,b2y=min(bx,x-1),min(by,y-1),max(b2x,x+M.size-1),max(b2y,y+M.size-1)
				else postponed[#postponed+1]=miner end
			end
			column=column+1
		end
		line=line+1
	end
	local result={sx=sx,sy=sy,bx=bx,by=by,b2x=b2x,b2y=b2y,miners=miners,postponed=postponed,
		lane_layout=lanes,heuristics=H,price=price,heuristic_score=0}
	common.finalize_heuristic_values(result,H,C)
	return result
end

local function issue(state,x,y,reason)
	state.preview_error=state.preview_error or reason
	local c=state.coords
	local p=util.revert_world(c.gx,c.gy,state.direction_choice,x,y,c.tw,c.th)
	state._preview_issues=state._preview_issues or {}
	state._preview_issues[#state._preview_issues+1]={position={x=floor(p[1])+0.5,y=floor(p[2])+0.5},reason=reason}
end

function layout:prepare_miner_layout(state)
	simple.prepare_miner_layout(self,state)
	if state._beacon_rows then rows.reserve(state);rows.finish(state) end
	local limit=capacity.limit(state)
	local budget=capacity.output_budget(state)
	local groups=capacity.row_groups(state.miner_lanes,state.miner_lane_count,limit,function(miner)
		return common.get_mining_drill_production_from_state(state,nil,miner)
	end,budget and budget*2)
	local required=1
	for i=1,state.miner_lane_count do
		required=max(required,#groups[i])
	end
	if required>state._capacity_gap and state._capacity_pass<8 and required<=128 then
		state._capacity_gap=required
		return "initialize_capacity_layout"
	end
	local M=state.miner
	local out=M.output_rotated[S]
	if out.y~=M.size or out.x<1 or out.x>=M.size then
		issue(state,state.best_attempt.sx,state.best_attempt.sy,{"mpp.belt_capacity_geometry"})
	end
	if required>state._capacity_gap then
		issue(state,state.best_attempt.sx,state.best_attempt.sy,{"mpp.belt_capacity_space"})
	end
	state.belts={}
	for i=1,state.miner_lane_count do
		for j,group in ipairs(groups[i]) do
			local first,last=group.miners[1],group.miners[#group.miners]
			local source_y=first.y+out.y
			local x1,x2=first.x+out.x,last.x+out.x
			local rate=group.rate/state.belt.speed
			state.belts[#state.belts+1]={index=#state.belts+1,has_drills=true,is_output=true,lane1=group.miners,
				x1=x1,x2=x2,x_entry=first.x,x_end=last.x+M.size-1,
				x_start=state.best_attempt.sx-state._capacity_beacon_width-state.beacon_pipe_gap-3,
				y=source_y+j-1,source_y=source_y,turn_x=x1-1,
				throughput1=rate,throughput2=0,merged_throughput1=rate,merged_throughput2=0}
			if group.rate>limit+1e-8 and not budget then
				issue(state,x1,source_y,{"mpp.belt_capacity_single",string.format("%.2f",group.rate),string.format("%.2f",limit)})
			end
		end
	end
	state.belt_count=#state.belts
	local covered=capacity.coverage(state)
	for _,tile in ipairs(state.resource_tiles) do
		local original=state._capacity_original_coverage[tile.y]
		if original and original[tile.x] and not (covered[tile.y] and covered[tile.y][tile.x]) then
			issue(state,tile.x,tile.y,{"mpp.belt_capacity_space"})
		end
	end
	state._capacity_original_coverage=nil
	return "prepare_pipe_layout"
end

function layout:prepare_pipe_layout(state)
	state.builder_pipes={}
	state.place_pipes=state.beacon_pipe_gap>0
	if not state.place_pipes then return "prepare_pole_layout" end
	local M,attempt=state.miner,state.best_attempt
	if not M.pipe_left or not M.pipe_right or M.pipe_left[S]==nil or M.pipe_left[S]~=M.pipe_right[S] then
		issue(state,attempt.sx,attempt.sy,{"mpp.belt_capacity_geometry"})
		return "prepare_pole_layout"
	end
	local specs={}
	for i=1,state.miner_lane_count do
		local y=attempt.lane_layout[i].y+M.pipe_left[S]
		local present={}
		for _,miner in ipairs(state.miner_lanes[i] or {}) do present[miner.column]=true end
		for column=1,state.miner_max_column do
			local x=attempt.sx+(column-1)*state.miner_stride
			if not present[column] then specs[#specs+1]={structure="horizontal",x=x-1,y=y,w=M.size+1} end
			if column<state.miner_max_column then
				specs[#specs+1]={structure="horizontal",x=x+M.size,y=y,w=state.miner_stride-M.size-1}
			end
		end
		specs[#specs+1]={structure="cap_vertical",x=attempt.sx-1,y=y,skip_up=i==1,skip_down=i==state.miner_lane_count}
		if i>1 then
			local previous=attempt.lane_layout[i-1].y
			local py=previous+M.pipe_left[S]
			specs[#specs+1]={structure="joiner_vertical",x=attempt.sx-1,y=py+1,h=y-py-1,belt_y=previous+M.size}
		end
	end
	state.pipe_layout_specification=specs
	common.create_pipe_building_environment(state).process_specification(specs)
	return "prepare_pole_layout"
end

function layout:prepare_pole_layout(state)
	state.builder_power_poles,state.builder_lamps={},{}
	if state.pole_choice=="none" or state.pole_choice=="zero_gap" then return "prepare_belt_layout" end
	local M,attempt,G=state.miner,state.best_attempt,state.grid
	local selected=obstacles.active(state) and obstacles.get(setmetatable({_belt_routing=true},{__index=state}))
	local function place(x,y)
		local tile=G:get_tile(x,y)
		if not tile or tile.built_thing then return end
		local spec={name=state.pole_choice,quality=state.pole_quality_choice,thing="pole",grid_x=x,grid_y=y}
		local _,box=rows.position(state,spec)
		if selected and obstacles.blocked_box(selected,box) then return end
		state.builder_power_poles[#state.builder_power_poles+1]=spec
		G:build_thing_simple(x,y,"pole")
	end
	local join_x=attempt.sx-state._capacity_beacon_width-state.beacon_pipe_gap-1
	local step=max(1,floor(min(state.pole.wire,state.pole.radius*2)))
	for i=1,state.miner_lane_count do
		local y=attempt.lane_layout[i].y-1
		for column=1,state.miner_max_column do
			local x=attempt.sx+(column-1)*state.miner_stride
			place(x,y);place(x+M.size-1,y)
			for py=y+step,y+M.size+state._capacity_gap,step do
				place(x,py);place(x+M.size-1,py)
			end
		end
		place(join_x,y)
		local last=y+M.size+state._capacity_gap+1
		for py=y+step,last-1,step do place(join_x,py) end
	end
	rows.prune_poles(state)
	return "prepare_belt_layout"
end

function layout:prepare_belt_layout(state)
	local env,built=common.create_belt_building_environment(state)
	local G=state.grid
	local receivers={}
	for _,belt in ipairs(state.belts) do
		local row=receivers[belt.source_y] or {};receivers[belt.source_y]=row
		for _,miner in ipairs(belt.lane1 or {}) do row[miner.x+state.miner.output_rotated[S].x]=true end
	end
	local function blocked(x,y)
		local tile=G:get_tile(x,y)
		return tile and tile.built_thing
	end
	local function horizontal(x1,x2,y)
		local x=x1
		while x<=x2 do
			if blocked(x,y) then issue(state,x,y,{"mpp.belt_capacity_route"});return end
			if x<x2 and blocked(x+1,y) then
				local right=x+1
				-- A tunnel endpoint needs a second free tile before another obstruction.
				while right<=x2 and (blocked(right,y) or right<x2 and blocked(right+1,y)) do right=right+1 end
				if right>x2 or not state.belt.related_underground_belt or right-x>state.belt.underground_reach then
					issue(state,x,y,{"mpp.belt_capacity_route"});return
				end
				for hidden=x+1,right-1 do
					if receivers[y] and receivers[y][hidden] then issue(state,hidden,y,{"mpp.belt_capacity_route"});return end
				end
				env.create_underground(x,y,W,"output");env.create_underground(right,y,W,"input")
				x=right+1
			else env.create_belt(x,y,W);x=x+1 end
		end
	end
	-- Groups further to the right descend to lower bus lanes, so their turns never cross earlier groups.
	for _,belt in ipairs(state.belts) do
		if belt.y==belt.source_y then horizontal(belt.x_start,belt.x2,belt.y)
		else
			horizontal(belt.turn_x+1,belt.x2,belt.source_y)
			for y=belt.source_y,belt.y-1 do
				if blocked(belt.turn_x,y) then issue(state,belt.turn_x,y,{"mpp.belt_capacity_route"})
				else env.create_belt(belt.turn_x,y,S) end
			end
			horizontal(belt.x_start,belt.turn_x,belt.y)
		end
	end
	-- Pair already-limited groups on opposite sides, leaving each side's capacity independent.
	local starts={}
	for _,spec in ipairs(built) do
		if spec.grid_x==state.belts[1].x_start then starts[spec.grid_y]=spec end
	end
	local budget=capacity.output_budget(state)
	local outputs=#state.belts
	for i=2,#state.belts,2 do
		local source,target=state.belts[i],state.belts[i-1]
		local start=starts[source.y]
		if start and not start.type and (budget and outputs>budget or capacity.merge_candidate(state,source)) then
			start.direction=N
			for y=target.y+1,source.y-1 do env.create_belt(source.x_start,y,N) end
			target.lane2=source.lane1
			target.throughput2=source.throughput1
			target.merged_throughput2=source.throughput1
			source.is_output=false;source.merge_direction=N
			outputs=outputs-1
		end
	end
	state.builder_belts=built
	common.commit_built_tiles_to_grid(G,built,"belt")
	return "prepare_lamp_layout"
end

function layout:prepare_connections(state)
	if state.preview_error then
		if not state.preview_only then state.player.print(state.preview_error);return false end
		return "prepare_beacons"
	end
	return simple.prepare_connections(self,state)
end

return layout
