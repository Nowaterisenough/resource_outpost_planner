local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local renderer = {}
local N,E,S,W,ROTATION = defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west,16
local names={[N]="north",[E]="east",[S]="south",[W]="west"}
local directions={N,E,S,W}
local pipe_shapes={[0]="single",[1]="ending_up",[2]="ending_right",[4]="ending_down",[8]="ending_left",
	[5]="straight_vertical",[10]="straight_horizontal",[3]="corner_up_right",[9]="corner_up_left",
	[6]="corner_down_right",[12]="corner_down_left",[7]="t_right",[11]="t_up",[13]="t_left",[14]="t_down",[15]="cross"}
local function key(x,y) return x..","..y end
local function position(pos) return pos.x or pos[1],pos.y or pos[2] end
local sprite_paths={}
local artworks={entity={},tile={}}
local entity_shapes={}

local function entity_shape(name)
	local shape=entity_shapes[name]
	if not shape then
		local proto=prototypes.entity[name]
		if not proto then return end
		-- Only prototype data is cached here; world neighbors are rebuilt on every render.
		shape={type=proto.type,ports={}}
		local boxes=proto.fluidbox_prototypes or {}
		for _,direction in ipairs(directions) do
			local ports={}
			for _,box in pairs(boxes) do
				for _,connection in pairs(box.pipe_connections) do
					if connection.connection_type=="normal" then
						local offset=connection.positions[direction/4+1]
						if offset then
							local x,y=position(offset)
							ports[#ports+1]={x=x,y=y,facing=(connection.direction+direction)%ROTATION}
						end
					end
				end
			end
			shape.ports[direction]=ports
		end
		entity_shapes[name]=shape
	end
	return shape
end

local function color_key(color)
	return table.concat({color.r or color[1] or 0,color.g or color[2] or 0,
		color.b or color[3] or 0,color.a or color[4] or 1},",")
end

local function valid_sprite(path)
	local valid=sprite_paths[path]
	if valid==nil then
		-- Sprite prototypes are fixed for this script lifetime, including missing variants.
		valid=helpers.is_valid_sprite_path(path)
		sprite_paths[path]=valid
	end
	return valid
end

local function artwork(spec,tile,variant)
	local name=(tile and "tile-" or "")..spec.inner_name
	local cache=tile and artworks.tile or artworks.entity
	local options=cache[spec.inner_name]
	if not options then options={};cache[spec.inner_name]=options end
	local direction=spec.direction or N
	local k=variant..":"..direction..":"..(spec.mirror and 1 or 0)
	local result=options[k]
	if result then return result end
	result={}
	local prefix="mpp-preview-"..name.."-"
	local base=prefix..variant
	local horizontal=direction==N or direction==S
	local sx=spec.mirror and horizontal and -1 or 1
	local sy=spec.mirror and not horizontal and -1 or 1
	if spec.mirror and valid_sprite(base.."-flipped-1") then base=base.."-flipped";sx,sy=1,1 end
	if not valid_sprite(base.."-1") then base=prefix..(names[direction] or "north") end
	local function append(prefix,x_scale,y_scale,orientation)
		local index=1
		while valid_sprite(prefix..index) do
			result[#result+1]={sprite=prefix..index,sx=x_scale,sy=y_scale,orientation=orientation or 0}
			index=index+1
		end
	end
	if valid_sprite(base.."-1") then append(base.."-",sx,sy)
	elseif tile then result.rectangle=true
	else
		local box=obstacles.entity_box(spec.inner_name,{x=0,y=0},spec.direction)
		local sprite="entity/"..spec.inner_name
		if valid_sprite(sprite) then
			result[1]={sprite=sprite,sx=sx*(box.right_bottom.x-box.left_top.x)/2,
				sy=sy*(box.right_bottom.y-box.left_top.y)/2,orientation=0}
		end
	end
	if not tile and entity_shape(spec.inner_name).type=="inserter" then
		append("mpp-preview-"..spec.inner_name.."-hand-",1,1,direction/16)
	end
	for _,style in ipairs(result) do
		style.key=style.sprite..":"..style.sx..":"..style.sy..":"..style.orientation
	end
	options[k]=result
	return result
end

local function topology(draft)
	local nodes,ports={},{}
	local function add(name,pos,direction,kind,mirror)
		local shape=entity_shape(name)
		if not shape then return end
		local x,y=position(pos)
		direction=direction or N
		nodes[key(x,y)]={type=shape.type,direction=direction,kind=kind}
		if shape.type=="splitter" then
			local delta=util.direction_coord[direction]
			for _,sign in ipairs{-1,1} do
				nodes[key(x+delta.y*sign/2,y-delta.x*sign/2)]={type="transport-belt",direction=direction}
			end
		end
		for _,port in ipairs(shape.ports[direction] or {}) do
			local px,py,facing=port.x,port.y,port.facing
			if mirror then
				if direction==N or direction==S then px=-px; facing=(-facing)%ROTATION
				else py=-py; facing=(S-facing)%ROTATION end
			end
			local k=key(x+px,y+py)
			ports[k]=ports[k] or {}
			ports[k][facing]=true
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
	local shape=entity_shape(spec.inner_name)
	local direction=spec.direction or N
	local name=names[direction] or "north"
	local x,y=position(spec.position)
	if shape.type=="underground-belt" then return name.."-"..(spec.type or "input") end
	if shape.type=="transport-belt" then
		local count,incoming=0,nil
		for _,dir in ipairs(directions) do
			local delta=util.direction_coord[dir]
			local other=nodes[key(x-delta.x,y-delta.y)]
			if other and (other.type=="transport-belt" or other.type=="underground-belt" and other.kind=="output")
				and other.direction==dir and dir~=(direction+S)%ROTATION then count=count+1;incoming=dir end
		end
		-- Atlas curve names describe the entry side, opposite to the incoming belt's movement.
		if count==1 and incoming~=direction then return names[(incoming+S)%ROTATION].."_to_"..name end
		local delta=util.direction_coord[direction]
		local front=nodes[key(x+delta.x,y+delta.y)]
		if count==0 then return "starting_"..name end
		if not front or (front.type~="transport-belt" and front.type~="underground-belt") then return "ending_"..name end
		return name
	end
	if shape.type=="pipe" or shape.type=="heat-pipe" then
		local mask=0
		for index,dir in ipairs(directions) do
			local delta=util.direction_coord[dir]
			local k=key(x+delta.x,y+delta.y)
			local other=nodes[k]
			local connected=other and other.type==shape.type
			if shape.type=="pipe" then connected=ports[k] and ports[k][(dir+S)%ROTATION] or connected end
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
	-- Handles and their metadata must survive save/load and multiplayer joins together.
	local previous=draft.sprite_renderings
	local reusable=previous and previous.surface==draft.surface and previous.player_index==draft.player_index
		and previous.entries
	local entries,retained={},{}
	local styles={}
	local previous_styles=previous and previous.styles or {}
	local constants=prototypes.utility_constants or {}
	local allowed=constants.building_buildable_tint or {0.4,1,0.4,1}
	local blocked=constants.building_not_buildable_tint or {1,0.4,0.4,1}
	local allowed_key,blocked_key=color_key(allowed),color_key(blocked)
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
	local function draw(style,pos,tint)
		local stored=styles[style.key]
		if not stored then
			-- Keep stored table sharing independent of local prototype caches after a join/load.
			stored=previous_styles[style.key] or {sprite=style.sprite,sx=style.sx,sy=style.sy,orientation=style.orientation}
			styles[style.key]=stored
		end
		style=stored
		local x,y=position(pos)
		local color=tint==blocked and blocked_key or allowed_key
		local entry=reusable and reusable[#entries+1]
		-- Compact records: object, id, style, x, y, color. Thousands survive until Apply/Cancel.
		if entry and entry[1].valid then
			local object=entry[1]
			local old=entry[3]
			if old~=style then
				if old.sprite~=style.sprite then object.sprite=style.sprite end
				if old.sx~=style.sx then object.x_scale=style.sx end
				if old.sy~=style.sy then object.y_scale=style.sy end
				if old.orientation~=style.orientation then object.orientation=style.orientation end
			end
			if entry[4]~=x or entry[5]~=y then object.target=pos end
			if entry[6]~=color then object.color=tint end
			retained[entry[2]]=true
			entry[3],entry[4],entry[5],entry[6]=style,x,y,color
		else
			-- Reuse the ordered prefix only, so replacing an invalid handle preserves layer order.
			reusable=nil
			local object=rendering.draw_sprite{surface=draft.surface,players={player},sprite=style.sprite,target=pos,
				x_scale=style.sx,y_scale=style.sy,tint=tint,orientation=style.orientation,render_layer="cursor",light_mode="glow"}
			entry={object,object.id,style,x,y,color}
		end
		entries[#entries+1]=entry
		objects[#objects+1]=entry[1]
	end
	for _,spec in ipairs(draft.specs) do
		local x,y=position(spec.position)
		local tile=spec.name=="tile-ghost"
		local variant=tile and "north" or renderer.variant(spec,nodes,ports)
		local layers=artwork(spec,tile,variant)
		local tint=spec.preview_blocked and blocked or allowed
		if not tile and not spec.preview_existing and (selected_obstacles and obstacles.blocked_box(selected_obstacles,
			obstacles.entity_box(spec.inner_name,{x=x,y=y},spec.direction))
			or draft.surface.can_place_entity and not draft.surface.can_place_entity{
			name=spec.inner_name,position={x=x,y=y},direction=spec.direction,force=player.force,
			build_check_type=defines.build_check_type.blueprint_ghost,forced=choices.deconstruction_choice==true}) then tint=blocked end
		local target=tile and {x+0.5,y+0.5} or {x,y}
		if layers.rectangle then
			objects[#objects+1]=rendering.draw_rectangle{surface=draft.surface,players={player},
				left_top={x,y},right_bottom={x+1,y+1},filled=true,draw_on_ground=true,color={0.2,0.5,0.2,0.5}}
		end
		for _,style in ipairs(layers) do draw(style,target,tint) end
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
	draft.sprite_renderings={surface=draft.surface,player_index=draft.player_index,entries=entries,styles=styles}
	return objects,retained
end

return renderer
