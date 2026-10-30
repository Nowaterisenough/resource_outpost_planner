defines={direction={north=0,east=4,south=8,west=12}}
script={active_mods={},feature_flags={},register_metatable=function() end}
game={tick=1}
storage={players={}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
prototypes={entity={},tile={},quality={},item={}}
local function tile(name,layers,cover)
	local proto={name=name,collision_mask={layers=layers},default_cover_tile=cover}
	prototypes.tile[name]=proto
	return {name=name,prototype=proto,position={x=0,y=0}}
end
local grass=tile("grass-1",{ground_tile=true})
local water=tile("water",{water_tile=true},{name="landfill"})
local lava=tile("lava",{lava_tile=true},{name="foundation"})
local void=tile("out-of-map",{out_of_map=true})
local space=tile("se-space",{})
local mod_tile=tile("mod-coverable",{object=true},{name="foundation"})
local obstacles=require("mpp.obstacles")
local queries={}
local entities={}
local ignored_entity_types={resource=true,character=true,unit=true,corpse=true,["item-entity"]=true,["tile-ghost"]=true}
local surface={
	find_tiles_filtered=function(query)
		queries[#queries+1]=query
		assert(query.name,"terrain query materializes every ground tile")
		local names={};for _,name in ipairs(query.name) do names[name]=true end
		assert(not names[grass.name],"ordinary ground reaches Lua")
		for _,t in ipairs{water,lava,void,space,mod_tile} do assert(names[t.name],"hazard omitted: "..t.name) end
		return {}
	end,
	find_entities_filtered=function(query)
		assert(query.type and query.invert==true,"obstacle scan materializes ignored entities")
		local excluded={};for _,kind in ipairs(query.type) do excluded[kind]=true end
		for kind in pairs(ignored_entity_types) do assert(excluded[kind],"ignored type reaches Lua: "..kind) end
		for kind in pairs(excluded) do assert(ignored_entity_types[kind],"obstacle type excluded: "..kind) end
		local result={}
		for _,e in ipairs(entities) do if not excluded[e.type] then result[#result+1]=e end end
		return result
	end,
}
local area={{-100,-100},{100,100}}
obstacles.collect(surface,area,nil,{terrain_mode_choice="avoid"})
local function box(x1,y1,x2,y2) return {left_top={x=x1,y=y1},right_bottom={x=x2,y=y2}} end
local function entity(bounds,kind,unit)
	return {valid=true,type=kind or "container",unit_number=unit,bounding_box=bounds,
		prototype={collision_mask={layers={object=true}}}}
end
local near=box(.1,.1,.9,.9)
local sliver=box(1.9999,1.1,2.5,1.9)
entities={entity(near),entity(sliver),entity(box(-2.8,-2.8,-2.2,-2.2))}
local distant_reads=0
for i=1,2000 do
	local data=box(1000+i,1000,1000.8+i,1000.8)
	local observed=setmetatable({}, {__index=function(_,field) distant_reads=distant_reads+1;return data[field] end})
	entities[#entities+1]=entity(observed)
end
local index=obstacles.collect(surface,area,nil,{deconstruction_choice=true})
distant_reads=0
assert(obstacles.blocked_box(index,box(.2,.2,.8,.8)))
assert(not obstacles.blocked_box(index,box(.91,.1,.99,.9)),"bucket hit ignores exact collision bounds")
assert(obstacles.blocked_box(index,box(1.9998,1.2,2,1.8)),"fractional cell-edge overlap lost")
assert(obstacles.blocked_box(index,box(-2.7,-2.7,-2.3,-2.3)),"negative cell indexing lost")
assert(not obstacles.blocked_box(index,box(10.1,10.1,10.9,10.9)))
assert(distant_reads==0,"local placement checks scan distant buildings")
local cases=5
for x=-5,8 do for y=-5,8 do
	local probe=box(x*.41,y*.37,x*.41+.35,y*.37+.46)
	local expected=false
	for _,e in ipairs(entities) do
		local b=e.bounding_box
		if probe.left_top.x<b.right_bottom.x and probe.right_bottom.x>b.left_top.x
			and probe.left_top.y<b.right_bottom.y and probe.right_bottom.y>b.left_top.y then expected=true;break end
	end
	assert(obstacles.blocked_box(index,probe)==expected,"spatial index differs from exact overlap test")
	assert(obstacles.blocked_bounds(index,probe.left_top.x,probe.left_top.y,probe.right_bottom.x,probe.right_bottom.y)==expected,"numeric bounds differ from exact collision test")
	cases=cases+1
end end
entities={entity(near,"cliff",1),entity(sliver,"container",2),entity(box(5,5,6,6),"entity-ghost",3)}
entities[3].ghost_prototype=entities[3].prototype
index=obstacles.collect(surface,area,{[3]=true},{cliff_mode_choice="avoid",deconstruction_choice=false})
assert(#index.boxes==1 and obstacles.blocked_box(index,near),"cliff mode changed")
index=obstacles.collect(surface,area,{[3]=true},{cliff_mode_choice="remove",deconstruction_choice=true})
assert(#index.boxes==1 and obstacles.blocked_box(index,sliver),"retained building or owned ghost handling changed")
entities={}
for kind in pairs(ignored_entity_types) do
	entities[#entities+1]=setmetatable({type=kind},{__index=function() error("ignored entity inspected in Lua: "..kind) end})
end
local retained_bounds={}
for i,kind in ipairs{"entity-ghost","cliff","container","tree","simple-entity","straight-rail","cargo-wagon"} do
	local bounds=box(i*2,.1,i*2+.9,.9)
	local e=entity(bounds,kind,100+i)
	if kind=="entity-ghost" then e.ghost_prototype=e.prototype end
	entities[#entities+1]=e;retained_bounds[#retained_bounds+1]=bounds
end
index=obstacles.collect(surface,area,nil,{cliff_mode_choice="avoid",deconstruction_choice=true})
assert(#index.boxes==#retained_bounds,"engine filtering dropped an actual obstacle")
for _,bounds in ipairs(retained_bounds) do assert(obstacles.blocked_box(index,bounds),"retained obstacle lost") end
local state={surface=surface,coords={x1=0,y1=0,x2=24,y2=24},terrain_mode_choice="avoid",
	_belt_search_margin=400,_belt_search_area={{-16,-32},{160,96}}}
local before=#queries
obstacles.get(state)
local q=queries[#queries]
assert(q.area[1][1]==-16 and q.area[2][1]==160,"route scan uses an inflated square")
state._belt_search_area={{-12,-28},{140,90}}
obstacles.get(state);assert(#queries==before+1,"contained route repeats the world scan")
state._belt_search_area={{-48,-64},{192,128}}
obstacles.get(state);assert(#queries==before+2,"wider retry uses a stale obstacle snapshot")
game.tick=2
obstacles.get(state);assert(#queries==before+3,"world changes are hidden across ticks")
local shape_reads=0
prototypes.entity.machine={tile_width=2,tile_height=3,collision_box=box(-.7,-1.1,.9,1.4),
	has_flag=function() shape_reads=shape_reads+1;return false end}
local expected_shapes={{1.3,2.4,2.9,4.9},{1.1,2.3,3.6,3.9},{1.1,2.1,2.7,4.6},{1.4,2.1,3.9,3.7}}
for i,direction in ipairs{0,4,8,12} do
	for repeat_index=1,5 do
		local actual=obstacles.entity_box("machine",{x=2.2,y=3.2},direction)
		local values={actual.left_top.x,actual.left_top.y,actual.right_bottom.x,actual.right_bottom.y}
		for j,value in ipairs(values) do assert(math.abs(value-expected_shapes[i][j])<1e-9,"cached geometry changes snapping or rotation") end
	end
end
assert(shape_reads==4,"prototype shape is recomputed for every route cell")
prototypes.entity.machine={tile_width=2,tile_height=3,collision_box=box(-.7,-1.1,.9,1.4),has_flag=function() return true end}
local free=obstacles.entity_box("machine",{x=2.2,y=3.2},0)
assert(math.abs(free.left_top.x-1.5)<1e-9 and math.abs(free.left_top.y-2.1)<1e-9,"off-grid geometry or prototype replacement uses stale offsets")
-- Empty output corridors need no per-cell engine lookup. A real overlapping
-- belt still needs direction/quality matching before it can be reused.
do
	local native_queries,existing=0,{}
	local proto={type="transport-belt",tile_width=1,tile_height=1,collision_box=box(-.4,-.4,.4,.4),
		collision_mask={layers={object=true}},has_flag=function() return false end}
	prototypes.entity["test-belt"]=proto
	local map={find_tiles_filtered=function() return {} end,find_entities_filtered=function(query)
		if query.position then native_queries=native_queries+1 end
		return existing
	end}
	local state={surface=map,coords={x1=0,y1=0,x2=10,y2=10},player={index=1,force={}},output_only=true,remove_entities_choice=false}
	for x=1,20 do assert(obstacles.can_place(state,"test-belt",{x=x+.5,y=.5},0)) end
	assert(native_queries==0,"empty output probes query the engine for existing belts")
	existing[1]={valid=true,name="test-belt",type="transport-belt",position={x=.5,y=.5},direction=0,
		quality={name="normal"},prototype=proto,bounding_box=box(.1,.1,.9,.9)}
	game.tick=game.tick+1
	assert(obstacles.can_place(state,"test-belt",{x=.5,y=.5},0),"matching placed belt no longer reusable")
	assert(not obstacles.can_place(state,"test-belt",{x=.5,y=.5},4),"opposing existing belt treated as reusable")
	state.belt_quality_choice="legendary"
	assert(not obstacles.can_place(state,"test-belt",{x=.5,y=.5},0),"existing belt quality is ignored")
	cases=cases+4
end
do
 local queries=0
 local proto=prototypes.entity["test-belt"]
 local entity={valid=true,name="test-belt",type="transport-belt",position={x=32,y=0},direction=0,quality={name="normal"}}
 local map={find_entities_filtered=function(query) queries=queries+1;return {entity} end}
 local state={surface=map,player={force={}},output_only=true,preview_only=true}
 for i=1,10 do assert(obstacles.shared_entity(state,"test-belt",{x=32,y=0},0)==entity) end
 assert(queries==1,"same-tick preview repeats spatial engine queries")
 assert(not obstacles.shared_entity(state,"test-belt",{x=32,y=0},4),"shared preview ignores direction")
 assert(not obstacles.shared_entity(state,"test-belt",{x=32,y=0},0,"legendary"),"shared preview ignores quality")
 entity.valid=false
 assert(not obstacles.shared_entity(state,"test-belt",{x=32,y=0},0),"destroyed cached entity reused")
 entity.valid=true;game.tick=game.tick+1
 assert(obstacles.shared_entity(state,"test-belt",{x=32,y=0},0)==entity and queries==2,"next-tick preview reuses stale world query")
 state.preview_only=false
 obstacles.shared_entity(state,"test-belt",{x=32,y=0},0);obstacles.shared_entity(state,"test-belt",{x=32,y=0},0)
 assert(queries==4,"actual construction reuses the read-only preview cache")
 cases=cases+6
end
-- Negative chunk boundaries include neighboring cells, and candidate order
-- must not hide a matching ghost behind a wrong direction/quality entity.
do
 local bad={valid=true,name="test-belt",type="transport-belt",position={x=-32,y=0},direction=4,quality={name="normal"}}
 local ghost={valid=true,name="entity-ghost",type="entity-ghost",ghost_name="test-belt",
  position={x=-32.0005,y=-.0005},direction=0,quality={name="legendary"}}
 local queries=0
 local map={find_entities_filtered=function() queries=queries+1;return {bad,ghost} end}
 local state={surface=map,player={force={}},output_only=true,preview_only=true}
 assert(obstacles.shared_entity(state,"test-belt",{x=-32,y=0},0,"legendary")==ghost,"negative chunk boundary loses matching ghost")
 assert(not obstacles.shared_entity(state,"test-belt",{x=-32,y=0},0),"wrong quality ghost reused")
 assert(queries==1,"negative chunk repeats an unchanged query")
 cases=cases+3
end
print("Obstacles OK: "..cases.." collision comparisons, engine entity/terrain filters, local queries and scan bounds")
