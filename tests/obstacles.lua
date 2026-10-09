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
local surface={
	find_tiles_filtered=function(query)
		queries[#queries+1]=query
		assert(query.name,"terrain query materializes every ground tile")
		local names={};for _,name in ipairs(query.name) do names[name]=true end
		assert(not names[grass.name],"ordinary ground reaches Lua")
		for _,t in ipairs{water,lava,void,space,mod_tile} do assert(names[t.name],"hazard omitted: "..t.name) end
		return {}
	end,
	find_entities_filtered=function() return entities end,
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
	cases=cases+1
end end
entities={entity(near,"cliff",1),entity(sliver,"container",2),entity(box(5,5,6,6),"entity-ghost",3)}
entities[3].ghost_prototype=entities[3].prototype
index=obstacles.collect(surface,area,{[3]=true},{cliff_mode_choice="avoid",deconstruction_choice=false})
assert(#index.boxes==1 and obstacles.blocked_box(index,near),"cliff mode changed")
index=obstacles.collect(surface,area,{[3]=true},{cliff_mode_choice="remove",deconstruction_choice=true})
assert(#index.boxes==1 and obstacles.blocked_box(index,sliver),"retained building or owned ghost handling changed")
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
print("Obstacles OK: "..cases.." collision comparisons, filtered terrain, local queries and scan bounds")
