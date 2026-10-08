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
local belt_planner = require("mpp.belt_planner")
local input_mode = require("mpp.input_mode")
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
	belt_planner.restore_cursors()
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
	
	if #storage.tasks == 0 and #storage.immediate_tasks == 0 and not preview.has_pending()
		and not belt_planner.has_pending_cursor() then
		return script.on_event(defines.events.on_tick, nil)
	end
end

local function set_belt_target(player, surface, position, direction)
	local data=storage.players[player.index]
	if not data or (data.preview and data.preview.applying) then return end
	local target={position=position,direction=direction}
	if data.preview then
		if data.preview.surface==surface and data.choices.belt_planner_choice then
			preview.set_belt_target(data,target)
		end
		return
	end
	local spec=data.belt_planner_stack[#data.belt_planner_stack]
	if not spec then player.print({"mpp.msg_belt_planner_err_no_previous_state"}); return end
	if surface~=spec.surface then return end
	local choices=table.deepcopy(data.choices)
	choices._collected_ghosts=data.last_state and data.last_state._collected_ghosts
	local state,err=belt_planner.create_state(spec,target,choices)
	if not state then player.print(err); return end
	table.insert(storage.immediate_tasks,state)
	script.on_event(defines.events.on_tick,task_runner_handler)
end

script.on_event(defines.events.on_pre_build, function(event)
	local player = game.get_player(event.player_index)
	if not player then return end
	local target = belt_planner.take_cursor_target(player, event)
	if not target then return end
	script.on_event(defines.events.on_tick, task_runner_handler)
	set_belt_target(player, player.surface, target.position, target.direction)
end)

local function select_preview(event,append)
	local player=game.get_player(event.player_index)
	if not player then return end
	if event.item=="mpp-belt-planner" then
		local area=event.area
		set_belt_target(player,event.surface,
			{x=floor((area.left_top.x+area.right_bottom.x)/2)+0.5,y=floor((area.left_top.y+area.right_bottom.y)/2)+0.5},
			storage.players[player.index].belt_planner_direction or NORTH)
		return
	end
	if event.item~="resource-outpost-planner" then return end
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

	if storage.tasks and (#storage.tasks > 0 or #storage.immediate_tasks > 0 or preview.has_pending()
		or belt_planner.has_pending_cursor()) then
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
		if player_data.preview.surface~=player.surface then preview.cancel(player_data) end
	end
	input_mode.reconcile(player_data, player)
	if player_data.blueprint_add_mode and frame and frame.visible then
		return
	end

	if player_data.input_mode then
		gui.show_interface(player)
		algorithm.on_gui_open(player_data)
	end
end

script.on_event(defines.events.on_player_cursor_stack_changed, cursor_stack_check)

script.on_event(defines.events.on_player_changed_surface, cursor_stack_check)

local function toggle_interface(event)
	local player = game.get_player(event.player_index)
	local data = storage.players[event.player_index]
	if not player or not data then return end
	local frame = player.gui.screen.mpp_settings_frame
	if frame and frame.visible then
		gui.hide_interface(player)
		algorithm.on_gui_close(data)
	else
		input_mode.idle(data, player)
		gui.show_interface(player)
		algorithm.on_gui_open(data)
	end
end

script.on_event("resource-outpost-planner-keybind", toggle_interface)
script.on_event(defines.events.on_lua_shortcut, function(event)
	if event.prototype_name == "resource-outpost-planner-shortcut" then toggle_interface(event) end
end)

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
	end
end)

do
	local events = compatibility.get_se_events()
	for k, v in pairs(events) do
		script.on_event(v, cursor_stack_check)
	end
end

-- Fallback for tagged markers built by older saves or other scripts.
script.on_event(defines.events.on_built_entity, function(event)
	local entity=event.entity
	local tags=event.tags or entity.tags
	if not tags or not tags.mpp_belt_planner then return end
	local position,surface,direction=entity.position,entity.surface,entity.direction
	entity.destroy()
	if tags.mpp_belt_planner=="main" then
		local player=game.get_player(event.player_index)
		if player then set_belt_target(player,surface,position,direction) end
	end
end, {{filter = "ghost_type", type = "transport-belt"}})

---@param player_data PlayerData
---@param direction DirectionString
function rotate_direction(player_data, direction)
	
	player_data.choices.direction_choice = direction
	gui.update_direction_section(player_data)
	preview.request(player_data)
end

local function rotate_belt_target(event, reverse)
	local player = game.get_player(event.player_index)
	if player and belt_planner.rotate_cursor(player, event, reverse) then return true end
	if not event.selected_prototype or event.selected_prototype.name~="mpp-belt-planner" then return false end
	local data=storage.players[event.player_index]
	local direction=((data.belt_planner_direction or NORTH)+(reverse and -EAST or EAST))%ROTATION
	data.belt_planner_direction=direction
	if data.preview and data.preview.belt_target then
		preview.set_belt_target(data,{position=data.preview.belt_target.position,direction=direction})
	end
	game.get_player(event.player_index).play_sound{path="utility/rotated_medium"}
	return true
end

script.on_event("resource-outpost-planner-keybind-rotate", function(e)
	---@cast e EventData.CustomInputEvent
	if rotate_belt_target(e,false) then return end
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

script.on_event("resource-outpost-planner-keybind-flip-horizontal", function(e)
	local player = game.get_player(e.player_index)
	if player then belt_planner.flip_cursor(player, true) end
end)

script.on_event("resource-outpost-planner-keybind-flip-vertical", function(e)
	local player = game.get_player(e.player_index)
	if player then belt_planner.flip_cursor(player, false) end
end)

script.on_event("resource-outpost-planner-keybind-rotate-reversed", function(e)
	---@cast e EventData.CustomInputEvent
	if rotate_belt_target(e,true) then return end
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
