local current_version = require("mpp.version")
local conf = require("configuration")
local enums = require("mpp.enums")
local preview = require("mpp.preview")
local belt_load = require("mpp.belt_load")
local equipment_fields={miner_choice="entity",belt_choice="entity",pole_choice="entity",pipe_choice="entity",
	logistics_choice="entity",beacon_choice="entity",ore_filter_resource_choice="entity",module_choice="item",beacon_module_choice="item"}

local function missing(kind,name)
	return type(name)=="string" and name~="none" and name~="zero_gap" and not prototypes[kind][name]
end

local function valid_blueprint(cache)
	for _,entity in ipairs(cache.entities or {}) do
		if missing("entity",entity.name) or missing("quality",entity.quality) then return false end
	end
	return true
end

local function valid_plan(state)
	if not state or not state.surface or not state.surface.valid or not state.player or not state.player.valid then return false end
	for key,kind in pairs(equipment_fields) do if missing(kind,state[key]) then return false end end
	for key,value in pairs(state) do
		if type(key)=="string" and key:match("_quality_choice$") and missing("quality",value) then return false end
	end
	for _,r in ipairs(state.resources or {}) do if not r.valid then return false end end
	if state.cache and not valid_blueprint(state.cache) then return false end
	for _,spec in ipairs(state.ore_filter_reserved or state._ore_filter_reserved or {}) do
		if missing("entity",spec.name) then return false end
	end
	if state.belt and missing("entity",state.belt.related_underground_belt) then return false end
	for key,list in pairs(state) do
		if type(key)=="string" and key:match("^builder_") and type(list)=="table" then
			for _,s in ipairs(list) do
				if missing("entity",s.inner_name or s.name) or missing("quality",s.quality) then return false end
			end
		end
	end
	if state.oil_settings then
		for key,value in pairs(state.oil_settings.choices) do
			local kind=key:match("_quality_choice$") and "quality" or key:match("module_choice$") and "item" or "entity"
			if missing(kind,value) then return false end
		end
	end
	return true
end

local function retire_invalid_tasks(tasks)
	for i=#tasks,1,-1 do
		local state=tasks[i]
		if not valid_plan(state) then
			-- A belt extension shares its owner's ghost list. Only a new mine owns
			-- the complete list and can roll back a partially applied task here.
			if state.type=="layout" and not state.preview_only and state.player and state.player.valid then
				local data=storage.players[state.player.index]
				for _,ghost in ipairs(state._collected_ghosts or {}) do
					if ghost.valid and (ghost.type=="entity-ghost" or ghost.type=="tile-ghost") then ghost.destroy() end
				end
				for _,e in ipairs(state._deconstruction_orders or {}) do
					if e.valid then e.cancel_deconstruction(state.player.force) end
				end
				if data and state._from_preview then data.last_state=state._undo_state end
			end
			preview.dispose_task(state)
			table.remove(tasks,i)
		end
	end
end

local function repair_player(data)
	for key,kind in pairs(equipment_fields) do
		if missing(kind,data.choices[key]) then data.choices[key]=conf.default_config.choices[key] end
	end
	if missing("entity",data.choices.space_belt_choice) then data.choices.space_belt_choice=data.choices.belt_choice end
	local chosen=data.choices.blueprint_choice
	if chosen then
		local cached=chosen.valid and chosen.valid_for_read and data.blueprints.cache[chosen.item_number]
		if not cached or not valid_blueprint(cached) then
			data.choices.blueprint_choice=nil
		end
	end
	if data.last_state then
		local last=data.last_state
		last.resource_count=last.resource_count or #(last.resources or {})
		last.resources=nil
		if not valid_plan(last) then
			-- Undo only needs live handles. Obsolete output geometry cannot be edited.
			last.belts,last.belt,last.miner=nil,nil,nil
			require("mpp.belt_planner").clear_belt_planner_stack(data)
		end
	end
	for i=#(data.belt_planner_stack or {}),1,-1 do
		if not valid_plan(data.belt_planner_stack[i]) then table.remove(data.belt_planner_stack,i) end
	end
end

-- resetting a GUI manually from console
-- /c __resource-outpost-planner__ game.player.gui.screen.mpp_settings_frame.destroy()

---@param player LuaPlayer
local function reset_gui(player, player_data)
	preview.cancel(player_data,true)
	local root = player.gui.left["mpp_settings_frame"] or player.gui.screen["mpp_settings_frame"]
	if root then
		root.destroy()
	end
	local cursor_stack = player.cursor_stack
	if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read and cursor_stack.name == "resource-outpost-planner" then
		cursor_stack.clear()
	end
	
	player_data.gui = {
		section = {},
		tables = {},
		selections = {},
		advanced_settings = nil,
		filtering_settings = nil,
		blueprint_add_button = nil,
		blueprint_add_section = nil,
		blueprint_receptacle = nil,
		layout_dropdown = nil,
		quality_toggle = nil,
	}
end

script.on_configuration_changed(function(config_changed_data)
	local version = storage.version or 0
	storage.version = current_version
	local game_players = game.players
	
	if version < 010700 then -- do a clean slate before 1.7
		rendering.clear("resource-outpost-planner")
		
		if storage.players then
			for player_index, data in pairs(storage.players) do
				local mpp_root = game_players[player_index].gui.screen.mpp_settings_frame
				if mpp_root and mpp_root.valid then
					mpp_root.destroy()
				end
				
				---@cast data PlayerData
				data.last_state = nil
				local bp_inventory = data.blueprint_items
				if bp_inventory and bp_inventory.valid then
					bp_inventory.destroy()
				end
			end
		end
		
		local scr_inv = storage.script_inventory
		if scr_inv and scr_inv.valid then
			scr_inv.destroy()
		end
		
		local t = List()
		for k, _ in pairs(storage) do
			t:push(k)
		end
		for _, key in ipairs(t) do
			storage[key] = nil
		end
		
		conf.initialize_storage()
	end
	
	if version < 010706 then
		if storage.tasks and #storage.tasks > 1 then
			for k, state in pairs(storage.tasks) do
				if state._preview_rectangle and state._preview_rectangle.valid then
					state._preview_rectangle.destroy()
				end
			end
			storage.tasks = {}
		end
	end
	
	retire_invalid_tasks(storage.tasks or {})
	retire_invalid_tasks(storage.immediate_tasks or {})
	for _,data in pairs(storage.players or {}) do repair_player(data) end
	for _, state in pairs(storage.tasks or {}) do
		conf.migrate_statistics_choice(state)
		conf.migrate_terrain_choices(state)
		belt_load.migrate_choices(state)
	end

	if config_changed_data.mod_changes["resource-outpost-planner"] and version < current_version then
		storage.tasks = storage.tasks or {}
		conf.initialize_deconstruction_filter()
		for player_index, data in pairs(storage.players) do
			---@cast data PlayerData
			local player = game_players[player_index]
			reset_gui(player, data)
			--conf.initialize_global(player_index)
			conf.update_player_data(player_index)
			conf.update_player_quality_data(player_index)
		end
	else
		for player_index, data in pairs(storage.players) do
			reset_gui(game_players[player_index], data)
			conf.update_player_quality_data(player_index)
		end
	end
	
end)
