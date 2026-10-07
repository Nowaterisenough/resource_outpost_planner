local config = require("oil.config")
local mpp_util = require("mpp.mpp_util")

local gui = {}

function gui.update(player, player_data, root, helpers)
	local data = config.get(player_data)
	root.clear()
	data.gui.selections = {}
	for _, section in ipairs(config.get_sections()) do
		if section.category or section.name == "pipe" or section.name == "pole" then goto continue end
		local group = root.add{type="flow", direction="vertical", style="mpp_section"}
		group.add{type="label", caption=section.caption, style="subheader_caption_label"}
		local values = {}
		if section.allow_none then
			values[#values + 1] = {
				value="none", icon="mpp_no_entity", tooltip={"mpp.choice_none"}, no_quality=true,
			}
		end
		for _, proto in ipairs(section.values) do
			values[#values + 1] = {value=proto.name, icon="entity/"..proto.name, tooltip=proto.localised_name}
		end
		if #values == 0 then
			values[1] = {value="none", icon="mpp_no_entity", tooltip={"mpp-oil.msg_no_valid_pumpjacks"}, disabled=true}
		end
		local row = group.add{type="table", style="filter_slot_table", column_count=6}
		helpers.entities(data, row, "mpp_oil_choice", section.name, values,
			{shown_quality=data.qualities[section.name]})

		if player_data.quality_pickers and script.feature_flags.quality then
			local qualities = {}
			for _, value in ipairs(mpp_util.quality_list()) do
				if player.force.is_quality_unlocked(value.value) then qualities[#qualities + 1] = value end
			end
			local quality_row = group.add{type="table", style="mpp_quality_table", column_count=10}
			helpers.entities(data, quality_row, "mpp_oil_choice", section.name.."_quality", qualities,
				{style_func=helpers.quality_style, alternate_visibility=true})
		end
		::continue::
	end
	local utility = root.add{type="flow", direction="horizontal"}
	utility.add{type="label", caption={"mpp-oil.settings_beacon_utility"},
		tooltip={"mpp-oil.settings_beacon_utility_tooltip"}}
	local field = utility.add{
		type="textfield", text=tostring(data.min_beacon_utility), numeric=true,
		allow_decimal=true, allow_negative=false, lose_focus_on_confirm=true,
		tags={mpp_oil_utility=true},
	}
	field.style.width = 60
end

function gui.on_click(event, player_data)
	local action = event.element.tags.mpp_oil_choice
	if not action then return false end
	local data = config.get(player_data)
	local value = event.element.tags.value
	if data.gui.selections[action] and data.gui.selections[action][value] then
		data.choices[action.."_choice"] = value
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
