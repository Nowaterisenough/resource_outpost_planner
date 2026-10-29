-- Advisory only: recipe availability never changes terrain or placement choices.
local terrain = require("mpp.terrain")
local warnings = {}
local recipes_by_item

local function recipe_index()
	if recipes_by_item then return recipes_by_item end
	recipes_by_item = {}
	for name, recipe in pairs(prototypes.recipe) do
		-- Generated recycling recipes are enabled even before the material's
		-- technology. Recovering imported items is not a crafting unlock.
		local recycling = false
		for _, category in pairs(recipe.categories) do
			if category:find("recycling", 1, true) then recycling = true; break end
		end
		if not recycling then
			for _, product in pairs(recipe.products) do
				if product.type == "item" then
					local recipes = recipes_by_item[product.name] or {}
					recipes_by_item[product.name] = recipes
					recipes[#recipes + 1] = name
				end
			end
		end
	end
	return recipes_by_item
end

local function locked_materials(force, cover)
	local items = cover.items_to_place_this or {}
	if #items == 0 then return end
	local recipes = recipe_index()
	-- Modded tiles can accept several items or have alternative recipes.
	for _, item in pairs(items) do
		for _, name in ipairs(recipes[item.name] or {}) do
			if force.recipes[name] and force.recipes[name].enabled then return end
		end
	end
	local names = {""}
	for _, item in pairs(items) do
		if #names > 1 then names[#names + 1] = " / " end
		names[#names + 1] = {"", "[item="..item.name.."] ", prototypes.item[item.name].localised_name}
	end
	return names
end

function warnings.for_player(player, choices)
	local covers = {}
	local function add(name)
		local proto = prototypes.tile[name]
		if not proto then return end
		local tile = {name=name, prototype=proto}
		if not terrain.blocked_tile(tile) then return end
		local cover = terrain.cover_tile(tile, choices)
		if not cover then return end
		local key = terrain.fill_setting(tile)
		covers[key] = covers[key] or {}
		covers[key][cover.name] = cover
	end
	-- Read generator definitions, not map tiles; opening settings must not scan
	-- generated chunks. This also follows modded planets' native cover tiles.
	local surface = player.surface
	local settings = surface.map_gen_settings.autoplace_settings
	for name in pairs(settings and settings.tile and settings.tile.settings or {}) do add(name) end
	if not covers.fill_water_choice then
		add(surface.planet and surface.planet.name == "aquilo" and "ammoniacal-ocean" or "water")
	end
	if not covers.fill_lava_choice then add("lava") end
	if not covers.fill_oil_ocean_choice then add("oil-ocean-shallow") end
	local result = {}
	for key, tiles in pairs(covers) do
		local ordered = {}; for name in pairs(tiles) do ordered[#ordered + 1] = name end
		table.sort(ordered)
		local missing = {""}
		for _, name in ipairs(ordered) do
			local materials = locked_materials(player.force, tiles[name])
			if materials then
				if #missing > 1 then missing[#missing + 1] = ", " end
				missing[#missing + 1] = materials
			end
		end
		if #missing > 1 then result[key] = {"mpp.fill_research_warning", missing} end
	end
	return result
end

return warnings
