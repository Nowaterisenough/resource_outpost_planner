local directions={"north","east","south","west"}
local types={"mining-drill","transport-belt","underground-belt","electric-pole","pipe","pipe-to-ground",
	"heat-pipe","beacon","lamp","container","logistic-container","inserter","assembling-machine","furnace"}

local function picture(proto,direction)
	local graphics=proto.graphics_set
	local source=graphics and (graphics.animation or graphics.idle_animation)
		or proto.animation or proto.animations or proto.picture_off or proto.picture or proto.pictures
	if not source and graphics and graphics.animation_list and graphics.animation_list[1] then source=graphics.animation_list[1].animation end
	if proto.type=="transport-belt" then
		source=proto.belt_animation_set and proto.belt_animation_set.animation_set
	elseif proto.type=="underground-belt" then
		source=proto.structure and proto.structure.direction_in
	end
	if not source then return end
	return source[direction] or source.straight_vertical_single or source.single or source
end

local function collect(source,layers)
	if not source then return end
	if source.layers then for _,layer in ipairs(source.layers) do collect(layer,layers) end; return end
	if source.sheet then collect(source.sheet,layers); return end
	if source.sheets then for _,sheet in ipairs(source.sheets) do collect(sheet,layers) end; return end
	local filename=source.filename or source.filenames and source.filenames[1]
	local width,height=source.width or source.size,source.height or source.size
	if not filename or type(width)~="number" or type(height)~="number" or source.draw_as_shadow or source.draw_as_light
		or filename:find("smoke",1,true) then return end
	-- Static first frames use the game's artwork without introducing placeable preview entities.
	layers[#layers+1]={filename=filename,width=width,height=height,x=source.x or 0,y=source.y or 0,
		scale=source.scale or 1,shift=source.shift,tint=source.tint,blend_mode=source.blend_mode}
end

local sprites={}
for _,entity_type in ipairs(types) do
	for name,proto in pairs(data.raw[entity_type] or {}) do
		for _,direction in ipairs(directions) do
			local layers={}
			local visuals=proto.graphics_set and proto.graphics_set.working_visualisations or {}
			for _,visual in ipairs(visuals) do
				if visual.always_draw and (visual.secondary_draw_order or 0)<0 then
					collect(visual[direction.."_animation"] or visual.animation,layers)
				end
			end
			collect(picture(proto,direction),layers)
			for _,visual in ipairs(visuals) do
				if visual.always_draw and (visual.secondary_draw_order or 0)>=0 then
					collect(visual[direction.."_animation"] or visual.animation,layers)
				end
			end
			if entity_type=="transport-belt" then
				local belt=proto.belt_animation_set
				local animation=belt and belt.animation_set
				local indexes={north=3,east=1,south=4,west=2}
				if animation and animation.filename and animation.direction_count then
					for _,layer in ipairs(layers) do
						local frames=animation.frame_count or 1
						local length=animation.line_length and animation.line_length>0 and animation.line_length or frames
						local frame=((belt[direction.."_index"] or indexes[direction])-1)*frames
						layer.x=layer.x+(frame % length)*layer.width
						layer.y=layer.y+math.floor(frame/length)*layer.height
					end
				end
			end
			for index,layer in ipairs(layers) do
				layer.type="sprite"
				layer.name="mpp-preview-"..name.."-"..direction.."-"..index
				sprites[#sprites+1]=layer
			end
		end
	end
end
data:extend(sprites)
