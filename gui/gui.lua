local algorithm = require("algorithm")
local mpp_util = require("mpp.mpp_util")
local enums = require("mpp.enums")
local blueprint_meta = require("mpp.blueprintmeta")
local compatibility = require("mpp.compatibility")
local input_mode = require("mpp.input_mode")
local common = require("layouts.common")
local oil_gui = require("oil.gui")
local oil_config = require("oil.config")
local preview = require("mpp.preview")
local beacons = require("mpp.beacons")
local conf = require("configuration")

local layouts = algorithm.layouts

local gui = {}
local workflow_version = 9

local direction_sprites = {
	north = "virtual-signal/up-arrow",
	east = "virtual-signal/right-arrow",
	south = "virtual-signal/down-arrow",
	west = "virtual-signal/left-arrow",
}

--[[
	tag explanations:
	mpp_action - a choice between several settings for a "*_choice"
	mpp_toggle - a toggle for a boolean "*_choice"
]]

---@alias MppTagAction
---| "mpp_action"
---| "mpp_toggle"
---| "mpp_terrain_mode"
---| "mpp_blueprint_add_mode"
---| "mpp_blueprint_receptacle"
---| "mpp_fake_blueprint_button"
---| "mpp_delete_blueprint_button"
---| "mpp_drop_down"
---| "mpp_undo"

---@alias MppSettingSections
---| "layout"
---| "direction"
---| "miner"
---| "miner_quality"
---| "belt"
---| "belt_quality"
---| "space_belt"
---| "space_belt_quality"
---| "logistics"
---| "logistics_quality"
---| "pole"
---| "pole_quality"
---| "misc"
---| "debugging"

---@type table<MppSettingSections, true>
local entity_sections = {
	miner = true,
	belt=true,
	space_belt=true,
	logistics=true,
	pole=true,
	pipe=true,
	beacon=true,
}

---@class SettingValueEntry
---@field type string|nil Button type
---@field value string Value name
---@field tooltip LocalisedString
---@field caption LocalisedString?
---@field caption_width integer?
---@field icon SpritePath
---@field icon_enabled SpritePath?
---@field order string?
---@field sort number[]?
---@field default number? For "drop-down" element
---@field refresh boolean? Update selections when clicked?
---@field filterable boolean? Can entity be hidden
---@field disabled boolean? Is button disabled
---@field no_quality boolean? Don't show quality badge

---@class SettingValueEntryPrototype : SettingValueEntry
---@field action "mpp_prototype" Action tag override
---@field elem_type string
---@field elem_filters PrototypeFilter?
---@field elem_value string?|table?

---@class TagsSimpleChoiceButton
---@field value string
---@field default string
---@field mpp_filterable boolean

---@class SettingSectionCreateOptions
---@field direction? GuiDirection
---@field column_count? number
---@field caption? LocalisedString
---@field secondary? boolean

---Creates a setting section (label + table)
---Can be hidden
---@param player_data PlayerData
---@param root any
---@param name MppSettingSections
---@param opts? SettingSectionCreateOptions
---@return LuaGuiElement
---@return LuaGuiElement
---@return LuaGuiElement?
local function create_setting_section(player_data, root, name, opts)
	opts = opts or {}
	local section = root.add{type="flow", direction="vertical", style="mpp_section"}
	if opts.secondary then
		section.style.natural_width = 0
		section.style.horizontally_stretchable = true
	end
	player_data.gui.section[name] = section
	section.add{type="label", name="section_label", style="subheader_caption_label", visible=not opts.secondary, caption=opts.caption or {"mpp.settings_"..name.."_label"}}
	local row = section.add{type="flow", name="selection_row", direction="vertical"}
	row.style.vertical_spacing = 2
	local table_root = row.add{
		type="table",
		direction=opts.direction or "horizontal",
		style="filter_slot_table",
		column_count=opts.column_count or 6,
	}
	player_data.gui.tables[name] = table_root
	
	return table_root, section
end

local function create_settings_column(root, width)
	local column = root.add{type="flow", direction="vertical"}
	column.style.width = width
	return column
end

---@param player_data PlayerData
---@param section LuaGuiElement
---@param name string
---@param opts? SettingSectionCreateOptions
---@return unknown
local function append_quality_table(player_data, section, name, opts)
	local quality_root = section.selection_row.add{type="flow", direction="horizontal"}
	quality_root.style.horizontal_spacing = 0
	player_data.gui.tables[name] = quality_root
	quality_root.visible = script.feature_flags.quality
	return quality_root
end

local function style_helper_selection(check)
	if check then return "yellow_slot_button" end
	return "slot_button"
end

local function setting_toggle_icon(name, enabled)
	return "mpp_setting_"..name..(enabled and "_enabled" or "_disabled")
end

local function style_helper_blueprint_toggle(check)
	return check and "mpp_blueprint_mode_button_active" or "mpp_blueprint_mode_button"
end

---@param player_data PlayerData
local function helper_undo_available(player_data)
	return player_data.last_state and #player_data.last_state._collected_ghosts > 0
end

local function style_helper_quality(check, filtered)
	return filtered and "mpp_button_quality_hidden" or check and "mpp_button_quality_active" or "mpp_button_quality"
end

---@class SettingSelectorOptions
---@field style_func? fun(bool, bool): string first param to check if is currently selected, second param if is filtered
---@field shown_quality? string Adds quality badge on the icon
---@field alternate_visibility? true Don't show the eye if setting is filtered
---@field optional? boolean Clicking the active choice or right-clicking disables the equipment

---@param player_data PlayerData global player GUI reference object
---@param root LuaGuiElement
---@param action_type string Default action tag
---@param action MppSettingSections
---@param values (SettingValueEntry | SettingValueEntryPrototype)[]
---@param opts? SettingSelectorOptions
local function create_setting_selector(player_data, root, action_type, action, values, opts)
	opts = opts or {}
	local action_class = {}
	player_data.gui.selections[action] = action_class
	root.clear()
	local selected = player_data.choices[action.."_choice"]
	if #values == 0 then
		root.add{type="label", caption={"mpp.label_no_available_choices"}}
		return
	end

	local style_helper = opts.style_func or style_helper_selection
	
	for _, value in ipairs(values) do

		local is_filtered = mpp_util.get_entity_hidden(player_data, action, value.value)
		if not player_data.entity_filtering_mode and is_filtered then
			goto continue
		end

		local action_type_override = value.action or action_type
		local toggle_value = action_type == "mpp_toggle" and player_data.choices[value.value.."_choice"]
		local style_check = value.value == selected or toggle_value
		if value.selected ~= nil then style_check = value.selected end
		local button_root = root
		if action == "misc" then
			button_root = root.add{type="flow", direction="vertical", style="mpp_setting_cell"}
		end
		local button
		if value.type == "choose-elem-button" then
			---@type LuaGuiElement
			button = button_root.add{
				type="choose-elem-button",
				style=style_helper(value.elem_value ~= nil),
				tooltip=mpp_util.wrap_tooltip(value.tooltip),
				elem_type=value.elem_type,
				elem_filters=value.elem_filters,
				tags={[action_type_override]=action, value=value.value, default=value.default},
			}
			button.elem_value = value.elem_value
			local fake_placeholder = button.add{
				type="sprite",
				sprite=value.icon,
				ignored_by_interaction=true,
				style="mpp_fake_item_placeholder",
				visible=not value.elem_value,
			}
		else
			local icon = value.icon
			if style_check and value.icon_enabled then icon = value.icon_enabled end
			local tooltip = value.tooltip
			if opts.optional then tooltip = {"", tooltip, "\n", {"mpp.label_optional_equipment_toggle"}} end
			---@type LuaGuiElement
			button = button_root.add{
				type="sprite-button",
				style=style_helper(style_check, is_filtered),
				sprite=icon,
				tags={
					[action_type_override]=action,
					value=value.value,
					default=value.default,
					refresh=value.refresh,
					mpp_icon_default=value.icon,
					mpp_icon_enabled=value.icon_enabled,
					mpp_filterable=value.filterable,
					mpp_optional=opts.optional,
				},
				tooltip=mpp_util.tooltip_entity_not_available(value.disabled, tooltip),
				enabled=not value.disabled,
			}
			if is_filtered and not opts.alternate_visibility then
				---@type LuaGuiElement
				local hidden =  button.add{
					type="sprite",
					style="mpp_filtered_entity",
					name="filtered",
					sprite="mpp_entity_filtered_overlay",
					ignored_by_interaction=true,
				}
			end
			if not value.no_quality and opts.shown_quality and script.feature_flags.quality then
				local flow = button.add{
					type="flow",
					direction = "vertical",
				}
				flow.style.size = 40
				local padding = flow.add{
					type="sprite",
					resize_to_sprite = false,
					ignored_by_interaction = true,
				}
				padding.style.height = 14
				local quality_badge = flow.add{
					type = "sprite",
					style = "mpp_quality_badge",
					resize_to_sprite = false,
					name = "quality_badge",
					sprite = "quality/"..opts.shown_quality,
					ignored_by_interaction = true,
					enabled=not value.disabled,
				}
			end
		end
		if action == "misc" then
			local label = button_root.add{
				type="label",
				caption=value.caption or {"mpp.icon_"..value.value},
				style="mpp_setting_caption",
				tooltip=mpp_util.wrap_tooltip(value.tooltip),
				ignored_by_interaction=true,
			}
			if value.caption_width then
				button_root.style.natural_width = value.caption_width
				label.style.minimal_width = value.caption_width
				label.style.maximal_width = value.caption_width
			end
		end
		action_class[value.value] = button

		::continue::
	end
