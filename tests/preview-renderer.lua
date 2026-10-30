-- Run from the repository root with Lua 5.2.
local sprites={}
local function image(name,width,height) return {filename=name,width=width,height=height,scale=0.5,shift={0.25,-0.5}} end
local belt=image("belt.png",128,128); belt.frame_count=16; belt.direction_count=20
local input=image("underground.png",192,192); input.y=192
data={raw={
	["transport-belt"]={belt={belt_animation_set={animation_set=belt}}},
	["underground-belt"]={underground={belt_animation_set={animation_set=belt},structure={
		back_patch={sheet=image("back.png",192,192)},front_patch={sheet=image("front.png",192,192)},
		direction_in={sheet=input},direction_out={sheet=image("underground.png",192,192)}}}},
	["electric-pole"]={pole={pictures={layers={image("pole.png",84,252)}}}},
	["mining-drill"]={miner={graphics_set={animation={north=image("miner-N.png",190,198),east=image("miner-E.png",198,190)}}}},
	pipe={pipe={pictures={straight_vertical_single=image("pipe-single.png",160,160),corner_up_right=image("pipe-corner.png",128,128)}}},
	["heat-pipe"]={heat={connection_sprites={single={image("heat-single.png",64,64)}}}},
	tile={landfill={variants={main={{picture="landfill.png",size=1}}}}},
},extend=function(_,values) for _,v in ipairs(values) do sprites[v.name]=v end end}
data.raw["electric-pole"].pole.pictures.layers[1].direction_count=4
require("prototypes.preview")
assert(sprites["mpp-preview-belt-east_to_north-1"].y==4*128,"curve uses straight belt frame")
assert(sprites["mpp-preview-belt-starting_north-1"].y==16*128,"belt entrance uses wrong frame")
for i,dir in ipairs{"north","east","south","west"} do
	for _,kind in ipairs{"input","output"} do
		local prefix="mpp-preview-underground-"..dir.."-"..kind.."-"
		local facing=(i-1+(kind=="output" and 2 or 0))%4
		for _,layer in ipairs{1,3,4} do assert(sprites[prefix..layer].x==facing*192,"tunnel structure or patch faces backwards") end
		assert(sprites[prefix..3].y==(kind=="input" and 192 or 0),"wrong entrance/exit texture")
		assert(sprites[prefix..2].y==sprites["mpp-preview-belt-"..dir.."-1"].y,"tunnel correction reversed belt flow artwork")
	end
end
assert(sprites["mpp-preview-pole-east-1"].x==84 and sprites["mpp-preview-pole-east-1"].shift[2]==-0.5,"rotated sprite loses native offset")
assert(sprites["mpp-preview-miner-east-1"].filename=="miner-E.png","miner direction artwork changed")
assert(sprites["mpp-preview-pipe-corner_up_right-1"] and sprites["mpp-preview-heat-single-1"],"connected pipes fall back to icons")
assert(sprites["mpp-preview-tile-landfill-north-1"].width==32,"landfill is not drawn at tile size")

