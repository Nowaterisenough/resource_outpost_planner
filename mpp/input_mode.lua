local belt_planner = require("mpp.belt_planner")
local common = require("layouts.common")
local output_balancer = require("mpp.output_balancer")
local train_station = require("mpp.train_station")

local input_mode = {}
local changing = {}

local function get_player(data, player)
	if player then return player end
	if data.preview then return game.get_player(data.preview.player_index) end
	if data.last_state then return data.last_state.player end
	for index, candidate in pairs(storage.players or {}) do
		if candidate == data then return game.get_player(index) end
	end
end

local function cursor_mode(player)
	local stack = player and player.cursor_stack
	if not stack or not stack.valid_for_read then return end
	if stack.name == "resource-outpost-planner" then return "select" end
	if stack.name == "mpp-blueprint-belt-planner" or stack.name == "mpp-belt-planner" then return "output" end
end

function input_mode.output_specification(data, player)
	if data.choices.layout_choice == "oil" then return end
	if data.choices.output_station_choice and (data.output_station_count_invalid or not train_station.valid_choices(data.choices)) then return end
	if not data.choices.output_station_choice and data.choices.output_balance_choice and data.output_count_invalid then return end
	local draft = data.preview
	local spec = draft and draft.belt_specification or nil
	if not draft then
		spec = data.last_state and common.create_belt_planner_specification(data.last_state)
	end
	if spec and (not player or spec.surface == player.surface) then
		spec.station_choices=data.choices.output_station_choice and train_station.choices(data.choices) or nil
		spec.output_count=spec.station_choices and train_station.output_count(data.choices)
			or data.choices.output_balance_choice and output_balancer.output_count(spec,data.choices) or nil
		return spec
	end
end

function input_mode.update_gui(data)
	local ui = data.gui or {}
	local applying = data.preview and data.preview.applying
	for mode, button in pairs{select=ui.select_tool, output=ui.output_tool} do
		if button.valid then
			button.style = data.input_mode == mode and "mpp_tool_button_active" or "button"
			button.enabled = not applying and (mode == "select"
				or input_mode.output_specification(data, game.get_player(button.player_index)) ~= nil)
		end
	end
end

function input_mode.idle(data, player)
	player = get_player(data, player)
	data.input_mode = nil
	if player then
		changing[player.index] = true
		belt_planner.release_cursor(data, player)
		if cursor_mode(player) == "select" then player.clear_cursor() end
		changing[player.index] = nil
	end
	input_mode.update_gui(data)
end

function input_mode.select(data, player)
	changing[player.index] = true
	if not player.clear_cursor() then changing[player.index] = nil; return false end
	belt_planner.release_cursor(data, player)
	player.cursor_stack.set_stack("resource-outpost-planner")
	player.cursor_stack_temporary = true
	data.input_mode = "select"
	changing[player.index] = nil
	input_mode.update_gui(data)
	return true
end

function input_mode.output(data, player)
	local spec = input_mode.output_specification(data, player)
	if not spec or (data.preview and data.preview.applying) then return false end
	if not data.preview and data.choices.output_station_choice then
		if not input_mode.begin_output_preview or not input_mode.begin_output_preview(data,player) then return false end
		data.choices.belt_planner_choice=true
		spec=input_mode.output_specification(data,player)
	end
	if not data.preview then common.save_belt_specification(data.last_state) end
	changing[player.index] = true
	local blueprint,err=belt_planner.give_blueprint({player=player},spec)
	local given=blueprint~=nil
	if err then
		player.print(err)
		if data.preview and input_mode.invalidate_output then input_mode.invalidate_output(data,err) end
	end
	if given then data.input_mode = "output" end
	changing[player.index] = nil
	input_mode.update_gui(data)
	return given
end

function input_mode.reconcile(data, player)
	if changing[player.index] then return end
	data.input_mode = cursor_mode(player)
	if data.input_mode ~= "output" then data.belt_cursor_restore = nil end
	input_mode.update_gui(data)
end

return input_mode