end

---@param player_data PlayerData global player GUI reference object
---@param root LuaGuiElement
---@param action_type string Default action tag
---@param action MppSettingSections
---@param values (SettingValueEntry | SettingValueEntryPrototype)[]
---@param opts? SettingSelectorOptions
local function create_quality_selector(player_data, root, action_type, action, values, opts)
	root.clear()
	local player = game.get_player(root.player_index)
	local qualities = {}
	for _, quality in ipairs(values) do
		if player.force.is_quality_unlocked(quality.value) then qualities[#qualities+1] = quality end
	end
	table.sort(qualities, function(a,b)
		local left, right = prototypes.quality[a.value], prototypes.quality[b.value]
		return left.level == right.level and a.value < b.value or left.level < right.level
	end)
	local selected = player_data.choices[action.."_choice"]
	local equipment = player_data.choices[action:sub(1,-9).."_choice"]
	player_data.gui.selections[action] = {}
	for _, quality in ipairs(qualities) do
		local button = root.add{
			type="sprite-button", sprite="quality/"..quality.value,
			style=style_helper_quality(quality.value == selected),
			enabled=equipment~=nil and equipment~="none" and equipment~="zero_gap",
			tooltip=quality.tooltip,
			tags={mpp_quality=action, value=quality.value, mpp_oil_quality=action_type=="mpp_oil_choice"},
		}
		player_data.gui.selections[action][quality.value] = button
	end
	storage.players[root.player_index].gui.quality_selectors[action] = root
end

---@param player_data PlayerData
---@param button LuaGuiElement
local function set_player_blueprint(player_data, button)
	local choices = player_data.choices
	local player_blueprints = player_data.blueprints
	local blueprint_number = button.tags.mpp_fake_blueprint_button
	local blueprint_flow = player_blueprints.flow[button.parent.index]

	local current_blueprint = choices.blueprint_choice
	if current_blueprint == blueprint_number then
		return nil
	end
	
	if current_blueprint and current_blueprint.valid then
		local current_blueprint_button = player_blueprints.button[current_blueprint.item_number]
		current_blueprint_button.style = "mpp_fake_blueprint_button"
	end
	
	local blueprint = player_blueprints.mapping[blueprint_number]
	button.style = "mpp_fake_blueprint_button_selected"
	choices.blueprint_choice = blueprint
end

---@param player_data PlayerData
---@param table_root LuaGuiElement
---@param blueprint_item LuaItemStack
---@param cursor_stack LuaItemStack|nil
local function create_blueprint_entry(player_data, table_root, blueprint_item, cursor_stack)
	local blueprint_line = table_root.add{type="flow"}
	local item_number = blueprint_item.item_number --[[@as number]]
	player_data.blueprints.flow[item_number] = blueprint_line
	player_data.blueprints.mapping[item_number] = blueprint_item
	
	local blueprint_button = blueprint_line.add{
		type="button",
		style=(player_data.choices.blueprint_choice == blueprint_item and "mpp_fake_blueprint_button_selected" or "mpp_fake_blueprint_button"),
		tags={mpp_fake_blueprint_button=item_number},
	}
	player_data.blueprints.button[item_number] = blueprint_button

	local icons = blueprint_item.preview_icons or blueprint_item.default_icons
	
	local function sprite_path(signal)
		local sprite = signal.name
		if signal.type == "virtual" then
			sprite = "virtual-signal/"..sprite --wube pls
		elseif signal.type then
			sprite = signal.type .. "/" .. sprite
		else
			sprite = "entity/" .. sprite
		end
		if not helpers.is_valid_sprite_path(sprite) then
			return "item/item-unknown"
		end
		return sprite
	end
	
	if table_size(icons) > 1 then
		local fake_table = blueprint_button.add{
			type="table",
			style="mpp_fake_blueprint_table",
			direction="horizontal",
			column_count=2,
			tags={mpp_fake_blueprint_table=true},
			ignored_by_interaction=true,
		}

		for k, v in pairs(icons) do
			local sprite = sprite_path(v.signal)
			fake_table.add{
				type="sprite",
				sprite=(sprite),
				style="mpp_fake_blueprint_sprite",
				tags={mpp_fake_blueprint_sprite=true},
			}
		end
	else
		local bp_signal = ({next(icons)})[2].signal --[[@as SignalID]]
		local sprite = sprite_path(bp_signal)
		blueprint_button.add{
			type="sprite",
			sprite=(sprite),
			ignored_by_interaction=true,
			style="mpp_fake_item_placeholder_blueprint",
			tags={mpp_fake_blueprint_sprite=true},
		}
	end

	local delete_button = blueprint_line.add{
		type="sprite-button",
		sprite="mpp_cross",
		style="mpp_delete_blueprint_button",
		tags={mpp_delete_blueprint_button=item_number},
		tooltip=mpp_util.wrap_tooltip{"gui.delete-blueprint-record"},
	}
	player_data.blueprints.delete[item_number] = delete_button

	local label, tooltip = mpp_util.blueprint_label(blueprint_item)
	blueprint_line.add{
		type="label",
		caption=label,
		tooltip=mpp_util.wrap_tooltip(tooltip),
	}

	local cached = player_data.blueprints.cache[item_number]
	if not cached then
		cached = blueprint_meta:new(blueprint_item)
		player_data.blueprints.cache[item_number] = cached
	else
		if not cached:check_valid() then
			blueprint_button.style = "mpp_fake_blueprint_button_invalid"
			if player_data.choices.blueprint_choice == blueprint_item then
				player_data.choices.blueprint_choice = nil
			end
		end
	end
	if cursor_stack and cursor_stack.valid and cached.valid then
		player_data.blueprints.original_id[item_number] = cursor_stack.item_number
	end

	if not player_data.choices.blueprint_choice and cached.valid then
		set_player_blueprint(player_data, blueprint_button)
	end
end

---@param player LuaPlayer
function gui.create_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen.add{type="frame", name="mpp_settings_frame", direction="vertical"}
	---@type PlayerData
	local player_data = storage.players[player.index]
	local player_gui = player_data.gui
	player_gui.section, player_gui.tables, player_gui.selections = {}, {}, {}
	local equipment_width = script.feature_flags.quality and 260 or 172
	local secondary_width = 172
	frame.style.minimal_width = 340

	local titlebar = frame.add{type="flow", name="mpp_titlebar", direction="horizontal"}
	titlebar.add{type="label", style="frame_title", name="mpp_titlebar_label", caption={"mpp.settings_frame"}}
	titlebar.add{type="empty-widget", name="mpp_titlebar_spacer", horizontally_strechable=true}
	player_gui.quality_toggle, player_gui.advanced_settings, player_gui.filtering_settings = nil, nil, nil
	player_gui.unified = true
	player_gui.workflow_version = workflow_version
	do -- Miner selection
		local row = frame.add{type="flow", direction="horizontal"}
		row.style.horizontal_spacing = 12
		local table_root, section = create_setting_section(player_data, row, "miner", {column_count=4})
		section.style.width = equipment_width
		local quality_root = append_quality_table(player_data, section, "miner_quality", {column_count=10})
		append_quality_table(player_data,section,"oil_extractor_quality",{column_count=10})
		local _, modules = create_setting_section(player_data, row, "module", {column_count=1, caption={"mpp.settings_module_label"}})
		modules.style.width = secondary_width
		append_quality_table(player_data,modules,"module_quality")
	end

	local body = frame.add{
		type="scroll-pane", direction="vertical",
		horizontal_scroll_policy="never", vertical_scroll_policy="auto",
	}
	player_gui.settings_body = body
	body.style.left_padding = 0
	body.style.right_padding = 0
	body.style.maximal_height = math.max(180, math.min(640, math.floor(player.display_resolution.height / player.display_scale) - 280))
	local mining = body.add{type="flow", direction="vertical", style="mpp_section"}
	player_gui.mining_settings_root = mining
	local layout_row = mining.add{type="flow", direction="horizontal", style="mpp_settings_columns"}
	local transport = body.add{type="flow", direction="vertical", style="mpp_section"}
	transport.add{type="label", caption={"mpp.settings_transport_label"}, style="subheader_caption_label"}
	local transport_row = transport.add{type="flow", direction="horizontal", style="mpp_settings_columns"}
	local belt_column = create_settings_column(transport_row, equipment_width)
	player_gui.mining_transport_root = belt_column.add{type="flow", direction="vertical"}
	player_gui.mining_transport_root.style.width = equipment_width
	local pipe_column = create_settings_column(transport_row, secondary_width)
	player_gui.oil_settings_root = pipe_column.add{type="flow", direction="vertical"}
	local power = body.add{type="flow", direction="vertical", style="mpp_section"}
	power.add{type="label", caption={"mpp.settings_power_label"}, style="subheader_caption_label"}
	local power_row = power.add{type="flow", direction="horizontal", style="mpp_settings_columns"}
	local pole_column = create_settings_column(power_row, equipment_width)
	local power_column = create_settings_column(power_row, secondary_width)
	player_gui.power_options = power_column.add{type="table", column_count=1, style="filter_slot_table"}
	player_gui.oil_heat_root = power_column.add{type="flow", direction="vertical"}
	player_gui.beacon_group = body.add{type="flow", direction="vertical", style="mpp_section"}

	do -- layout selection
		local table_root, section = create_setting_section(player_data, layout_row, "layout", {column_count=2})
		section.style.width = equipment_width

		local choices = List()
		local index = 1
		player_gui.layout_values = {}
		for _, layout in ipairs(layouts) do
			if layout.name ~= "oil" then
				choices:push(layout.translation)
				player_gui.layout_values[#choices] = layout.name
				if algorithm.get_mining_layout(player_data).name == layout.name then index = #choices end
			end
		end

		local flow = table_root.add{type="flow", direction="horizontal"}

		player_gui.layout_dropdown = flow.add{
			type="drop-down",
			items=choices,
			style="mpp_quality_dropdown",
			selected_index=index --[[@as uint]],
			tags={mpp_drop_down="layout", mpp_value_map="layout", default=1},
		}

		player_gui.blueprint_add_button = flow.add{
			type="sprite-button",
			name="blueprint_add_button",
			sprite=setting_toggle_icon("blueprint_add", player_data.blueprint_add_mode),
			style=style_helper_blueprint_toggle(),
			tooltip=mpp_util.wrap_tooltip{"mpp.blueprint_add_mode"},
			tags={mpp_blueprint_add_mode=true},
		}
		player_gui.blueprint_add_button.visible = algorithm.get_mining_layout(player_data).name == "blueprints"
	end

	do -- Direction selection
		local table_root, section = create_setting_section(player_data, layout_row, "direction", {caption={"mpp.settings_direction_short_label"}})
		section.style.width = secondary_width
		section.section_label.caption = {"", section.section_label.caption, " [img=info]"}
		section.section_label.tooltip = mpp_util.wrap_tooltip{"mpp.label_rotate_keybind_tip"}
		create_setting_selector(player_data, table_root, "mpp_action", "direction", {
			{value="north", icon=direction_sprites.north},
			{value="east", icon=direction_sprites.east},
			{value="south", icon=direction_sprites.south},
			{value="west", icon=direction_sprites.west},
		})
	end

	do -- Belt selection
		local table_root, section = create_setting_section(player_data, player_gui.mining_transport_root, "belt", {column_count=4, secondary=true})
	end

	do -- Space belt selection
		local table_root, section = create_setting_section(player_data, player_gui.mining_transport_root, "space_belt", {column_count=4, secondary=true})
	end
	do -- Shared beacon controls
		local group = player_gui.beacon_group
		local row = group.add{type="flow", direction="horizontal"}
		row.style.horizontal_spacing = 12
		local _,section=create_setting_section(player_data,row,"beacon",{column_count=1})
		section.style.width = equipment_width
		section.section_label.tooltip=mpp_util.wrap_tooltip{"mpp.choice_beacon"}
		append_quality_table(player_data,section,"beacon_quality")
		local _,modules=create_setting_section(player_data,row,"beacon_module",{column_count=1})
		modules.style.width = secondary_width
		append_quality_table(player_data,modules,"beacon_module_quality")
	end

	player_gui.beacon_utility = player_gui.beacon_group.add{type="flow", direction="horizontal"}
	player_gui.beacon_utility.add{type="label", caption={"mpp-oil.settings_beacon_utility"},
		tooltip={"mpp-oil.settings_beacon_utility_tooltip"}}
	player_gui.beacon_utility_field = player_gui.beacon_utility.add{type="textfield", text="2", numeric=true,
		allow_decimal=true, allow_negative=false, lose_focus_on_confirm=true, tags={mpp_oil_utility=true}}
	player_gui.beacon_utility_field.style.width = 48

	do -- Logistics selection
		local table_root, section = create_setting_section(player_data, player_gui.mining_transport_root, "logistics", {column_count=4, secondary=true})
		local quality_root = append_quality_table(player_data, section, "logistics_quality", {column_count=10})
	end

	do -- Electric pole selection
		local table_root, section = create_setting_section(player_data, pole_column, "pole", {column_count=4, secondary=true})
		section.style.width = equipment_width
		local quality_root = append_quality_table(player_data, section, "pole_quality", {column_count=10})
	end
	do -- Shared pipe selection
		local table_root, section = create_setting_section(player_data, pipe_column, "pipe", {column_count=1, secondary=true})
		section.style.width = secondary_width
	end

	do -- Blueprint settings
		---@type LuaGuiElement, LuaGuiElement
		--local table_root, section = create_setting_section(player_data, frame, "blueprints")
		local section = mining.add{type="flow", direction="vertical"}
		player_data.gui.section["blueprints"] = section
		section.add{type="label", style="subheader_caption_label", caption={"mpp.settings_blueprints_label"}}

		local root = section.add{type="flow", direction="vertical"}
		player_data.gui.tables["blueprints"] = root

		player_gui.blueprint_add_section = section.add{
			type="flow",
			direction="horizontal",
		}

		player_gui.blueprint_receptacle = player_gui.blueprint_add_section.add{
			type="sprite-button",
			sprite="mpp_blueprint_add",
			tags={mpp_blueprint_receptacle=true},
		}
		local blueprint_label = player_gui.blueprint_add_section.add{
			type="label",
			caption={"mpp.label_add_blueprint", },
		}
		player_gui.blueprint_add_section.visible = player_data.blueprint_add_mode

		for i = 1, #player_data.blueprint_items do
			---@type LuaItemStack
			local item = player_data.blueprint_items[i]
			if item.valid and item.is_blueprint then
				create_blueprint_entry(player_data, root, item)
			end
		end
	end

	do -- Misc selection
		local table_root, section = create_setting_section(player_data, body, "misc", {column_count=6})
		create_setting_section(player_data, body, "terrain", {column_count=3})
	end

	do -- Debugging rendering options
		local table_root, section = create_setting_section(player_data, body, "debugging")
	end

	local footer=frame.add{type="flow",direction="vertical",style="mpp_section"}
	player_gui.preview_status=nil
	local tools=footer.add{type="flow",direction="horizontal"}
	player_gui.select_tool=tools.add{type="button",caption={"mpp.tool_select"},tooltip={"mpp.tool_select_tooltip"},tags={mpp_input_mode="select"}}
	player_gui.output_tool=tools.add{type="button",caption={"mpp.icon_belt_planner"},tooltip={"mpp.choice_belt_planner"},enabled=false,tags={mpp_input_mode="output"}}
	local actions=footer.add{type="flow",direction="horizontal"}
	player_gui.preview_apply=actions.add{type="button",style="confirm_button",caption={"mpp.preview_apply"},enabled=false,tags={mpp_preview_apply=true}}
	player_gui.preview_cancel=actions.add{type="button",style="back_button",caption={"mpp.preview_cancel"},enabled=false,tags={mpp_preview_cancel=true}}
	player_gui.undo_button=actions.add{type="button",caption={"controls.undo"},tooltip=mpp_util.wrap_tooltip{"controls.undo"},
		enabled=helper_undo_available(player_data),tags={mpp_undo=true}}
end

---@param player_data PlayerData
local function update_direction_section(player_data)
	local section = player_data.gui.selections.direction
	local choice = player_data.choices.direction_choice
	
	for key, element in pairs(section) do
		element.style = style_helper_selection(key == choice)
		element.sprite = direction_sprites[key]
	end
end

gui.update_direction_section = update_direction_section

---@param player LuaPlayer
local function update_miner_selection(player)
	local player_data = storage.players[player.index]
	local player_choices = player_data.choices
	local layout = algorithm.get_mining_layout(player_data)
	local restrictions = layout.restrictions

	player_data.gui.section["miner"].visible = true

	local near_radius_min, near_radius_max = restrictions.miner_size[1], restrictions.miner_size[2]
	local far_radius_min, far_radius_max = restrictions.miner_radius[1], restrictions.miner_radius[2]
	local values = List() --[[@as List<SettingValueEntry>]]
	local existing_choice_is_valid = false
	local cached_miners, cached_resources = enums.get_available_miners()
	
	for _, miner_proto in pairs(cached_miners) do
		local miner = mpp_util.miner_struct(miner_proto.name)
		if mpp_util.check_filtered(miner_proto) or miner.filtered then goto skip_miner end
		if mpp_util.check_entity_hidden(player_data, "miner", miner_proto) then goto skip_miner end

		local is_restricted = not restrictions.miner_available or common.is_miner_restricted(miner, restrictions)
			or not layout:restriction_miner(miner)

		---@type List<LocalisedString>
		local tooltip = List{
			"", mpp_util.entity_name_with_quality(miner_proto.localised_name, player_choices.miner_quality_choice),
			"\n[img=mpp_tooltip_category_size] ", {"description.tile-size"}, (": %ix%i\n"):format(miner.size, miner.size),
			"[img=mpp_tooltip_category_mining_area] ", {"description.mining-area"}, (": %ix%i"):format(miner.real_area, miner.real_area),
		}
		tooltip
			:conditional_append(miner.power_source_tooltip ~= nil, "\n", miner.power_source_tooltip)
			:conditional_append(miner.area <= miner.size, "\n[color=yellow]", {"mpp.label_insufficient_area"}, "[/color]")
			:conditional_append(miner.drops_full_belt_stacks, "\n", {"mpp.label_drops_full_belt_stacks", 1 + player.force.belt_stack_size_bonus})
			:conditional_append(not miner.supports_fluids, "\n[color=yellow]", {"mpp.label_no_fluid_mining"}, "[/color]")
			:conditional_append(miner.oversized, "\n[color=yellow]", {"mpp.label_oversized_drill"}, "[/color]")
			:conditional_append(is_restricted,"\n",{"mpp.label_miner_layout_switch"})

		values:push{
			value=miner.name,
			tooltip=tooltip,
			icon=("entity/"..miner.name),
			order=miner_proto.order,
			filterable=true,
			disabled=false,
			sort={miner.size, miner.area},
		}
		
		if miner.name == player_choices.miner_choice then existing_choice_is_valid = true end

		::skip_miner::
	end

	if not existing_choice_is_valid and #values > 0 then
		if mpp_util.table_find(values, function(v) return v.value == layout.defaults.miner end) then
			player_choices.miner_choice = layout.defaults.miner
		else
			player_choices.miner_choice = values[1].value
		end
		existing_choice_is_valid = true
	elseif #values == 0 then
		player_choices.miner_choice = "none"
	end
	
	table.sort(values, function(a, b)
		local a1, a2, a3, b1, b2, b3 = a.sort[1], a.sort[2], a.order, b.sort[1], b.sort[2], b.order
		return (a1 == b1 and (a2 == b2 and a3 < b3 or a2 < b2)) or a1 < b1
	end)
	for _,value in ipairs(values) do value.selected=player_choices.layout_choice~="oil" and value.value==player_choices.miner_choice end
	local oil=oil_config.get(player_data)
	local section=oil_config.get_extractor_section(player_data)
	if section then
		for _,proto in ipairs(section.values) do
			values:push{value=proto.name,action="mpp_oil_extractor",icon="entity/"..proto.name,
				tooltip={"",proto.localised_name,"\n",{"mpp.settings_oil_label"}},
				selected=player_choices.layout_choice=="oil" and oil.choices[section.name.."_choice"]==proto.name,
				no_quality=true}
		end
	end

	local table_root = player_data.gui.tables["miner"]
	create_setting_selector(
		player_data,
		table_root,
		"mpp_action",
		"miner",
		values,
		{shown_quality=player_data.choices.miner_quality_choice}
	)
	
	create_quality_selector(
		player_data,
		player_data.gui.tables["miner_quality"],
		"mpp_action",
		"miner_quality",
		mpp_util.quality_list(),
		{style_func = style_helper_quality, alternate_visibility=true}
	)
end

---@param player LuaPlayer
local function update_belt_selection(player)
	local player_data = storage.players[player.index]
	local choices = player_data.choices
	local layout = algorithm.get_mining_layout(player_data)
	local restrictions = layout.restrictions
	
	local is_space = compatibility.is_space(player.surface.index)
	player_data.gui.section["belt"].visible = restrictions.belt_available and not is_space
	if not restrictions.belt_available or is_space then return end

	local values = List() --[[@as List<SettingValueEntry>]]
	local existing_choice_is_valid = false

	local belts = prototypes.get_entity_filtered{{filter="type", type="transport-belt"}}
	for _, belt in pairs(belts) do
		if mpp_util.check_filtered(belt) then goto skip_belt end
		local belt_struct = mpp_util.belt_struct(belt.name)
		if mpp_util.check_entity_hidden(player_data, "belt", belt) then goto skip_belt end

		local is_restricted = common.is_belt_restricted(belt_struct, restrictions)
		if not player_data.entity_filtering_mode and is_restricted then goto skip_belt end

		local belt_speed = belt_struct.speed * 2
		local specifier = belt_speed % 1 == 0 and ": %.0f " or ": %.1f "

		local tooltip = {
			"", mpp_util.entity_name_with_quality(belt.localised_name, choices.belt_quality_choice), "\n",
			{"description.belt-speed"}, specifier:format(belt_speed),
			{"description.belt-items"}, "/s",
		}

		if restrictions.uses_underground_belts and not belt_struct.related_underground_belt then
			table.insert(tooltip, {"", "\n[color=yellow]", {"mpp.label_belt_find_underground"}, "[/color]"})
		end

		values:push{
			value=belt.name,
			tooltip=tooltip,
			icon=("entity/"..belt.name),
			order=belt.order,
			filterable=true,
			disabled=is_restricted,
			sort={belt_struct.speed},
		}
		if belt.name == choices.belt_choice then existing_choice_is_valid = true end

		::skip_belt::
	end

	if not existing_choice_is_valid and #values > 0 then
		if mpp_util.table_find(values, function(v) return v.value == layout.defaults.belt end) then
			choices.belt_choice = layout.defaults.belt
		else
			choices.belt_choice = values[1].value
		end
		existing_choice_is_valid = true
	elseif #values == 0 then
		player_data.choices.belt_choice = "none"
	end
	
	table.sort(values, function(a, b)
		local a1, a2, b1, b2 = a.sort[1], a.order, b.sort[1], b.order
		return (a1 == b1 and a2 < b2) or a1 < b1
	end)

	local table_root = player_data.gui.tables["belt"]
	create_setting_selector(player_data, table_root, "mpp_action", "belt", values)
end

---@param player LuaPlayer
local function update_space_belt_selection(player)
	local player_data = storage.players[player.index]
	local choices = player_data.choices
	local layout = algorithm.get_mining_layout(player_data)
	local restrictions = layout.restrictions

	local is_space = compatibility.is_space(player.surface.index)
	player_data.gui.section["space_belt"].visible = restrictions.belt_available and is_space
	if not restrictions.belt_available or not is_space then return end

	local values = List() --[[@as List<SettingValueEntry>]]
	local existing_choice_is_valid = false

	local belts = prototypes.get_entity_filtered{{filter="type", type="transport-belt"}}
	for _, belt in pairs(belts) do
		if mpp_util.check_filtered(belt) then goto skip_belt end
		--if not compatibility.is_buildable_in_space(belt.name) then goto skip_belt end
		local belt_struct = mpp_util.belt_struct(belt.name)
		if mpp_util.check_entity_hidden(player_data, "space_belt", belt) then goto skip_belt end
		
		local is_restricted = common.is_belt_restricted(belt_struct, restrictions) or not compatibility.is_buildable_in_space(belt.name)
		if not player_data.entity_filtering_mode and is_restricted then goto skip_belt end
		--if is_space and not string.match(belt.name, "^se%-") then goto skip_belt end

		local belt_speed = belt.belt_speed * 60 * 8
		local specifier = belt_speed % 1 == 0 and ": %.0f " or ": %.1f "

		local tooltip = {
			"", mpp_util.entity_name_with_quality(belt.localised_name, choices.space_belt_quality_choice), "\n",
			{"description.belt-speed"}, specifier:format(belt_speed),
			{"description.belt-items"}, "/s",
		}

		values:push{
			value=belt.name,
			tooltip=tooltip,
			icon=("entity/"..belt.name),
			order=belt.order,
			filterable=true,
			disabled=is_restricted,
			sort={belt_struct.speed},
		}
		if belt.name == choices.space_belt_choice then existing_choice_is_valid = true end

		::skip_belt::
	end

	if not existing_choice_is_valid and #values > 0 then
		if mpp_util.table_find(values, function(v) return v.value == layout.defaults.belt end) then
			choices.space_belt_choice = "se-space-transport-belt"
		else
			choices.space_belt_choice = values[1].value
		end
	elseif #values == 0 then
		choices.space_belt_choice = "none"
	end
	
	table.sort(values, function(a, b)
		local a1, a2, b1, b2 = a.sort[1], a.order, b.sort[1], b.order
		return (a1 == b1 and a2 < b2) or a1 < b1
	end)

	local table_root = player_data.gui.tables["space_belt"]
	create_setting_selector(player_data, table_root, "mpp_action", "space_belt", values)
end


---@param player_data PlayerData
local function update_logistics_selection(player_data)
	local choices = player_data.choices
	local layout = algorithm.get_mining_layout(player_data)
	local restrictions = layout.restrictions
	local values = List() --[[@as List<SettingValueEntry>]]

	player_data.gui.section["logistics"].visible = restrictions.logistics_available
	if not restrictions.logistics_available then return end

	local filter = {
		["passive-provider"]=true,
		["active-provider"]=true,
		["storage"] = true,
	}

	local existing_choice_is_valid = false
	local logistics = prototypes.get_entity_filtered{{filter="type", type="logistic-container"}}
	for _, chest in pairs(logistics) do
		if mpp_util.check_filtered(chest) then goto skip_chest end
		if mpp_util.check_entity_hidden(player_data, "logistics", chest) then goto skip_chest end
		local cbox = chest.collision_box
		local size = math.ceil(cbox.right_bottom.x - cbox.left_top.x)
		if size > 1 then goto skip_chest end
		if not filter[chest.logistic_mode] then goto skip_chest end

		values:push{
			value=chest.name,
			tooltip=chest.localised_name,
			icon=("entity/"..chest.name),
			order=chest.order,
			filterable=true,
		}
		if chest.name == choices.logistics_choice then existing_choice_is_valid = true end

		::skip_chest::
	end

	if not existing_choice_is_valid and #values > 0 then
		if mpp_util.table_find(values, function(v) return v.value == layout.defaults.logistics end) then
			choices.logistics_choice = layout.defaults.logistics
		else
			choices.logistics_choice = values[1].value
		end
	elseif #values == 0 then
		choices.logistics_choice = "none"
	end

	local table_root = player_data.gui.tables["logistics"]
	create_setting_selector(player_data, table_root, "mpp_action", "logistics", values,
		{shown_quality=player_data.choices.logistics_quality_choice}
	)
	
	create_quality_selector(
		player_data,
		player_data.gui.tables["logistics_quality"],
		"mpp_action",
		"logistics_quality",
		mpp_util.quality_list(),
		{style_func = style_helper_quality, alternate_visibility=true}
	)
end

---@param player_data PlayerData
local function update_pole_selection(player_data)
	local choices = player_data.choices
	local layout = algorithm.get_mining_layout(player_data)
	local restrictions = layout.restrictions

	player_data.gui.section["pole"].visible = true

	local values = List() --[[@as List<SettingValueEntry>]]

	local existing_choice_is_valid = ("none" == choices.pole_choice or (layout.restrictions.pole_zero_gap and "zero_gap" == choices.pole_choice))
	local poles = prototypes.get_entity_filtered{{filter="type", type="electric-pole"}}
	for _, pole_proto in pairs(poles) do
		if mpp_util.check_filtered(pole_proto) then goto skip_pole end
		if mpp_util.check_entity_hidden(player_data, "pole", pole_proto) then goto skip_pole end
		-- TODO: re-add if pole_proto.supply_area_distance < 0.5 then goto skip_pole end
		local pole = mpp_util.pole_struct(pole_proto.name, choices.pole_quality_choice)
		if pole.filtered then goto skip_pole end
		local is_restricted = common.is_pole_restricted(pole, restrictions)
		local oil_available = oil_config.is_available("pole", pole_proto.name)

		if not player_data.entity_filtering_mode and is_restricted and not oil_available then goto skip_pole end

		local specifier = (pole.wire % 1 == 0 and ": %.0f ") or (pole.wire * 10 % 1 == 0 and ": %.1f ") or ": %.2f "
		local tooltip = {
			"", mpp_util.entity_name_with_quality(pole_proto.localised_name, choices.pole_quality_choice), "\n",
			"[img=mpp_tooltip_category_size] ", {"description.tile-size"}, (": %ix%i\n"):format(pole.size, pole.size),
			"[img=mpp_tooltip_category_supply_area] ", {"description.supply-area"}, (": %ix%i\n"):format(pole.supply_width, pole.supply_width),
			" [img=tooltip-category-electricity] ", {"description.wire-reach"}, specifier:format(pole.wire),
		}
		if restrictions.pole_available and is_restricted and oil_available then
			tooltip[#tooltip+1] = "\n"
			tooltip[#tooltip+1] = {"mpp.label_oil_only_pole", prototypes.entity[layout.defaults.pole].localised_name}
		end

		values:push{
			value=pole_proto.name,
			tooltip=tooltip,
			icon=("entity/"..pole_proto.name),
			order=pole_proto.order,
			filterable=true,
			disabled=is_restricted and not oil_available,
		}
		if pole_proto.name == choices.pole_choice then existing_choice_is_valid = true end

		::skip_pole::
	end

	if not existing_choice_is_valid then
		choices.pole_choice = layout.defaults.pole
	end

	local table_root = player_data.gui.tables["pole"]
	create_setting_selector(player_data, table_root, "mpp_action", "pole", values,
		{shown_quality=player_data.choices.pole_quality_choice, optional=restrictions.pole_omittable}
	)
	
	create_quality_selector(
		player_data,
		player_data.gui.tables["pole_quality"],
		"mpp_action",
		"pole_quality",
		mpp_util.quality_list(),
		{style_func = style_helper_quality, alternate_visibility=true}
	)
end

local function update_pipe_selection(player_data)
	local choices = player_data.choices
	local section = player_data.gui.section.pipe
	section.visible = choices.layout_choice ~= "oil"
	local values = {}
	for _, proto in ipairs(oil_config.get_section("pipe").values) do
		values[#values+1] = {value=proto.name, icon="entity/"..proto.name,
			tooltip=proto.localised_name}
	end
	create_setting_selector(player_data,player_data.gui.tables.pipe,"mpp_action","pipe",values)
end

---@param player_data PlayerData
local function update_module_selection(player_data)
	local is_oil = player_data.choices.layout_choice == "oil"
	local data = is_oil and oil_config.get(player_data) or player_data
	local choices = data.choices
	local extractor = is_oil and oil_config.get_extractor_section(player_data)
	local name = is_oil and extractor and choices[extractor.name.."_choice"] or choices.miner_choice
	local quality = is_oil and extractor and data.qualities[extractor.name] or choices.miner_quality_choice
	local drill = prototypes.entity[name or "none"]
	local supported = (is_oil or algorithm.get_mining_layout(player_data).restrictions.module_available)
		and drill and drill.get_inventory_size(defines.inventory.mining_drill_modules, quality) > 0
	player_data.gui.section.module.visible = supported or false
	if not supported then return end
	local item = prototypes.item[choices.module_choice]
	if not item or not beacons.module_allowed(drill, item) then choices.module_choice = "none"; item=nil end
	if not prototypes.quality[choices.module_quality_choice] then choices.module_quality_choice = "normal" end
	local value = item and {name=item.name, quality=choices.module_quality_choice} or nil
	local tooltip = {"", {"gui.module"}, "\n", {"mpp.label_right_click_to_clear"}}
	if item then
		tooltip = {"", mpp_util.entity_name_with_quality(item.localised_name, choices.module_quality_choice),
			"\n", {"description.module-slots"}, ": ", drill.get_inventory_size(defines.inventory.mining_drill_modules, quality),
			"\n", {"mpp.label_right_click_to_clear"}}
	end
	local filters={}
	for _, module in pairs(prototypes.get_item_filtered{{filter="type",type="module"}}) do
		if beacons.module_allowed(drill,module) then filters[#filters+1]={filter="name",name=module.name,mode="or"} end
	end
	create_setting_selector(player_data, player_data.gui.tables.module, "mpp_action", "module", {
		{action=is_oil and "mpp_oil_module" or "mpp_prototype", value="module", type="choose-elem-button", elem_type="item-with-quality",
			elem_filters=filters, elem_value=value, icon="mpp_setting_module_disabled", tooltip=tooltip},
	})
	create_quality_selector(data,player_data.gui.tables.module_quality,is_oil and "mpp_oil_choice" or "mpp_action",
		"module_quality",mpp_util.quality_list())
end

local function update_beacon_selection(player_data)
	local is_oil=player_data.choices.layout_choice=="oil"
	local data=is_oil and oil_config.get(player_data) or player_data
	local choices=data.choices
	choices.beacon_choice=choices.beacon_choice or "none"
	choices.beacon_quality_choice=choices.beacon_quality_choice or "normal"
	choices.beacon_module_choice=choices.beacon_module_choice or "speed-module-3"
	choices.beacon_module_quality_choice=choices.beacon_module_quality_choice or "normal"
	local values={}
	local available=false
	for _,proto in ipairs(oil_config.get_section("beacon").values) do
		values[#values+1]={value=proto.name,icon="entity/"..proto.name,
			tooltip=mpp_util.entity_name_with_quality(proto.localised_name,choices.beacon_quality_choice)}
		if proto.name==choices.beacon_choice then available=true end
	end
	if not available then choices.beacon_choice="none" end
	local drill=prototypes.entity[player_data.choices.miner_choice]
	local supported=is_oil or (algorithm.get_mining_layout(player_data).restrictions.beacon_available
		and drill~=nil and not (drill.effect_receiver and not drill.effect_receiver.uses_beacon_effects)
	)
	player_data.gui.section.beacon.visible=supported
	player_data.gui.beacon_group.visible=supported
	player_data.gui.section.beacon.section_label.tooltip=is_oil and {"mpp-oil.settings_beacon_utility_tooltip"} or mpp_util.wrap_tooltip{"mpp.choice_beacon"}
	create_setting_selector(data,player_data.gui.tables.beacon,is_oil and "mpp_oil_choice" or "mpp_action","beacon",values,
		{shown_quality=choices.beacon_quality_choice, optional=true})
	create_quality_selector(data,player_data.gui.tables.beacon_quality,is_oil and "mpp_oil_choice" or "mpp_action","beacon_quality",
		mpp_util.quality_list(),{style_func=style_helper_quality,alternate_visibility=true})
	local proto=prototypes.entity[choices.beacon_choice]
	local density=player_data.gui.beacon_density
	if density and density.valid then density.destroy();player_data.gui.beacon_density=nil end
	local arrangement=player_data.gui.beacon_arrangement
	if not arrangement or not arrangement.valid then
		arrangement=player_data.gui.beacon_group.add{type="label",caption={"mpp.beacon_rows"},
			tooltip=mpp_util.wrap_tooltip{"mpp.choice_beacon"}}
		player_data.gui.beacon_arrangement=arrangement
	end
	arrangement.visible=not is_oil and supported and proto~=nil
	player_data.gui.beacon_utility.visible=is_oil and proto~=nil
	local filters={}
	if proto then
		for _,item in pairs(prototypes.get_item_filtered{{filter="type",type="module"}}) do
			if beacons.module_allowed(proto,item) then filters[#filters+1]={filter="name",name=item.name,mode="or"} end
		end
	end
	table.sort(filters,function(a,b) return a.name<b.name end)
	local item=prototypes.item[choices.beacon_module_choice]
	if proto and item and not beacons.module_allowed(proto,item) then choices.beacon_module_choice="none";item=nil end
	local value=item and {name=item.name,quality=choices.beacon_module_quality_choice} or nil
	player_data.gui.section.beacon_module.visible=supported and proto~=nil and #filters>0
	create_setting_selector(player_data,player_data.gui.tables.beacon_module,"mpp_action","beacon_module",{
		{action=is_oil and "mpp_oil_module" or "mpp_prototype",value="beacon_module",type="choose-elem-button",elem_type="item-with-quality",
			elem_filters=filters,elem_value=value,icon="mpp_setting_module_disabled",
			tooltip={"",{"mpp.choice_beacon_module"},"\n",{"mpp.label_right_click_to_clear"}}},
	})
	create_quality_selector(data,player_data.gui.tables.beacon_module_quality,is_oil and "mpp_oil_choice" or "mpp_action",
		"beacon_module_quality",mpp_util.quality_list())
end

local function update_misc_selection(player)
	local player_data = storage.players[player.index]
	local choices = player_data.choices
	local layout = algorithm.get_mining_layout(player_data)
	local values = List() --[[@as List<SettingValueEntry>]]

	values:push{
		value="ore_filtering",
		tooltip={"mpp.choice_ore_filtering"},
		icon=setting_toggle_icon("ore_filtering"),
		icon_enabled=setting_toggle_icon("ore_filtering", true),
	}

	values:push{
		action="mpp_terrain_mode", value="cliff_mode", selected=true,
		caption={"mpp.icon_cliff_mode_"..choices.cliff_mode_choice},
		tooltip={"mpp.choice_cliff_mode_"..choices.cliff_mode_choice},
		icon=setting_toggle_icon("avoid_cliffs", choices.cliff_mode_choice=="avoid"),
	}

	values:push{
		action="mpp_terrain_mode", value="terrain_mode", selected=true,
		caption_width=76,
		caption={"mpp.icon_terrain_mode_"..choices.terrain_mode_choice},
		tooltip={"mpp.choice_terrain_mode_"..choices.terrain_mode_choice},
		icon=setting_toggle_icon("avoid_water", choices.terrain_mode_choice=="avoid"),
	}

	if layout.restrictions.belt_merging_available then
		values:push{
			value="belt_merge",
			icon_enabled=setting_toggle_icon("belt_merge", true),
			icon=setting_toggle_icon("belt_merge"),
			tooltip={"mpp.choice_merge_belts"},
		}
	end


	if layout.restrictions.lamp_available then
		values:push{
			value="lamp",
			tooltip={"mpp.choice_lamp"},
			icon=setting_toggle_icon("lamp"),
			icon_enabled=setting_toggle_icon("lamp", true),
		}
	end
	

	if layout.restrictions.deconstruction_omit_available then
		values:push{
			value="deconstruction",
			tooltip={"mpp.choice_deconstruction"},
			icon=setting_toggle_icon("deconstruction"),
			icon_enabled=setting_toggle_icon("deconstruction", true),
		}
	end

	if compatibility.is_space(player.surface_index) and layout.restrictions.landfill_omit_available then
		local existing_choice = choices.space_landfill_choice
		if not prototypes.tile[existing_choice] then
			existing_choice = "se-space-platform-scaffold"
			choices.space_landfill_choice = existing_choice
		end

		values:push{
			action="mpp_prototype",
			value="space_landfill",
			icon=("item/"..existing_choice),
			elem_type="item",
			elem_filters={
				{filter="name", name="se-space-platform-scaffold"},
				{filter="name", name="se-space-platform-plating", mode="or"},
				{filter="name", name="se-spaceship-floor", mode="or"},
			},
			elem_value = choices.space_landfill_choice,
			type="choose-elem-button",
		}
	end

	if layout.restrictions.coverage_tuning then
		values:push{
			value="coverage",
			tooltip={"mpp.choice_coverage"},
			icon=setting_toggle_icon("coverage"),
			icon_enabled=setting_toggle_icon("coverage", true),
		}
	end

	if layout.restrictions.start_alignment_tuning then
		values:push{
			value="start",
			tooltip={"mpp.choice_start"},
			icon=setting_toggle_icon("start"),
			icon_enabled=setting_toggle_icon("start", true),
		}
	end

	if layout.restrictions.placement_info_available or layout.restrictions.lane_filling_info_available then
		values:push{
			value="statistics",
			tooltip={"mpp.choice_statistics"},
			icon=setting_toggle_icon("print_placement_info"),
			icon_enabled=setting_toggle_icon("print_placement_info", true),
		}
	end

	if layout.restrictions.pipe_available then
		values:push{
			value="force_pipe_placement",
			tooltip={"mpp.choice_force_pipe_placement"},
			icon=setting_toggle_icon("force_pipe_placement"),
			icon_enabled=setting_toggle_icon("force_pipe_placement", true),
		}
	end

	if player_data.advanced and false then
		values:push{
			value="dumb_power_connectivity",
			tooltip={"mpp.dumb_power_connectivity"},
			icon=("entity/medium-power-pole"),
		}
	end

	local groups = {misc=List(), terrain=List(), power=List()}
	for _, value in ipairs(values) do
		if value.value=="cliff_mode" or value.value=="terrain_mode" or value.value=="deconstruction" or value.value=="space_landfill" then
			groups.terrain:push(value)
		elseif value.value=="lamp" then groups.power:push(value)
		elseif choices.layout_choice~="oil" then groups.misc:push(value) end
	end
	player_data.gui.section.misc.visible = #groups.misc>0
	player_data.gui.power_options.visible = choices.layout_choice~="oil" and #groups.power>0
	local selections = {}
	for _, group in ipairs{"misc", "terrain", "power"} do
		local root = group=="power" and player_data.gui.power_options or player_data.gui.tables[group]
		create_setting_selector(player_data, root, "mpp_toggle", "misc", groups[group])
		for key, button in pairs(player_data.gui.selections.misc) do selections[key]=button end
	end
	player_data.gui.selections.misc = selections
end

---@param player_data PlayerData
local function update_blueprint_selection(player_data)
	local choices = player_data.choices
	local player_blueprints = player_data.blueprints
	player_data.gui.section["blueprints"].visible = algorithm.get_mining_layout(player_data).name == "blueprints"
	player_data.gui["blueprint_add_section"].visible = player_data.blueprint_add_mode
	player_data.gui["blueprint_add_button"].style = style_helper_blueprint_toggle(player_data.blueprint_add_mode)
	player_data.gui["blueprint_add_button"].sprite = setting_toggle_icon("blueprint_add", player_data.blueprint_add_mode)

	for key, value in pairs(player_blueprints.delete) do
		value.visible = player_data.blueprint_add_mode
	end
end

local function update_debugging_selection(player_data)

	local is_debugging = not not debugadapter
	player_data.gui.section["debugging"].visible = is_debugging
	if not is_debugging then
		return
	end

	---@type SettingValueEntry[]
	local values = {
		{
			value="draw_clear_rendering",
			tooltip="Clear rendering",
			icon=("mpp_no_entity"),
		},
		{
			value="draw_drill_struct",
			tooltip="Draw drill struct overlay",
			icon=("entity/electric-mining-drill"),
		},
		{
			value="draw_raw_drill_struct",
			tooltip="Draw drill struct overlay",
			icon=("entity/electric-mining-drill"),
		},
		{
			value="draw_pole_layout_simple",
			tooltip="Draw power pole layout",
			icon=("entity/medium-electric-pole"),
		},
		{
			value="draw_pole_layout_interleaved",
			tooltip="Draw power pole layout compact",
			icon=("entity/medium-electric-pole"),
		},
		{
			value="draw_built_things",
			tooltip="Draw built tile values",
			icon=("mpp_print_placement_info_enabled"),
		},
		{
			value="draw_drill_convolution",
			tooltip="Draw a drill convolution preview",
			icon=("mpp_debugging_grid_convolution"),
		},
		{
			value="draw_power_grid",
			tooltip="Draw power grid connectivity",
			icon=("entity/substation"),
		},
		{
			value="draw_pole_joiner",
			tooltip="Draw power pole joiner",
			icon=("entity/substation"),
		},
		{
			value="draw_centricity",
			tooltip="Draw layout centricity",
			icon=("mpp_plus"),
		},
		{
			value="draw_blueprint_data",
			tooltip="Draw blueprint entities",
			icon=("item/blueprint"),
		},
		{
			value="draw_deconstruct_preview",
			tooltip="Draw deconstruct preview",
			icon=("item/deconstruction-planner"),
		},
		{
			value="draw_can_place_entity",
			tooltip="Draw entity placement checks",
			icon=("item/blueprint"),
		},
		{
			value="draw_inserter_rotation_preview",
			tooltip="Draw inserter rotation preview",
			icon=("item/inserter"),
		},
		{
			value="draw_cliff_collisions",
			tooltip="Draw cliff collisions (area select)",
			icon=("entity/cliff"),
		},
		{
			value="draw_consumed_resources",
			tooltip="Draw consumed resource tiles",
			icon=("entity/copper-ore"),
		},
		{
			value="draw_belt_specification",
			tooltip="Draw belt specification",
			icon=("item/transport-belt"),
		}
	}

	local debugging_section = player_data.gui.section["debugging"]
	debugging_section.visible = #values > 0

	local table_root = player_data.gui.tables["debugging"]
	create_setting_selector(player_data, table_root, "mpp_action", "debugging", values)
end

---@param player_data PlayerData
local function update_quality_sections(player_data)
	local quality_enabled = script.feature_flags.quality
	player_data.gui.tables["miner_quality"].visible = quality_enabled and player_data.choices.layout_choice~="oil"
		and algorithm.get_mining_layout(player_data).restrictions.miner_available
	player_data.gui.tables.oil_extractor_quality.visible=quality_enabled and player_data.choices.layout_choice=="oil"
	for _, name in ipairs{"pole", "beacon", "logistics", "module", "beacon_module"} do
		player_data.gui.tables[name.."_quality"].visible = quality_enabled
	end
end

---@param player LuaPlayer
local function update_oil_selection(player)
	local player_data = storage.players[player.index]
	local root = player_data.gui.oil_settings_root
	if not root or not root.valid then return end
	oil_gui.update(player, player_data, root, {
		entities=create_setting_selector,
	})
	local data=oil_config.get(player_data)
	local section=oil_config.get_extractor_section(player_data)
	if section then
		local qualities={}
		for _,quality in ipairs(mpp_util.quality_list()) do
			if player.force.is_quality_unlocked(quality.value) then qualities[#qualities+1]=quality end
		end
		create_quality_selector(data,player_data.gui.tables.oil_extractor_quality,"mpp_oil_choice",
			section.name.."_quality",qualities,{style_func=style_helper_quality,alternate_visibility=true})
	end
end

local function update_selections(player)
	---@type PlayerData
	local player_data = storage.players[player.index]
	player_data.gui.quality_selectors = {}
	oil_config.get(player_data)
	local is_oil=player_data.choices.layout_choice=="oil"
	player_data.gui.mining_settings_root.visible=not is_oil
	player_data.gui.mining_transport_root.visible=not is_oil
	player_data.gui.oil_heat_root.visible=is_oil
	player_data.gui.power_options.visible=not is_oil
	player_data.gui.section.miner.section_label.caption={"mpp.settings_miner_mode_label", {is_oil and "mpp.mode_oil" or "mpp.mode_mining"}}
	player_data.gui.oil_settings_root.visible=is_oil
	update_direction_section(player_data)
	player_data.gui.section.direction.visible = true
	if player_data.gui.layout_dropdown.valid then
		for index, name in ipairs(player_data.gui.layout_values) do
			if name == algorithm.get_mining_layout(player_data).name then
				player_data.gui.layout_dropdown.selected_index = index
				break
			end
		end
	end
	player_data.gui.blueprint_add_button.visible = algorithm.get_mining_layout(player_data).name == "blueprints"
	mpp_util.update_undo_button(player_data)
	update_miner_selection(player)
	update_belt_selection(player)
	update_space_belt_selection(player)
	update_logistics_selection(player_data)
	update_pole_selection(player_data)
	update_pipe_selection(player_data)
	update_oil_selection(player)
	update_module_selection(player_data)
	update_beacon_selection(player_data)
	update_blueprint_selection(player_data)
	update_misc_selection(player)
	update_debugging_selection(player_data)
	update_quality_sections(player_data)
	preview.update_gui(player_data)
end

function gui.update_quality_sections(player_data)
	local root = player_data.gui.tables.miner
	if root and root.valid then
		local player = game.get_player(root.player_index)
		if player_data.gui.workflow_version ~= workflow_version then gui.show_interface(player)
		else update_selections(player) end
	end
end

function gui.update_oil_settings(player)
	local data = storage.players[player.index]
	local root = data.gui.oil_settings_root
	if root and root.valid then
		if data.gui.workflow_version ~= workflow_version then gui.show_interface(player)
		else update_selections(player) end
	end
end

---@param player LuaPlayer
function gui.show_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen["mpp_settings_frame"]
	local player_data = storage.players[player.index]
	conf.migrate_statistics_choice(player_data.choices)
	conf.migrate_terrain_choices(player_data.choices)
	player_data.blueprint_add_mode = false
	player_data.entity_filtering_mode = false
	if frame and player_data.gui.workflow_version ~= workflow_version then
		for name, status in pairs(player_data.filtered_entities) do
			if status == "user_hidden" then player_data.filtered_entities[name] = nil end
		end
		frame.destroy()
		frame = nil
	end
	if frame then
		frame.visible = true
	else
		gui.create_interface(player)
	end
	update_selections(player)
end

---@param player LuaPlayer
local function abort_blueprint_mode(player)
	local player_data = storage.players[player.index]
	if not player_data.blueprint_add_mode then return end
	player_data.blueprint_add_mode = false
	update_blueprint_selection(player_data)
	local cursor_stack = player.cursor_stack
	if cursor_stack == nil then return end
	player.clear_cursor()
	input_mode.reconcile(player_data, player)
end

---@param player LuaPlayer
function gui.hide_interface(player)
	---@type LuaGuiElement
	local frame = player.gui.screen["mpp_settings_frame"]
	local player_data = storage.players[player.index]
	player_data.blueprint_add_mode = false
	input_mode.idle(player_data, player)
	if frame then
		frame.visible = false
	end
end

-- TODO: refactor this into handlers

---@param event EventDataGuiClick
local function on_gui_click(event)
	local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
	---@type PlayerData
	local player_data = storage.players[event.player_index]
	local evt_ele_tags = event.element.tags
	local ours=false
	for key in pairs(evt_ele_tags) do
		if type(key)=="string" and key:sub(1,4)=="mpp_" then ours=true; break end
	end
	if not ours then return end
	if evt_ele_tags.mpp_drop_down then return end
	if player_data.preview and player_data.preview.applying then return end
	if evt_ele_tags.mpp_input_mode then
		abort_blueprint_mode(player)
		local mode = evt_ele_tags.mpp_input_mode
		if player_data.input_mode == mode or event.button == defines.mouse_button_type.right then
			input_mode.idle(player_data, player)
		elseif mode == "select" then input_mode.select(player_data, player)
		elseif player_data.preview then preview.give_belt_planner(player_data)
		else input_mode.output(player_data, player) end
		return
	end
	if evt_ele_tags.mpp_preview_apply then preview.apply(player_data); return end
	if evt_ele_tags.mpp_preview_cancel then preview.cancel(player_data); return end
	if evt_ele_tags.mpp_quality then
		abort_blueprint_mode(player)
		local action, value = evt_ele_tags.mpp_quality, evt_ele_tags.value
		if not event.element.enabled or not prototypes.quality[value] or not player.force.is_quality_unlocked(value) then return end
		local data = evt_ele_tags.mpp_oil_quality and oil_config.get(player_data) or player_data
		data.choices[action.."_choice"] = value
		if evt_ele_tags.mpp_oil_quality then data.qualities[action:sub(1,-9)] = value end
		update_selections(player)
		preview.request(player_data)
		return
	end
	if evt_ele_tags.mpp_oil_extractor then
		local data=oil_config.get(player_data)
		local section=oil_config.get_extractor_section(player_data)
		if section then data.choices[section.name.."_choice"]=evt_ele_tags.value end
		player_data.choices.layout_choice="oil"
		algorithm.clear_selection(player_data)
		update_selections(player)
		preview.request(player_data)
		return
	end
	if evt_ele_tags.mpp_mode then
		player_data.choices.layout_choice=evt_ele_tags.value=="oil" and "oil" or algorithm.get_mining_layout(player_data).name
		algorithm.clear_selection(player_data)
		update_selections(player)
		preview.request(player_data)
		return
	end
	if evt_ele_tags.mpp_oil_choice then
		abort_blueprint_mode(player)
		oil_gui.on_click(event, player_data)
		algorithm.clear_selection(player_data)
		update_selections(player)
		preview.request(player_data)
		return
	end
	if evt_ele_tags["mpp_action"] then
		abort_blueprint_mode(player)

		local action = evt_ele_tags["mpp_action"]
		local value = evt_ele_tags["value"]
		local choice = action.."_choice"
		local last_value = player_data.choices[choice]
		local entity = action..":"..value

		if choice == "miner_choice" or choice == "blueprint_choice" then
			algorithm.clear_selection(player_data)
		end

		if player_data.gui.selections[action][last_value] then
			player_data.gui.selections[action][last_value].style = style_helper_selection(false)
		end

		player_data.filtered_entities[entity] = false
		local disabled = evt_ele_tags.mpp_optional and (last_value == value or event.button == defines.mouse_button_type.right)
		player_data.choices[choice] = disabled and "none" or value
		if action=="miner" then algorithm.select_miner(player_data,value) end
		update_selections(player)
	elseif evt_ele_tags["mpp_terrain_mode"] then
		abort_blueprint_mode(player)
		local value = evt_ele_tags.value
		local key = value.."_choice"
		local other = value == "cliff_mode" and "remove" or "fill"
		player_data.choices[key] = player_data.choices[key] == "avoid" and other or "avoid"
		update_selections(player)
	elseif evt_ele_tags["mpp_toggle"] then
		abort_blueprint_mode(player)
		
		local action = evt_ele_tags["mpp_toggle"]
		local value = evt_ele_tags["value"]
		local last_value = player_data.choices[value.."_choice"]

		if evt_ele_tags.mpp_icon_enabled then
			if not last_value then
				event.element.sprite = evt_ele_tags.mpp_icon_enabled --[[@as string]]
			else
				event.element.sprite = evt_ele_tags.mpp_icon_default --[[@as string]]
			end
		end

		player_data.choices[value.."_choice"] = not last_value
		event.element.style = style_helper_selection(not last_value)
		if value == "statistics" and player_data.last_state then
			for _, object in pairs(player_data.last_state._render_objects or {}) do
				if object.valid and object.only_in_alt_mode then object.visible = not last_value end
			end
		end
		if evt_ele_tags.refresh then update_selections(player) end
	elseif evt_ele_tags["mpp_blueprint_add_mode"] then
		player_data.blueprint_add_mode = not player_data.blueprint_add_mode
		input_mode.idle(player_data, player)
		player.clear_cursor()
		player_data.gui["blueprint_add_section"].visible = player_data.blueprint_add_mode
		player_data.gui["blueprint_add_button"].style = style_helper_blueprint_toggle(player_data.blueprint_add_mode)
		player_data.gui["blueprint_add_button"].sprite = setting_toggle_icon("blueprint_add", player_data.blueprint_add_mode)
		update_blueprint_selection(player_data)
	elseif evt_ele_tags["mpp_blueprint_receptacle"] then
		local cursor_stack = player.cursor_stack
		if (
			not cursor_stack or
			not cursor_stack.valid or
			not cursor_stack.valid_for_read or
			not cursor_stack.is_blueprint
		) then
			if cursor_stack and not cursor_stack.is_blueprint then
				player.print({"mpp.msg_blueprint_valid"})
			end
			return nil
		elseif not mpp_util.validate_blueprint(player, cursor_stack) then
			return nil
		end

		local player_blueprints = player_data.blueprint_items
		local pending_slot = player_blueprints.find_empty_stack()
		
		---@param bp LuaItemStack
		local function check_existing(bp)
			for k, v in pairs(player_data.blueprints.original_id) do
				if v == bp.item_number then return true end
			end
		end
		if check_existing(cursor_stack) then
			player.print({"mpp.msg_blueprint_existing"})
			return nil
		end

		if pending_slot == nil then
			player_blueprints.resize(#player_blueprints+1--[[@as uint16]])
			pending_slot = player_blueprints.find_empty_stack()
		end
		
		if pending_slot then
			pending_slot.set_stack(cursor_stack)
			local blueprint_table = player_data.gui.tables["blueprints"]
			create_blueprint_entry(player_data, blueprint_table, pending_slot, cursor_stack)
		else
			player.print({"mpp.msg_blueprint_fatal_error"}, {r=1,g=0,b=0})
		end

	elseif evt_ele_tags["mpp_fake_blueprint_button"] then
		local button = event.element
		if button.style.name ~= "mpp_fake_blueprint_button_invalid" then
			set_player_blueprint(player_data, button)
			abort_blueprint_mode(player)
		end
	elseif evt_ele_tags["mpp_delete_blueprint_button"] then
		local choices = player_data.choices
		local deleted_number = evt_ele_tags["mpp_delete_blueprint_button"]
		local player_blueprints = player_data.blueprints
		if choices.blueprint_choice and choices.blueprint_choice.item_number == deleted_number then
			choices.blueprint_choice = nil
		end
		player_blueprints.mapping[deleted_number].clear()
		player_blueprints.flow[deleted_number].destroy()

		player_blueprints.mapping[deleted_number] = nil
		player_blueprints.flow[deleted_number] = nil
		player_blueprints.button[deleted_number] = nil
		player_blueprints.delete[deleted_number] = nil
		player_blueprints.cache[deleted_number] = nil
		player_blueprints.original_id[deleted_number] = nil
	elseif evt_ele_tags["mpp_undo"] then
		if player_data.preview then preview.cancel(player_data); return end
		local state = player_data.last_state
		if not state then return end
		input_mode.idle(player_data, player)
		algorithm.cleanup_last_state(player_data)
		preview.update_gui(player_data)
		return
	end
	preview.request(player_data)
end
script.on_event(defines.events.on_gui_click, on_gui_click)

---@param event EventDataGuiSelectionStateChanged
local function on_gui_selection_state_changed(event)
	local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
	local element = event.element
	local evt_ele_tags = element.tags
	if evt_ele_tags["mpp_drop_down"] == nil then return end
	local action = evt_ele_tags["mpp_drop_down"]
	local value_map = evt_ele_tags["mpp_value_map"]
	
	abort_blueprint_mode(player)
	---@type PlayerData
	local player_data = storage.players[event.player_index]
	if player_data.preview and player_data.preview.applying then return end

	local value
	if value_map == "layout" then
		value = player_data.gui.layout_values[element.selected_index]
	elseif value_map == "beacon_density" then
		value = beacons.density_values[element.selected_index]
	else
		return
	end
	if action == "layout" then
		player_data.choices.mining_layout_choice = value
		if player_data.choices.layout_choice ~= "oil" then player_data.choices.layout_choice = value end
		algorithm.clear_selection(player_data)
	else
		player_data.choices[action.."_choice"] = value
	end
	update_selections(player)
	preview.request(player_data)
end
script.on_event(defines.events.on_gui_selection_state_changed, on_gui_selection_state_changed)

---@param event EventData.on_gui_elem_changed
local function on_gui_elem_changed(event)
	local element = event.element
	local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
	---@type PlayerData
	local player_data = storage.players[event.player_index]
	if player_data.preview and player_data.preview.applying then return end
	local evt_ele_tags = element.tags
	if evt_ele_tags.mpp_oil_module then
		local choices = oil_config.get(player_data).choices
		local action = evt_ele_tags.value
		local value = element.elem_value
		choices[action.."_choice"] = value and value.name or "none"
		choices[action.."_quality_choice"] = value and value.quality or "normal"
		update_selections(player)
		preview.request(player_data)
	elseif evt_ele_tags["mpp_prototype"] then
		local action = evt_ele_tags.value
		local old_choice = player_data.choices[action.."_choice"]
		local old_quality_choice = player_data.choices[action.."_choice"]
		local elem_value = element.elem_value
		if type(elem_value) == "string" then
			element.children[1].visible = false
			player_data.choices[action.."_choice"] = elem_value or "none"
		elseif elem_value then
			local choice = elem_value.name
			local quality_choice = element.elem_value.quality
			element.children[1].visible = false
			player_data.choices[action.."_choice"] = choice or "none"
			player_data.choices[action.."_quality_choice"] = quality_choice or "normal"
		else
			element.children[1].visible = true
			player_data.choices[action.."_choice"] = "none"
			player_data.choices[action.."_quality_choice"] = "normal"
		end
		update_selections(player)
		preview.request(player_data)
	end
end

script.on_event(defines.events.on_gui_elem_changed, on_gui_elem_changed)

script.on_event(defines.events.on_gui_text_changed, function(event)
	local data = storage.players[event.player_index]
	if data and event.element.tags.mpp_oil_utility and not (data.preview and data.preview.applying) then
		if oil_gui.on_text_changed(event, data) then preview.request(data)
		else preview.invalidate(data,{"mpp.preview_invalid_utility"}) end
	end
end)

return gui
