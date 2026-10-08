local config = require("oil.config")

local gui = {}

function gui.update(player, player_data, root, helpers)
	local data = config.get(player_data)
	root.clear()
	data.gui.selections = {}
	for _, section in ipairs(config.get_sections()) do
		if section.name ~= "pipe-to-ground" and section.name ~= "heat-pipe" then goto continue end
		local target = section.name == "heat-pipe" and player_data.gui.oil_heat_root or root
		if section.name == "heat-pipe" then target.clear() end
		local group = target.add{type="flow", direction="vertical", style="mpp_section"}
		group.style.natural_width = 0
		local values = {}
		for _, proto in ipairs(section.values) do
			values[#values + 1] = {value=proto.name, icon="entity/"..proto.name,
				tooltip=section.name=="heat-pipe" and {"", proto.localised_name, "\n", {"mpp-oil.settings_heat-pipe_tooltip"}} or proto.localised_name}
		end
		local selection_row = group.add{type="flow", direction="vertical"}
		selection_row.style.vertical_spacing = 2
		local row = selection_row.add{type="table", style="filter_slot_table", column_count=1}
		helpers.entities(data, row, "mpp_oil_choice", section.name, values, {optional=section.allow_none})
		::continue::
	end
	player_data.gui.beacon_utility_field.text = tostring(data.min_beacon_utility)
end

function gui.on_click(event, player_data)
	local action = event.element.tags.mpp_oil_choice
	if not action then return false end
	local data = config.get(player_data)
	local value = event.element.tags.value
	if data.gui.selections[action] and data.gui.selections[action][value] then
		local disabled = event.element.tags.mpp_optional
			and (data.choices[action.."_choice"] == value or event.button == defines.mouse_button_type.right)
		data.choices[action.."_choice"] = disabled and "none" or value
		if action:sub(-8) == "_quality" then data.qualities[action:sub(1, -9)] = value end
	end
	return true
end

function gui.on_text_changed(event, player_data)
	if event.element.tags.mpp_oil_utility then
		local value = tonumber(event.element.text)
		if value and value >= 0 then config.get(player_data).min_beacon_utility = value; return true end
		return false
	end
end

return gui
