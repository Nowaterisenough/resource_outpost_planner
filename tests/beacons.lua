-- Run from the repository root with Lua 5.2.
defines={direction={},inventory={mining_drill_modules=1,beacon_modules=2},events={on_tick=1}}
local directions={"north","northnortheast","northeast","eastnortheast","east","eastsoutheast","southeast","southsoutheast",
	"south","southsouthwest","southwest","westsouthwest","west","westnorthwest","northwest","northnorthwest"}
for i,name in ipairs(directions) do defines.direction[name]=i-1 end
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local result={};for k,v in pairs(t) do result[k]=table.deepcopy(v) end;return result
end
script={active_mods={},feature_flags={quality=true},register_metatable=function() end}
prototypes={entity={},item={},quality={}}
require("mpp.global_extends")
local beacons=require("mpp.beacons")
local common=require("layouts.common")
local cases=0
local function equal(actual,expected,label)
	assert(math.abs(actual-expected)<1e-9,label..": "..actual.." ~= "..expected)
	cases=cases+1
end
local function check(value,label) assert(value,label);cases=cases+1 end
local function fixture()
	local beacon={type="beacon",name="beacon",tile_width=3,tile_height=3,profile={1,0.5,0.25},
		distribution_effectivity=1.5,distribution_effectivity_bonus_per_quality_level=0.2,
		allowed_effects={speed=true,consumption=true,pollution=true},allowed_module_categories={speed=true,efficiency=true},
		get_inventory_size=function(inv,quality) assert(inv==defines.inventory.beacon_modules);return quality=="legendary" and 3 or 2 end,
		get_supply_area_distance=function() return 3 end}
	local speed={name="speed",type="module",category="speed",
		get_module_effects=function(quality) return {speed=quality=="legendary" and 1.25 or 0.5,consumption=0.7,quality=-0.025} end}
	local efficiency={name="efficiency",type="module",category="efficiency",get_module_effects=function() return {consumption=-0.8} end}
	local productivity={name="productivity",type="module",category="productivity",get_module_effects=function() return {speed=-0.15,productivity=0.1} end}
	local drill={mining_speed=0.5,tile_width=3,tile_height=3,uses_force_mining_productivity_bonus=true,
		effect_receiver={uses_beacon_effects=true,uses_module_effects=true},get_inventory_size=function() return 3 end}
	prototypes={entity={beacon=beacon,drill=drill,ore={mineable_properties={mining_time=1,products={{type="item",amount=1}}}}},
		item={speed=speed,efficiency=efficiency,productivity=productivity},quality={normal={level=0},legendary={level=5}}}
	local miner={}
	return {beacon_choice="beacon",beacon_quality_choice="normal",beacon_module_choice="speed",beacon_module_quality_choice="normal",
		miner_choice="drill",miner_quality_choice="normal",module_choice="none",resource_counts={{name="ore"}},
		player={force={mining_drill_productivity_bonus=0}},surface={},layout_choice="simple",
		_beacons_prepared=true,_beacon_counts={[miner]=1},miner={drops_full_belt_stacks=false}},miner
end
local state,miner=fixture()
equal(beacons.target_count(state),4,"new and existing choices default to dense coverage")
for _,value in ipairs{0,1,2,4} do
	state.beacon_density_choice=value
	equal(beacons.target_count(state),value,"density selection accepts each supported target")
