local mpp_util = require("mpp.mpp_util")
local belt_planner = require("mpp.belt_planner")
local preview = require("mpp.preview")

local task_runner = {}

function task_runner.mining_patch_task(state)
	local layout = algorithm.layouts[state.layout_choice]

	local last_callback = state._callback
	---@type TickResult
	local tick_result

	if state.preview_only then
		local success
		success,tick_result=pcall(layout.tick,layout,state)
		if not success then
			log("Planner preview failed: "..tostring(tick_result))
			state.preview_error={"mpp.preview_failed"}
			tick_result=false
		end
	elseif not debugadapter then
		tick_result = layout:tick(state)
	else
		local success
		success, tick_result = pcall(layout.tick, layout, state)
		if success == false then
			game.print(tick_result)
			tick_result = false
		end
	end

	if last_callback == tick_result then
		if debugadapter then
			table.remove(storage.tasks, 1)
		else
			error("Layout "..state.layout_choice.." step "..tostring(tick_result).." called itself again")
		end
	elseif tick_result == nil then
		if debugadapter then
			game.print(("Callback for layout %s after call %s has no result"):format(state.layout_choice, state._callback))
			table.remove(storage.tasks, 1)

			---@type PlayerData
			local player_data = storage.players[state.player.index]
			player_data.last_state = nil
			if state._preview_rectangle and state._preview_rectangle.valid then
				state._preview_rectangle.destroy()
			end
			mpp_util.update_undo_button(player_data)
		else
			error("Layout "..state.layout_choice.." missing a callback name")
		end
	elseif tick_result == false then
		if state.preview_only then
			preview.dispose_task(state)
			preview.complete(state)
			table.remove(storage.tasks,1)
			return
		end
		if state._from_preview and state.preview_error then
			local data=storage.players[state.player.index]
			preview.dispose_task(state)
			table.remove(storage.tasks,1)
			data.last_state=state._undo_state
			data.preview.applying=false
			preview.invalidate(data,state.preview_error)
			return
		end
		local player = state.player
		if state._obstacle_skipped and state._obstacle_skipped > 0 then
			player.print({"mpp.msg_obstacle_skipped",state._obstacle_skipped})
		end
		if state.blueprint then state.blueprint.clear() end
		if state.blueprint_inventory then state.blueprint_inventory.destroy() end
		if state._preview_rectangle and state._preview_rectangle.valid then
			state._preview_rectangle.destroy()
		end
		
		---@type PlayerData
		local player_data = storage.players[player.index]
		state._previous_state = nil
		state._undo_state = nil
		player_data.tick_expires = math.huge
		if debugadapter then
			player_data.last_state = state
		else
			player_data.last_state = {
				type = state.type,
				player = state.player,
				surface = state.surface,
				resources = state.resources,
				coords = state.coords,
				layout_choice = state.layout_choice,
				direction_choice = state.direction_choice,
				belts = state.belts,
				belt_choice = state.belt_choice,
				belt_quality_choice = state.belt_quality_choice,
				belt_planner_belts = state.belt_planner_belts,
				_preview_rectangle = state._preview_rectangle,
				_collected_ghosts = state._collected_ghosts,
				_deconstruction_orders = state._deconstruction_orders,
				avoid_obstacles_choice = state.avoid_obstacles_choice,
				avoid_cliffs_choice = state.avoid_cliffs_choice,
				avoid_water_choice = state.avoid_water_choice,
				cliff_mode_choice = state.cliff_mode_choice,
				terrain_mode_choice = state.terrain_mode_choice,
				deconstruction_choice = state.deconstruction_choice,
				_render_objects = state._render_objects,
				_lane_info_rendering = state._lane_info_rendering,
			}
		end

		state.player.play_sound{path="utility/build_blueprint_large"}
		table.remove(storage.tasks, 1)
		mpp_util.update_undo_button(player_data)
		if state._from_preview then preview.applied(state) end
	elseif tick_result ~= true then
		state._callback = tick_result
	end
end

---@param state BeltinatorState
function task_runner.belt_plan_task(state)
	belt_planner.layout(state)
end

return task_runner
