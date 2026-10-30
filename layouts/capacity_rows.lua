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

local function column_offset(state,column)
	return (column-1)*state.miner_stride
end

local function row_gap(state,line)
	return state._capacity_row_gaps and (state._capacity_row_gaps[line] or 1) or state._capacity_gap
end

function layout:initialize_capacity_layout(state)
	local reuse=state.grid and state.resource_tiles
	state._capacity_rows=true
	state._capacity_tight_big=state.miner.size==5 and state._mining_layout_choice=="compact"
	-- A disabled load controller must never retain a previous split corridor.
	-- Keep this local to compact big drills; other layouts retain their spacing.
	if state._capacity_tight_big then
		state._capacity_separate_power=nil
		if not state.belt_merge_choice then
			state._capacity_gap=1
			state._capacity_row_gaps={}
		end
	end
	state._capacity_gap=state._capacity_gap or 1
	if state.miner.size>=5 then state._capacity_row_gaps=state._capacity_row_gaps or {} end
	state._capacity_pass=(state._capacity_pass or 0)+1
	state.preview_error=nil
	state.preview_warning=nil
	for _,field in ipairs{"saved_attempts","best_attempt","_preview_issues",
		"_beacons_prepared","_beacon_counts","_beacon_merges","_beacon_planning","power_grid","_capacity_checked",
		"builder_belt_connections","balanced_output_count","fill_tiles","fill_tile_progress"} do state[field]=nil end
	state.builder_beacons={}
	self:initialize(state)
	state._beacon_rows=beacons.enabled(state) and true or nil
	state._capacity_fluid=state.miner.supports_fluids and state.pipe_choice~="none"
		and (state.requires_fluid or state.force_pipe_placement_choice or state._mining_layout_choice=="pipe")
	-- Adjacent same-facing drills pass fluid directly through their side ports.
	state.beacon_pipe_gap=state._capacity_fluid and (state._beacon_rows or state.miner.size<5) and 1 or 0
	local proto=state._beacon_rows and prototypes.entity[state.beacon_choice]
	state._capacity_beacon_width=proto and proto.tile_width or 0
	-- Big compact layouts put beacons in local drill-sized pockets instead of
	-- opening a three-tile-wide strip through the whole patch.
	state._capacity_beacon_slots=state._capacity_tight_big and state._beacon_rows
		and proto.tile_width<=3 and proto.tile_height<=3
	if state._capacity_beacon_slots then state._capacity_beacon_width=0;state.beacon_pipe_gap=0 end
	state.miner_stride=state.miner.size+state._capacity_beacon_width+2*state.beacon_pipe_gap
	if reuse then
		-- Changing lane spacing does not change ore convolution or forbidden tiles.
		for _,row in pairs(state.grid) do
			for _,tile in pairs(row) do tile.built_thing=nil;tile.consumed=false end
		end
		return self:prepare_layout_attempts(state)
	end
	state.resource_tiles=nil;state.resource_iter=nil
	return "initialize_grid"
end