end
state.beacon_density_choice=3;equal(beacons.target_count(state),4,"invalid density resets to default")
state.beacon_density_choice=nil
check(beacons.enabled(state),"mining beacon enabled")
state.beacon_choice="none";check(not beacons.enabled(state),"beacon disabled by default")
equal(common.get_mining_drill_production_from_state(state,nil,miner),0.5,"disabled beacon production")
state.beacon_choice="beacon"
for _,layout in ipairs{"blueprints","oil"} do state.layout_choice=layout;check(not beacons.enabled(state),"template and oil use their own beacons") end
state.layout_choice="simple";prototypes.entity.drill.effect_receiver.uses_beacon_effects=false
check(not beacons.enabled(state),"drill refuses beacon effects")
state,miner=fixture()
check(beacons.module_allowed(prototypes.entity.beacon,prototypes.item.speed),"allowed speed module")
check(beacons.module_allowed(prototypes.entity.beacon,prototypes.item.efficiency),"allowed efficiency module")
check(not beacons.module_allowed(prototypes.entity.beacon,prototypes.item.productivity),"disallowed category")
prototypes.entity.beacon.allowed_module_categories=nil
check(not beacons.module_allowed(prototypes.entity.beacon,prototypes.item.productivity),"disallowed productivity effect")
check(not beacons.module_allowed(prototypes.entity.beacon,nil),"missing module")
check(not beacons.module_allowed(prototypes.entity.beacon,{type="item"}),"ordinary item")
equal(beacons.effects(state,miner).speed,1.5,"one beacon effects")
equal(common.get_mining_drill_production_from_state(state,nil,miner),1.25,"one beacon production")
state._beacon_counts[miner]=2;equal(beacons.effects(state,miner).speed,1.5,"two beacon attenuation")
state._beacon_counts[miner]=3;equal(beacons.effects(state,miner).speed,1.125,"three beacon attenuation")
state._beacon_counts[miner]=4;equal(beacons.effects(state,miner).speed,1.5,"last profile entry extends")
state._beacon_counts[miner]=0;equal(beacons.effects(state,miner).speed,0,"uncovered drill")
equal(beacons.effects(state,{}).speed,0,"unknown drill")
state._beacon_counts[miner]=1;state.beacon_quality_choice="legendary"
equal(beacons.effects(state,miner).speed,3.75,"beacon quality effectivity and slots")
state.beacon_module_quality_choice="legendary"
equal(beacons.effects(state,miner).speed,9.375,"independent beacon module quality")
state.module_choice="productivity"
equal(common.get_mining_drill_production_from_state(state,nil,miner),6.45125,"separate drill and beacon modules")
local plan=beacons.module_plan(state)
check(plan[1].id.name=="speed" and plan[1].id.quality=="legendary","beacon module request item and quality")
check(#plan[1].items.in_inventory==3 and plan[1].items.in_inventory[1].stack==0
	and plan[1].items.in_inventory[3].stack==2,"all beacon slots requested with zero based indices")
state.beacon_module_choice="none";check(not beacons.module_plan(state),"clearing module removes request")
state.beacon_module_choice="productivity";check(not beacons.module_plan(state),"forbidden module removes request")
state,miner=fixture()
prototypes.entity.beacon.profile={1,0.7071}
prototypes.entity.beacon.get_inventory_size=function() return 2 end
prototypes.item.productivity.get_module_effects=function() return {speed=-0.15,productivity=0.16} end
state.beacon_quality_choice="legendary";state.beacon_module_quality_choice="legendary"
state.module_choice="productivity";state.player.force.mining_drill_productivity_bonus=0.7
state._beacon_counts[miner]=2
equal(common.get_mining_drill_production_from_state(state,nil,miner),10.233792,"native four decimal effect precision")
state,miner=fixture()
prototypes.entity.beacon.profile={1,0.7071,0.5774,0.5,0.4472,0.4082,0.3780,0.3536,0.3333}
prototypes.entity.drill.get_inventory_size=function() return 4 end
state.module_choice="productivity"
state._beacon_counts[miner]=9
equal(common.get_mining_drill_production_from_state(state,nil,miner),3.42972,"nine towers retain native half-decimal rounding")
state,miner=fixture()
state._beacons_prepared=false
local bound=beacons.effects(state,miner).speed
state._beacons_prepared=true
for n=0,25 do state._beacon_counts[miner]=n;check(beacons.effects(state,miner).speed<=bound,"preplacement bound keeps merges safe") end

state,miner=fixture()
local simple=require("layouts.simple")
state.belt={speed=7.5}
local uncovered={};state._beacon_counts[uncovered]=0
local belt={lane1={miner},lane2={uncovered}}
local a,b=simple:_calculate_belt_throughput(state,belt,defines.direction.west)
equal(a,1.25/7.5,"covered belt side")
equal(b,0.5/7.5,"uncovered belt side")

-- Replaying accepted merges must use actual coverage instead of the early upper bound.
local original_prepare=beacons.prepare
beacons.prepare=function() end
local source={lane1={miner},lane2={}}
local target={lane1={uncovered},lane2={uncovered}}
source.merge_target=target;source.merge_strategy="back-merge"
state.belts={source,target}
common.record_beacon_merge(state,source,target,defines.direction.south,defines.direction.east)
common.prepare_beacons(state,simple)
equal(target.merged_throughput1,0.5/7.5,"back merge first side")
equal(target.merged_throughput2,1.75/7.5,"back merge swapped second side")
source.merge_strategy="side-merge";state._beacon_merges={}
common.record_beacon_merge(state,source,target,defines.direction.south,defines.direction.west)
common.prepare_beacons(state,simple)
equal(target.merged_throughput1,1.75/7.5,"side merge adds actual covered output")
equal(target.merged_throughput2,0.5/7.5,"side merge preserves other side")
beacons.prepare=original_prepare

