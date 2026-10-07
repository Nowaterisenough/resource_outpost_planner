require("mpp.global_extends")
local conf = require("configuration")
local compatibility = require("mpp.compatibility")
require("migration")
algorithm = require("algorithm")
local gui = require("gui.gui")
local grid_meta = require("mpp.grid_mt")
local bp_meta = require("mpp.blueprintmeta")
local render_util = require("mpp.render_util")
local mpp_util = require("mpp.mpp_util")
local task_runner = require("mpp.task_runner")
local preview = require("mpp.preview")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local EAST, NORTH, SOUTH, WEST, ROTATION = mpp_util.directions()
local floor = math.floor

---@class MppStorage
---@field players table<number, PlayerData>
---@field tasks State[]
---@field immediate_tasks TaskState[]
---@field version number

storage = storage --[[@as MppStorage]]

script.on_init(conf.initialize_storage)

---@param event EventData
function task_runner_handler(event)
	preview.tick()
	if #storage.immediate_tasks > 0 then
		local tasks = storage.immediate_tasks
		storage.immediate_tasks = {}
		for _, task in ipairs(tasks) do
			if not debugadapter then
				task_runner.belt_plan_task(task --[[@as BeltinatorState]])
			else
				local success
				success, tick_result = pcall(task_runner.belt_plan_task, task)
				if success == false then
					game.print(tick_result)
					tick_result = false
				end
			end
		end
	end
	
	if #storage.tasks > 0 then
		local layout_task = storage.tasks[1]
		task_runner.mining_patch_task(layout_task)
	end
	
	if #storage.tasks == 0 and #storage.immediate_tasks == 0 and not preview.has_pending() then
		return script.on_event(defines.events.on_tick, nil)
	end
end

local function select_preview(event,append)
	local player=game.get_player(event.player_index)
	if not player or event.item~="resource-outpost-planner" then return end
	for _,task in ipairs(storage.tasks) do
		if task.player==player and not task.preview_only then return end
	end
	if preview.select(event,append) then
		gui.show_interface(player)
		algorithm.on_gui_open(storage.players[player.index])
	end
end

script.on_event(defines.events.on_player_selected_area,function(event) select_preview(event,false) end)
script.on_event(defines.events.on_player_alt_selected_area,function(event) select_preview(event,true) end)

script.on_event(defines.events.on_player_alt_reverse_selected_area, function(event)
	---@cast event EventData.on_player_alt_reverse_selected_area
	if not debugadapter then return end

	local player = game.get_player(event.player_index)
	if not player then return end
	local cursor_stack = player.cursor_stack
	if not cursor_stack or not cursor_stack.valid or not cursor_stack.valid_for_read then return end
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name ~= "resource-outpost-planner" then return end

	---@type PlayerData
	local player_data = storage.players[event.player_index]

	local debugging_choice = player_data.choices.debugging_choice
	debugging_func = render_util[debugging_choice]

	if debugging_func then

		local res, error = pcall(
			debugging_func,
			player_data, event
		)

		if res == false then
			game.print(error)
		end
	else
		game.print("No valid debugging function selected")
	end

end)

script.on_event(defines.events.on_player_reverse_selected_area, function(event)
	if not debugadapter then return end

	local player = game.get_player(event.player_index)
	if not player then return end
	local cursor_stack = player.cursor_stack
	if not cursor_stack or not cursor_stack.valid or not cursor_stack.valid_for_read then return end
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name ~= "resource-outpost-planner" then return end

	rendering.clear("resource-outpost-planner")
end)

