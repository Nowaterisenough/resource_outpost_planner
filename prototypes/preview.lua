local directions={"north","east","south","west"}
local types={"mining-drill","transport-belt","underground-belt","electric-pole","pipe","pipe-to-ground",
	"heat-pipe","beacon","lamp","container","logistic-container","inserter","assembling-machine","furnace",
	"splitter","storage-tank","straight-rail","train-stop","rail-signal","rail-chain-signal","locomotive","cargo-wagon"}
local belt_indexes={east=1,west=2,north=3,south=4,east_to_north=5,north_to_east=6,
	west_to_north=7,north_to_west=8,south_to_east=9,east_to_south=10,south_to_west=11,west_to_south=12,
	starting_south=13,ending_south=14,starting_west=15,ending_west=16,
	starting_north=17,ending_north=18,starting_east=19,ending_east=20}
local connections={single="straight_vertical_single",straight_vertical="straight_vertical",straight_horizontal="straight_horizontal",
	corner_up_right="corner_right_up",corner_up_left="corner_left_up",corner_down_right="corner_right_down",corner_down_left="corner_left_down",
	t_up="t_up",t_down="t_down",t_right="t_right",t_left="t_left",cross="cross",
	ending_up="ending_up",ending_down="ending_down",ending_right="ending_right",ending_left="ending_left"}

local function collect(source,layers,direction_index,row_index,sheet_count,inherited)
	if not source then return end
	if source.rotated then collect(source.rotated,layers,direction_index,row_index,sheet_count);return end
	if source.layers then
		for _,layer in ipairs(source.layers) do collect(layer,layers,direction_index,row_index,sheet_count,source) end
		return
	end
	if source.sheet then collect(source.sheet,layers,direction_index,row_index,4); return end
	if source.sheets then
		for _,sheet in ipairs(source.sheets) do collect(sheet,layers,direction_index,row_index,4) end
		return
	end
	if source[1] then collect(source[1],layers,direction_index,row_index,sheet_count); return end
	local width,height=source.width or source.size,source.height or source.size
	if type(width)~="number" or type(height)~="number" or source.draw_as_shadow or source.draw_as_light then return end
	local frames=source.frame_count or inherited and inherited.frame_count or 1
	local count=source.direction_count or inherited and inherited.direction_count or sheet_count or 1
	local facing=direction_index or 0
	if source.back_equals_front then facing=(facing%2)*2 end
	local row=row_index or math.floor(facing*count/4)
	if count==1 and not row_index then row=0 end
	local frame=row*frames
	local length=source.line_length or inherited and inherited.line_length
	if not length or length==0 then length=frames>1 and frames or count end
	local filename=source.filename
	local file_row=math.floor(frame/length)
	if not filename and source.filenames then
		local lines=source.lines_per_file or inherited and inherited.lines_per_file
		if not lines then return end
		filename=source.filenames[math.floor(file_row/lines)+1]
		file_row=file_row%lines
	end
	if not filename or filename:find("smoke",1,true) then return end
	-- Keep native dimensions and offsets while selecting the blueprint idle frame.
	layers[#layers+1]={filename=filename,width=width,height=height,
		x=(source.x or 0)+(frame%length)*width,y=(source.y or 0)+file_row*height,
		scale=source.scale or 1,shift=source.shift,tint=source.tint,blend_mode=source.blend_mode}
end

