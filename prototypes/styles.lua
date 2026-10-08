
local default_style = data.raw["gui-style"].default

default_style.mpp_preview_status = {
	type="label_style",parent="label",single_line=false,
	maximal_width=260,font_color={0.82,0.82,0.82},
}

default_style.mpp_preview_hint = {
	type="label_style",parent="label",font="default-small",single_line=false,
	maximal_width=260,font_color={0.65,0.65,0.65},
}

default_style.mpp_settings_columns = {
	type="horizontal_flow_style", parent="horizontal_flow", horizontal_spacing=12,
}

default_style.mpp_settings_column = {
	type="vertical_flow_style", parent="vertical_flow", natural_width=260,
}

default_style.mpp_auto_resource_label = {
	type="label_style", parent="label", font="default-small",
	font_color={0.72,0.72,0.72}, bottom_margin=8,
}

default_style.mpp_setting_cell = {
	type = "vertical_flow_style",
	parent = "vertical_flow",
	vertical_spacing = 1,
	horizontal_align = "center",
	natural_width = 40,
}

default_style.mpp_setting_caption = {
	type = "label_style",
	parent = "label",
	single_line = false,
	font = "default-small",
	font_color = {0.82, 0.82, 0.82},
	horizontal_align = "center",
	minimal_width = 40,
	maximal_width = 40,
	minimal_height = 40,
	maximal_height = 40,
}

--- taken from flib
default_style.mpp_selected_frame_action_button = {
	type = "button_style",
	parent = "frame_action_button",
	default_graphical_set = {
		base = {position = {225, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	hovered_graphical_set = {
		base = {position = {369, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	clicked_graphical_set = {
		base = {position = {352, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	}
}

default_style.mpp_blueprint_mode_button = {
	type = "button_style",
	parent = "slot_button",
	size = 28,
}

default_style.mpp_tool_button_active = table.deepcopy(default_style.mpp_selected_frame_action_button)
default_style.mpp_tool_button_active.parent = "button"

default_style.mpp_blueprint_mode_button_active = {
	type = "button_style",
	parent = "slot_button",
	size = 28,
	default_graphical_set = {
		base = {position = {225, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	hovered_graphical_set = {
		base = {position = {369, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	clicked_graphical_set = {
		base = {position = {352, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	}
}

default_style.mpp_quality_table = {
	type = "table_style",
	parent = "filter_slot_table",
	-- top_padding = 4,
	column_widths = {width=24},
}
default_style.mpp_button_quality = {
	type = "button_style",
	parent = "slot_button",
	size = 24,
}
default_style.mpp_button_quality_active = {
	type = "button_style",
	parent = "yellow_slot_button",
	size = 24,
}
default_style.mpp_button_quality_hidden = {
	type = "button_style",
	parent = "red_slot_button",
	size = 24,
}
default_style.mpp_quality_badge = {
	type = "image_style",
	size = 14,
}

default_style.mpp_fake_item_placeholder = {
	type="image_style",
	stretch_image_to_widget_size = true,
	size=32,
}

default_style.mpp_fake_item_placeholder_blueprint = {
	type="image_style",
	stretch_image_to_widget_size = true,
	left_margin=4,
	top_margin=4,
	size=32,
}

default_style.mpp_fake_blueprint_button = {
	type="button_style",
	parent="shortcut_bar_button_blue",
	padding=3,
	size=48,
}
default_style.mpp_delete_blueprint_button = {
	type="button_style",
	parent="shortcut_bar_button_red",
	padding=0,
	size=24,
}

default_style.mpp_fake_blueprint_button_selected = {
	type="button_style",
	parent="shortcut_bar_button_blue",
	padding=3,
	size=48,
	default_graphical_set = {
		base = {position = {225, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	hovered_graphical_set = {
		base = {position = {369, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	},
	clicked_graphical_set = {
		base = {position = {352, 17}, corner_size = 8},
		shadow = {position = {440, 24}, corner_size = 8, draw_type = "outer"},
	}
}

default_style.mpp_fake_blueprint_button_invalid = {
	type="button_style",
	parent="shortcut_bar_button_red",
	padding=3,
	size=48,
}

default_style.mpp_fake_blueprint_table = {
	type="table_style",
	padding=0,
	cell_padding=0,
	horizontal_spacing=2,
	vertical_spacing=2,
}

default_style.mpp_quality_dropdown = {
	type = "dropdown_style",
	parent = "dropdown",
	maximal_width = 240,
	default_font_color = {1, 1, 1},
}

default_style.mpp_fake_blueprint_sprite = {
	type="image_style",
	size=16,
	stretch_image_to_widget_size=true,
}

default_style.mpp_filtered_entity = {
	type="image_style",
	size=32,
	stretch_image_to_widget_size=true,
}

default_style.mpp_section = {
	type="vertical_flow_style",
	parent="vertical_flow",
	natural_width=240,
}

default_style.mpp_label_warning_style = {
	type = "label_style",
	font_color = {1, 1, 0},
	single_line = false,
	horizontally_squashable = "on",
	horizontally_stretchable = "on",
}