local function placement_fixture(scaling)
	local s=fixture()
	for _,name in ipairs{"drill","beacon"} do
		prototypes.entity[name].collision_box={left_top={x=-1.4,y=-1.4},right_bottom={x=1.4,y=1.4}}
		prototypes.entity[name].has_flag=function() return false end
	end
	s._beacons_prepared=nil;s._beacon_counts=nil
	s.pole_choice="none";s.direction_choice="west";s.performance_scaling=scaling
	s.coords={gx=0,gy=0,tw=24,th=24};s.best_attempt={miners={}};s.builder_miners={}
	for i=1,8 do
		local x,y=4+((i-1)%4)*6,4+math.floor((i-1)/4)*6
		s.best_attempt.miners[i]={origin_x=x,origin_y=y}
		s.builder_miners[i]={name="drill",grid_x=x,grid_y=y}
	end
	s.grid={get_tile=function() return {} end,build_thing_simple=function() end}
	return s
end
local function finish_placement(s)
	local ticks=0
	while beacons.prepare(s,common.get_mining_drill_production_from_state) do
		ticks=ticks+1;assert(ticks<100,"beacon batching never completes")
		assert(not s._beacons_prepared,"unfinished beacons used in production")
	end
	return ticks
end
local batched=placement_fixture(0.25)
check(finish_placement(batched)>1,"beacon candidates are processed across ticks")
check(batched._beacons_prepared and not batched._beacon_planning,"temporary planning state cleared")
check(batched.beacon_summary[1]>0 and batched.beacon_summary[2]>0,"batched placement covers drills")
local immediate=placement_fixture(100)
equal(finish_placement(immediate),0,"large budget completes immediately")
equal(#batched.builder_beacons,#immediate.builder_beacons,"batch budget preserves tower count")
for i,spec in ipairs(batched.builder_beacons) do
	local other=immediate.builder_beacons[i]
	check(spec.grid_x==other.grid_x and spec.grid_y==other.grid_y,"batch budget preserves chosen positions")
end
for i,drill in ipairs(batched.best_attempt.miners) do
	equal(batched._beacon_counts[drill],immediate._beacon_counts[immediate.best_attempt.miners[i]],"batch budget preserves coverage")
end

local function joint_fixture(size,area,scaling)
	local s=placement_fixture(scaling or 100)
	local proto=prototypes.entity.drill
	proto.tile_width=size;proto.tile_height=size
	proto.collision_box={left_top={x=-size/2+0.1,y=-size/2+0.1},right_bottom={x=size/2-0.1,y=size/2-0.1}}
	prototypes.entity.beacon.profile={1,0.7071,0.5774,0.5,0.4472,0.4082}
	local outer=math.floor((area-size)/2)
	s.miner={size=size,area=area,extent_negative=-outer,extent_positive=size+outer-1}
	s.resource_tiles={};s.best_attempt={miners={},heuristics={}};s.builder_miners={};s.miner_lanes={};s.belts={}
	for y=1,24 do for x=1,24 do s.resource_tiles[#s.resource_tiles+1]={x=x,y=y} end end
	for row=1,4 do
		local lane={};s.miner_lanes[row]=lane
		local y=1+(row-1)*size+math.floor(row/2)
		for column=1,math.ceil(24/size) do
			local x=1+(column-1)*size
			local miner={x=x,y=y,origin_x=x+math.floor(size/2),origin_y=y+math.floor(size/2),line=row,column=column}
			s.best_attempt.miners[#s.best_attempt.miners+1]=miner;lane[#lane+1]=miner
			s.builder_miners[#s.builder_miners+1]={name="drill",grid_x=miner.origin_x,grid_y=miner.origin_y}
		end
	end
	for row=1,4,2 do s.belts[#s.belts+1]={lane1=s.miner_lanes[row],lane2=s.miner_lanes[row+1]} end
	return s
end
local function resource_coverage(s)
	local covered={}
	for _,miner in ipairs(s.best_attempt.miners) do
		for y=miner.y+s.miner.extent_negative,miner.y+s.miner.extent_positive do
			for x=miner.x+s.miner.extent_negative,miner.x+s.miner.extent_positive do covered[x..","..y]=true end
		end
	end
	return covered
end
local joint=joint_fixture(5,13)
local original_count=#joint.best_attempt.miners
local before=resource_coverage(joint)
finish_placement(joint)
check(#joint.best_attempt.miners<original_count,"shared interior towers replace redundant big drills")
check(#joint.builder_miners==#joint.best_attempt.miners,"removed drill is not built")
local after=resource_coverage(joint)
for _,tile in ipairs(joint.resource_tiles) do
	local k=tile.x..","..tile.y
	check(not before[k] or after[k],"joint optimization preserves each previously covered ore tile")
end
local total=0
for _,miner in ipairs(joint.best_attempt.miners) do total=total+common.get_mining_drill_production_from_state(joint,nil,miner) end
check(total>original_count*0.5,"joint layout increases actual production")
for _,belt in ipairs(joint.belts) do for _,lane in ipairs{belt.lane1,belt.lane2} do
	for _,miner in ipairs(lane) do check(joint._beacon_counts[miner]~=nil,"belt loads exclude removed drills") end
end end
local joint_batched=joint_fixture(5,13,0.25)
finish_placement(joint_batched)
equal(#joint_batched.best_attempt.miners,#joint.best_attempt.miners,"joint batching preserves drill count")
equal(#joint_batched.builder_beacons,#joint.builder_beacons,"joint batching preserves tower count")
for i,tower in ipairs(joint.builder_beacons) do
	local other=joint_batched.builder_beacons[i]
	check(tower.grid_x==other.grid_x and tower.grid_y==other.grid_y,"joint batching preserves regular positions")
end
local light=joint_fixture(5,13)
light.beacon_density_choice=1
finish_placement(light)
local filled=joint_fixture(5,13)
filled.beacon_density_choice=0
finish_placement(filled)
local function mean_towers(s)
	local sum=0
	for _,count in pairs(s._beacon_counts) do sum=sum+count end
	return sum/#s.best_attempt.miners
end
check(#joint.builder_beacons>#light.builder_beacons,"dense target keeps adding towers after every drill is covered")
check(mean_towers(joint)>mean_towers(light),"dense target increases actual overlap per drill")
check(#filled.builder_beacons>=#joint.builder_beacons,"fill mode does not prune to the target density")
local lowest,highest=math.huge,0
for _,count in pairs(joint._beacon_counts) do lowest=math.min(lowest,count);highest=math.max(highest,count) end
equal(joint.beacon_summary[4],lowest,"preview reports least affected drill")
equal(joint.beacon_summary[5],highest,"preview reports most affected drill")
local filled_coverage=resource_coverage(filled)
for _,tile in ipairs(filled.resource_tiles) do
	local k=tile.x..","..tile.y
	check(not before[k] or filled_coverage[k],"fill mode still preserves every previously mined ore tile")
end
local electric=joint_fixture(3,5)
local electric_count=#electric.best_attempt.miners
finish_placement(electric)
equal(#electric.best_attempt.miners,electric_count,"electric drill center ore cannot be sacrificed for a tower")
local efficiency=joint_fixture(5,13)
efficiency.beacon_module_choice="efficiency"
local efficiency_count=#efficiency.best_attempt.miners
finish_placement(efficiency)
equal(#efficiency.best_attempt.miners,efficiency_count,"efficiency towers never remove drills at a production loss")

local routed=placement_fixture(100)
prototypes.entity.route={tile_width=1,tile_height=1,collision_box={left_top={x=-0.4,y=-0.4},right_bottom={x=0.4,y=0.4}},has_flag=function() return false end}
routed.builder_belt_connections={}
for y=-3,20 do routed.builder_belt_connections[#routed.builder_belt_connections+1]={name="route",grid_x=0,grid_y=y} end
finish_placement(routed)
local obstacle_boxes=require("mpp.obstacles")
local util=require("mpp.mpp_util")
local function world_box(s,spec)
	local c=s.coords
	local p=util.revert_world(c.gx,c.gy,s.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
	return obstacle_boxes.entity_box(spec.name,{x=p[1],y=p[2]},defines.direction.north)
end
for _,tower in ipairs(routed.builder_beacons) do for _,belt in ipairs(routed.builder_belt_connections) do
	local a,b=world_box(routed,tower),world_box(routed,belt)
	check(a.left_top.x>=b.right_bottom.x or a.right_bottom.x<=b.left_top.x or a.left_top.y>=b.right_bottom.y or a.right_bottom.y<=b.left_top.y,
		"beacon placement preserves every output route tile")
end end
print("Beacons OK: "..cases.." selections, profiles, qualities, requests, per-drill loads and merge cases")
