local util = require("mpp.mpp_util")
local terrain = require("mpp.terrain")
local planner = require("mpp.belt_planner")
local builder = require("mpp.builder")
local common = require("layouts.common")
local cache = {}
local geometry_revision = 8 -- Big double corridors distribute production across all four belt sides.

local ignored_types={"resource","character","unit","corpse","item-entity","tile-ghost"}
local hazard_names

local function equal(a,b)
	if a==b then return true end
	if type(a)~="table" or type(b)~="table" then return false end
	for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
	for k in pairs(b) do if a[k]==nil then return false end end
	return true
end

local function options(choices)
	local result=table.deepcopy(choices)
	-- Activating the output tool alone does not change the mining layout.
	result.belt_planner_choice=nil
	return result
end

local function same_options(saved,choices)
	for k,v in pairs(choices) do
		if k~="belt_planner_choice" and not equal(saved[k],v) then return false end
	end
	for k in pairs(saved) do if choices[k]==nil then return false end end
	return true
end

local function world(state,area)
	local result={entities={},tiles={},force=state.player.force.index,
		productivity=state.player.force.mining_drill_productivity_bonus,
		stack=state.player.force.belt_stack_size_bonus,effects=table.deepcopy(state.surface.global_effect)}
	for _,e in pairs(state.surface.find_entities_filtered{area=area,type=ignored_types,invert=true}) do
		if e.valid then
			local p,b=e.position,e.bounding_box
			local row=table.concat({e.name,e.type=="entity-ghost" and e.ghost_name or "",p.x,p.y,e.direction,
				e.quality.name,e.force.index,b.left_top.x,b.left_top.y,b.right_bottom.x,b.right_bottom.y},":")
			result.entities[row]=(result.entities[row] or 0)+1
		end
	end
	if not hazard_names then
		hazard_names={}
		for name,proto in pairs(prototypes.tile) do
			if terrain.blocked_tile{name=name,prototype=proto} then hazard_names[#hazard_names+1]=name end
		end
		table.sort(hazard_names)
	end
	if #hazard_names>0 then
		for _,tile in pairs(state.surface.find_tiles_filtered{area=area,name=hazard_names}) do
			result.tiles[tile.position.x..","..tile.position.y]=tile.name
		end
	end
	return result
end

local function resources_match(snapshot)
	-- Older development saves have per-resource records; rebuild their basis.
	if not snapshot.entities then return false end
	for i,entity in ipairs(snapshot.entities) do
		if not entity.valid or entity.amount~=snapshot.amounts[i] then return false end
		local p=entity.position
		if p.x~=snapshot.x[i] or p.y~=snapshot.y[i] then return false end
	end
	return true
end

local function trimmed(state,target,choices)
	return not state._capacity_rows and choices.belt_planner_choice==true and target~=nil
		and not choices.belt_merge_choice and not choices.output_balance_choice and not choices.output_station_choice
		and target.direction==util.bp_direction[state.direction_choice][defines.direction.west]
end

function cache.begin(state)
	if not state.preview_only or state._apply_after_preview or state._force_build_mode or state._preview_environment
		or state._beacon_logistics or state.layout_choice=="blueprints" or state.layout_choice=="oil" then return end
	local data=storage.players[state.player.index]
	if not data or not data.preview then return end
	local c=state.coords
	local margin=state.miner.area+32
	local area={{c.x1-margin,c.y1-margin},{c.x2+margin,c.y2+margin}}
	local resources={entities=state.resources,amounts={},x={},y={}}
	for i,e in ipairs(state.resources) do
		if not e.valid then return end
		local p=e.position
		resources.amounts[i],resources.x[i],resources.y[i]=e.amount,p.x,p.y
	end
	state._preview_environment={area=area,world=world(state,area),resources=resources,choices=options(data.choices)}
end

function cache.capture(state)
	if not state._preview_environment or state.preview_error or state._apply_after_preview
		or state.beacon_choice~="none" and not state._beacon_rows then return end
	-- Save only routing occupancy, not the ore convolution grid or discarded attempts.
	local occupied={}
	for y,row in pairs(state.grid) do
		for x,tile in pairs(row) do if tile.built_thing then
			occupied[y]=occupied[y] or {};occupied[y][x]={built_thing=tile.built_thing}
		end end
	end
	local planned={}
	for _,list in ipairs{state.builder_miners or {},state.builder_pipes or {},state.builder_belts or {},
		state.builder_power_poles or {},state.builder_lamps or {},state.builder_beacons or {},state.builder_all or {},
		state._ore_filter_reserved or {}} do
		for _,spec in ipairs(list) do
			planned[#planned+1]={name=spec.name,grid_x=spec.grid_x,grid_y=spec.grid_y,direction=spec.direction}
		end
	end
	state._output_basis={geometry_revision=geometry_revision,occupied=occupied,planned=planned,trimmed=trimmed(state,state.belt_target,state),
		environment=state._preview_environment,_capacity_rows=state._capacity_rows}
end

function cache.complete(state,draft)
	if state._from_output_cache or not state._output_basis or state.preview_error
		or (state._obstacle_skipped or 0)>0 or not state._output_preview_range then return end
	local basis=state._output_basis
	local env=basis.environment
	if not resources_match(env.resources) or not equal(env.world,world(state,env.area)) then return end
	local range=state._output_preview_range
	basis.before,basis.after={},{}
	for i,spec in ipairs(state._preview_specs) do
		-- The full planner deduplicates shared mining/output landfill. A layout
		-- captured with landfill needs the full path so none of those tiles are lost.
		if spec.name=="tile-ghost" then return end
		if i<range[1] or i>range[2] then
			local list=i<range[1] and basis.before or basis.after
			list[#list+1]=spec
		end
	end
	basis.spec=common.create_belt_planner_specification(state)
	if not basis.spec then return end
	basis.state={}
	for _,key in ipairs{"player","surface","resources","coords","direction_choice","belt_choice","belt_quality_choice",
		"belts","belt","miner","belt_count","statistics_choice","beacon_summary","preview_warning","_previous_state"} do
		basis.state[key]=state[key]
	end
	basis.state.best_attempt={sx=state.best_attempt.sx,sy=state.best_attempt.sy}
	draft.output_basis=basis
end

function cache.resume(data)
	local draft=data.preview
	local basis=draft.output_basis
	if not basis or basis.geometry_revision~=geometry_revision or not draft.belt_target then return end
	local env,source=basis.environment,basis.state
	if not source.surface.valid or source.surface~=draft.surface or not source.player.valid
		or not same_options(env.choices,data.choices)
		or basis.trimmed~=trimmed({_capacity_rows=basis._capacity_rows,direction_choice=source.direction_choice},draft.belt_target,data.choices)
		or not resources_match(env.resources) or not equal(env.world,world(source,env.area)) then return end
	local state={}
	for k,v in pairs(data.choices) do state[k]=v end
	for k,v in pairs(source) do state[k]=v end
	state.type="layout";state.layout_choice="simple";state._callback="refresh_output";state.tick=0
	state.preview_only=true;state.preview_revision=draft.revision;state.belt_target=table.deepcopy(draft.belt_target)
	state._from_output_cache=true;state._output_basis=basis;state._preview_specs={};state._render_objects={}
	return state
end

function cache.refresh(state)
	local basis=state._output_basis
	local connection,err=planner.create_state(basis.spec,state.belt_target,state)
	local routes,issues={},{}
	if connection then
		connection.preview_only=true
		connection.planned=basis.planned
		connection.grid={get_tile=function(_,x,y) return basis.occupied[y] and basis.occupied[y][x] end}
		local ok,result,diagnostic=planner.plan(connection)
		if ok then routes=result;state.balanced_output_count=connection.balanced_output_count
		else err=result;routes=diagnostic and diagnostic.routes or {};issues=diagnostic and diagnostic.issues or {} end
		local create=builder.create_entity_builder(connection,{diagnostic=true,obstacles_checked=ok})
		connection._preview_specs={}
		for _,spec in ipairs(routes) do create(spec) end
		planner.place_landfill(connection,routes)
		state._preview_specs=connection._preview_specs
	end
	if err and #issues==0 then issues={{position=state.belt_target.position,reason=err}} end
	local combined={}
	for _,spec in ipairs(basis.before) do combined[#combined+1]=spec end
	for _,spec in ipairs(state._preview_specs) do combined[#combined+1]=spec end
	for _,spec in ipairs(basis.after) do combined[#combined+1]=spec end
	state._preview_specs=combined;state._preview_issues=issues;state.preview_error=err
	return "finish"
end

return cache
