local enums = {}

---@type LuaEntityPrototype[]
local cached_miners = {}
---@type table<string, boolean>
local cached_resource_categories = {}

local solid_resources = {}
local miner_blacklist = {
	["se-core-miner-drill"] = true
}

function enums.get_default_miner()
	if script.active_mods["nullius"] then
		return "nullius-medium-miner-1"
	end
	return "electric-mining-drill"
end

local FMD_active = script.active_mods["Cursed-FMD"]

---Get mining drills and resource categories
---@return LuaEntityPrototype[], table
function enums.get_available_miners()
	enums.get_available_miners = function() return cached_miners, cached_resource_categories end

	local all_miners = prototypes.get_entity_filtered{{filter="type", type="mining-drill"}}
	local all_resources = prototypes.get_entity_filtered{{filter="type", type="resource"}}
	local solid_categories = {}
	for name, proto in pairs(all_resources) do
		local products = proto.mineable_properties.products or {}
		local solid = #products > 0 and proto.resource_category ~= "se-core-mining"
		for _, product in ipairs(products) do
			if product.type == "fluid" then solid = false; break end
		end
		if solid then
			solid_resources[name] = true
			solid_categories[proto.resource_category] = true
		end
	end

	for miner_name, miner_proto in pairs(all_miners) do
		local supported = false
		for category in pairs(miner_proto.resource_categories or {}) do
			if solid_categories[category] then supported = true; break end
		end
		if not supported then miner_blacklist[miner_name] = true end
		---@cast miner_proto LuaEntityPrototype
		local fluidboxes = miner_proto.fluidbox_prototypes
		for _, fluidbox in pairs(fluidboxes) do
			---@cast fluidbox LuaFluidBoxPrototype
			if fluidbox.production_type == "output" then
				miner_blacklist[miner_name] = true
			end
		end
	end

	local miners = {}
	local resource_categories = {}
	for name, proto in pairs(all_miners) do
		if FMD_active and string.find(name, "__") then goto continue_miner end
		if proto.hidden then goto continue_miner end
		if miner_blacklist[name] then goto continue_miner end
		--if not proto.resource_categories["basic-solid"] then goto continue_miner end
		for resource_category, bool in pairs(proto.resource_categories) do
			if solid_categories[resource_category] then resource_categories[resource_category] = bool end
		end

		miners[name] = proto

		::continue_miner::
	end

	cached_miners = miners
	cached_resource_categories = resource_categories
	--[[ {
		["basic-solid"] = true,
		["hard-resource"] = true,
	}]]
	return enums.get_available_miners()
end

function enums.is_solid_resource(name)
	return solid_resources[name] == true
end

enums.space_surfaces = {
	["asteroid-belt"] = true,
	["asteroid-field"] = true,
	["orbit"] = true,
	["anomaly"] = true,
}

return enums
