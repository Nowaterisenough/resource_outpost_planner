local graphics = "__mining-patch-planner__/graphics/"

-- Columns follow render-settings-icons.py. Native backgrounds indicate selection.
local names = {
	"ore_filtering", "avoid_water", "avoid_cliffs", "belt_planner", "belt_merge",
	"module", "lamp", "pipe", "deconstruction", "landfill", "coverage", "start",
	"print_placement_info", "display_lane_filling", "force_pipe_placement",
	"advanced", "quality", "entity_filtering", "undo", "blueprint_add",
	"avoid_obstacles",
}

local sprites = {}
for column, name in ipairs(names) do
	for _, suffix in ipairs{"_disabled", "_enabled", ""} do
		sprites[#sprites + 1] = {
			type = "sprite",
			name = "mpp_setting_"..name..suffix,
			filename = graphics.."settings-icons.png",
			size = 64,
			x = (column - 1) * 64,
			y = 0,
			mipmap_count = 0,
			flags = {"icon"},
		}
	end
end

data:extend(sprites)