defines={direction={north=0,east=4,south=8,west=12},build_check_type={blueprint_ghost=1}}
local N,E,S,W=0,4,8,12
local positions={[N]={x=0,y=-1},[E]={x=1,y=0},[S]={x=0,y=1},[W]={x=-1,y=0}}
package.loaded["mpp.mpp_util"]={direction_coord=positions}
package.loaded["mpp.obstacles"]={
	active=function(choices) return choices.cliff_mode_choice or choices.terrain_mode_choice or choices.avoid_cliffs_choice end,
	entity_box=function() return {left_top={x=-0.5,y=-0.5},right_bottom={x=0.5,y=0.5}} end,
}
local renderer=require("mpp.preview_renderer")
prototypes={entity={},utility_constants={building_buildable_tint={0.4,1,0.4,1},building_not_buildable_tint={1,0.4,0.4,1}}}
for name,typ in pairs{belt="transport-belt",underground="underground-belt",pipe="pipe",heat="heat-pipe",miner="mining-drill"} do prototypes.entity[name]={type=typ} end
local spec={inner_name="belt",direction=N,position={x=0.5,y=0.5}}
local cases=8
local curves={
	[N]={[E]="west_to_north",[W]="east_to_north"},
	[E]={[N]="south_to_east",[S]="north_to_east"},
	[S]={[E]="west_to_south",[W]="east_to_south"},
	[W]={[N]="south_to_west",[S]="north_to_west"},
}
for _,out in ipairs{N,E,S,W} do
	for _,incoming in ipairs{N,E,S,W} do
		if incoming~=out and incoming~=(out+S)%16 then
			local delta=positions[incoming]
			local nodes={[tostring(0.5-delta.x)..","..tostring(0.5-delta.y)]={type="transport-belt",direction=incoming}}
			spec.direction=out
			local variant=renderer.variant(spec,nodes,{})
			assert(variant==curves[out][incoming],"curve artwork uses movement instead of entry side")
			cases=cases+1
		end
	end
end
spec={inner_name="pipe",direction=N,position={x=0.5,y=0.5}}
assert(renderer.variant(spec,{["0.5,-0.5"]={type="pipe"},["1.5,0.5"]={type="pipe"}}, {})=="corner_up_right","pipe corner is not connected")
assert(renderer.variant(spec,{}, {["0.5,-0.5"]={[S]=true}})=="ending_up","pipe does not meet machine port")
spec.inner_name="underground"; spec.direction=E; spec.type="output"
assert(renderer.variant(spec,{}, {})=="east-output","underground output lost")
cases=cases+3

