-- Run from the repository root with Lua 5.2.
defines={direction={},inventory={mining_drill_modules=1},events={on_tick=1}}
local names={"north","northnortheast","northeast","eastnortheast","east","eastsoutheast","southeast","southsoutheast",
	"south","southsouthwest","southwest","westsouthwest","west","westnorthwest","northwest","northnorthwest"}
for i,name in ipairs(names) do defines.direction[name]=i-1 end
function table_size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
script={active_mods={},feature_flags={quality=true},register_metatable=function() end}
prototypes={entity={},item={},quality={}}
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local result={}; for k,v in pairs(t) do result[k]=table.deepcopy(v) end; return result
end
require("mpp.global_extends")
local common=require("layouts.common")
local N,E,S,W=defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west
local cases=0
local function equal(actual,expected,label)
	assert(math.abs(actual-expected)<1e-9,label..": "..actual.." ~= "..expected)
	cases=cases+1
end
local function fixture()
	local drill={mining_speed=0.5,uses_force_mining_productivity_bonus=true,
		get_inventory_size=function(inv,quality) assert(inv==defines.inventory.mining_drill_modules); return quality=="legendary" and 5 or 3 end}
	prototypes={entity={drill=drill,ore={mineable_properties={mining_time=1,products={{type="item",amount=1}}}}},item={}}
	return {miner_choice="drill",miner_quality_choice="normal",module_choice="none",resource_counts={{name="ore"}},
		miner={module_inventory_size=3,drops_full_belt_stacks=false},player={force={mining_drill_productivity_bonus=0,belt_stack_size_bonus=3}},surface={}}
end
local state=fixture()
equal(common.get_mining_drill_production_from_state(state),0.5,"normal iron production")
state.player.force.mining_drill_productivity_bonus=0.5
equal(common.get_mining_drill_production_from_state(state),0.75,"research productivity")
prototypes.entity.drill.uses_force_mining_productivity_bonus=false
equal(common.get_mining_drill_production_from_state(state),0.5,"drill ignores research")
state=fixture()
state.miner_quality_choice="legendary"
equal(common.get_mining_drill_production_from_state(state),0.5,"drill quality conserves ore without increasing speed")
state.module_choice="module"
state.module_quality_choice="legendary"
prototypes.item.module={get_module_effects=function(quality) assert(quality=="legendary"); return {speed=1.25,productivity=0.1} end}
equal(common.get_mining_drill_production_from_state(state),5.4375,"native module quality and actual slot count")
state=fixture()
state.module_choice="module"
prototypes.item.module={get_module_effects=function() return {speed=-0.5,productivity=0.1} end}
equal(common.get_mining_drill_production_from_state(state),0.13,"speed reduction floor")
state=fixture()
prototypes.entity.drill.effect_receiver={base_effect={speed=0.2,productivity=0.5},uses_surface_effects=true,
	uses_module_effects=false,speed_limits={low=-0.8,high=1},productivity_limits={low=0,high=2}}
state.surface.global_effect={speed=1,productivity=0.2}
state.module_choice="module"
equal(common.get_mining_drill_production_from_state(state),1.7,"base and surface effects and limits")
state=fixture()
prototypes.entity.drill.mining_speed=2.5
prototypes.entity.ore.mineable_properties={mining_time=5,products={{type="item",amount=10}}}
equal(common.get_mining_drill_production_from_state(state),5,"multiple-item resource output")
state.player.force.mining_drill_productivity_bonus=1
prototypes.entity.ore.mineable_properties.products={
	{type="item",amount_min=1,amount_max=3,ignored_by_productivity=2,independent_probability=0.5,shared_probability={min=0.2,max=0.8}},
	{type="item",amount=1,extra_count_fraction=0.5,ignored_by_productivity=1},
	{type="fluid",amount=100},
}
equal(common.get_mining_drill_production_from_state(state),1.35,"expected item yield and productivity exclusions")
state=fixture()
equal(common.get_belt_capacity_multiplier(state),1,"ordinary drill does not output researched stacks")
state.miner.drops_full_belt_stacks=true
equal(common.get_belt_capacity_multiplier(state),4,"stacked drill capacity")

for _,name in ipairs{"simple","compact","sparse","super_compact"} do
	local layout=table.deepcopy(require("layouts."..name))
	layout._calculate_belt_throughput=function(_,_,belt) return belt.throughput1,belt.throughput2 end
	local function belt(a,b) return {has_drills=true,is_output=true,throughput1=a,throughput2=b,merged_throughput1=a,merged_throughput2=b} end
	state=fixture()
	state.miner.drops_full_belt_stacks=true
	local source,target=belt(0.6,0.6),belt(1.8,1.8)
	layout:_apply_belt_merge_strategy(state,source,target,S)
	assert(source.merge_target==target and not source.is_output,name.." ignores researched stack capacity")
	equal(target.merged_throughput1,2.4,name.." merged first side")
	equal(target.merged_throughput2,2.4,name.." merged second side")
	source,target=belt(2.1,2.1),belt(2.2,2.2)
	layout:_apply_belt_merge_strategy(state,source,target,N)
	assert(not source.merge_target and source.is_output,name.." merges overloaded sides")
	state.miner.drops_full_belt_stacks=false
	source,target=belt(0.6,0.6),belt(0.8,0.8)
	layout:_apply_belt_merge_strategy(state,source,target,S)
	assert(not source.merge_target,name.." uses stack bonus for an ordinary drill")
	cases=cases+3
end

local drawn={}
local function draw(spec)
	drawn[#drawn+1]=spec
	return {valid=true,destroy=function() end}
end
rendering={draw_text=draw,draw_line=draw,draw_polygon=draw,draw_circle=draw}
state=fixture()
state.statistics_choice=true
state.belt={speed=7.5}
state.direction_choice="west"
state.coords={gx=0,gy=0,tw=50,th=50,is_horizontal=true}
state.best_attempt={sx=0}
state._render_objects=List()
state.belt_count=3
state.belts={}
for i=1,3 do
	state.belts[i]={has_drills=true,lane1={},lane2={},x_start=0,x_entry=0,x2=10,y=i*6,merged_throughput1=0.4,merged_throughput2=0.4}
end
common.display_lane_filling(state)
local total
for _,spec in pairs(drawn) do if type(spec.text)=="table" and spec.text[1]=="mpp.msg_print_info_lane_throuput_total" then total=spec.text end end
assert(total and total[2]=="18.00" and total[3]==3,"total reports theoretical minimum instead of actual output belts")
cases=cases+1
drawn={}
common.draw_belt_stats(state,state.belts[1],7.5,2,0,0)
assert(drawn[1].text=="15.00/s (200%)" and drawn[1].color[1]==1,"overloaded lane is hidden by capping")
assert(drawn[2].text=="0.00/s (0%)" and drawn[3].text=="7.50+/s","unbalanced sides are incorrectly added before capping")
cases=cases+2
drawn={}
state.miner.drops_full_belt_stacks=true
common.draw_belt_stats(state,state.belts[1],7.5,2,0,0)
assert(drawn[1].text=="15.00/s (50%)" and drawn[3].text=="15.00/s","stacked saturation display disagrees with merge capacity")
cases=cases+1
print("Throughput OK: "..cases.." production, capacity, merge and saturation cases")
