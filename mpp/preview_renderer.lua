local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local renderer = {}
local N,E,S,W,ROTATION = defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west,16
local names={[N]="north",[E]="east",[S]="south",[W]="west"}
local pipe_shapes={[0]="single",[1]="ending_up",[2]="ending_right",[4]="ending_down",[8]="ending_left",
	[5]="straight_vertical",[10]="straight_horizontal",[3]="corner_up_right",[9]="corner_up_left",
	[6]="corner_down_right",[12]="corner_down_left",[7]="t_right",[11]="t_up",[13]="t_left",[14]="t_down",[15]="cross"}
local function key(x,y) return x..","..y end
local function position(pos) return pos.x or pos[1],pos.y or pos[2] end

local function topology(draft)
	local nodes,ports={},{}
	local function add(name,pos,direction,kind,mirror)
		local proto=prototypes.entity[name]
		if not proto then return end
		local x,y=position(pos)
		direction=direction or N
		nodes[key(x,y)]={type=proto.type,direction=direction,kind=kind}
		if proto.type=="splitter" then
			local delta=util.direction_coord[direction]
			for _,sign in ipairs{-1,1} do
				nodes[key(x+delta.y*sign/2,y-delta.x*sign/2)]={type="transport-belt",direction=direction}
			end
		end
		for _,box in pairs(proto.fluidbox_prototypes or {}) do
			for _,connection in pairs(box.pipe_connections) do
				if connection.connection_type=="normal" then
					local offset=connection.positions[direction/4+1]
					if offset then
						local px,py=position(offset)
						local facing=(connection.direction+direction)%ROTATION
						if mirror then
							if direction==N or direction==S then px=-px; facing=(-facing)%ROTATION
							else py=-py; facing=(S-facing)%ROTATION end
						end
						local k=key(x+px,y+py)
						ports[k]=ports[k] or {}
						ports[k][facing]=true
					end
				end
			end
		end
	end
	local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
	for _,spec in ipairs(draft.specs) do
		local x,y=position(spec.position)
		x1,y1,x2,y2=math.min(x1,x),math.min(y1,y),math.max(x2,x),math.max(y2,y)
	end
	if x1~=math.huge then
		for _,entity in pairs(draft.surface.find_entities_filtered{area={{x1-4,y1-4},{x2+4,y2+4}},
			type={"transport-belt","underground-belt","splitter","pipe","pipe-to-ground","heat-pipe",
				"mining-drill","assembling-machine","furnace","storage-tank","entity-ghost"}}) do
			if entity.valid then
				local ghost=entity.type=="entity-ghost"
				local kind=(ghost and entity.ghost_type or entity.type)=="underground-belt" and entity.belt_to_ground_type or nil
				add(ghost and entity.ghost_name or entity.name,entity.position,entity.direction,kind,entity.mirroring)
			end
		end
	end
	for _,spec in ipairs(draft.specs) do
		if spec.name=="entity-ghost" then add(spec.inner_name,spec.position,spec.direction,spec.type,spec.mirror) end
	end
	return nodes,ports
end

