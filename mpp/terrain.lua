local terrain = {}

function terrain.avoid_cliffs(choices)
	if choices.cliff_mode_choice then return choices.cliff_mode_choice == "avoid" end
	return choices.avoid_cliffs_choice == true or choices.avoid_obstacles_choice == true
end

local tile_choices = {"fill_water_choice", "fill_lava_choice", "fill_oil_ocean_choice", "fill_other_choice"}
terrain.tile_choices = tile_choices

function terrain.fill_setting(tile)
	local name, layers = tile.name, tile.prototype.collision_mask.layers
	return (layers.lava_tile or name:find("lava", 1, true)) and "fill_lava_choice"
		or (name:find("oil-ocean", 1, true) or name:find("lightning", 1, true)) and "fill_oil_ocean_choice"
		or layers.water_tile and "fill_water_choice" or "fill_other_choice"
end

function terrain.avoid_tiles(choices, tile)
	if tile then
		local setting = terrain.fill_setting(tile)
		if choices[setting] ~= nil then return choices[setting] ~= true end
	else
		local independent = false
		for _, setting in ipairs(tile_choices) do
			if choices[setting] == true then return false end
			if choices[setting] ~= nil then independent = true end
		end
		if independent then return true end
	end
	if choices.terrain_mode_choice then return choices.terrain_mode_choice == "avoid" end
	return choices.avoid_water_choice == true or choices.landfill_choice == true or choices.avoid_obstacles_choice == true
end

function terrain.retain_entities(choices, entity)
	if entity then
		local proto = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
		local kind = proto and proto.type or entity.type
		local setting = kind == "tree" and "remove_trees_choice"
			or kind == "simple-entity" and "remove_rocks_choice" or "remove_entities_choice"
		if choices[setting] ~= nil then return choices[setting] ~= true end
	end
	if choices.remove_entities_choice ~= nil then return not choices.remove_entities_choice end
	return choices.deconstruction_choice == true or choices.avoid_obstacles_choice == true
end

function terrain.blocked_tile(tile)
	local layers = tile.prototype.collision_mask.layers
	return layers.water_tile or layers.lava_tile or layers.out_of_map or layers.empty_space
		or tile.name == "se-space" or tile.name:find("lava", 1, true) ~= nil
		or (not layers.ground_tile and (layers.object or tile.prototype.default_cover_tile ~= nil))
end

function terrain.cover_tile(tile, choices)
	local layers = tile.prototype.collision_mask.layers
	if tile.name == "se-space" then return prototypes.tile[choices.space_landfill_choice] end
	if tile.name == "out-of-map" or layers.out_of_map or layers.empty_space then return nil end
	return tile.prototype.default_cover_tile
end

function terrain.blocks_tile(tile, choices)
	return terrain.blocked_tile(tile) and (terrain.avoid_tiles(choices, tile) or not terrain.cover_tile(tile, choices))
end

function terrain.blocks_entity(entity, choices)
	local kind = entity.type == "entity-ghost" and entity.ghost_prototype.type or entity.type
	if kind == "cliff" then return terrain.avoid_cliffs(choices) end
	-- Native Force apply clears natural obstacles. Its validation replan must
	-- allow the same trees/rocks inside the mine, including pipe corridors.
	if choices._force_build_mode and (kind == "tree" or kind == "simple-entity") then return false end
	return terrain.retain_entities(choices, entity)
end

local ignored = {resource=true, character=true, unit=true, corpse=true, ["item-entity"]=true, ["tile-ghost"]=true}

function terrain.deconstruct(state, area)
	if state.preview_only then return end
	local player = state.player
	state._deconstruction_orders = state._deconstruction_orders or {}
	-- Rails and rolling stock share space; demolition would instantly remove our own rail ghosts.
	local collected=state._collected_ghosts or {}
	local owned=state._owned_ghost_units
	if not owned or state._owned_ghost_list~=collected or #collected<(state._owned_ghost_scan_length or 0) then
		owned={};state._owned_ghost_units=owned
		state._owned_ghost_list=collected;state._owned_ghost_scan_length=0
	end
	for i=(state._owned_ghost_scan_length or 0)+1,#collected do
		local ghost=collected[i]
		if ghost.valid and ghost.type=="entity-ghost" and ghost.unit_number then owned[ghost.unit_number]=true end
	end
	state._owned_ghost_scan_length=#collected
	for _, entity in pairs(state.surface.find_entities_filtered{area=area, force={player.force, "neutral"}}) do
		if entity.valid and not owned[entity.unit_number] and not ignored[entity.type] and not terrain.blocks_entity(entity, state) then
			local proto = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
			local layers = proto.collision_mask.layers
			if entity.type == "cliff" or layers.object or layers.player or layers.train then
				if not entity.to_be_deconstructed(player.force) then
					state._deconstruction_orders[#state._deconstruction_orders + 1] = entity
					entity.order_deconstruction(player.force, player)
				end
			end
		end
	end
end

return terrain