local sprites={}
local function register(name,variant,layers)
	for index,layer in ipairs(layers) do
		layer.type="sprite"
		layer.name="mpp-preview-"..name.."-"..variant.."-"..index
		sprites[#sprites+1]=layer
	end
end

local function machine_layers(proto,graphics,direction,direction_index)
	local layers={}
	local visuals=graphics and graphics.working_visualisations or {}
	local function visual(layer)
		collect(layer[direction.."_animation"] or layer.animation,layers,direction_index)
	end
	for _,layer in ipairs(visuals) do
		if layer.always_draw and (layer.secondary_draw_order or 0)<0 then visual(layer) end
	end
	local source=graphics and (graphics.idle_animation or graphics.animation)
		or proto.animation or proto.animations or proto.picture_off or proto.picture or proto.pictures
	if not source and graphics and graphics.animation_list and graphics.animation_list[1] then source=graphics.animation_list[1].animation end
	if source then collect(source[direction] or source.single or source,layers,direction_index) end
	for _,layer in ipairs(visuals) do
		if layer.always_draw and (layer.secondary_draw_order or 0)>=0 then visual(layer) end
	end
	return layers
end

for _,entity_type in ipairs(types) do
	for name,proto in pairs(data.raw[entity_type] or {}) do
		if entity_type=="transport-belt" then
			local belt=proto.belt_animation_set or {}
			for variant,index in pairs(belt_indexes) do
				local layers={}
				collect(belt.animation_set,layers,0,(belt[variant.."_index"] or index)-1)
				register(name,variant,layers)
			end
		elseif entity_type=="pipe" or entity_type=="heat-pipe" then
			local pictures=proto.pictures or proto.connection_sprites or {}
			for variant,heat_variant in pairs(connections) do
				local layers={}
				collect(pictures[variant] or pictures[heat_variant] or (variant=="single" and pictures.single),layers)
				register(name,variant,layers)
			end
			local layers={}; collect(pictures.straight_vertical_single or pictures.single,layers)
			register(name,"north",layers)
		else
			for direction_index,direction in ipairs(directions) do
				if entity_type=="straight-rail" then
					local layers={}
					local facing=(direction=="north" or direction=="south") and "north" or "east"
					local pictures=proto.pictures and proto.pictures[facing] or {}
					for _,part in ipairs{"stone_path_lower","stone_path","tie","screw","metal"} do collect(pictures[part],layers,0) end
					register(name,direction,layers)
				elseif entity_type=="inserter" then
					local layers={};collect(proto.platform_picture,layers,direction_index-1)
					register(name,direction,layers)
				elseif entity_type=="splitter" then
					local layers={}
					local belt=proto.belt_animation_set or {}
					for _,sign in ipairs{-1,1} do
						local lane={}
						collect(belt.animation_set,lane,0,(belt[direction.."_index"] or belt_indexes[direction])-1)
						for _,layer in ipairs(lane) do
							local shift=layer.shift or {0,0}
							local x,y=shift.x or shift[1],shift.y or shift[2]
							if direction=="north" or direction=="south" then x=x+sign/2 else y=y+sign/2 end
							layer.shift={x,y}; layers[#layers+1]=layer
						end
					end
					collect(proto.structure and proto.structure[direction],layers)
					collect(proto.structure_patch and proto.structure_patch[direction],layers)
					register(name,direction,layers)
				elseif entity_type=="underground-belt" then
					for _,kind in ipairs{"input","output"} do
						local layers={}
						local structure=proto.structure or {}
						collect(structure.back_patch,layers,direction_index-1)
						local belt=proto.belt_animation_set or {}
						collect(belt.animation_set,layers,0,(belt[direction.."_index"] or belt_indexes[direction])-1)
						collect(structure[kind=="input" and "direction_in" or "direction_out"],layers,direction_index-1)
						collect(structure.front_patch,layers,direction_index-1)
						register(name,direction.."-"..kind,layers)
					end
				else
					register(name,direction,machine_layers(proto,proto.graphics_set,direction,direction_index-1))
					if proto.graphics_set_flipped then
						register(name,direction.."-flipped",machine_layers(proto,proto.graphics_set_flipped,direction,direction_index-1))
					end
				end
			end
			if entity_type=="inserter" then
				local layers={};collect(proto.hand_base_picture,layers,0);collect(proto.hand_closed_picture,layers,0)
				register(name,"hand",layers)
			end
		end
	end
end

for name,proto in pairs(data.raw.tile or {}) do
	local main=proto.variants and proto.variants.main and proto.variants.main[1]
	if main and main.picture then
		register("tile-"..name,"north",{{filename=main.picture,width=32*(main.size or 1),height=32*(main.size or 1),
			scale=main.scale or 1,x=main.x or 0,y=main.y or 0}})
	end
end
data:extend(sprites)
