-- Cache invalidation and read-only routing state, without a game process.
defines={direction={west=12}}
function table.deepcopy(value)
	if type(value)~="table" then return value end
	local result={};for k,v in pairs(value) do result[k]=table.deepcopy(v) end;return result
end
package.loaded["mpp.mpp_util"]={bp_direction={west={[12]=12}}}
package.loaded["mpp.terrain"]={blocked_tile=function(t) return t.prototype.hazard end}
local routing_error,seen_grid
package.loaded["mpp.belt_planner"]={
	create_state=function(spec,target,choices)
		return {belt_target=target,coords=spec.coords,player=choices.player,surface=choices.surface}
	end,
	plan=function(state)
		seen_grid=state.grid
		assert(state.grid:get_tile(1,2).built_thing=="miner","mining occupancy lost")
		assert(state.grid:get_tile(-50,20)==nil,"old output occupancy retained")
		assert(#state.planned==1 and state.planned[1].name=="miner","cached planned entity was mutated")
		local routes={{name="belt",grid_x=state.belt_target.position.x,grid_y=state.belt_target.position.y}}
		if routing_error then return false,routing_error,{routes=routes,issues={{position={x=0,y=0},reason=routing_error}}} end
		state.balanced_output_count=8;return true,routes
	end,
	place_landfill=function() end,
}
package.loaded["mpp.builder"]={create_entity_builder=function(state)
	return function(spec) state._preview_specs[#state._preview_specs+1]={name="entity-ghost",inner_name=spec.name,
		position={x=spec.grid_x,y=spec.grid_y}} end
end}
package.loaded["layouts.common"]={create_belt_planner_specification=function(state)
	return {count=1,coords=state.coords}
end}
prototypes={tile={grass={hazard=false},water={hazard=true}}}
local cache=require("mpp.preview_output_cache")
local count=0
local function check(value,label) assert(value,label);count=count+1 end
local entities,tiles
local function fixture()
	routing_error=nil;entities={};tiles={}
	local surface={valid=true,global_effect={speed=0},find_entities_filtered=function() return entities end,
		find_tiles_filtered=function() return tiles end}
	local player={valid=true,index=1,force={index=1,mining_drill_productivity_bonus=2,belt_stack_size_bonus=3}}
	local ore={valid=true,amount=100,position={x=5,y=6}}
	local choices={layout_choice="compact",direction_choice="west",belt_merge_choice=true,belt_planner_choice=false,
		output_balance_choice=true,output_belt_count_choice=8,belt_load_min_choice=0.8,belt_load_max_choice=1.1}
	local data={choices=choices,preview={surface=surface,revision=1}}
	storage={players={[1]=data}}
	local state={preview_only=true,preview_revision=1,player=player,surface=surface,resources={ore},
		coords={x1=0,y1=0,x2=10,y2=10},miner={area=5},layout_choice="compact",beacon_choice="none",
		grid={[2]={[1]={built_thing="miner",amount=123},[2]={amount=456}}},
		builder_miners={{name="miner",grid_x=1,grid_y=2,direction=0}},direction_choice="west",
		belt_merge_choice=true,belts={{is_output=true}},belt={},best_attempt={sx=1,sy=1,miners={{}}},
		_preview_specs={{name="entity-ghost",inner_name="miner"},{name="entity-ghost",inner_name="old-output"},
			{name="entity-ghost",inner_name="pole"}},_output_preview_range={2,2}}
	cache.begin(state);cache.capture(state)
	-- The normal builder mutates specs and grid after the connection checkpoint.
	state.builder_miners[1].name="entity-ghost";state.grid[20]={[-50]={built_thing="belt"}}
	cache.complete(state,data.preview)
	check(data.preview.output_basis~=nil,"valid mining preview was not retained")
	data.choices.belt_planner_choice=true;data.preview.belt_target={position={x=-20,y=3},direction=12}
	return data,state,ore
end
local data,state,ore=fixture()
local resumed=cache.resume(data)
check(resumed and resumed._from_output_cache and resumed._callback=="refresh_output","output activation misses cache")
check(resumed.preview_only and not resumed.output_only,"cached mining draft can build during refresh")
check(cache.refresh(resumed)=="finish","cache refresh bypasses the queued completion step")
check(#resumed._preview_specs==3 and resumed._preview_specs[1].inner_name=="miner"
	and resumed._preview_specs[2].inner_name=="belt" and resumed._preview_specs[3].inner_name=="pole","base/output draw order changed")
check(not resumed.grid and resumed.balanced_output_count==8,"ephemeral grid stored in pending task")
check(not data.preview.output_basis.occupied[20],"output routing mutated persistent mining occupancy")
data.preview.belt_target.position.x=-30
local again=cache.resume(data);cache.refresh(again)
check(again._preview_specs[2].position.x==-30 and resumed._preview_specs[2].position.x==-20,"previous request routes reused or mutated")
routing_error={"mpp.msg_obstacle_route_failed"}
again=cache.resume(data);cache.refresh(again)
check(again.preview_error==routing_error and #again._preview_issues==1,"route failure hidden by successful cached mining geometry")
check(data.preview.output_basis.before[1].inner_name=="miner","failed output poisoned mining basis")

for _,change in ipairs{
	function(d,s,r) r.amount=r.amount-1 end,
	function(d,s,r) r.valid=false end,
	function(d,s,r) r.position.x=r.position.x+1 end,
	function(d,s) s.player.force.mining_drill_productivity_bonus=3 end,
	function(d,s) s.player.force.belt_stack_size_bonus=1 end,
	function(d,s) s.player.force.index=2 end,
	function(d,s) s.surface.global_effect.speed=1 end,
	function(d) d.choices.output_belt_count_choice=4 end,
	function(d) d.choices.output_station_choice=true end,
	function(d) d.choices.belt_load_max_choice=1.2 end,
	function(d) d.choices.module_choice="speed-module" end,
	function(d) d.preview.output_basis.geometry_revision=nil end,
	function(d,s) s.surface.valid=false end,
	function(d,s) d.preview.surface={} end,
	function() tiles={{name="water",position={x=4,y=4}}} end,
	function() entities={{valid=true,name="steel-chest",type="container",position={x=4,y=4},direction=0,
		quality={name="normal"},force={index=1},bounding_box={left_top={x=3.6,y=3.6},right_bottom={x=4.4,y=4.4}}}} end,
} do
	data,state,ore=fixture();change(data,state,ore)
	check(not cache.resume(data),"mining input change reused stale geometry")
end

data,state=fixture()
data.choices.belt_merge_choice=false;data.choices.output_balance_choice=false
local basis=data.preview.output_basis
basis.environment.choices=table.deepcopy(data.choices);basis.environment.choices.belt_planner_choice=nil
basis.trimmed=false
check(not cache.resume(data),"untrimmed collection reused for a compact same-facing output")
data.preview.belt_target.direction=0
check(cache.resume(data),"rotation that retains collection geometry should reuse it")

data,state=fixture();data.preview.output_basis=nil
state._preview_specs[1].name="tile-ghost"
cache.complete(state,data.preview)
check(not data.preview.output_basis,"mining landfill incorrectly assumed independent of output")
data,state=fixture();data.preview.output_basis=nil
state._preview_specs[2].name="tile-ghost"
cache.complete(state,data.preview)
check(not data.preview.output_basis,"output landfill may also cover mining tiles")
data,state,ore=fixture();data.preview.output_basis=nil;ore.amount=1
cache.complete(state,data.preview)
check(not data.preview.output_basis,"resources changed during mining planning but basis was retained")
data,state=fixture();data.preview.output_basis=nil;state._obstacle_skipped=1
cache.complete(state,data.preview)
check(not data.preview.output_basis,"partial mining placement was retained")
data,state=fixture();state._preview_environment=nil;state._apply_after_preview=true
cache.begin(state)
check(not state._preview_environment,"Apply validation performed cache bookkeeping")
data,state,ore=fixture()
local reads,ore_position=0,ore.position
ore.position=nil
setmetatable(ore,{__index=function(_,key)
	if key=="position" then reads=reads+1;return {x=ore_position.x,y=ore_position.y} end
end})
check(cache.resume(data) and reads==1,"cached resource validation reads native position more than once")
data.preview.output_basis.environment.resources={{entity=ore,amount=100,x=5,y=6}}
check(not cache.resume(data),"legacy cache representation should fall back to a full replan")
data,state=fixture();data.choices.output_balance_choice=nil
check(not cache.resume(data),"removing a saved option retained obsolete output geometry")
data,state=fixture();state._preview_environment=nil;state._beacon_logistics=true
cache.begin(state)
check(not state._preview_environment,"logistics beacon layout created an unused output cache")
print("Preview output cache: "..count.." reuse, invalidation, diagnostics and isolation checks passed")
