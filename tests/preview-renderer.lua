-- Run from the repository root with Lua 5.2.
local sprites={}
local function image(name,width,height) return {filename=name,width=width,height=height,scale=0.5,shift={0.25,-0.5}} end
local belt=image("belt.png",128,128); belt.frame_count=16; belt.direction_count=20
local input=image("underground.png",192,192); input.y=192
data={raw={
	["transport-belt"]={belt={belt_animation_set={animation_set=belt}}},
	["underground-belt"]={underground={structure={direction_in={sheet=input},direction_out={sheet=image("underground.png",192,192)}}}},
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
assert(sprites["mpp-preview-underground-east-input-1"].x==192 and sprites["mpp-preview-underground-east-input-1"].y==192,"underground entrance ignores direction")
assert(sprites["mpp-preview-underground-west-output-1"].x==576 and sprites["mpp-preview-underground-west-output-1"].y==0,"underground exit uses entrance artwork")
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
rendering={draw_sprite=function(v) drawn[#drawn+1]=v; return {valid=true} end,
	draw_rectangle=function() error("native artwork still has an occupancy rectangle") end}
helpers={is_valid_sprite_path=function(name) return sprites[name]~=nil end}
game={get_player=function() return {force={}} end}
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

draft.specs={{name="entity-ghost",inner_name="miner",position={0.5,0.5},direction=N,preview_blocked=true}}
drawn={}
renderer.render(draft,{})
assert(drawn[1].tint==prototypes.utility_constants.building_not_buildable_tint,"unconnected but physically placeable belt stays green")
local obstacles=package.loaded["mpp.obstacles"]
obstacles.collect=function(_,_,_,choices) assert(choices.avoid_cliffs_choice);return {} end
obstacles.blocked_box=function() return true end
draft.specs[1].preview_blocked=nil
drawn={}
renderer.render(draft,{avoid_cliffs_choice=true,deconstruction_choice=true})
assert(drawn[1].tint==prototypes.utility_constants.building_not_buildable_tint,"forced placement overrides a selected obstacle in the preview")
cases=cases+2
print("Preview renderer OK: "..cases.." artwork, topology and blueprint rendering cases")