function renderer.variant(spec,nodes,ports)
	local proto=prototypes.entity[spec.inner_name]
	local direction=spec.direction or N
	local name=names[direction] or "north"
	local x,y=position(spec.position)
	if proto.type=="underground-belt" then return name.."-"..(spec.type or "input") end
	if proto.type=="transport-belt" then
		local incoming={}
		for _,dir in ipairs{N,E,S,W} do
			local delta=util.direction_coord[dir]
			local other=nodes[key(x-delta.x,y-delta.y)]
			if other and (other.type=="transport-belt" or other.type=="underground-belt" and other.kind=="output")
				and other.direction==dir and dir~=(direction+S)%ROTATION then incoming[#incoming+1]=dir end
		end
		-- Atlas curve names describe the entry side, opposite to the incoming belt's movement.
		if #incoming==1 and incoming[1]~=direction then return names[(incoming[1]+S)%ROTATION].."_to_"..name end
		local delta=util.direction_coord[direction]
		local front=nodes[key(x+delta.x,y+delta.y)]
		if #incoming==0 then return "starting_"..name end
		if not front or (front.type~="transport-belt" and front.type~="underground-belt") then return "ending_"..name end
		return name
	end
	if proto.type=="pipe" or proto.type=="heat-pipe" then
		local mask=0
		for index,dir in ipairs{N,E,S,W} do
			local delta=util.direction_coord[dir]
			local k=key(x+delta.x,y+delta.y)
			local other=nodes[k]
			local connected=other and other.type==proto.type
			if proto.type=="pipe" then connected=ports[k] and ports[k][(dir+S)%ROTATION] or connected end
			if connected then mask=mask+2^(index-1) end
		end
		return pipe_shapes[mask]
	end
	return name
end

function renderer.render(draft,choices)
	local player=game.get_player(draft.player_index)
	local nodes,ports=topology(draft)
	local objects={}
	local constants=prototypes.utility_constants or {}
	local allowed=constants.building_buildable_tint or {0.4,1,0.4,1}
	local blocked=constants.building_not_buildable_tint or {1,0.4,0.4,1}
	local selected_obstacles
	if obstacles.active(choices) then
		local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
		for _,spec in ipairs(draft.specs) do
			if spec.name=="entity-ghost" then
				local x,y=position(spec.position)
				local box=obstacles.entity_box(spec.inner_name,{x=x,y=y},spec.direction)
				x1,y1=math.min(x1,box.left_top.x),math.min(y1,box.left_top.y)
				x2,y2=math.max(x2,box.right_bottom.x),math.max(y2,box.right_bottom.y)
			end
		end
		if x1~=math.huge then selected_obstacles=obstacles.collect(draft.surface,{{x1,y1},{x2,y2}},nil,choices) end
	end
	local function draw(sprite,pos,tint,sx,sy)
		objects[#objects+1]=rendering.draw_sprite{surface=draft.surface,players={player},sprite=sprite,target=pos,
			x_scale=sx or 1,y_scale=sy or 1,tint=tint,render_layer="cursor",light_mode="glow"}
	end
	for _,spec in ipairs(draft.specs) do
		local x,y=position(spec.position)
		local tile=spec.name=="tile-ghost"
		local variant=tile and "north" or renderer.variant(spec,nodes,ports)
		local prefix="mpp-preview-"..(tile and "tile-" or "")..spec.inner_name.."-"
		local base=prefix..variant
		local horizontal=spec.direction==N or spec.direction==S or not spec.direction
		local sx=spec.mirror and horizontal and -1 or 1
		local sy=spec.mirror and not horizontal and -1 or 1
		if spec.mirror and helpers.is_valid_sprite_path(base.."-flipped-1") then base=base.."-flipped"; sx,sy=1,1 end
		if not helpers.is_valid_sprite_path(base.."-1") then base=prefix..(names[spec.direction] or "north") end
		local tint=spec.preview_blocked and blocked or allowed
		if not tile and (selected_obstacles and obstacles.blocked_box(selected_obstacles,
			obstacles.entity_box(spec.inner_name,{x=x,y=y},spec.direction))
			or draft.surface.can_place_entity and not draft.surface.can_place_entity{
			name=spec.inner_name,position={x=x,y=y},direction=spec.direction,force=player.force,
			build_check_type=defines.build_check_type.blueprint_ghost,forced=choices.deconstruction_choice==true}) then tint=blocked end
		local target=tile and {x+0.5,y+0.5} or {x,y}
		if helpers.is_valid_sprite_path(base.."-1") then
			local layer=1
			while helpers.is_valid_sprite_path(base.."-"..layer) do
				draw(base.."-"..layer,target,tint,sx,sy)
				layer=layer+1
			end
		elseif tile then
			objects[#objects+1]=rendering.draw_rectangle{surface=draft.surface,players={player},
				left_top={x,y},right_bottom={x+1,y+1},filled=true,draw_on_ground=true,color={0.2,0.5,0.2,0.5}}
		else
			local box=obstacles.entity_box(spec.inner_name,{x=x,y=y},spec.direction)
			local sprite="entity/"..spec.inner_name
			if helpers.is_valid_sprite_path(sprite) then
				draw(sprite,target,tint,sx*(box.right_bottom.x-box.left_top.x)/2,sy*(box.right_bottom.y-box.left_top.y)/2)
			end
		end
	end
	local labels={}
	for _,issue in ipairs(draft.issues or {}) do
		local x,y=position(issue.position)
		if issue.left_top then
			objects[#objects+1]=rendering.draw_rectangle{surface=draft.surface,players={player},
				left_top=issue.left_top,right_bottom=issue.right_bottom,filled=true,
				color={1,0.15,0.1,0.3},draw_on_ground=true}
		else
			objects[#objects+1]=rendering.draw_circle{surface=draft.surface,players={player},
				target={x,y},radius=0.7,color={1,0.15,0.1,1},width=3,filled=false,draw_on_ground=false}
		end
		local crowded=false
		for _,label in ipairs(labels) do if (label.x-x)^2+(label.y-y)^2<16 then crowded=true; break end end
		if issue.reason and not crowded and #labels<8 then
			objects[#objects+1]=rendering.draw_text{surface=draft.surface,players={player},text=issue.reason,
				target={x,y-1.5},color={1,0.25,0.15,1},alignment="center",scale=0.9,scale_with_zoom=true,
				render_layer="cursor",font="default-bold"}
			labels[#labels+1]={x=x,y=y}
		end
	end
	return objects
end

return renderer
