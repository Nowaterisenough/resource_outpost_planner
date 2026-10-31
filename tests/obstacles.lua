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
-- Force placement can defer entity conflicts to the engine, but never makes
-- forbidden terrain passable (even if a matching ghost already sits there).
do
 local proto=prototypes.entity["test-belt"]
 local ghost={valid=true,name="entity-ghost",type="entity-ghost",ghost_name="test-belt",
  position={x=.5,y=.5},direction=0,quality={name="normal"},ghost_prototype=proto,bounding_box=box(.1,.1,.9,.9)}
 local facility=entity(box(2.1,.1,2.9,.9),"container",901)
 for _,mode in ipairs{"forced","superforced"} do
  for _,hazard in ipairs{water,lava,void} do for _,fill in ipairs{false,true} do
   local map={find_tiles_filtered=function() return {hazard} end,
    find_entities_filtered=function() return {ghost,facility} end}
   local state={surface=map,coords={x1=0,y1=0,x2=10,y2=10},player={index=1,force={}},
    _force_build_mode=mode,_belt_routing=true,output_only=true,remove_entities_choice=false,
    fill_water_choice=false,fill_lava_choice=fill,fill_other_choice=true}
   local expected=hazard==lava and fill
   assert(obstacles.can_place(state,"test-belt",{x=.5,y=.5},0)==expected,"force ignores terrain or reuses a ghost over lava")
   local check=obstacles.placement_checker(state,"test-belt",0)
   assert(check{x=.5,y=.5}==expected,"cached forced checker ignores terrain")
   assert(check{x=2.5,y=.5},"force no longer delegates facility conflicts to native placement")
   cases=cases+3
  end end
 end
end
-- A dry pair of endpoints must not tunnel under internal lava. Repair the
-- complete pair, preserve the mining receiver, and leave a connected route.
do
 local original_get,original_can_place=obstacles.get,obstacles.can_place
 prototypes.entity["test-underground"]={type="underground-belt"}
 local function k(x,y) return x..","..y end
 local hazard={}
 for x=6,7 do for y=-2,2 do hazard[k(x,y)]=true end end
 local index={tiles={},underground_tiles={},boxes={}}
 for x=6,7 do for y=-2,2 do index.tiles[k(x-1,y-1)]=true;index.underground_tiles[k(x-1,y-1)]=true end end
 obstacles.get=function() return index end
 obstacles.can_place=function(_,_,position) return not hazard[k(math.floor(position.x+.5),math.floor(position.y+.5))] end
 local cells={}
 local state={coords={gx=0,gy=0,tw=20,th=20},direction_choice="west",belt_choice="test-belt",
  belt={underground_reach=9,related_underground_belt="test-underground"},
  miner={output_rotated={[8]={x=0,y=1}}},best_attempt={miners={{x=11,y=-1,direction=8}}},
  grid={get_tile=function(_,x,y) return cells[k(x,y)] end}}
 local specs={}
 for _,x in ipairs{0,1,2,3,4,10,11,12} do
  local underground=x==4 or x==10
  specs[#specs+1]={name=underground and "test-underground" or "test-belt",grid_x=x,grid_y=0,
   direction=12,type=underground and (x==10 and "input" or "output") or nil}
  cells[k(x,0)]={built_thing="belt"}
 end
 local crossing={name="test-belt",grid_x=5,grid_y=0,direction=8}
 specs[#specs+1]=crossing;cells[k(5,0)]={built_thing="belt"}
 local ok,routed=obstacles.route_belts(state,specs)
 assert(ok,"dry tunnel endpoints over lava rejected instead of repaired")
 local positions={}
 for _,spec in ipairs(routed) do
  local key=k(spec.grid_x,spec.grid_y)
  assert(not positions[key],"detour visits its own surface tile twice")
  assert(not hazard[key],"repaired endpoint/surface belt sits on lava")
  positions[key]=spec
 end
 assert(positions[k(5,0)]==crossing,"repair destroyed a surface crossing inside the original tunnel")
 assert(positions[k(11,0)].name=="test-belt","repair hid a drill receiver underground")
 local delta={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
 local node,seen=positions[k(12,0)],{}
 while node and not (node.grid_x==0 and node.grid_y==0) do
  assert(not seen[node],"internal detour loops forever");seen[node]=true
  local d=delta[node.direction]
  if node.type=="input" then
   local output
   for distance=1,9 do
    local x,y=node.grid_x+d[1]*distance,node.grid_y+d[2]*distance
    assert(not hazard[k(x,y)],"underground detour still crosses lava")
    local candidate=positions[k(x,y)]
    if candidate and candidate.type=="output" and candidate.direction==node.direction then output=candidate;break end
   end
   assert(output,"detour tunnel has no matching output");node=output
  else node=positions[k(node.grid_x+d[1],node.grid_y+d[2])] end
 end
 assert(node,"repaired internal belt does not reach the mine edge")
 -- Filling must cover hidden tunnel cells, including cells without surface
 -- entities, so retained endpoints can pair once the foundations are built.
 index.tiles={};obstacles.can_place=function() return true end
 local fill_specs={}
 for _,x in ipairs{0,1,2,3,4,10,11,12} do
  local u=x==4 or x==10
  fill_specs[#fill_specs+1]={name=u and "test-underground" or "test-belt",grid_x=x,grid_y=0,direction=12,type=u and (x==10 and "input" or "output") or nil}
 end
 local fill_ok,fill=obstacles.route_belts(state,fill_specs)
 assert(fill_ok)
 assert(#fill==#fill_specs,"fill unnecessarily replaced a compact tunnel")
 assert(state._underground_fill and state._underground_fill[k(5,-1)] and state._underground_fill[k(6,-1)],"hidden lava lacks required foundation")
 assert(not state._underground_fill[k(7,-1)],"hidden foundation extends onto dry ground")
 index.underground_tiles={}
 local dry_ok,dry=obstacles.route_belts(state,fill_specs)
 assert(dry_ok and dry==fill_specs and not state._underground_fill,"clear terrain rebuilds an unchanged plan or retains stale underground fill")
 obstacles.get,obstacles.can_place=original_get,original_can_place
 cases=cases+3
end
print("Obstacles OK: "..cases.." collision comparisons, engine entity/terrain filters, local queries and scan bounds")
