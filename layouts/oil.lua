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
	local ignored = obstacles.ignored_entities(state)
	for _, resource in ipairs(state.resources) do
		local choice = data.choices[resource.prototype.resource_category.."_pumpjack_choice"]
		if not choice or not prototypes.entity[choice] then return false, {"mpp-oil.msg_no_valid_pumpjacks"} end
		local box = obstacles.entity_box(choice, resource.position, defines.direction.north)
		if not obstacles.active(state) or not obstacles.blocked_box(obstacles.collect(state.surface,box,ignored,state),box) then
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
		remove_entities_choice = state.remove_entities_choice,
	}
end

function layout:start(state)
	if state._previous_state and not state.preview_only then
		for _, ghost in pairs(state._previous_state._collected_ghosts or {}) do
			if ghost.valid then ghost.order_deconstruction(state.player.force, state.player) end
		end
	end
	state._deconstruction_orders = {}
	state.oil_force=state.player.force
	return "plan_oil"
end

function layout:rollback(state)
	for _,ghost in ipairs(state._collected_ghosts) do if ghost.valid then ghost.destroy() end end
	for _,entity in ipairs(state._deconstruction_orders) do
		if entity.valid and state.oil_force.valid then entity.cancel_deconstruction(state.oil_force) end
	end
	state._collected_ghosts = {}
	state._deconstruction_orders = {}
end

function layout:plan_oil(state)
	local ghosts = state._collected_ghosts
	local blocked = false
	local success, result = pcall(planner.step, state, {
		message = function(message)
			if type(message)=="table" and message[1]~="mpp-oil.msg_count_patches" then state.oil_message=message end
			if not state.preview_only then state.player.print(message) end
		end,
		on_preview = function(spec) return builder.record_preview(state,spec) end,
		module_plan = function(proto,quality) return config.module_plan(state.oil_settings,proto,quality) end,
		on_created = function(ghost)
			if ghost and ghost.valid then ghosts[#ghosts + 1] = ghost end
		end,
		on_blocked = function() blocked = true end,
		on_deconstruction = function(entity)
			if not entity.to_be_deconstructed(state.player.force) then
				state._deconstruction_orders[#state._deconstruction_orders + 1] = entity
			end
		end,
	})
	if success and result==nil and not blocked then return true end
	state.oil_job=nil
	if not success or not result or blocked then
		state.preview_error = blocked and {"mpp.msg_obstacle_route_failed"} or state.oil_message or {"mpp.preview_oil_failed"}
		if state.preview_only then
			state._preview_specs = {}
			if not success then log("Oil preview failed: "..tostring(result)) end
			return false
		end
		self:rollback(state)
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
