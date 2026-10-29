local pole_connections = require("mpp.pole_connections")
local planner = require("mpp.belt_planner")
local builder = require("mpp.builder")
local common = require("layouts.common")
local capacity = require("mpp.belt_capacity")
local forced_build = require("mpp.forced_build")
local output = {}

function output.begin(data,player)
	local source=data.last_state
	if not source or source.surface~=player.surface then return false end
	local spec=common.create_belt_planner_specification(source)
	if not spec then return false end
	data.preview={player_index=player.index,surface=source.surface,resources=source.resources or {},
		revision=0,renderings={},specs={},issues={},output_only=true,source_spec=spec,belt_specification=spec}
	return true
end

local function prepare(data,preview_only,mode)
	local draft,source=data.preview,data.last_state
	if not draft.belt_target then return nil,{"mpp.preview_empty"} end
	local choices={}
	for k,v in pairs(data.choices) do choices[k]=v end
	choices._force_build_mode=mode
	choices._previous_state=source
	choices._collected_ghosts=source._collected_ghosts or {}
	choices._deconstruction_orders=source._deconstruction_orders
	local state,err=planner.create_state(draft.source_spec,draft.belt_target,choices)
	if not state then return nil,err end
	state.preview_warning=capacity.output_warning(source,data.choices)
	state.output_only=true
	state.preview_only=preview_only
	state._preview_specs={}
	local ok,routes,diagnostic=planner.plan(state)
	if not ok then return state,routes,diagnostic end
	return state,nil,{routes=routes,issues={}}
end

function output.refresh(data)
	local draft=data.preview
	if not draft.belt_target then draft.ready=false;draft.error=nil;draft.warning=nil;draft.specs={};draft.issues={};return false end
	local state,err,diagnostic=prepare(data,true)
	draft.error=err
	draft.warning=state and state.preview_warning
	draft.issues=diagnostic and diagnostic.issues or {{position=draft.belt_target.position,reason=err}}
	draft.specs={}
	if state and diagnostic then
		local create=builder.create_entity_builder(state,{diagnostic=true})
		for _,spec in ipairs(diagnostic.routes or {}) do create(spec) end
		planner.place_landfill(state,diagnostic.routes)
		draft.specs=state._preview_specs
	end
	draft.ready=state~=nil and err==nil and #draft.specs>0
	draft.entity_count,draft.tile_count=0,0
	for _,spec in ipairs(draft.specs) do
		if spec.name=="tile-ghost" then draft.tile_count=draft.tile_count+1 else draft.entity_count=draft.entity_count+1 end
	end
	return draft.ready
end

function output.apply(data,mode,facility_removal)
	if data.choices.remove_entities_choice then
		facility_removal=facility_removal or mode==nil
		mode=defines.build_mode.superforced
	end
	if not mode and not output.refresh(data) then return false end
	local fallback=not facility_removal and data.preview.error and mode or nil
	local state,err,diagnostic=prepare(data,mode~=nil,fallback)
	if err and mode and not fallback and not facility_removal then state,err,diagnostic=prepare(data,true,mode) end
	if err or not state then data.preview.error=err;data.preview.ready=false;return false end
	local create=builder.create_entity_builder(state,{do_deconstruction=true})
	for _,spec in ipairs(diagnostic.routes) do create(spec) end
	planner.place_landfill(state,diagnostic.routes)
	if mode and not forced_build.apply(state,mode) then
		data.preview.error={"mpp.preview_force_empty"};data.preview.ready=false;return false
	end
	if not mode then pole_connections.connect(state) end
	local source=data.last_state
	for _,object in pairs(state._render_objects or {}) do
		source._render_objects=source._render_objects or {};source._render_objects[#source._render_objects+1]=object
	end
	source._collected_ghosts=state._collected_ghosts
	source._deconstruction_orders=state._deconstruction_orders
	source.balanced_output_count=state.balanced_output_count
	for _,field in ipairs{"output_station_choice","output_locomotive_count_choice","output_wagon_count_choice",
		"output_loading_side_choice","output_balance_choice","output_belt_count_choice"} do source[field]=data.choices[field] end
	return true
end

return output
