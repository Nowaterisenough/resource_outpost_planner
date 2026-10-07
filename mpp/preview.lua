local obstacles = require("mpp.obstacles")

local preview = {}

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
	local ui,draft=data.gui,data.preview
	if not ui.preview_apply or not ui.preview_apply.valid then return end
	ui.preview_apply.enabled=draft~=nil and draft.ready==true and not draft.applying
	ui.preview_cancel.enabled=draft~=nil and not draft.applying
	ui.undo_button.enabled=draft~=nil or (data.last_state and #data.last_state._collected_ghosts>0) or false
	if not draft then ui.preview_status.caption={"mpp.preview_select"}
	elseif draft.applying then ui.preview_status.caption={"mpp.preview_applying"}
	elseif draft.error then ui.preview_status.caption={"",{"mpp.preview_failed"},"\n",draft.error}
	elseif not draft.ready then ui.preview_status.caption={"mpp.preview_updating"}
	else ui.preview_status.caption={"mpp.preview_ready",draft.resource_count,draft.entity_count,draft.tile_count} end
end

function preview.cancel(data,force)
	if not data then return true end
	if data.preview and data.preview.applying and not force then return false end
	stop_tasks(data.preview and data.preview.player_index or -1)
	if data.preview then destroy(data.preview.renderings) end
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
	destroy(draft.renderings); draft.renderings={}
	preview.update_gui(data)
end

function preview.request(data)
	local draft=data.preview
	if not draft or draft.applying then return end
	stop_tasks(draft.player_index)
	draft.revision=draft.revision+1
	draft.ready=false
	draft.error=nil
	draft.refresh_at=game.tick+8
	preview.update_gui(data)
	script.on_event(defines.events.on_tick,task_runner_handler)
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
	preview.cancel(data)
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
				})
				if not ok then log("Preview validation failed: "..tostring(state)); state=nil; err={"mpp.preview_failed"} end
			end
			if state then storage.tasks[#storage.tasks+1]=state
			else
				destroy(draft.renderings); draft.renderings={}
				draft.error=err or {"mpp.msg_miner_err_0"}
				preview.update_gui(data)
			end
		end
	end
end

local direction_names={[defines.direction.north]="north",[defines.direction.east]="east",
	[defines.direction.south]="south",[defines.direction.west]="west"}

local function render(data,draft)
	local player=game.get_player(draft.player_index)
	local objects={}
	local function add(object) objects[#objects+1]=object end
	for _,spec in ipairs(draft.specs) do
		local pos=spec.position
		local x,y=pos.x or pos[1],pos.y or pos[2]
		if spec.name=="tile-ghost" then
			add(rendering.draw_rectangle{surface=draft.surface,players={player},
				left_top={x,y},right_bottom={x+1,y+1},filled=true,draw_on_ground=true,color={0.42,0.63,0.8,0.24}})
		else
			local box=obstacles.entity_box(spec.inner_name,{x=x,y=y},spec.direction)
			add(rendering.draw_rectangle{surface=draft.surface,players={player},
				left_top=box.left_top,right_bottom=box.right_bottom,filled=false,draw_on_ground=true,
				width=1,color={0.42,0.63,0.8,0.8}})
			local sprite="mpp-preview-"..spec.inner_name.."-"..(direction_names[spec.direction] or "north")
			local sx,sy=1,1
			if helpers.is_valid_sprite_path(sprite.."-1") then
				for layer=1,16 do
					if not helpers.is_valid_sprite_path(sprite.."-"..layer) then break end
					add(rendering.draw_sprite{surface=draft.surface,players={player},sprite=sprite.."-"..layer,target={x,y},
						x_scale=spec.mirror and -1 or 1,y_scale=1,tint={0.55,0.75,0.95,0.55}})
				end
				sprite=nil
			else
				sprite="entity/"..spec.inner_name
				sx=(box.right_bottom.x-box.left_top.x)/2
				sy=(box.right_bottom.y-box.left_top.y)/2
			end
			if sprite and helpers.is_valid_sprite_path(sprite) then
				add(rendering.draw_sprite{surface=draft.surface,players={player},sprite=sprite,target={x,y},
					x_scale=spec.mirror and -sx or sx,y_scale=sy,tint={0.55,0.75,0.95,0.55}})
			end
		end
	end
	destroy(draft.renderings)
	draft.renderings=objects
end

function preview.complete(state)
	local data=storage.players[state.player.index]
	local draft=data and data.preview
	if not draft or draft.revision~=state.preview_revision or draft.applying then return end
	draft.error=state.preview_error
	draft.specs=state._preview_specs
	draft.resource_count=#state.resources
	draft.entity_count,draft.tile_count=0,0
	for _,spec in ipairs(draft.specs) do
		if spec.name=="tile-ghost" then draft.tile_count=draft.tile_count+1
		else draft.entity_count=draft.entity_count+1 end
	end
	if #draft.specs==0 and not draft.error then draft.error={"mpp.preview_empty"} end
	draft.ready=not draft.error
	if draft.ready then render(data,draft)
	else destroy(draft.renderings); draft.renderings={} end
	preview.update_gui(data)
end

function preview.apply(data)
	local draft=data.preview
	if not draft or not draft.ready or draft.applying or draft.refresh_at then return false end
	local player=game.get_player(draft.player_index)
	if not player or player.surface~=draft.surface then return false end
	local resources={}
	for _,entity in ipairs(draft.resources) do if entity.valid then resources[#resources+1]=entity end end
	if #resources~=#draft.resources then preview.request(data); return false end
	-- Revalidate the current world before committing; dry runs never consume undo or construction orders.
	algorithm.clear_selection(data)
	local state,err=algorithm.on_player_selected_area{player_index=draft.player_index,entities=resources,surface=draft.surface}
	if not state then draft.ready=false; draft.error=err; preview.update_gui(data); return false end
	state._from_preview=true
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
