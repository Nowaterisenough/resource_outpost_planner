local obstacles = require("mpp.obstacles")
local forced = {}

-- Consume only a successfully planned preview, never diagnostic route guides.
function forced.apply(state, mode)
	if state.preview_error or not state._preview_specs or #state._preview_specs==0 then return false end
	if mode~=defines.build_mode.forced and mode~=defines.build_mode.superforced then return false end
	local entities,tiles={},{}
	local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
	for _,spec in ipairs(state._preview_specs) do
		local p=spec.position
		local position={x=p.x or p[1],y=p.y or p[2]}
		if spec.name=="tile-ghost" then tiles[#tiles+1]={name=spec.inner_name,position=position}
		else
			local entity={entity_number=#entities+1,name=spec.inner_name,position=position,
				direction=spec.direction,orientation=spec.orientation,quality=spec.quality,mirror=spec.mirror,type=spec.type,
				items=spec.insert_plan,input_priority=spec.input_priority,output_priority=spec.output_priority,
				filter=spec.filter,station=spec.station_name,manual_trains_limit=spec.station_name and 1 or nil,
				pickup_position=spec.pickup_position,drop_position=spec.drop_position}
			entities[#entities+1]=entity
		end
		local box=spec.name=="tile-ghost" and {left_top=position,right_bottom={x=position.x+1,y=position.y+1}}
			or obstacles.entity_box(spec.inner_name,position,spec.direction)
		x1,y1=math.min(x1,box.left_top.x),math.min(y1,box.left_top.y)
		x2,y2=math.max(x2,box.right_bottom.x),math.max(y2,box.right_bottom.y)
	end
	local area={{x1-.1,y1-.1},{x2+.1,y2+.1}}
	local surface,player=state.surface,state.player
	local before,orders={},{}
	for _,e in pairs(surface.find_entities_filtered{area=area,type={"resource","corpse","item-entity"},invert=true}) do
		if e.unit_number then before[e.unit_number]=true end
		orders[e]=e.to_be_deconstructed(player.force)
	end
	local inventory=game.create_inventory(1)
	local ok,result=pcall(function()
		local stack=inventory[1]
		stack.set_stack{name="blueprint"}
		-- Do not recenter: positions already match the preview, including the rail grid.
		stack.set_blueprint_entities(entities,false)
		if #tiles>0 then stack.set_blueprint_tiles(tiles) end
		-- build_blueprint recenters unsnapped blueprints even with fix_positions=false.
		stack.blueprint_snap_to_grid={1,1}
		stack.blueprint_absolute_snapping=true
		stack.blueprint_position_relative_to_grid={0,0}
		return stack.build_blueprint{surface=surface,force=player.force,position={0,0},
			build_mode=mode,by_player=player,skip_fog_of_war=false}
	end)
	inventory.destroy()
	if not ok then error(result) end
	state._collected_ghosts=state._collected_ghosts or {}
	state._deconstruction_orders=state._deconstruction_orders or {}
	local created=0
	for _,e in pairs(result) do
		if e.valid and not before[e.unit_number] then
			state._collected_ghosts[#state._collected_ghosts+1]=e;created=created+1
		end
	end
	local changed=0
	for e,ordered in pairs(orders) do
		if e.valid and not ordered and e.to_be_deconstructed(player.force) then
			state._deconstruction_orders[#state._deconstruction_orders+1]=e;changed=changed+1
		end
	end
	-- Mark pieces the native forced build skipped, without claiming existing ghosts.
	local skipped=0
	state._render_objects=state._render_objects or {}
	for _,spec in ipairs(entities) do
		local found=false
		for _,e in pairs(surface.find_entities_filtered{position=spec.position,radius=.05,force=player.force}) do
			if (e.name==spec.name or e.type=="entity-ghost" and e.ghost_name==spec.name)
				and e.direction==(spec.direction or defines.direction.north) and e.quality.name==(spec.quality or "normal")
				and not e.to_be_deconstructed(player.force) then found=true;break end
		end
		if not found then
			skipped=skipped+1
			local box=obstacles.entity_box(spec.name,spec.position,spec.direction)
			state._render_objects[#state._render_objects+1]=rendering.draw_rectangle{surface=surface,players={player},
				left_top=box.left_top,right_bottom=box.right_bottom,color={1,.15,.05,.8},width=2,time_to_live=600}
		end
	end
	player.print({"mpp.preview_force_result",created,skipped})
	return created>0 or changed>0 or skipped==0
end

return forced
