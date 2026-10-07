local base = require("layouts.base")
local config = require("oil.config")
local planner = require("oil.vendor.planner")
local obstacles = require("mpp.obstacles")
local builder = require("mpp.builder")

local layout = table.deepcopy(base)
layout.name = "oil"
layout.translation = {"", "[entity=pumpjack] ", {"mpp.settings_layout_choice_oil"}}
for name, value in pairs(layout.restrictions) do
	if type(value) == "boolean" then layout.restrictions[name] = false end
end
layout.restrictions.direction_available = false
layout.resource_filter = config.is_fluid_resource

function layout:get_resource_categories(player_data)
	return config.get_resource_categories(player_data)
end

function layout:validate(state)
	local data = config.get(storage.players[state.player.index])
	if not data.choices.pipe_choice then return false, {"mpp.msg_err_no_pipe_choice"} end
	local name
	for _, entity in ipairs(state.resources) do
		if name and entity.name ~= name then return false, {"mpp.msg_oil_mixed_resources"} end
		name = entity.name
	end
	if not data.remove_existing or state.avoid_obstacles_choice then
		if state.avoid_obstacles_choice then
			local safe={}
			for _, resource in ipairs(state.resources) do
				local choice=data.choices[resource.prototype.resource_category.."_pumpjack_choice"]
				if choice and obstacles.can_place(state,choice,resource.position,defines.direction.north) then safe[#safe+1]=resource end
			end
			if #safe==0 then return false,{"mpp.msg_no_safe_resources"} end
			state.resources=safe
		end
		local previous = state._previous_state or storage.players[state.player.index].last_state
		local retained_force
		if not data.retain_entities then retained_force = state.player.force end
		local owned = {}
		for _, ghost in pairs(previous and previous._collected_ghosts or {}) do
			if ghost.valid and ghost.unit_number then owned[ghost.unit_number] = true end
		end
		for _, resource in ipairs(state.resources) do
			local choice = data.choices[resource.prototype.resource_category.."_pumpjack_choice"]
			local proto = choice and prototypes.entity[choice]
			if not proto then return false, {"mpp-oil.msg_no_valid_pumpjacks"} end
			local box, pos = proto.collision_box, resource.position
			local area = {{pos.x + box.left_top.x, pos.y + box.left_top.y},
				{pos.x + box.right_bottom.x, pos.y + box.right_bottom.y}}
			for _, entity in pairs(state.surface.find_entities_filtered{
				area=area, force=retained_force, collision_mask=proto.collision_mask.layers,
			}) do
				if entity.type ~= "character" and entity.type ~= "entity-ghost" then
					return false, {"mpp-oil.msg_all_subtargets_invalid", proto.localised_name}
				end
			end
			for _, ghost in pairs(state.surface.find_entities_filtered{
				area=area, force=retained_force, type="entity-ghost",
			}) do
				if not owned[ghost.unit_number] then
					for layer in pairs(ghost.ghost_prototype.collision_mask.layers) do
						if proto.collision_mask.layers[layer] then
							return false, {"mpp-oil.msg_all_subtargets_invalid", proto.localised_name}
						end
					end
				end
			end
		end
	end
	return true
end

function layout:initialize(state)
	local data = config.get(storage.players[state.player.index])
	state.oil_settings = {
		choices = table.deepcopy(data.choices),
		qualities = table.deepcopy(data.qualities),
		min_beacon_utility = data.min_beacon_utility,
		add_landfill = data.add_landfill and not state.avoid_obstacles_choice,
		remove_existing = data.remove_existing and not state.avoid_obstacles_choice,
		retain_entities = data.retain_entities,
		avoid_obstacles = state.avoid_obstacles_choice,
	}
end

function layout:start(state)
	if state._previous_state and not state.preview_only then
		for _, ghost in pairs(state._previous_state._collected_ghosts or {}) do
			if ghost.valid then ghost.order_deconstruction(state.player.force, state.player) end
		end
	end
	local ghosts = state._collected_ghosts
	local ordered = {}
	local blocked = false
	local plan_message
	state._deconstruction_orders = {}
	local obstruction_index
	if state.avoid_obstacles_choice or state.oil_settings.retain_entities then
		obstruction_index = obstacles.get(state)
		if not state.avoid_obstacles_choice then
			-- Entity retention still permits terrain filling when its shared option is enabled.
			obstruction_index = {tiles={}, boxes=obstruction_index.boxes}
		end
	end
	local success, result = pcall(planner.Plan, state.player, state.oil_settings, state.resources, state.surface, {
		preview_only = state.preview_only,
		on_message = function(message) plan_message=message end,
		on_preview = function(spec) return builder.record_preview(state,spec) end,
		obstacles = obstruction_index,
		on_created = function(ghost)
			if ghost and ghost.valid then ghosts[#ghosts + 1] = ghost end
		end,
		on_blocked = function() blocked = true end,
		on_deconstruction = function(entity)
			if not ordered[entity] and not entity.to_be_deconstructed(state.player.force) then
				ordered[entity] = true
				state._deconstruction_orders[#state._deconstruction_orders + 1] = entity
			end
		end,
	})
	if not success or not result or blocked then
		if state.preview_only then
			state._preview_specs = {}
			state.preview_error = blocked and {"mpp.msg_obstacle_route_failed"} or plan_message or {"mpp.preview_oil_failed"}
			if not success then log("Oil preview failed: "..tostring(result)) end
			return false
		end
		for _, ghost in ipairs(ghosts) do if ghost.valid then ghost.destroy() end end
		for _, entity in ipairs(state._deconstruction_orders) do
			if entity.valid then entity.cancel_deconstruction(state.player.force, state.player) end
		end
		state._collected_ghosts = {}
		state._deconstruction_orders = {}
		if blocked then
			state.player.print({"mpp.msg_obstacle_route_failed"})
		elseif not success then
			log("Oil planning failed: "..tostring(result))
			state.player.print({"mpp.msg_oil_plan_failed"})
		end
	end
	return false
end

return layout
