local preview_renderer = require("mpp.preview_renderer")
local belt_planner = require("mpp.belt_planner")
local common = require("layouts.common")
local diagnostics = require("mpp.preview_diagnostics")
local input_mode = require("mpp.input_mode")

local preview = {}
local render

local function destroy(objects)
	for _, object in pairs(objects or {}) do if object.valid then object.destroy() end end
end

function preview.dispose_task(state)
	if state.blueprint and state.blueprint.valid_for_read then state.blueprint.clear() end
	if state.blueprint_inventory and state.blueprint_inventory.valid then state.blueprint_inventory.destroy() end
	if state._preview_rectangle and state._preview_rectangle.valid then state._preview_rectangle.destroy() end
	destroy(state._render_objects)
end

local function stop_tasks(player_index)
	for index=#storage.tasks,1,-1 do
		local state=storage.tasks[index]
		if state.preview_only and state.player.index==player_index then
			preview.dispose_task(state)
			table.remove(storage.tasks,index)
		end
	end
end

function preview.update_gui(data)
	input_mode.update_gui(data)
	local ui,draft=data.gui,data.preview
	if not ui.preview_apply or not ui.preview_apply.valid then return end
	ui.preview_apply.enabled=draft~=nil and draft.ready==true and not draft.applying
	ui.preview_cancel.enabled=draft~=nil and not draft.applying
	ui.undo_button.enabled=draft~=nil or (data.last_state and #data.last_state._collected_ghosts>0) or false
	ui.preview_apply.tooltip=draft and draft.error
		and {"",draft.error,"\n",{"mpp.preview_diagnostics_hint"}} or nil
end

function preview.cancel(data,force,keep_selection)
	if not data then return true end
	if data.preview and data.preview.applying and not force then return false end
	stop_tasks(data.preview and data.preview.player_index or -1)
	if data.preview then destroy(data.preview.renderings) end
	if not (keep_selection and data.input_mode == "select") then input_mode.idle(data) end
	data.preview=nil
	preview.update_gui(data)
	return true
end

function preview.invalidate(data,err)
	if not data.preview or data.preview.applying then return end
	local draft=data.preview
	stop_tasks(draft.player_index)
	draft.revision=draft.revision+1
	draft.refresh_at=nil
	draft.ready=false
	draft.error=err
	draft.specs=draft.specs or {}
	local pos=draft.belt_target and draft.belt_target.position or draft.specs[1] and draft.specs[1].position
	draft.issues=pos and {{position=pos,reason=err}} or diagnostics.resource_issues(draft.resources,err)
	render(data,draft)
	preview.update_gui(data)
end

function preview.request(data)
	local draft=data.preview
	if not draft or draft.applying then return end
	if not data.choices.belt_planner_choice then
		draft.belt_target=nil
		if data.input_mode == "output" then input_mode.idle(data) end
	end
	stop_tasks(draft.player_index)
	draft.revision=draft.revision+1
	draft.ready=false
	draft.error=nil
	draft.refresh_at=game.tick+8
	preview.update_gui(data)
	script.on_event(defines.events.on_tick,task_runner_handler)
end

function preview.give_belt_planner(data)
	local draft=data.preview
	if not draft or draft.applying then return false end
	data.choices.belt_planner_choice=true
	return input_mode.output(data, game.get_player(draft.player_index))
end

function preview.set_belt_target(data, target)
	local draft=data.preview
	if not draft or draft.applying or not draft.belt_specification then return false end
	draft.belt_target=target
	preview.request(data)
	return true
end

function preview.select(event,append)
	local data=storage.players[event.player_index]
	if data.preview and data.preview.applying then return false end
	local selected,seen={},{}
	local function add(entities)
		for _,entity in pairs(entities or {}) do
			if entity.valid and entity.type=="resource" and entity.surface==event.surface then
				local pos=entity.position
				local key=entity.name..":"..pos.x..","..pos.y
				if not seen[key] then selected[#selected+1]=entity; seen[key]=true end
			end
		end
	end
	if append and data.preview then add(data.preview.resources) else add(data.selection_collection) end
	add(event.entities)
	if #selected==0 then return false end
	preview.cancel(data,false,true)
	-- Remove our last unfinished plan before it can obstruct the new preview.
	algorithm.cleanup_last_state(data)
	algorithm.clear_selection(data)
	algorithm.select_resource_layout(data,selected)
	data.preview={player_index=event.player_index,surface=event.surface,resources=selected,revision=0,renderings={}}
	preview.request(data)
	return true
end

function preview.has_pending()
	for _,data in pairs(storage.players or {}) do
		if data.preview and data.preview.refresh_at then return true end
	end
	return false
end

function preview.tick()
	for _,data in pairs(storage.players) do
		local draft=data.preview
		if draft and draft.refresh_at and game.tick>=draft.refresh_at then
			draft.refresh_at=nil
			local resources={}
			for _,entity in pairs(draft.resources) do if entity.valid then resources[#resources+1]=entity end end
			draft.resources=resources
			local state,err
			if #resources>0 and draft.surface.valid then
				local ok
				ok,state,err=pcall(algorithm.on_player_selected_area,{
					player_index=draft.player_index,entities=resources,surface=draft.surface,
					preview_only=true,preview_revision=draft.revision,
					belt_target=data.choices.belt_planner_choice and draft.belt_target or nil,
				})
				if not ok then log("Preview validation failed: "..tostring(state)); state=nil; err={"mpp.preview_failed"} end
			end
			if state then storage.tasks[#storage.tasks+1]=state
			else
				draft.error=err or {"mpp.msg_miner_err_0"}
				draft.specs={}
				draft.issues=diagnostics.resource_issues(resources,draft.error)
				render(data,draft)
				preview.update_gui(data)
			end
		end
	end
end

render = function(data,draft)
	local objects=preview_renderer.render(draft,data.choices)
	destroy(draft.renderings)
	draft.renderings=objects
end

local function commit(data)
	local draft=data.preview
	local undo_state=data.last_state
	algorithm.clear_selection(data)
	local state,err=algorithm.on_player_selected_area{player_index=draft.player_index,entities=draft.resources,surface=draft.surface,
		belt_target=data.choices.belt_planner_choice and draft.belt_target or nil}
	if not state then
		draft.applying=false
		preview.invalidate(data,err)
		return false
	end
	state._from_preview=true
	state._undo_state=undo_state
	storage.tasks[#storage.tasks+1]=state
	return true
end

function preview.complete(state)
	local data=storage.players[state.player.index]
	local draft=data and data.preview
	if not draft or draft.revision~=state.preview_revision or (draft.applying and not state._apply_after_preview) then return end
	draft.error=state.preview_error
	local captured, diagnostic_error=pcall(diagnostics.capture,state)
	if not captured then
		log("Preview diagnostics failed: "..tostring(diagnostic_error))
		state._preview_issues=diagnostics.resource_issues(state.resources,state.preview_error)
	end
	draft.belt_specification=common.create_belt_planner_specification(state)
	draft.specs=state._preview_specs or {}
	draft.issues=state._preview_issues or {}
	draft.resource_count=#state.resources
	draft.beacon_summary=state.beacon_summary
	draft.entity_count,draft.tile_count=0,0
	for _,spec in ipairs(draft.specs) do
		if spec.name=="tile-ghost" then draft.tile_count=draft.tile_count+1
		else draft.entity_count=draft.entity_count+1 end
	end
	if #draft.specs==0 and not draft.error then draft.error={"mpp.preview_empty"} end
	if draft.error and #draft.specs==0 and #draft.issues==0 then
		draft.issues=diagnostics.resource_issues(draft.resources,draft.error)
	end
	draft.ready=not draft.error
	if state._apply_after_preview then
		if draft.ready then commit(data)
		else draft.applying=false end
	end
	render(data,draft)
	if draft.ready or (#draft.specs>0 and state.belts and state.belt) then
		state._render_objects=List()
		common.display_lane_filling(state)
		for _,object in pairs(state._render_objects) do draft.renderings[#draft.renderings+1]=object end
	end
	preview.update_gui(data)
	if data.input_mode == "output" then
		if draft.belt_specification then belt_planner.update_blueprint(state.player,draft.belt_specification)
		else input_mode.idle(data, state.player) end
	end
end

function preview.apply(data)
	local draft=data.preview
	if not draft or not draft.ready or draft.applying or draft.refresh_at then return false end
	local player=game.get_player(draft.player_index)
	if not player or player.surface~=draft.surface then return false end
	input_mode.idle(data, player)
	local resources={}
	for _,entity in ipairs(draft.resources) do if entity.valid then resources[#resources+1]=entity end end
	if #resources~=#draft.resources then preview.request(data); return false end
	-- Recheck the entire route before any construction or deconstruction begins.
	local state,err=algorithm.on_player_selected_area{player_index=draft.player_index,entities=resources,surface=draft.surface,
		preview_only=true,preview_revision=draft.revision,
		belt_target=data.choices.belt_planner_choice and draft.belt_target or nil}
	if not state then preview.invalidate(data,err); return false end
	state._apply_after_preview=true
	draft.applying=true
	storage.tasks[#storage.tasks+1]=state
	preview.update_gui(data)
	script.on_event(defines.events.on_tick,task_runner_handler)
	return true
end

function preview.applied(state)
	local data=storage.players[state.player.index]
	if data.preview then data.preview.applying=false; preview.cancel(data) end
end

return preview
