local direction = defines.direction
local mpp_util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local EAST, NORTH, SOUTH, WEST, ROTATION = mpp_util.directions()
local coord_revert_world = mpp_util.revert_world
local builder = {}

local quality_enabled = script.feature_flags.quality
local directional = {}

function builder.record_preview(state, spec)
	if spec.name == "entity-ghost" then
		local proto = prototypes.entity[spec.inner_name]
		if directional[proto.name]==nil then
			local ok,value=pcall(function() return proto.supports_direction end)
			if ok then directional[proto.name]=value==true
			else directional[proto.name]=proto.type~="electric-pole" and proto.type~="lamp"
				and proto.type~="beacon" and proto.type~="pipe" and proto.type~="heat-pipe"
				and proto.type~="container" and proto.type~="logistic-container" and proto.type~="furnace" end
		end
		if not directional[proto.name] then spec.direction=direction.north end
		local pos = spec.position
		local x,y = pos.x or pos[1],pos.y or pos[2]
		if not proto.has_flag("placeable-off-grid") then
			local w,h = proto.tile_width,proto.tile_height
			if spec.direction == direction.east or spec.direction == direction.west then w,h = h,w end
			local ox,oy = (w % 2)/2,(h % 2)/2
			x,y = math.floor(x+0.5-ox)+ox,math.floor(y+0.5-oy)+oy
		end
		spec.position = {x=x,y=y}
	end
	state._preview_specs[#state._preview_specs+1] = spec
	return spec
end

---@class GhostSpecification : LuaSurface.create_entity_param.entity_ghost
---@field inner_name? nil
---@field position? nil
---@field grid_x number Grid x coordinate
---@field grid_y number Grid x coordinate
---@field radius number? Object radius or default to 0.5 if nil
---@field extent_w number? Object extent from origin, converted from radius if nil
---@field extent_h number? Object extent from origin, converted from radius if nil
---@field thing GridBuilding Enum for the grid
---@field items table<string, number>? Item requests
---@field pickup_position MapPosition.0?
---@field drop_position MapPosition.0?

---@class PowerPoleGhostSpecification : GhostSpecification
---@field no_light boolean
---@field ix number
---@field iy number

---@alias EntityBuilderFunction fun(ghost: GhostSpecification, check_allowed: boolean?): LuaEntity?

---@class EntityBuilderOptions
---@field do_deconstruction boolean?

--- Builder for a convenience function that automatically translates
--- internal grid state for a surface.create_entity call
---@param state MinimumPreservedState | State | BeltinatorState
---@param opts EntityBuilderOptions?
---@return EntityBuilderFunction
function builder.create_entity_builder(state, opts)
	opts = opts or {}
	local c = state.coords
	local grid = state.grid
	local DIR = state.direction_choice
	local surface = state.surface
	local gx, gy, tw, th = c.gx, c.gy, c.tw, c.th
	local direction_conv = mpp_util.bp_direction[state.direction_choice]
	local collected_ghosts = state._collected_ghosts
	-- local is_space = state.is_space

	local deconstruction_planner
	if opts.do_deconstruction and not state.avoid_obstacles_choice and not state.preview_only then
		deconstruction_planner = storage.script_inventory[state.deconstruction_choice and 2 or 1]
	end
	
	local _player = state.player
	local _force = _player.force
	local _build_check_type = defines.build_check_type.blueprint_ghost
	
	return function(ghost, check_allowed)
		ghost.raise_built = true
		ghost.player = _player
		ghost.force = _force
		---@diagnostic disable-next-line: assign-type-mismatch
		ghost.inner_name = ghost.name
		ghost.name="entity-ghost"
		local position = coord_revert_world(gx, gy, DIR, ghost.grid_x, ghost.grid_y, tw, th)
		---@diagnostic disable-next-line: assign-type-mismatch
		ghost.position = position
		ghost.direction=direction_conv[ghost.direction or defines.direction.north]
		if state.avoid_obstacles_choice and not obstacles.can_place(state,ghost.inner_name,
			{x=position[1],y=position[2]},ghost.direction) then
			state._obstacle_skipped = (state._obstacle_skipped or 0) + 1
			return
		end
		
		if not quality_enabled then ghost.quality = nil end
		
		local pickup, drop = ghost.pickup_position, ghost.drop_position
		if pickup then
			local x, y = mpp_util.rotate((pickup.x or pickup[1]), (pickup.y or pickup[2]), direction[DIR])
			ghost.pickup_position = {x=x, y=y}
		end
		if drop then
			local x, y = mpp_util.rotate((drop.x or drop[1]), (drop.y or drop[2]), direction[DIR])
			ghost.drop_position = {x=x, y=y}
		end

		--local can_place = surface.can_place_entity(ghost)
		if check_allowed and not surface.can_place_entity{
			name = ghost.inner_name,
			-- name = "entity-ghost",
			-- inner_name = ghost.inner_name,
			force = _force,
			position = position,
			direction = ghost.direction,
			build_check_type = _build_check_type,
			--forced = true,
		} then
			return
		end
		
		if deconstruction_planner then
			local x, y = position[1], position[2]
			local left_top = {x+.01, y+.01}
			local right_bottom = {position[1]+.99, position[2]+.99}
			surface.deconstruct_area{
				force = _force,
				player = _player,
				area = {
					left_top = left_top,
					right_bottom = right_bottom,
				},
				item = deconstruction_planner,
			}
			-- rendering.draw_rectangle{
			-- 	left_top = left_top,
			-- 	right_bottom = right_bottom,
			-- 	color = {1, 0, 0},
			-- 	surface = surface,
			-- }
		end

		local result
		if state.preview_only then result = builder.record_preview(state,ghost)
		else result = surface.create_entity(ghost) end
		if result then
			if ghost.thing and grid then
				grid:build_specification(ghost)
			end
			
			if collected_ghosts and not state.preview_only then
				collected_ghosts[#collected_ghosts+1] = result
			end
		end
		return result
	end
end

return builder