script.on_load(function()
	if storage.players then
		for _, ply in pairs(storage.players) do
			---@cast ply PlayerData
			if ply.blueprints then
				for _, bp in pairs(ply.blueprints.cache) do
					setmetatable(bp, bp_meta)
				end
			end
			if ply.last_state then
				if ply.last_state.grid then
					setmetatable(ply.last_state.grid, grid_meta)
				end
			end
		end
	end

	if storage.tasks and (#storage.tasks > 0 or preview.has_pending()) then
		script.on_event(defines.events.on_tick, task_runner_handler)
		for _, task in ipairs(storage.tasks) do
			---@type Layout
			local layout = algorithm.layouts[task.layout_choice]
			layout:on_load(task)
		end
	end
end)

local function cursor_stack_check(e)
	---@cast e EventData.on_player_cursor_stack_changed
	local player = game.get_player(e.player_index)
	if not player then return end
	---@type PlayerData
	local player_data = storage.players[e.player_index]
	if not player_data then return end
	local frame = player.gui.screen["mpp_settings_frame"]
	if player_data.preview then
		if player_data.preview.surface~=player.surface then preview.cancel(player_data)
		else gui.show_interface(player); return end
	end
	if player_data.blueprint_add_mode and frame and frame.visible then
		return
	end

	local cursor_stack = player.cursor_stack
	if (cursor_stack and
		cursor_stack.valid and
		cursor_stack.valid_for_read and
		cursor_stack.name == "resource-outpost-planner"
	) then
		gui.show_interface(player)
		algorithm.on_gui_open(player_data)
	else
		local duration = mpp_util.get_display_duration(e.player_index)
		if e.tick < player_data.tick_expires then
			player_data.tick_expires = e.tick + duration
		end
		gui.hide_interface(player)
		algorithm.on_gui_close(player_data)
		algorithm.clear_selection(player_data)
	end
end

script.on_event(defines.events.on_player_cursor_stack_changed, cursor_stack_check)

script.on_event(defines.events.on_player_changed_surface, cursor_stack_check)

script.on_event(defines.events.on_research_finished, function(event)
	---@cast event EventData.on_research_finished
	local effects = event.research.prototype.effects
	local qualities_to_unhide = List()
	for _, effect in pairs(effects) do
		---@cast effect TechnologyModifier
		if effect.type == "unlock-quality" then
			qualities_to_unhide:push(effect.quality --[[@as string]])
		end
	end
	
	if #qualities_to_unhide == 0 then return end
	
	conf.unhide_qualities_for_force(event.research.force, qualities_to_unhide)
	for player_index, player_data in pairs(storage.players) do
		gui.update_quality_sections(player_data)
		gui.update_oil_settings(game.get_player(player_index))
	end
end)

do
	local events = compatibility.get_se_events()
	for k, v in pairs(events) do
		script.on_event(v, cursor_stack_check)
	end
end

script.on_event(defines.events.on_built_entity, function(event)
	local ent = event.entity
	local tags = ent.tags
	if tags == nil or tags.mpp_belt_planner == nil then return end
	
	local position = ent.position
	local gx, gy = position.x, position.y
	local world_direction = ent.direction
	local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
	local surface = ent.surface
	
	ent.destroy()
	
	if tags.mpp_belt_planner ~= "main" then return end
	
	local belt_planner_stack = storage.players[event.player_index].belt_planner_stack
	
	if #belt_planner_stack == 0 then
		game.get_player(event.player_index).print({"mpp.msg_belt_planner_err_no_previous_state"})
		return
	end
	
	---@type BeltPlannerSpecification
	local spec = belt_planner_stack[#belt_planner_stack]
	
	local coords = spec.coords
	
	do
		if surface ~= spec.surface then
			return
		end
		
		local mid_x, mid_y = coords.gx + coords.w / 2, coords.gy + coords.h / 2
		if math.abs(mid_x - gx) > 100 or math.abs(mid_y - gy) > 100 then
			game.get_player(event.player_index).print({"mpp.msg_belt_planner_err_too_far"})
			return
		end
	end
	
	local conv = coord_convert[spec.direction_choice]
	-- local rot = mpp_util.bp_direction[state.direction_choice][direction]
	-- local bump = state.direction_choice == "north" or state.direction_choice EAST
	local belt_direction = mpp_util.clamped_rotation(((-defines.direction[spec.direction_choice]) % ROTATION)-EAST, world_direction)
	local x, y = gx - coords.gx - .5, gy - coords.gy - .5
	local tx, ty = conv(x, y, coords.w, coords.h)
	tx, ty = floor(tx + 1), floor(ty + 1)
	
	---@type BeltinatorState
	local beltinator_state = {
		avoid_obstacles_choice = storage.players[event.player_index].choices.avoid_obstacles_choice,
		type = "belt_planner",
		surface = player.surface,
		player = player,
		coords = spec.coords,
		direction_choice = spec.direction_choice,
		belt_x = tx,
		belt_y = ty,
		belt_specification = spec,
		belt_choice = spec.belt_choice,
		belt_direction = belt_direction,
		x_start = spec[1].x_start,
	}
	
	table.insert(storage.immediate_tasks, beltinator_state)
	script.on_event(defines.events.on_tick, task_runner_handler)
	
end, {{filter = "ghost_type", type = "transport-belt"}})

---@param player_data PlayerData
---@param direction DirectionString
function rotate_direction(player_data, direction)
	
	player_data.choices.direction_choice = direction
	gui.update_direction_section(player_data)
	preview.request(player_data)
end

script.on_event("resource-outpost-planner-keybind-rotate", function(e)
	---@cast e EventData.CustomInputEvent
	if not e.selected_prototype or e.selected_prototype.name ~= "resource-outpost-planner" then return end
	local player_index = e.player_index
	local ply = storage.players[player_index] --[[@as PlayerData]]
	local current_direction = ply.choices.direction_choice
	
	if current_direction == "east" then
		rotate_direction(ply, "south")
	elseif current_direction == "south" then
		rotate_direction(ply, "west")
	elseif current_direction == "west" then
		rotate_direction(ply, "north")
	else
		rotate_direction(ply, "east")
	end
	game.get_player(player_index).play_sound{path="utility/rotated_medium"}
end)

script.on_event("resource-outpost-planner-keybind-rotate-reversed", function(e)
	---@cast e EventData.CustomInputEvent
	if not e.selected_prototype or e.selected_prototype.name ~= "resource-outpost-planner" then return end
	
	local player_index = e.player_index
	local ply = storage.players[player_index] --[[@as PlayerData]]
	local current_direction = ply.choices.direction_choice
	
	if current_direction == "east" then
		rotate_direction(ply, "north")
	elseif current_direction == "south" then
		rotate_direction(ply, "east")
	elseif current_direction == "west" then
		rotate_direction(ply, "south")
	else
		rotate_direction(ply, "west")
	end
	game.get_player(player_index).play_sound{path="utility/rotated_medium"}
end)
