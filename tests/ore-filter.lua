defines={direction={north=0,east=4,south=8,west=12}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
script={active_mods={},feature_flags={}}
prototypes={entity={},item={},quality={}}
local function entity(name,kind,w,h,speed)
	local proto={name=name,type=kind,tile_width=w,tile_height=h,belt_speed=speed,
		collision_box={left_top={x=-w/2+.1,y=-h/2+.1},right_bottom={x=w/2-.1,y=h/2-.1}},
		has_flag=function() return false end}
	prototypes.entity[name]=proto;return proto
end
for _,name in ipairs{"iron-ore","copper-ore"} do
	local p=entity(name,"resource",1,1)
	p.localised_name=name;p.mineable_properties={products={{name=name,type="item"}}}
end
entity("resource-deposit","resource",1,1).mineable_properties={products={{name="custom-crystal",type="item"}}}
entity("crude-oil","resource",1,1).mineable_properties={products={{name="crude-oil",type="fluid"}}}
entity("belt","transport-belt",1,1,.125)
entity("sorter","splitter",2,1,.125)
entity("wrong-speed","splitter",2,1,.25)
local util=require("mpp.mpp_util")
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local blocked=false
package.loaded["mpp.obstacles"]={entity_box=require("mpp.obstacles").entity_box,can_place=function() return not blocked end}
local filter=require("mpp.ore_filter")
check(filter.product("resource-deposit")=="custom-crystal","resource name used instead of mined item")
check(filter.product("crude-oil")==nil,"fluid resource is selectable")
check(#filter.resource_filters()==3,"resource picker contains non-solid resources")
local state={ore_filtering_choice=true,ore_filter_resource_choice="none",resource_counts={{name="copper-ore",count=900},{name="iron-ore",count=1}}}
local ok,err=filter.select(state)
check(not ok and err[1]=="mpp.ore_filter_select","missing selection silently chose majority ore")
state.ore_filter_resource_choice="iron-ore"
check(filter.select(state) and state.ore_filtering_selected=="iron-ore" and state.ore_filter_item=="iron-ore","explicit minority ore ignored")
state.ore_filter_resource_choice="resource-deposit"
ok,err=filter.select(state)
check(not ok and err[1]=="mpp.ore_filter_missing","absent selected ore accepted")
for _,direction in ipairs{"north","east","south","west"} do
	for count=1,12 do
		local s={ore_filter_item="iron-ore",ore_filter_with_splitters=true,belt_choice="belt",belt_quality_choice="legendary",
			direction_choice=direction,coords={gx=0,gy=0,tw=100,th=100},belts={},builder_belts={}}
		for i=1,count do
			s.belts[i]={is_output=true,x_start=0,y=i}
			s.builder_belts[i]={name="belt",grid_x=0,grid_y=i,direction=12}
		end
		check(filter.prepare(s),"dense adjacent outlets failed")
		check(#s._ore_filter_reserved==count,"unfiltered outlets are unprotected")
		local filters=0
		for _,spec in ipairs(s.builder_belts) do if spec.filter then
			filters=filters+1
			check(spec.name=="sorter" and spec.filter.name=="iron-ore" and spec.output_priority=="left","splitter configuration wrong")
			check(spec.filter.comparator==">=" and spec.filter.quality=="normal","higher-quality ore is rejected")
			check(spec.quality=="legendary","splitter quality lost")
			check(spec.grid_x==s.belts[filters].x_start,"output source bypasses splitter")
			check(spec.grid_y==s.belts[filters].y-.5,"filter points to waste port")
		end end
		check(filters==count,"an output has no filter")
		local length=#s.builder_belts
		check(filter.prepare(s) and #s.builder_belts==length,"repeated preparation duplicates filters")
	end
end
local s={ore_filter_item="iron-ore",ore_filter_with_splitters=true,belt_choice="belt",direction_choice="west",
	coords={gx=0,gy=0,tw=100,th=100},belts={{is_output=true,x_start=0,y=1}},builder_belts={}}
blocked=true
check(not filter.prepare(s) and #s.builder_belts==0 and s.belts[1].x_start==0,"failed filter plan partially changed geometry")
blocked=false;s._beacon_logistics=true
check(filter.prepare(s) and #s.builder_belts==0,"logistics layout received belt splitters")
print("Ore filtering OK: "..checks.." explicit resource, product, tier, quality, rotation, isolation and atomicity checks")