local drawn={}
local render_id=0
rendering={draw_sprite=function(v)
	drawn[#drawn+1]=v;render_id=render_id+1
	local object={valid=true,id=render_id,definition=v,sprite=v.sprite,target=v.target,color=v.tint,
		x_scale=v.x_scale,y_scale=v.y_scale,orientation=v.orientation or 0,render_layer=v.render_layer}
	object.destroy=function() object.valid=false end
	return object
end,
	draw_rectangle=function() error("native artwork still has an occupancy rectangle") end}
local sprite_checks=0
helpers={is_valid_sprite_path=function(name) sprite_checks=sprite_checks+1;return sprites[name]~=nil end}
game={get_player=function(index) return {index=index,force={}} end}
local surface={find_entities_filtered=function() return {} end,can_place_entity=function(v) return v.position.x~=4.5 end}
local draft={surface=surface,player_index=1,specs={
	{name="entity-ghost",inner_name="miner",position={0.5,0.5},direction=N},
	{name="entity-ghost",inner_name="miner",position={4.5,0.5},direction=E,mirror=true},
	{name="tile-ghost",inner_name="landfill",position={0,0}},
}}
local objects=renderer.render(draft,{})
assert(#objects==3 and #drawn==3,"preview lost native artwork")
assert(drawn[1].x_scale==1 and drawn[1].y_scale==1 and drawn[1].tint==prototypes.utility_constants.building_buildable_tint,"blueprint preview changes original size or tint")
assert(drawn[2].tint==prototypes.utility_constants.building_not_buildable_tint and drawn[2].y_scale==-1,"blocked or mirrored blueprint preview wrong")
assert(drawn[3].target[1]==0.5 and drawn[3].target[2]==0.5,"tile texture is off-center")
assert(drawn[1].render_layer=="cursor" and drawn[1].light_mode=="glow","preview differs from blueprint visibility")
cases=cases+4
local first_checks=sprite_checks
drawn={}
surface.can_place_entity=function() return true end
local updated,retained=renderer.render(draft,{})
assert(sprite_checks==first_checks,"unchanged sprite paths were queried again, including missing variants")
assert(#drawn==0 and updated[2].y_scale==-1,"cached sprite lost mirrored artwork")
assert(updated[2].color==prototypes.utility_constants.building_buildable_tint,"sprite cache hid a live placement change")
assert(updated[1]==objects[1] and updated[3]==objects[3] and updated[2]==objects[2],"sprite handles were rebuilt")
assert(retained[objects[1].id] and retained[objects[3].id] and retained[objects[2].id],"retained object ownership is wrong")
cases=cases+3

draft.specs={{name="entity-ghost",inner_name="miner",position={0.5,0.5},direction=N,preview_blocked=true}}
drawn={}
local failed=renderer.render(draft,{})
assert(failed[1].color==prototypes.utility_constants.building_not_buildable_tint,"unconnected but physically placeable belt stays green")
local obstacles=package.loaded["mpp.obstacles"]
obstacles.collect=function(_,_,_,choices) assert(choices.avoid_cliffs_choice);return {} end
obstacles.blocked_box=function() return true end
draft.specs[1].preview_blocked=nil
drawn={}
local selected=renderer.render(draft,{avoid_cliffs_choice=true,deconstruction_choice=true})
assert(selected[1]==failed[1] and #drawn==0,"unchanged blocked sprite was rebuilt")
assert(selected[1].color==prototypes.utility_constants.building_not_buildable_tint,"forced placement overrides a selected obstacle in the preview")
cases=cases+2
selected[1].destroy()
local restored=renderer.render(draft,{avoid_cliffs_choice=true})
assert(restored[1].valid and restored[1]~=selected[1],"externally destroyed sprite was reused")
draft.player_index=2
local other_player=renderer.render(draft,{})
assert(other_player[1]~=restored[1] and other_player[1].definition.players[1].index==2,"sprite leaked between players")
draft.surface={find_entities_filtered=function() return {} end,can_place_entity=function() return true end}
local other_surface=renderer.render(draft,{})
assert(other_surface[1]~=other_player[1] and other_surface[1].definition.surface==draft.surface,"sprite remained on the old surface")

draft.specs={{name="entity-ghost",inner_name="belt",position={.5,.5},direction=N}}
local straight=renderer.render(draft,{})
draft.specs[2]={name="entity-ghost",inner_name="belt",position={-.5,.5},direction=E}
local curved=renderer.render(draft,{})
assert(curved[1]==straight[1] and curved[1].sprite=="mpp-preview-belt-west_to_north-1","neighbor changes left stale belt artwork")

draft.specs={draft.specs[1],draft.specs[1]}
local duplicates=renderer.render(draft,{})
local next_duplicates=renderer.render(draft,{})
assert(duplicates[1]~=duplicates[2] and next_duplicates[1]~=next_duplicates[2],"identical overlapping layers share one object")
draft.specs[3]=draft.specs[1]
local ordered=renderer.render(draft,{})
ordered[2].destroy()
local repaired,repair_retained=renderer.render(draft,{})
assert(repaired[1]==ordered[1] and repaired[2]~=ordered[2] and repaired[3]~=ordered[3],"invalid handle did not rebuild the remaining draw order")
assert(repaired[1].id<repaired[2].id and repaired[2].id<repaired[3].id and not repair_retained[ordered[3].id])

prototypes.entity.arm={type="inserter"}
for _,name in ipairs{"mpp-preview-arm-north-1","mpp-preview-arm-east-1","mpp-preview-arm-hand-1"} do sprites[name]={} end
draft.specs={{name="entity-ghost",inner_name="arm",position={.5,.5},direction=N}}
local north_arm=renderer.render(draft,{})
draft.specs[1].direction=E
local east_arm=renderer.render(draft,{})
assert(#east_arm==2 and east_arm[2]==north_arm[2] and east_arm[2].orientation==.25,"rotated inserter reused a stale hand")
local other_draft={surface=draft.surface,player_index=draft.player_index,specs=draft.specs}
renderer.render(other_draft,{})
local style_before=draft.sprite_renderings.entries[1][3]
assert(style_before~=other_draft.sprite_renderings.entries[1][3],"separate drafts share local cache tables through storage")
package.loaded["mpp.preview_renderer"]=nil
local reloaded=require("mpp.preview_renderer")
local after_load,load_retained=reloaded.render(draft,{})
assert(after_load[1]==east_arm[1] and load_retained[east_arm[1].id],"script reload lost persisted sprite ownership")
assert(draft.sprite_renderings.entries[1][3]==style_before,"script reload changed persisted style table sharing")
reloaded.render(other_draft,{})
assert(other_draft.sprite_renderings.entries[1][3]~=style_before,"reloaded drafts started sharing local cache tables")
cases=cases+14

local prototype_reads=0
local boxes={{pipe_connections={
	{connection_type="normal",direction=N,positions={{1,-2},{2,1},{-1,2},{-2,-1}}},
	{connection_type="normal",direction=E,positions={{2,-1},{1,2},{-2,1},{-1,-2}}},
	{connection_type="underground",direction=N,positions={{0,-2},{2,0},{0,2},{-2,0}}},
	{connection_type="normal",direction=N,positions={}},
}}}
prototypes.entity.machine=setmetatable({type="assembling-machine"},{__index=function(_,name)
	if name=="fluidbox_prototypes" then prototype_reads=prototype_reads+1;return boxes end
end})
local connections={
	{dir=N,offset={1,-3},shape="ending_down"},
	{dir=N,mirror=true,offset={-1,-3},shape="ending_down"},
	{dir=E,offset={3,1},shape="ending_left"},
	{dir=E,mirror=true,offset={3,-1},shape="ending_left"},
	{dir=S,offset={-1,3},shape="ending_up"},
	{dir=S,mirror=true,offset={1,3},shape="ending_up"},
	{dir=W,offset={-3,-1},shape="ending_right"},
	{dir=W,mirror=true,offset={-3,1},shape="ending_right"},
	{dir=N,offset={3,-1},shape="ending_left"},
	{dir=N,mirror=true,offset={-3,-1},shape="ending_right"},
	{dir=E,offset={1,3},shape="ending_up"},
	{dir=E,mirror=true,offset={1,-3},shape="ending_down"},
	{dir=S,offset={-3,1},shape="ending_right"},
	{dir=S,mirror=true,offset={3,1},shape="ending_left"},
	{dir=W,offset={-1,-3},shape="ending_down"},
	{dir=W,mirror=true,offset={-1,3},shape="ending_up"},
}
for _,name in ipairs{"single","ending_up","ending_down","ending_left","ending_right"} do
	sprites["mpp-preview-pipe-"..name.."-1"]={}
end
local live_entities={}
draft.surface.find_entities_filtered=function() return live_entities end
for _,connection in ipairs(connections) do
	for _,source in ipairs{"spec","entity","ghost"} do
		local x,y=10+connection.offset[1],20+connection.offset[2]
		local pipe={name="entity-ghost",inner_name="pipe",position={x,y}}
		local machine={name="entity-ghost",inner_name="machine",position={10,20},direction=connection.dir,mirror=connection.mirror}
		draft.specs={pipe};live_entities={}
		if source=="spec" then draft.specs[2]=machine
		else live_entities[1]={valid=true,name="machine",type=source=="ghost" and "entity-ghost" or "assembling-machine",
			ghost_name="machine",ghost_type="assembling-machine",position={10,20},direction=connection.dir,mirroring=connection.mirror} end
		local connected=reloaded.render(draft,{})
		assert(connected[1].sprite=="mpp-preview-pipe-"..connection.shape.."-1","cached fluid port lost direction/mirror for "..source)
		draft.specs={pipe};live_entities={}
		local disconnected=reloaded.render(draft,{})
		assert(disconnected[1].sprite=="mpp-preview-pipe-single-1","cached prototype kept a removed world connection")
		cases=cases+1
	end
end
assert(prototype_reads==1,"fluidbox prototypes are still read per entity or direction")
draft.specs={{name="entity-ghost",inner_name="pipe",position={10,17}},
	{name="entity-ghost",inner_name="machine",position={10,20},direction=N}}
assert(reloaded.render(draft,{})[1].sprite=="mpp-preview-pipe-single-1","underground connection became a surface port")
cases=cases+2

prototypes.entity.fallback={type="electric-pole"}
sprites["entity/fallback"]={}
local original_box=obstacles.entity_box
obstacles.entity_box=function(name,pos,dir)
	if name~="fallback" then return original_box(name,pos,dir) end
	local x,y=pos.x or pos[1],pos.y or pos[2]
	return {left_top={x=x-1,y=y-2},right_bottom={x=x+1,y=y+2}}
end
draft.specs={{name="entity-ghost",inner_name="fallback",position={12,15},direction=E,mirror=true}}
local fallback=reloaded.render(draft,{})
assert(fallback[1].sprite=="entity/fallback" and fallback[1].x_scale==1 and fallback[1].y_scale==-2,"cached fallback lost collision-box scale or mirror")
draft.specs[1].position={-7,-9}
local moved_fallback=reloaded.render(draft,{})
local moved_target=moved_fallback[1].target
assert(moved_fallback[1]==fallback[1] and (moved_target.x or moved_target[1])==-7
	and (moved_target.y or moved_target[2])==-9 and moved_fallback[1].y_scale==-2,"cached fallback retained the old position")

prototypes.entity.flipped={type="assembling-machine"}
sprites["mpp-preview-flipped-north-1"]={}
sprites["mpp-preview-flipped-north-flipped-1"]={}
draft.specs={{name="entity-ghost",inner_name="flipped",position={.5,.5},mirror=true}}
local flipped=reloaded.render(draft,{})
assert(flipped[1].sprite=="mpp-preview-flipped-north-flipped-1" and flipped[1].x_scale==1,"native flipped artwork was mirrored twice")
draft.specs[1].mirror=false
assert(reloaded.render(draft,{})[1].sprite=="mpp-preview-flipped-north-1","cached artwork retained the mirrored variant")

rendering.draw_rectangle=function(v)
	render_id=render_id+1
	return {valid=true,id=render_id,definition=v}
end
draft.specs={{name="tile-ghost",inner_name="missing-tile",position={-4,-6}},
	{name="entity-ghost",inner_name="miner",position={.5,.5}}}
local mixed=reloaded.render(draft,{})
local mixed_again,mixed_retained=reloaded.render(draft,{})
assert(mixed_again[1]~=mixed[1] and mixed_again[1].definition.left_top[1]==-4,"missing tile lost its fallback rectangle")
assert(mixed_again[2]==mixed[2] and mixed_retained[mixed[2].id] and not mixed_retained[mixed[1].id],"fallback rectangle shifted the sprite reuse sequence")
cases=cases+6
prototypes.entity.rail={type="straight-rail"}
local rail_layers={"rail-stone-path-lower","rail-stone-path","rail-tie","rail-screw","rail-metal"}
for _,direction in ipairs{"north","east","south","west"} do
	for _,layer in ipairs(rail_layers) do sprites["mpp-preview-rail-"..direction.."-"..layer.."-1"]={} end
end
draft.specs={{name="entity-ghost",inner_name="rail",position={0,0},direction=E},
	{name="entity-ghost",inner_name="rail",position={2,0},direction=E}}
local rails=reloaded.render(draft,{})
assert(#rails==10,"rail preview omitted ties, fasteners or metals")
for i,layer in ipairs(rail_layers) do
	assert(rails[i].render_layer==layer and rails[i+5].render_layer==layer,"adjacent rail components share the cursor layer")
	assert(rails[i].sprite=="mpp-preview-rail-east-"..layer.."-1","horizontal rail uses wrong artwork")
end
draft.specs[1].direction=N;draft.specs[2].direction=N;draft.specs[2].position={0,2}
local rotated=reloaded.render(draft,{})
for i,layer in ipairs(rail_layers) do
	assert(rotated[i]==rails[i] and rotated[i].sprite=="mpp-preview-rail-north-"..layer.."-1","rotation lost rail layer reuse")
	assert(rotated[i].render_layer==layer,"rotated rail lost native layer")
end
draft.specs={{name="entity-ghost",inner_name="miner",position={.5,.5},direction=N}}
local ordinary=reloaded.render(draft,{})
assert(ordinary[1]==rotated[1] and ordinary[1].render_layer=="cursor","reused rail handle left ordinary artwork on the ground layer")
cases=cases+17
-- Coordinate grids preserve fractional/negative positions and live neighbors.
for _,origin in ipairs{{-1024.25,.125},{1000000.5,-999999.5}} do
	local x,y=origin[1],origin[2]
	draft.specs={{name="entity-ghost",inner_name="belt",position={x=x,y=y},direction=N},
		{name="entity-ghost",inner_name="belt",position={x=x-1,y=y},direction=E}}
	local connected=reloaded.render(draft,{})
	assert(connected[1].sprite=="mpp-preview-belt-west_to_north-1","numeric topology loses a fractional neighbor")
	draft.specs[2].position.x=x-2
	local removed=reloaded.render(draft,{})
	assert(removed[1].sprite=="mpp-preview-belt-starting_north-1","shared topology shape retains a removed neighbor")
	cases=cases+2
end
local box_queries,placement_queries,placeable=0,0,true
local saved_box=obstacles.entity_box
obstacles.entity_box=function(...)
	box_queries=box_queries+1;return saved_box(...)
end
obstacles.blocked_box=function() return false end
draft.surface.can_place_entity=function() placement_queries=placement_queries+1;return placeable end
draft.specs={{name="entity-ghost",inner_name="miner",position={x=.5,y=.5},direction=N}}
local clear=reloaded.render(draft,{avoid_cliffs_choice=true})
assert(box_queries==1 and placement_queries==1,"one entity recomputes its collision bounds")
box_queries,placement_queries,placeable=0,0,false
local newly_blocked=reloaded.render(draft,{avoid_cliffs_choice=true})
assert(box_queries==1 and placement_queries==1 and newly_blocked[1]==clear[1]
	and newly_blocked[1].color==prototypes.utility_constants.building_not_buildable_tint,"geometry reuse caches live placement answers")
draft.specs[1].preview_blocked=true;placement_queries=0;placeable=true
local diagnostic=reloaded.render(draft,{avoid_cliffs_choice=true})
assert(placement_queries==0 and diagnostic[1].color==prototypes.utility_constants.building_not_buildable_tint,
	"known blocked diagnostics needlessly probe placement or become green")
cases=cases+3
-- Build collision bounds and artwork in separate batches, reloading the Lua
-- module midway just as Factorio does while the job tables survive in storage.
draft.specs={}
for i=1,11 do draft.specs[i]={name="entity-ghost",inner_name="belt",direction=N,position={x=i+.5,y=.5}} end
local expected=reloaded.render(draft,{avoid_cliffs_choice=true})
local job=reloaded.begin(draft,{avoid_cliffs_choice=true})
assert(not reloaded.step(draft,job,3) and job.box_next==4,"collision preparation ignored its batch limit")
package.loaded["mpp.preview_renderer"]=nil
reloaded=require("mpp.preview_renderer")
local finished,retained,steps
steps=1
repeat finished,retained=reloaded.step(draft,job,3);steps=steps+1 until finished
assert(steps==8 and #finished==#expected,"incremental rendering skipped or duplicated entities")
for i,obj in ipairs(finished) do
 assert(obj==expected[i] and retained[obj.id],"save/load continuation changed ordered sprite reuse")
end
cases=cases+3
print("Preview renderer OK: "..cases.." artwork, topology, reuse, invalidation and isolation cases")