function layout:_placement_attempt(state,attempt)
	local M,C=state.miner,state.coords
	local miners,postponed,lanes,beacon_slots={},{},{},{}
	local H=common.init_heuristic_values()
	local sx,sy=attempt[1],attempt[2]
	local bx,by,b2x,b2y=math.huge,math.huge,-math.huge,-math.huge
	local heuristic=self:_get_miner_placement_heuristic(state)
	local line,price=1,0
	-- Poles and lamps share the belt corridor; only a failed crossing uses a separate row.
	local y=sy
	while y<=C.th+M.size-1 do
		local stagger=not state._beacon_rows and not state._capacity_fluid and M.size>=5
		local row_x=sx+(stagger and line%2==0 and floor(M.size/2) or 0)
		lanes[line]={y=y,row_index=line,start_x=row_x}
		local column=1
		local x=row_x
		while x<=C.tw+M.size do
			local tile=state.grid:get_tile(x,y)
			price=price+M.area
			if state._capacity_beacon_slots and line%2==1 and column%3==2 then
				beacon_slots[#beacon_slots+1]={x=x,y=y}
			elseif tile and not tile.forbidden and tile.neighbors_outer>0 then
				local miner={x=x,y=y,origin_x=x+M.x,origin_y=y+M.y,tile=tile,line=line,column=column,direction=S}
				if heuristic(tile) then
					miners[#miners+1]=miner
					common.add_heuristic_values(H,M,tile)
					bx,by,b2x,b2y=min(bx,x-1),min(by,y-1),max(b2x,x+M.size-1),max(b2y,y+M.size-1)
				else postponed[#postponed+1]=miner end
			end
			column=column+1
			x=row_x+column_offset(state,column)
		end
		y=y+M.size+row_gap(state,line)+(state._capacity_separate_power and 1 or 0)
		line=line+1
	end
	local result={sx=sx,sy=sy,bx=bx,by=by,b2x=b2x,b2y=b2y,miners=miners,postponed=postponed,
		lane_layout=lanes,beacon_slots=beacon_slots,heuristics=H,price=price,heuristic_score=0}
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
	local limit=state.belt_merge_choice and capacity.limit(state) or math.huge
	local budget=capacity.output_budget(state)
	-- Direct entry for big compact drills must retain the single-drill check
	-- previously performed before the capacity fallback. Beacon-row entry keeps
	-- its existing density-first warning behavior.
	if state.belt_merge_choice and not budget and not state._beacon_rows then
		local single_error=capacity.single_error(state)
		if single_error then issue(state,state.best_attempt.sx,state.best_attempt.sy,single_error) end
	end
	local production=common.mining_production_calculator(state)
	local groups
	if state._capacity_tight_big then
		groups=capacity.compact_row_groups(state.miner_lanes,state.miner_lane_count,limit,production,
			state._capacity_row_gaps,state._capacity_edge and 2 or 4)
	else
		groups=capacity.row_groups(state.miner_lanes,state.miner_lane_count,limit,production,budget and budget*2)
	end
	-- Pair contiguous receiving groups before reserving bus space. Both loads
	-- participate in the lower-bound decision; either group may be the short tail.
	local pairs_by_row,outputs={},0
	local compact=not state._capacity_edge
	local group_count=0
	for i=1,state.miner_lane_count do group_count=group_count+#groups[i] end
	local needed=budget and max(0,group_count-budget) or 0
	local lower=capacity.ratios(state)
	local trigger=2*state.belt.speed*common.get_belt_capacity_multiplier(state)*(lower-1e-8)
	for i=1,state.miner_lane_count do
		local pair={};pairs_by_row[i]=pair
		local j=1
		while j<=#groups[i] do
			local a,b=groups[i][j],groups[i][j+1]
			if b and (state._capacity_tight_big and #groups[i]>2 or not state._capacity_tight_big and (needed>0 or a.rate<trigger or b.rate<trigger)) then
				pair[j+1]=j;j=j+1;needed=max(0,needed-1)
			end
			outputs=outputs+1;j=j+1
		end
	end
	-- A budget spanning multiple rows may need edge merges across row boundaries.
	if budget and outputs>budget and not state._capacity_tight_big then compact=false end
	local bus_offset=not state._capacity_tight_big and (state._beacon_rows or state.beacon_pipe_gap>0
		or not state.belt.related_underground_belt or state.belt.underground_reach<state.miner_stride+1) and 1 or 0
	local required,resize=1,false
	local next_gaps=state._capacity_row_gaps and table.deepcopy(state._capacity_row_gaps)
	for i=1,state.miner_lane_count do
		local count,paired=0,false
		for j in ipairs(groups[i]) do
			if compact and pairs_by_row[i][j] then paired=true else count=count+1 end
		end
		local needed_gap=max(count+(compact and count>1 and bus_offset or 0),paired and 2 or 1)
		required=max(required,needed_gap)
		if state._capacity_row_gaps and needed_gap>row_gap(state,i) then
			next_gaps[i]=needed_gap;resize=true
		end
	end
	state._capacity_compact=compact
	if (resize or required>state._capacity_gap) and state._capacity_pass<8 and required<=128 then
		state._capacity_gap=required
		state._capacity_row_gaps=next_gaps
		return "initialize_capacity_layout"
	end
	local M=state.miner
	local out=M.output_rotated[S]
	if out.y~=M.size or out.x<1 or out.x>=M.size then
		issue(state,state.best_attempt.sx,state.best_attempt.sy,{"mpp.belt_capacity_geometry"})
	end
	if resize or required>state._capacity_gap then
		issue(state,state.best_attempt.sx,state.best_attempt.sy,{"mpp.belt_capacity_space"})
	end
	state.belts={}
	for i=1,state.miner_lane_count do
		local row_start,output_index=#state.belts,0
		for j,group in ipairs(groups[i]) do
			local first,last=group.miners[1],group.miners[#group.miners]
			local source_y=first.y+out.y
			local x1,x2=first.x+out.x,last.x+out.x
			local rate=group.rate/state.belt.speed
			local paired=compact and pairs_by_row[i][j]
			if not paired then output_index=output_index+1 end
			state.belts[#state.belts+1]={index=#state.belts+1,capacity_row=i,has_drills=true,is_output=true,lane1=group.miners,
				x1=x1,x2=x2,x_entry=first.x,x_end=last.x+M.size-1,
				x_start=state.best_attempt.sx-state._capacity_beacon_width-state.beacon_pipe_gap-3,
				y=source_y+output_index-1+(compact and output_index>1 and bus_offset or 0),source_y=source_y,turn_x=x1-1,
				throughput1=rate,throughput2=0,merged_throughput1=rate,merged_throughput2=0}
			if paired then
				local source,target=state.belts[#state.belts],state.belts[row_start+paired]
				source.is_output=false;source.merge_direction=N
				source.capacity_target=target.index;source.y=source_y+1
				-- A short side-feed leaves a four-tile underground crossing for
				-- the second output, even across missing drills or beacon pockets.
				if state._capacity_tight_big then source.turn_x=target.x2+2 end
				target.lane2=source.lane1;target.throughput2=rate;target.merged_throughput2=rate
			end
			if group.rate>limit+1e-8 and not budget and not state._capacity_tight_big then
				issue(state,x1,source_y,{"mpp.belt_capacity_single",string.format("%.2f",group.rate),string.format("%.2f",limit)})
			end
		end
	end
	state.belt_count=#state.belts
	local covered=capacity.coverage(state)
	for _,tile in ipairs(state.resource_tiles) do
		local original=state._capacity_original_coverage and state._capacity_original_coverage[tile.y]
		if original and original[tile.x] and not (covered[tile.y] and covered[tile.y][tile.x]) then
			issue(state,tile.x,tile.y,{"mpp.belt_capacity_space"})
		end
	end
	return "prepare_pipe_layout"
end

function layout:prepare_pipe_layout(state)
	state.builder_pipes={}
	state.place_pipes=state._capacity_fluid
	if not state.place_pipes then return "prepare_pole_layout" end
	local M,attempt=state.miner,state.best_attempt
	if not M.pipe_left or not M.pipe_right or M.pipe_left[S]==nil or M.pipe_left[S]~=M.pipe_right[S] then
		issue(state,attempt.sx,attempt.sy,{"mpp.belt_capacity_geometry"})
		return "prepare_pole_layout"
	end
	local specs={}
	for i=1,state.miner_lane_count do
		local y=attempt.lane_layout[i].y+M.pipe_left[S]
		-- Build each gap once. A missing first/inner drill must not put a
		-- horizontal underground endpoint on the vertical header or on the
		-- neighbouring gap's endpoint.
		local cursor=attempt.sx
		for _,miner in ipairs(state.miner_lanes[i] or {}) do
			if miner.x>cursor then
				specs[#specs+1]={structure="horizontal",x=cursor,y=y,w=miner.x-cursor-1}
			end
			cursor=miner.x+M.size
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

function layout:_prepare_separate_poles(state)
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
			local x=(attempt.lane_layout[i].start_x or attempt.sx)+column_offset(state,column)
			place(x,y);place(x+M.size-1,y)
			for py=y+step,y+M.size+row_gap(state,i),step do
				place(x,py);place(x+M.size-1,py)
			end
		end
		place(join_x,y)
		local last=y+M.size+row_gap(state,i)+1
		for py=y+step,last-1,step do place(join_x,py) end
	end
	rows.prune_poles(state)
	return "prepare_belt_layout"
end

function layout:prepare_pole_layout(state)
	if state._capacity_separate_power then return self:_prepare_separate_poles(state) end
	state.builder_power_poles,state.builder_lamps={},{}
	if state.pole_choice=="none" or state.pole_choice=="zero_gap" then return "prepare_belt_layout" end
	local M,attempt,G=state.miner,state.best_attempt,state.grid
	local selected=obstacles.active(state) and obstacles.get(setmetatable({_belt_routing=true},{__index=state}))
	local reserved={}
	local function reserve(x,y)
		reserved[y]=reserved[y] or {};reserved[y][x]=true
	end
	for _,belt in ipairs(state.belts) do
		for _,miner in ipairs(belt.lane1) do reserve(miner.x+M.output_rotated[S].x,belt.source_y) end
		for y=belt.source_y,belt.y do reserve(belt.turn_x,y) end
		if belt.capacity_target then
			reserve(state.belts[belt.capacity_target].x2,belt.source_y+1)
			if state._capacity_tight_big then
				-- Leave the junction and its downstream neighbour on the surface;
				-- a lamp here would turn the receiving tile into a tunnel endpoint.
				reserve(state.belts[belt.capacity_target].x2-1,belt.source_y)
				reserve(state.belts[belt.capacity_target].x2+1,belt.source_y)
				reserve(belt.turn_x+1,belt.source_y)
			end
		end
	end
	local function place(x,y,thing,name,list)
		local tile=G:get_tile(x,y)
		if not tile or tile.built_thing or reserved[y] and reserved[y][x] then return false end
		local spec={name=name,thing=thing,grid_x=x,grid_y=y,quality=thing=="pole" and state.pole_quality_choice or nil}
		local _,box=rows.position(state,spec)
		if selected and obstacles.blocked_box(selected,box) then return false end
		list[#list+1]=spec;G:build_thing_simple(x,y,thing)
		return true
	end
	local join_x=attempt.sx-state._capacity_beacon_width-state.beacon_pipe_gap-1
	local step=max(1,floor(min(state.pole.wire,state.pole.radius*2)))
	for i=1,state.miner_lane_count do
		local y=attempt.lane_layout[i].y+M.size
		for column=1,state.miner_max_column do
			local x=(attempt.lane_layout[i].start_x or attempt.sx)+column_offset(state,column)
			place(x,y,"pole",state.pole_choice,state.builder_power_poles)
			place(x+M.size-1,y,"pole",state.pole_choice,state.builder_power_poles)
			if state._beacon_rows and M.size+row_gap(state,i)>=2*state.pole.radius+prototypes.entity[state.beacon_choice].tile_height then
				local py=y+row_gap(state,i)-1
				place(x,py,"pole",state.pole_choice,state.builder_power_poles)
				place(x+M.size-1,py,"pole",state.pole_choice,state.builder_power_poles)
			end
		end
		place(join_x,y,"pole",state.pole_choice,state.builder_power_poles)
		if i<state.miner_lane_count then
			local last=attempt.lane_layout[i+1].y+M.size
			for py=y+step,last-1,step do place(join_x,py,"pole",state.pole_choice,state.builder_power_poles) end
		end
	end
	rows.prune_poles(state)
	-- Reserve lamps before routing, so a tunnel can cross the pair together.
	if state.lamp_choice then
		for _,pole in ipairs(state.builder_power_poles) do
			if not place(pole.grid_x+1,pole.grid_y,"lamp","small-lamp",state.builder_lamps) then
				place(pole.grid_x-1,pole.grid_y,"lamp","small-lamp",state.builder_lamps)
			end
		end
	end
	return "prepare_belt_layout"
end

function layout:prepare_lamp_layout(state)
	if state._capacity_separate_power then return simple.prepare_lamp_layout(self,state) end
	return "expensive_deconstruct"
end

function layout:_prepare_edge_belts(state)
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
	local function horizontal(x1,x2,y,tunnel)
		local x=x1
		while x<=x2 do
			if blocked(x,y) then issue(state,x,y,{"mpp.belt_capacity_route"});return end
			-- The second corridor is a through route, not a receiving belt.
			-- Tunnel it between the surface turn and outlet, including beneath
			-- shared poles/lamps. Adjacent tunnels connect on the surface.
			local right
			if tunnel and x>x1 and x<x2-2 and state.belt.related_underground_belt then
				right=min(x2-1,x+state.belt.underground_reach)
				while right>x+1 and (blocked(right,y) or blocked(right+1,y)) do right=right-1 end
				if right<=x+1 then right=nil end
			end
			if right then
				env.create_underground(x,y,W,"output");env.create_underground(right,y,W,"input")
				x=right+1
			elseif x<x2 and blocked(x+1,y) then
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
			horizontal(belt.x_start,belt.turn_x,belt.y,state._capacity_tight_big and state.belt_merge_choice)
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
		local auto_merge=not state._capacity_tight_big
			and (capacity.merge_candidate(state,source) or capacity.merge_candidate(state,target))
		if not state._capacity_tight_big and start and not start.type and (budget and outputs>budget or auto_merge) then
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

-- Track this pass's belts separately from the committed grid. Crossings must
-- tunnel beneath earlier merge branches, never silently overlap their surface belts.
function layout:_prepare_compact_belts(state)
	local env,built=common.create_belt_building_environment(state)
	local G,occupied,receivers=state.grid,{},{}
	for _,belt in ipairs(state.belts) do
		local row=receivers[belt.source_y] or {};receivers[belt.source_y]=row
		for _,miner in ipairs(belt.lane1) do row[miner.x+state.miner.output_rotated[S].x]=true end
	end
	local function blocked(x,y)
		local tile=G:get_tile(x,y)
		return occupied[y] and occupied[y][x] or tile and tile.built_thing
	end
	local failed=false
	local function create(x,y,direction,kind)
		if blocked(x,y) then failed=true;state._capacity_route_failure={x=x,y=y,reason="occupied",thing=blocked(x,y)};return end
		occupied[y]=occupied[y] or {};occupied[y][x]=true
		if kind then env.create_underground(x,y,direction,kind) else env.create_belt(x,y,direction) end
	end
	local function horizontal(x1,x2,y,tunnel)
		local x=x1
		while x<=x2 and not failed do
			if blocked(x,y) then failed=true;state._capacity_route_failure={x=x,y=y,reason="occupied",thing=blocked(x,y)};return end
			local right
			if tunnel and x>x1 and x<x2-2 and state.belt.related_underground_belt then
				right=min(x2-1,x+state.belt.underground_reach)
				while right>x+1 and (blocked(right,y) or blocked(right+1,y)) do right=right-1 end
				if right<=x+1 then right=nil end
			end
			if right then
				create(x,y,W,"output");create(right,y,W,"input");x=right+1
			elseif x<x2 and blocked(x+1,y) then
				local right=x+1
				while right<=x2 and (blocked(right,y) or right<x2 and blocked(right+1,y)) do right=right+1 end
				if right>x2 or not state.belt.related_underground_belt or right-x>state.belt.underground_reach then
					failed=true;state._capacity_route_failure={x=x,y=y,right=right,reach=state.belt.underground_reach,reason="reach"};return
				end
				for hidden=x+1,right-1 do
					if receivers[y] and receivers[y][hidden] then failed=true;return end
				end
				create(x,y,W,"output");create(right,y,W,"input");x=right+1
			else create(x,y,W);x=x+1 end
		end
	end
	-- Leave every drop tile on the surface. Merge into the last receiving tile
	-- of the previous group, so the opposite belt side is used next to the drill.
	for _,belt in ipairs(state.belts) do
		horizontal(belt.turn_x+1,belt.x2,belt.source_y)
		if belt.capacity_target then
			local target=state.belts[belt.capacity_target]
			-- Keep the receiving junction straight. Without its east input the
			-- native belt becomes a corner and preserves the same occupied side,
			-- rather than side-loading onto the other side of the target belt.
			if state._capacity_tight_big then create(target.x2+1,belt.source_y,W) end
			create(belt.turn_x,belt.source_y,S)
			horizontal(target.x2+1,belt.turn_x,belt.source_y+1)
			create(target.x2,belt.source_y+1,N)
		end
	end
	for _,belt in ipairs(state.belts) do
		if belt.is_output then
			for y=belt.source_y,belt.y-1 do create(belt.turn_x,y,S) end
			horizontal(belt.x_start,belt.turn_x,belt.y,state._capacity_tight_big and belt.y>belt.source_y)
		end
	end
	if failed then return false end
	state.builder_belts=built
	common.commit_built_tiles_to_grid(G,built,"belt")
	return true
end

function layout:prepare_belt_layout(state)
	if state._capacity_compact then
		if not self:_prepare_compact_belts(state) then
			-- Short-reach undergrounds or reserved pipes/poles can prevent this
			-- crossing. Retry the proven wider routing without partial grid edits.
			state._capacity_edge=true
			state._capacity_separate_power=not state._capacity_tight_big or nil
			return "initialize_capacity_layout"
		end
	else
		self:_prepare_edge_belts(state)
		if state.preview_error and state.preview_error[1]=="mpp.belt_capacity_route" and not state._capacity_separate_power and not state._capacity_tight_big then
			-- Output-budget edge merges can select this route directly, without
			-- going through the compact router's separate-power retry.
			state._capacity_edge=true;state._capacity_separate_power=true
			return "initialize_capacity_layout"
		end
	end
	state._capacity_original_coverage=nil
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
