local graphics = "__mining-patch-planner__/graphics/"

data:extend{
	{
		type="selection-tool",
		name="mining-patch-planner",
		icon=graphics.."drill-icon.png",
		icon_size = 64,
		flags = {"only-in-cursor", "spawnable", "not-stackable"},
		-- hidden_in_factoriopedia = true,
		hidden = true,
		stack_size = 1,
		order="c[automated-construction]-e[miner-planner]",
		draw_label_for_cursor_render = false,
		-- selection_cursor_box_type="entity",
		select = {
			border_color = {r=100/255, g=149/255, b=237/255, a=1},
			cursor_box_type = "entity",
			mode = "any-entity",
			entity_filter_mode = "whitelist",
			entity_type_filters = {"resource"},
			tile_filter_mode = "whitelist",
			tile_filters = {"water-wube"},
		},
		alt_select = {
			border_color = {r=237/255, g=149/255, b=100/255, a=1},
			cursor_box_type = "entity",
			mode = "any-entity",
			entity_filter_mode = "whitelist",
			entity_type_filters = {"resource"},
			tile_filter_mode = "whitelist",
			tile_filters = {"water-wube"},
		}
		-- selection_mode={"any-entity"},
		-- entity_filter_mode="whitelist",
		-- entity_type_filters = {"resource"},
		-- tile_filter_mode = "whitelist",
		-- tile_filters = {"water-wube"},
		-- alt_selection_color = {r=0, g=1, b=0, a=1},
		-- alt_selection_cursor_box_type="entity",
		-- alt_selection_mode={"any-entity"},
		-- alt_tile_filter_mode = "whitelist",
		-- alt_tile_filters = {"water-wube"},
		-- alt_entity_filter_mode="whitelist",
		-- alt_entity_type_filters = {"resource"},
		-- reverse_selection_mode={"any-entity"},
		-- reverse_selection_cursor_box_type="pair",
		-- reverse_entity_filter_mode="whitelist",
		-- reverse_entity_type_filters = {"resource"},
		-- reverse_tile_filters = {"water-wube" },
	},
	{
		type="custom-input",
		name="mining-patch-planner-keybind",
		key_sequence="CONTROL + M",
		action="lua",
	},
	{
		type="custom-input",
		name="mining-patch-planner-keybind-rotate",
		key_sequence="",
		linked_game_control="rotate",
		action="lua",
		include_selected_prototype = true,
	},
	{
		type="custom-input",
		name="mining-patch-planner-keybind-rotate-reversed",
		key_sequence="",
		linked_game_control="reverse-rotate",
		action="lua",
		include_selected_prototype = true,
	},
	{
		type="custom-input",
		name="mining-patch-planner-keybind-flip-horizontal",
		key_sequence="",
		linked_game_control="flip-horizontal",
		action="lua",
	},
	{
		type="custom-input",
		name="mining-patch-planner-keybind-flip-vertical",
		key_sequence="",
		linked_game_control="flip-vertical",
		action="lua",
	},
	{
		type="shortcut",
		name="mining-patch-planner-shortcut",
		icon = graphics.."drill-icon-toolbar.png",
		small_icon = graphics.."drill-icon-toolbar-small.png",
		order="b[blueprints]-i[miner-planner]",
		action = "lua",
		icon_size = 56,
		small_icon_size = 24,
		style="blue",
		associated_control_input="mining-patch-planner-keybind",
	},
}

local mpp_blueprint = table.deepcopy(data.raw["blueprint"]["blueprint"]) --[[@as data.BlueprintItemPrototype]]

mpp_blueprint.name = "mpp-blueprint-belt-planner"
mpp_blueprint.localised_name = {"mpp.belt_planner_name"}
mpp_blueprint.localised_description = {"mpp.belt_planner_description"}
mpp_blueprint.hidden = true
mpp_blueprint.hidden_in_factoriopedia = true
mpp_blueprint.auto_recycle = false
mpp_blueprint.flags = mpp_blueprint.flags or {}
table.insert(mpp_blueprint.flags, "only-in-cursor")

data.extend{mpp_blueprint}

local belt_target = table.deepcopy(data.raw["selection-tool"]["mining-patch-planner"])
belt_target.name = "mpp-belt-planner"
belt_target.localised_name = {"mpp.belt_planner_name"}
belt_target.localised_description = {"mpp.belt_planner_description"}
belt_target.icons = {{icon="__base__/graphics/icons/transport-belt.png", icon_size=64}}
belt_target.icon = nil
belt_target.select = {border_color={0.4,0.7,1}, cursor_box_type="pair", mode="any-tile"}
belt_target.alt_select = table.deepcopy(belt_target.select)
data:extend{belt_target}
