local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local ore_filter = {}

function ore_filter.product(resource)
	local proto = prototypes.entity[resource]
	if not proto or proto.type ~= "resource" then return end
	for _, product in ipairs(proto.mineable_properties.products or {}) do
		if product.type == "item" then return product.name end
	end
end

function ore_filter.resource_filters()
	local filters = {}
	for name, proto in pairs(prototypes.entity) do
		if proto.type == "resource" and ore_filter.product(name) then
			filters[#filters+1] = {filter="name", name=name, mode="or"}
		end
	end
	table.sort(filters, function(a,b) return a.name < b.name end)
	return filters
end

function ore_filter.select(state)
	if not state.ore_filtering_choice or state.layout_choice == "oil" then return true end
	local name = state.ore_filter_resource_choice
	local item = name and ore_filter.product(name)
	if not item then return false, {"mpp.ore_filter_select"} end
	local found = false
	for _, resource in ipairs(state.resource_counts) do if resource.name == name then found = true; break end end
	if not found then return false, {"mpp.ore_filter_missing", prototypes.entity[name].localised_name} end
	state.ore_filtering_selected, state.ore_filter_item = name, item
	return true
end

local function splitter_for(belt_name)
	local belt = prototypes.entity[belt_name]
	local preferred = prototypes.entity[(belt_name:gsub("transport%-belt", "splitter"))]
	local function matches(proto)
		return proto and proto.type == "splitter" and proto.belt_speed == belt.belt_speed
			and proto.tile_width == 2 and proto.tile_height == 1
	end
	if matches(preferred) then return preferred.name end
	local name
	for _, proto in pairs(prototypes.entity) do
		if matches(proto) and (not name or proto.name < name) then name = proto.name end
	end
	return name
end

function ore_filter.prepare(state)
	if not state.ore_filter_item or not state.ore_filter_with_splitters or state._beacon_logistics
		or state._ore_filters_prepared then return true end
	local outputs, left = {}, math.huge
	for _, belt in ipairs(state.belts or {}) do
		if belt.is_output then outputs[#outputs+1] = belt; left = math.min(left, belt.x_start) end
	end
	-- Logistics layouts retain the strict drill-area exclusion instead of belt filters.
	if #outputs == 0 then return true end
	local splitter = splitter_for(state.belt_choice)
	if not splitter then return false, {"mpp.ore_filter_equipment"} end
	table.sort(outputs, function(a,b) return a.y < b.y end)
	local planned = {}
	local function box(spec)
		local c = state.coords
		local p = util.revert_world(c.gx,c.gy,state.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
		return obstacles.entity_box(spec.name,{x=p[1],y=p[2]},util.bp_direction[state.direction_choice][spec.direction or defines.direction.north])
	end
	for _, list in ipairs{state.builder_miners or {},state.builder_pipes or {},state.builder_belts or {},
		state.builder_power_poles or {},state.builder_lamps or {},state.builder_beacons or {},state.builder_all or {}} do
		for _, spec in ipairs(list) do
			local proto = prototypes.entity[spec.name]
			if proto then
				planned[#planned+1] = box(spec)
				left = math.min(left, math.floor(spec.grid_x - math.max(proto.tile_width,proto.tile_height)/2 - 1))
			end
		end
	end
	local additions, reserved, starts = {}, {}, {}
	local function add(spec)
		local b = box(spec)
		for _, other in ipairs(planned) do
			if b.left_top.x < other.right_bottom.x and b.right_bottom.x > other.left_top.x
				and b.left_top.y < other.right_bottom.y and b.right_bottom.y > other.left_top.y then return false end
		end
		local c = state.coords
		local p = util.revert_world(c.gx,c.gy,state.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
		if not obstacles.can_place(state,spec.name,{x=p[1],y=p[2]},util.bp_direction[state.direction_choice][spec.direction]) then
			state._preview_issues = {{position={x=p[1],y=p[2]},reason={"mpp.ore_filter_space"}}}
			return false
		end
		additions[#additions+1] = spec
		planned[#planned+1] = b
		return true
	end
	for i, belt in ipairs(outputs) do
		-- Stagger towards the waste side: even adjacent collection rows never share an outlet.
		local x, y = left - 2 - (i-1)*3, belt.y
		starts[belt] = x
		for bx = x+1, belt.x_start-1 do
			if not add{name=state.belt_choice,quality=state.belt_quality_choice,thing="belt",
				grid_x=bx,grid_y=y,direction=defines.direction.west} then return false, {"mpp.ore_filter_space"} end
		end
		if not add{name=splitter,quality=state.belt_quality_choice,thing="belt",grid_x=x,grid_y=y-.5,
			direction=defines.direction.west,output_priority="left",filter={name=state.ore_filter_item,quality="normal",comparator=">="},
			extent_w=.5,extent_h=1} then return false, {"mpp.ore_filter_space"} end
		-- Never let the output router connect the unfiltered port back into the clean bundle.
		reserved[#reserved+1] = {name=state.belt_choice,grid_x=x-1,grid_y=y-1,direction=defines.direction.west}
	end
	for _, spec in ipairs(additions) do
		state.builder_belts[#state.builder_belts+1] = spec
		if state.grid then
			for y=math.floor(spec.grid_y),math.ceil(spec.grid_y) do state.grid:build_thing_simple(spec.grid_x,y,"belt") end
		end
	end
	if state.grid then
		for _, spec in ipairs(reserved) do state.grid:build_thing_simple(spec.grid_x,spec.grid_y,"ore-filter-reserved") end
	end
	for belt, x in pairs(starts) do belt.x_start = x end
	state._ore_filter_reserved = reserved
	state._ore_filters_prepared = true
	return true
end

return ore_filter
