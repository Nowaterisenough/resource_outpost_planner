local common = require("oil.vendor.common")
local blacklist = require("mpp.blacklist")

local config = {}
local cached_sections
local fluid_resources = {}

local function usable(proto)
	return not proto.hidden and not blacklist[proto.name]
		and proto.has_flag("player-creation") and not proto.has_flag("not-blueprintable")
end

local function sort_entities(values)
	table.sort(values, function(a, b)
		return a.order == b.order and a.name < b.name or a.order < b.order
	end)
end

function config.get_sections()
	if cached_sections then return cached_sections end
	local categories = {}
	for name, proto in pairs(prototypes.get_entity_filtered{{filter="type", type="resource"}}) do
		for _, product in pairs(proto.mineable_properties.products or {}) do
			if product.type == "fluid" then
				fluid_resources[name] = true
				local category = proto.resource_category
				categories[category] = categories[category] or {}
				categories[category][#categories[category] + 1] = proto
				break
			end
		end
	end

	local extractors = {}
	for _, proto in pairs(prototypes.get_entity_filtered{{filter="type", type="mining-drill"}}) do
		if usable(proto) then
			local outputs = {}
			for _, box in pairs(proto.fluidbox_prototypes) do
				if box.production_type == "output" then outputs[#outputs + 1] = box end
			end
			if #outputs == 1 and #outputs[1].pipe_connections == 1 then
				for category in pairs(proto.resource_categories or {}) do
					if categories[category] then
						extractors[category] = extractors[category] or {}
						extractors[category][#extractors[category] + 1] = proto
					end
				end
			end
		end
	end

	cached_sections = {}
	local category_names = {}
	for category in pairs(categories) do category_names[#category_names + 1] = category end
	table.sort(category_names)
	for _, category in ipairs(category_names) do
		local values = extractors[category] or {}
		sort_entities(values)
		cached_sections[#cached_sections + 1] = {
			name = category.."_pumpjack",
			category = category,
			caption = {"mpp-oil.settings_pumpjack_label", categories[category][1].localised_name},
			values = values,
			default = category == "basic-fluid" and "pumpjack" or nil,
		}
	end
	for _, selection in ipairs(common.simple_entity_selections) do
		local values = {}
		for _, proto in pairs(prototypes.get_entity_filtered{{filter="type", type=selection.filter_type}}) do
			local box = proto.collision_box
			local size = math.ceil(box.right_bottom.x - box.left_top.x)
			if usable(proto) and (not selection.max_size or size <= selection.max_size)
				and (not selection.predicate or selection.predicate(proto)) then
				values[#values + 1] = proto
			end
		end
		sort_entities(values)
		cached_sections[#cached_sections + 1] = {
			name = selection.name,
			caption = {"mpp-oil.settings_"..selection.name.."_label"},
			values = values,
			default = selection.default,
			allow_none = selection.allow_none,
		}
	end
	return cached_sections
end

function config.is_fluid_resource(entity)
	config.get_sections()
	return entity.valid and entity.type == "resource" and fluid_resources[entity.name] == true
end

function config.get_section(name)
	for _, section in ipairs(config.get_sections()) do
		if section.name == name then return section end
	end
end

function config.is_available(name, value)
	local section = config.get_section(name)
	for _, proto in ipairs(section and section.values or {}) do
		if proto.name == value then return true end
	end
	return false
end

function config.get_extractor_section(player_data)
	for _,entity in ipairs(player_data.preview and player_data.preview.resources or {}) do
		if entity.valid and config.is_fluid_resource(entity) then
			for _,section in ipairs(config.get_sections()) do
				if section.category==entity.prototype.resource_category then return section end
			end
		end
	end
	for _,section in ipairs(config.get_sections()) do if section.category then return section end end
end

function config.get(player_data)
	local data = player_data.oil_settings
	local existing = data ~= nil
	if not data then
		data = {
			choices = {}, qualities = {}, filtered_entities = {},
			gui = {selections = {}},
			min_beacon_utility = 2, add_landfill = true, remove_existing = false,
		}
		player_data.oil_settings = data
	end
	data.gui = data.gui or {selections = {}}
	data.gui.selections = data.gui.selections or {}
	data.filtered_entities = data.filtered_entities or {}
	local shared = player_data.choices
	if not data.shared_choices_version then
		-- Retain the previously active oil settings when upgrading to the shared controls.
		if existing and shared.layout_choice == "oil" then
			for _, name in ipairs{"pipe", "pole"} do
				shared[name.."_choice"] = data.choices[name.."_choice"] or shared[name.."_choice"]
				shared[name.."_quality_choice"] = data.qualities[name] or shared[name.."_quality_choice"]
			end
			shared.landfill_choice = data.add_landfill == false
			shared.deconstruction_choice = data.remove_existing ~= true
		end
		data.shared_choices_version = 1
	end
	for _, name in ipairs{"pipe", "pole"} do
		local value = shared[name.."_choice"]
		if name == "pole" and value == "zero_gap" then value = "none" end
		data.choices[name.."_choice"] = value
		data.qualities[name] = shared[name.."_quality_choice"]
	end
	data.add_landfill = not shared.landfill_choice
	data.remove_existing = not shared.deconstruction_choice
	data.retain_entities = shared.deconstruction_choice
	for _, section in ipairs(config.get_sections()) do
		local key = section.name.."_choice"
		local selected = data.choices[key]
		local valid = section.allow_none and selected == "none"
		local default
		for _, proto in ipairs(section.values) do
			valid = valid or selected == proto.name
			if proto.name == section.default then default = proto.name end
		end
		if not valid then
			data.choices[key] = section.allow_none and section.default == "none" and "none"
				or default or (section.values[1] and section.values[1].name)
				or (section.allow_none and "none" or nil)
		end
		local quality = data.qualities[section.name] or "normal"
		if not prototypes.quality[quality] then quality = "normal" end
		data.qualities[section.name] = quality
		data.choices[section.name.."_quality_choice"] = quality
	end
	shared.pipe_choice = data.choices.pipe_choice
	shared.pipe_quality_choice = data.qualities.pipe
	if shared.pole_choice ~= "zero_gap" then shared.pole_choice = data.choices.pole_choice end
	shared.pole_quality_choice = data.qualities.pole
	return data
end

function config.get_resource_categories(player_data)
	local data = config.get(player_data)
	local categories = {}
	for _, section in ipairs(config.get_sections()) do
		if section.category and data.choices[section.name.."_choice"] then
			categories[section.category] = true
		end
	end
	return categories
end

return config
