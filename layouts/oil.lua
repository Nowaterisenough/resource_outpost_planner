local base = require("layouts.base")
local config = require("oil.config")
local planner = require("oil.vendor.planner")
local obstacles = require("mpp.obstacles")
local builder = require("mpp.builder")
local diagnostics = require("mpp.preview_diagnostics")

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
	local safe, blocked = {}, {}
	for _, resource in ipairs(state.resources) do
		local choice = data.choices[resource.prototype.resource_category.."_pumpjack_choice"]
		if not choice or not prototypes.entity[choice] then return false, {"mpp-oil.msg_no_valid_pumpjacks"} end
		if obstacles.can_place(state, choice, resource.position, defines.direction.north) then
			safe[#safe+1] = resource
		else blocked[#blocked+1] = resource end
	end
	if #safe == 0 then return false, {"mpp.msg_no_safe_resources"} end
	state.resources = safe
	if state.preview_only and #blocked > 0 then
		state._preview_issues = diagnostics.resource_issues(blocked, {"mpp.msg_no_safe_resources"})
	end
	return true
end

function layout:initialize(state)
	local data = config.get(storage.players[state.player.index])
	state.oil_settings = {
		choices = table.deepcopy(data.choices),
		qualities = table.deepcopy(data.qualities),
		min_beacon_utility = data.min_beacon_utility,
		add_landfill = data.add_landfill,
		remove_existing = data.remove_existing,
		retain_entities = data.retain_entities,
		cliff_mode_choice = state.cliff_mode_choice,
		terrain_mode_choice = state.terrain_mode_choice,
		deconstruction_choice = state.deconstruction_choice,
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
	local obstruction_index = obstacles.get(state)
	local success, result = pcall(planner.Plan, state.player, state.oil_settings, state.resources, state.surface, {
		preview_only = state.preview_only,
		on_message = function(message) plan_message=message end,
		on_preview = function(spec) return builder.record_preview(state,spec) end,
		obstacles = obstruction_index,
		terrain_choices = state,
		module_plan = function(proto,quality) return config.module_plan(state.oil_settings,proto,quality) end,
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
