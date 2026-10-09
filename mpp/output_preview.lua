local planner = require("mpp.belt_planner")
local builder = require("mpp.builder")
local common = require("layouts.common")
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

local function prepare(data,preview_only)
	local draft,source=data.preview,data.last_state
	if not draft.belt_target then return nil,{"mpp.preview_empty"} end
	local choices={}
	for k,v in pairs(data.choices) do choices[k]=v end
	choices._previous_state=source
	choices._collected_ghosts=source._collected_ghosts or {}
	choices._deconstruction_orders=source._deconstruction_orders
	local state,err=planner.create_state(draft.source_spec,draft.belt_target,choices)
	if not state then return nil,err end
	state.output_only=true
	state.preview_only=preview_only
	state._preview_specs={}
	local ok,routes,diagnostic=planner.plan(state)
	if not ok then return state,routes,diagnostic end
	return state,nil,{routes=routes,issues={}}
end

function output.refresh(data)
	local draft=data.preview
	if not draft.belt_target then draft.ready=false;draft.error=nil;draft.specs={};draft.issues={};return false end
	local state,err,diagnostic=prepare(data,true)
	draft.error=err
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

function output.apply(data)
	if not output.refresh(data) then return false end
	local state,err,diagnostic=prepare(data,false)
	if err or not state then return false end
	local create=builder.create_entity_builder(state,{do_deconstruction=true})
	for _,spec in ipairs(diagnostic.routes) do create(spec) end
	planner.place_landfill(state,diagnostic.routes)
	local source=data.last_state
	source._collected_ghosts=state._collected_ghosts
	source._deconstruction_orders=state._deconstruction_orders
	source.balanced_output_count=state.balanced_output_count
	for _,field in ipairs{"output_station_choice","output_locomotive_count_choice","output_wagon_count_choice",
		"output_loading_side_choice","output_balance_choice","output_belt_count_choice"} do source[field]=data.choices[field] end
	return true
end

return output
