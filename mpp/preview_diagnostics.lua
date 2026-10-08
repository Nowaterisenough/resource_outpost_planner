local builder = require("mpp.builder")
local util = require("mpp.mpp_util")
local diagnostics = {}

function diagnostics.resource_issues(resources, reason)
	local issues={}
	for _,resource in ipairs(resources or {}) do
		if resource.valid then
			local p=resource.position
			issues[#issues+1]={position={x=p.x,y=p.y},
				left_top={x=math.floor(p.x),y=math.floor(p.y)},
				right_bottom={x=math.floor(p.x)+1,y=math.floor(p.y)+1},reason=#issues==0 and reason or nil}
		end
	end
	return issues
end

function diagnostics.capture(state)
	if not state.preview_only or not state.preview_error then return end
	state._preview_specs=state._preview_specs or {}
	local seen={}
	local function signature(name,x,y) return name..":"..x..","..y end
	for _,spec in ipairs(state._preview_specs) do
		local p=spec.position
		seen[signature(spec.inner_name,spec.grid_x or p.x or p[1],spec.grid_y or p.y or p[2])]=true
	end
	if state.coords then
		local create=builder.create_entity_builder(state,{diagnostic=true})
		local function add(source)
			if not source.name or source.name=="entity-ghost" or not prototypes.entity[source.name] then return end
			local k=signature(source.name,source.grid_x,source.grid_y)
			if not seen[k] then seen[k]=true; create(table.deepcopy(source)) end
		end
		for _,miner in ipairs(state.best_attempt and state.best_attempt.miners or {}) do
			local direction=miner.direction or (miner.line and miner.line%2==0 and defines.direction.north or defines.direction.south)
			if type(direction)=="string" then direction=defines.direction[direction] end
			if state.layout_choice~="blueprints" then direction=util.clamped_rotation(direction,state.miner.rotation_bump or 0) end
			add{name=state.miner_choice,quality=miner.ent and miner.ent.quality or state.miner_quality_choice,
				grid_x=miner.origin_x,grid_y=miner.origin_y,direction=direction,mirror=miner.ent and miner.ent.mirror or miner.mirror}
		end
		for _,list in ipairs{state.builder_pipes or {},state.builder_belts or {},state.builder_power_poles or {},
			state.builder_lamps or {},state.builder_beacons or {},state.builder_all or {},state.builder_belt_connections or {}} do
			for _,source in ipairs(list) do add(source) end
		end
	end
	state._preview_issues=state._preview_issues or {}
	if #state._preview_specs==0 then
		state._preview_issues=diagnostics.resource_issues(state.resources,state.preview_error)
	elseif #state._preview_issues==0 then
		state._preview_issues[1]={position=state._preview_specs[1].position,reason=state.preview_error}
	end
end

return diagnostics
