-- Run from the repository root with Lua 5.2.
defines={direction={north=0,east=4,south=8,west=12},inventory={mining_drill_modules=1}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},item={},quality={}}
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
require("mpp.global_extends")
local capacity=require("mpp.belt_capacity")
local layout=require("layouts.capacity_rows")
local compact_layout=require("layouts.compact")
local cases=0
local function check(value,label) assert(value,label);cases=cases+1 end
local function equal(a,b,label) check(math.abs(a-b)<1e-8,label) end
local state={belt_merge_choice=true,layout_choice="compact",belt={speed=30},miner={drops_full_belt_stacks=false},
	player={force={belt_stack_size_bonus=3}},belt_load_min_choice=0.8,belt_load_max_choice=1}
equal(capacity.limit(state),30,"upper ratio 1 permits exactly full load")
state.belt_load_max_choice=1.1
equal(capacity.limit(state),33,"upper ratio 1.1 means 110% load")
state.miner.drops_full_belt_stacks=true
equal(capacity.limit(state),132,"research stacks expand each receiving lane")
for _,range in ipairs{{-1,1},{1,0.8},{0,0},{0,101},{0,math.huge},{0/0,1},{0,0/0},{"0.8",1},{false,1}} do
	check(not capacity.valid_range(range[1],range[2]),"invalid range accepted")
end
check(not capacity.valid_range(nil,1),"empty minimum accepted")
check(not capacity.valid_range(0,nil),"empty maximum accepted")
for _,range in ipairs{{0,1},{0.8,1.1},{1,1},{0.25,0.9},{0,100}} do
	check(capacity.valid_range(range[1],range[2]),"valid range rejected")
end
local old={belt_merge_choice=false,belt_capacity_choice=true,belt_overflow_percent_choice=10}
capacity.migrate_choices(old)
check(old.belt_merge_choice and old.belt_capacity_choice==nil and old.belt_overflow_percent_choice==nil,"legacy split toggle not unified")
equal(old.belt_load_max_choice,1/0.9,"legacy loss did not convert to equivalent load")
old={belt_merge_choice=true};capacity.migrate_choices(old)
check(old.belt_merge_choice and old.belt_load_min_choice==0.8 and old.belt_load_max_choice==1,"legacy Merge defaults lost")
old.belt_merge_choice=false;old.belt_load_min_choice=0.5;old.belt_load_max_choice=1.2
capacity.migrate_choices(old)
check(not old.belt_merge_choice and old.belt_load_min_choice==0.5 and old.belt_load_max_choice==1.2,"migration is not idempotent")
local miners={{rate=15},{rate=15},{rate=5},{rate=25},{rate=31}}
local groups=capacity.groups(miners,30,function(m) return m.rate end)
check(#groups==3,"ordered exact-capacity groups")
check(#groups[1].miners==2 and #groups[2].miners==2 and groups[3].miners[1]==miners[5],"group drops or reorders drills")
check(groups[3].rate>30,"single-drill bottleneck remains detectable")
check(#capacity.groups({},30,function(m) return m.rate end)==0,"empty row produced an output")
state.miner.drops_full_belt_stacks=false
state.belts={{is_output=true,merged_throughput1=1.1,merged_throughput2=0},
	{is_output=true,merged_throughput1=1.1,merged_throughput2=0}}
check(not capacity.overloaded(state),"exactly 110% exceeds the 1.1 limit")
state.belts[1].merged_throughput1=1.12
check(capacity.overloaded(state),"112% load missed")
state.belts[1].merged_throughput1=1.1
local warning=capacity.output_warning(state,{output_balance_choice=true,output_belt_count_choice=1})
check(warning and warning[2]==1 and tonumber(warning[3])>54,"bottleneck loss incorrectly shares empty belt sides")
check(capacity.output_warning(state,{output_balance_choice=true,output_belt_count_choice=2}),"110% physical load hides its permitted loss")
state.belts[1].merged_throughput1=1;state.belts[2].merged_throughput1=1
check(not capacity.output_warning(state,{output_balance_choice=true,output_belt_count_choice=2}),"full capacity should not warn")
check(capacity.output_budget{output_station_choice=true,output_wagon_count_choice=3,output_loading_side_choice="double",output_balance_choice=true,output_belt_count_choice=1}==6,"station does not own output budget")
for _,name in ipairs{"oil","blueprints"} do
	state.layout_choice=name;check(not capacity.enabled(state),"unsupported layout is changed")
end
state.layout_choice="compact";state.belt_merge_choice=false
check(not capacity.enabled(state),"disabled feature changes layout")

for _,name in ipairs{"simple","compact","sparse","super_compact"} do
	local l=table.deepcopy(require("layouts."..name))
	l._calculate_belt_throughput=function(_,_,b) return b.throughput1,b.throughput2 end
	local function belt(a,b) return {has_drills=true,is_output=true,throughput1=a,throughput2=b,merged_throughput1=a,merged_throughput2=b} end
	state.belt_merge_choice=true;state.belt_load_min_choice=0.8;state.belt_load_max_choice=1.1
	local source,target=belt(0.55,0.55),belt(0.55,0.55)
	l:_apply_belt_merge_strategy(state,source,target,8)
	check(not source.is_output and target.merged_throughput1==1.1,name.." ignores configured upper limit")
	source,target=belt(0.56,0.56),belt(0.56,0.56)
	l:_apply_belt_merge_strategy(state,source,target,8)
	check(source.is_output,name.." merges beyond the upper limit")
	state.belt_load_min_choice=0.55
	source,target=belt(0.55,0.55),belt(0.55,0.55)
	l:_apply_belt_merge_strategy(state,source,target,8)
	check(source.is_output,name.." merges a belt already at the minimum")
	state.belt_load_min_choice=0
	source,target=belt(0.1,0.1),belt(0.1,0.1)
	l:_apply_belt_merge_strategy(state,source,target,8)
	check(source.is_output,name.." ignores zero minimum")
end

-- Reverse-flow merging must start with an east-facing input when its first
-- receiving tile is followed immediately by a pole/miner tunnel.
do
	local grid=setmetatable({},require("mpp.grid_mt"))
	grid[0]={};for x=0,18 do grid[0][x]={x=x,y=0} end
	for x=3,9 do grid[0][x].built_thing="miner" end
	local s={grid=grid,miner={},belts={},belt_choice="belt",belt_quality_choice="normal",
		belt={related_underground_belt="underground",underground_reach=9}}
	local env,built=require("layouts.common").create_belt_building_environment(s)
	env.place_interleaved_belt_east(2,14,0)
	local map={};for _,spec in ipairs(built) do map[spec.grid_x]=spec end
	check(map[2].direction==4 and map[2].type=="input","reverse merge starts with a backwards underground")
	check(map[10].direction==4 and map[10].type=="output","reverse merge tunnel has no matching exit")
	for x=11,14 do check(map[x].direction==4 and not map[x].type,"reverse merge does not reach its turn") end
end

-- Follow the actual emitted paths: each separated group must reach only its own outlet.
local W,S,N=12,8,0
for count=1,8 do
	local grid=setmetatable({},require("mpp.grid_mt"))
	for y=-5,20 do grid[y]={};for x=-5,50 do grid[y][x]={x=x,y=y} end end
	local s={_capacity_rows=true,grid=grid,miner={output_rotated={[S]={x=1}}},belt_choice="belt",belt_quality_choice="normal",
		belt={related_underground_belt="underground",underground_reach=9},belts={},builder_power_poles={}}
	for j=1,count do
		local first=(j-1)*6+2
		s.belts[j]={x_start=-3,x1=first,x2=first+3,turn_x=first-1,y=j,source_y=1,
			is_output=true,lane1={{x=first-1},{x=first+2}},throughput1=0.9}
	end
	check(layout:prepare_belt_layout(s)=="prepare_lamp_layout","wrong routing callback")
	check(not s.preview_error,"empty corridor blocked")
	local map={}
	for _,b in ipairs(s.builder_belts) do
		local key=b.grid_x..","..b.grid_y
		check(not map[key],"independent belt groups overlap")
		map[key]=b
	end
	for j,b in ipairs(s.belts) do
		for _,x in ipairs{b.x1,b.x2} do
			local y,steps=1,0
			local target=j%2==0 and j-1 or j
			while x~=-3 or y~=target do
				local node=assert(map[x..","..y],"disconnected collection belt")
				if node.direction==W then x=x-1 elseif node.direction==S then y=y+1 elseif node.direction==N then y=y-1 else error("wrong direction") end
				steps=steps+1;assert(steps<100,"collection belt cycle")
			end
			check(y==target,"collection belt feeds a different group")
		end
	end
end
-- Only the selected five-tile compact layout enters the big-drill router.
for _,case in ipairs{{"compact",5,"initialize_capacity_layout"},{"compact",3,"initialize_grid"},{"super_compact",5,"initialize_grid"},{"beacon_rows",5,"initialize_grid"}} do
 local s={layout_choice=case[1],miner={size=case[2]},preview_only=true}
 check(compact_layout:deconstruct_previous_ghosts(s)==case[3],"compact dispatch changed an unrelated layout")
 check(s.layout_choice==(case[3]=="initialize_capacity_layout" and "capacity_rows" or case[1]),"compact dispatch lost the selected layout")
end
-- Switching off automatic splitting must clear cached double corridors, including
-- beacon layouts which enter the capacity planner even while splitting is off.
do
 local probe=table.deepcopy(layout)
 probe.initialize=function() end
 probe.prepare_layout_attempts=function() return "ready" end
 local s={grid={},resource_tiles={},miner={size=5},_mining_layout_choice="compact",beacon_choice="none",
  belt_merge_choice=false,_capacity_gap=2,_capacity_row_gaps={[1]=2,[3]=2},_capacity_separate_power=true}
 check(probe:initialize_capacity_layout(s)=="ready","cached layout did not initialize")
 check(s._capacity_gap==1 and next(s._capacity_row_gaps)==nil and not s._capacity_separate_power,
  "disabling automatic belts retained a double corridor")
 s.belt_merge_choice=true;s._capacity_gap=2;s._capacity_row_gaps={[1]=2}
 probe:initialize_capacity_layout(s)
 check(s._capacity_gap==2 and s._capacity_row_gaps[1]==2,"enabled split retry lost its corridor")
end
-- Compact big-drill split buses use underground through routes. Both ends stay
-- on the surface so turns and edge merges still work, even with inline fixtures.
for _,blocked in ipairs{false,true} do for _,reach in ipairs{5,7,9} do
 local grid=setmetatable({},require("mpp.grid_mt"))
 for y=-5,5 do grid[y]={};for x=-5,50 do grid[y][x]={x=x,y=y} end end
 if blocked then grid[2][4].built_thing="pole";grid[2][5].built_thing="lamp" end
 local s={_capacity_rows=true,_capacity_tight_big=true,belt_merge_choice=true,belt_load_min_choice=.8,
  output_balance_choice=true,output_belt_count_choice=1,
  grid=grid,miner={output_rotated={[S]={x=2}}},belt_choice="belt",belt_quality_choice="normal",
  belt={speed=30,related_underground_belt="underground",underground_reach=reach},belts={
   {x_start=-3,x1=2,x2=12,turn_x=1,y=1,source_y=1,is_output=true,lane1={{x=0},{x=10}},throughput1=1},
   {x_start=-3,x1=27,x2=37,turn_x=26,y=2,source_y=1,is_output=true,lane1={{x=25},{x=35}},throughput1=1}}}
 layout:_prepare_edge_belts(s)
 check(not s.preview_error,"underground split bus failed")
 check(s.belts[1].is_output and s.belts[2].is_output,"double corridor collapsed at the mining edge")
 local map,tunnels={},0
 for _,spec in ipairs(s.builder_belts) do
  local key=spec.grid_x..","..spec.grid_y
  check(not map[key],"underground split bus overlaps another belt");map[key]=spec
  if spec.grid_y==2 and spec.type=="input" then tunnels=tunnels+1 end
  check(not grid[spec.grid_y][spec.grid_x].built_thing or grid[spec.grid_y][spec.grid_x].built_thing=="belt","split bus replaced inline equipment")
 end
 check(tunnels>0 and not map["-3,2"].type and not map["26,2"].type,"split bus lost surface turn/outlet")
 for _,belt in ipairs(s.belts) do for _,drop in ipairs{belt.x1,belt.x2} do
  local x,y,steps=drop,1,0
  while x~=belt.x_start or y~=belt.y do
   local spec=assert(map[x..","..y],"split bus disconnected")
   if spec.type=="input" then
    local exit
    for distance=1,reach do
     local candidate=map[(x-distance)..","..y]
     if candidate and candidate.type=="output" and candidate.direction==W then exit=candidate;break end
    end
    x=assert(exit,"split bus underground is unpaired").grid_x
   elseif spec.direction==W then x=x-1 elseif spec.direction==S then y=y+1 else error("wrong split bus direction") end
   steps=steps+1;check(steps<100,"split bus cycle")
  end
 end end
end end
-- Compact groups cross earlier merge branches underground, without losing any drop.
for _,size in ipairs{3,5} do for count=1,8 do for _,merged in ipairs{false,true} do
	local grid=setmetatable({},require("mpp.grid_mt"))
	for y=-5,20 do grid[y]={};for x=-5,80 do grid[y][x]={x=x,y=y} end end
	local offset=math.floor(size/2)
	local s={_capacity_rows=true,_capacity_compact=true,grid=grid,miner={output_rotated={[S]={x=offset}}},
		belt_choice="belt",belt_quality_choice="normal",belt={related_underground_belt="underground",underground_reach=9},belts={}}
	local output=0
	for j=1,count do
		local x=2+(j-1)*size
		local source=merged and j%2==0
		if not source then output=output+1 end
		s.belts[j]={index=j,x_start=-3,x1=x,x2=x,turn_x=x-1,y=source and 2 or output,source_y=1,
			is_output=not source,lane1={{x=x-offset}},capacity_target=source and j-1 or nil,throughput1=0.9}
	end
	check(layout:_prepare_compact_belts(s),"compact routing failed on an empty grid")
	local map,undergrounds={},0
	for _,b in ipairs(s.builder_belts) do
		local key=b.grid_x..","..b.grid_y
		check(not map[key],"compact routes overlap");map[key]=b
		if b.type then undergrounds=undergrounds+1 end
	end
	if merged and count>=3 then check(undergrounds>=2,"crossing did not use staggered undergrounds") end
	for j,belt in ipairs(s.belts) do
		local target=s.belts[belt.capacity_target or j]
		local x,y,steps=belt.x1,1,0
		while x~=target.x_start or y~=target.y do
			local node=assert(map[x..","..y],"compact route disconnected")
			if node.type=="input" then
				local exit
				for distance=1,9 do
					local candidate=map[(x-distance)..","..y]
					if candidate and candidate.type=="output" and candidate.direction==W then exit=candidate;break end
				end
				x=assert(exit,"unpaired compact underground").grid_x
			elseif node.direction==W then x=x-1 elseif node.direction==S then y=y+1 elseif node.direction==N then y=y-1 end
			steps=steps+1;check(steps<100,"compact belt cycle")
		end
	end
end end end
-- Big-drill dual corridors keep both outlets and a straight side-loading junction.
-- Missing drills and beacon pockets must not lengthen the crossing beyond yellow reach.
for count=2,4 do for _,spacing in ipairs{5,10,15} do for _,reach in ipairs{5,7,9,11} do
 local grid=setmetatable({},require("mpp.grid_mt"))
 for y=-5,10 do grid[y]={};for x=-5,65 do grid[y][x]={x=x,y=y} end end
 local s={_capacity_rows=true,_capacity_compact=true,_capacity_tight_big=true,grid=grid,
  miner={output_rotated={[S]={x=2}}},belt_choice="belt",belt_quality_choice="normal",
  belt={related_underground_belt="underground",underground_reach=reach},belts={}}
 local output=0
 for j=1,count do
  local x=2+(j-1)*spacing
  local paired=count>2 and j%2==0
  if not paired then output=output+1 end
  s.belts[j]={index=j,x_start=-3,x1=x,x2=x,turn_x=paired and s.belts[j-1].x2+2 or x-1,
   y=paired and 2 or output,source_y=1,is_output=not paired,lane1={{x=x-2}},capacity_target=paired and j-1 or nil}
 end
 check(layout:_prepare_compact_belts(s),"big dual corridor failed across a drill pocket")
 local map={}
 for _,b in ipairs(s.builder_belts) do
  local key=b.grid_x..","..b.grid_y;check(not map[key],"big dual corridor overlap");map[key]=b
 end
 check(map["-3,1"].direction==W and map["-3,2"].direction==W,"big dual corridor lost an independent outlet")
 for _,belt in ipairs(s.belts) do
  if belt.capacity_target then
   local target=s.belts[belt.capacity_target]
   local stub=map[(target.x2+1)..",1"]
   check(stub and not stub.type and stub.direction==W,"side loading became a corner instead of a straight junction")
   check(map[target.x2..",2"].direction==N,"paired group does not side-load")
  end
  local target=s.belts[belt.capacity_target or belt.index]
  local x,y,steps=belt.x1,1,0
  while x~=target.x_start or y~=target.y do
   local b=assert(map[x..","..y],"big dual corridor disconnected")
   if b.type=="input" then
    local exit
    for distance=1,reach do
     local other=map[(x-distance)..","..y]
     if other and other.type=="output" and other.direction==W then exit=other;break end
    end
    x=assert(exit,"big dual crossing exceeds underground reach").grid_x
   elseif b.direction==W then x=x-1 elseif b.direction==N then y=y-1 elseif b.direction==S then y=y+1 end
   steps=steps+1;check(steps<150,"big dual corridor cycle")
  end
 end
end end end
-- A failed compact attempt must leave the grid untouched for the wider retry.
do
	local grid=setmetatable({[1]={[0]={built_thing="pipe"}}},require("mpp.grid_mt"))
	local s={grid=grid,_capacity_rows=true,miner={output_rotated={[S]={x=1}}},belt={},belts={
		{x1=1,x2=1,x_start=-3,turn_x=0,y=1,source_y=1,is_output=true,lane1={{x=0}}}}}
	check(not layout:_prepare_compact_belts(s),"occupied surface route accepted")
	check(grid[1][0].built_thing=="pipe" and not s.builder_belts,"failed route changed the committed layout")
end
-- A fixed output budget relaxes grouping loads without dropping or reordering drills.
local rows={{{rate=10},{rate=20},{rate=30},{rate=10}},{{rate=5},{rate=25},{rate=20}}}
for budget=2,7 do
 local evaluated=0
 local grouped=capacity.row_groups(rows,2,30,function(m) evaluated=evaluated+1;return m.rate end,budget)
 local count=0
 for i,row in ipairs(grouped) do
  local cursor,total=1,0
  for _,g in ipairs(row) do
   count=count+1
   for _,m in ipairs(g.miners) do check(m==rows[i][cursor],"budget changes drill order");cursor=cursor+1;total=total+m.rate end
  end
  check(cursor==#rows[i]+1,"budget drops miners")
 end
 check(count<=budget,"group count exceeds available receiving lanes")
 check(evaluated==7,"budget search recalculates production")
end
-- A two-tile big-drill corridor bounds receiving groups without dropping ore production.
do
 local input={{},{}}
 for i=1,12 do input[1][i]={rate=10} end
 for i=1,3 do input[2][i]={rate=10} end
 local calls=0
 local grouped=capacity.row_groups(input,2,20,function(m) calls=calls+1;return m.rate end,nil,2)
 for i,row in ipairs(grouped) do
  check(#row<=2,"compact row exceeds its two receiving corridors")
  local cursor,total=1,0
  for _,g in ipairs(row) do for _,m in ipairs(g.miners) do
   check(m==input[i][cursor],"density constraint drops or reorders a drill")
   cursor=cursor+1;total=total+m.rate
  end end
  equal(total,#input[i]*10,"density constraint loses predicted production")
 end
 check(calls==15,"row-budget search reevaluates production")
 local dense={layout_choice="capacity_rows",_capacity_tight_big=true,belt_merge_choice=true,belt={speed=30},
  miner={drops_full_belt_stacks=false},belt_load_min_choice=.8,belt_load_max_choice=1.1,
  belts={{is_output=true,merged_throughput1=2,merged_throughput2=2}}}
 local warning=capacity.output_warning(dense)
 check(warning and warning[1]=="mpp.belt_capacity_dense" and warning[2]=="50.0","uncapped dense layout hides its internal bottleneck")
end
-- Compact big rows use all four sides without inheriting another row's peak
-- or a final output budget. Verify ordered minimax cuts against a brute oracle.
do
 local function optimum(rates,start,count)
  if count==1 then local sum=0;for i=start,#rates do sum=sum+rates[i] end;return sum end
  local best,sum=math.huge,0
  for i=start,#rates-count+1 do
   sum=sum+rates[i];best=math.min(best,math.max(sum,optimum(rates,i+1,count-1)))
  end
  return best
 end
 local values={{0,0,0,0},{100,1,1,1,1},{1,1,1,1,100},{4,4,2,2},{20,1,1,20,1,1,20,1}}
 for n=1,8 do
  for seed=1,25 do local v={};for j=1,n do v[j]=(seed*j*j+7*j)%23 end;values[#values+1]=v end
 end
 for _,rates in ipairs(values) do
  local miners,total={},0
  for j,rate in ipairs(rates) do miners[j]={rate=rate};total=total+rate end
  local calls=0
  local grouped=capacity.compact_row_groups({miners},1,0,function(m) calls=calls+1;return m.rate end,{[1]=2})[1]
  check(#grouped==math.min(4,#miners),"big row leaves a usable belt side empty")
  check(calls==#miners,"compact partition recalculates drill production")
  local cursor,peak,sum=1,0,0
  for _,g in ipairs(grouped) do
   peak=math.max(peak,g.rate);sum=sum+g.rate
   for _,m in ipairs(g.miners) do check(m==miners[cursor],"compact cut drops/reorders a drill");cursor=cursor+1 end
  end
  equal(sum,total,"four-sided collection loses production")
  check(cursor==#miners+1,"four-sided collection omits a drill")
  equal(peak,optimum(rates,1,#grouped),"compact side peak is not optimal")
 end
 local lanes={{},{},{}}
 for i=1,32 do lanes[1][i]={rate=30} end
 for i=1,8 do lanes[2][i]={rate=4} end
 for i=1,3 do lanes[3][i]={rate=1} end
 local groups=capacity.compact_row_groups(lanes,3,10,function(m) return m.rate end)
 check(#groups[1]==4 and #groups[2]==4 and #groups[3]==1,"one high-rate row reduced the other rows' receiving sides")
 for _,g in ipairs(groups[2]) do equal(g.rate,8,"medium row needlessly bottlenecks a side") end
 local disabled=capacity.compact_row_groups(lanes,3,math.huge,function(m) return m.rate end)
 for _,row in ipairs(disabled) do check(#row==1,"disabled split reserves another corridor") end
 local retained=capacity.compact_row_groups(lanes,3,1000,function(m) return m.rate end,{[2]=2})
 check(#retained[1]==1 and #retained[2]==4,"alignment retry leaves a retained double corridor half used")
 local edge=capacity.compact_row_groups(lanes,3,10,function(m) return m.rate end,nil,2)
 check(#edge[1]==2 and #edge[2]==2,"obstructed-route fallback exceeds two tiles")
end
local balanced=capacity.row_groups({{{rate=4},{rate=4},{rate=2},{rate=2}}},1,10,function(m) return m.rate end)
equal(math.max(balanced[1][1].rate,balanced[1][2].rate),8,"receiving sides were not balanced")
equal(balanced[1][1].rate+balanced[1][2].rate,12,"balancing lost production")
state.miner_lanes=rows;state.output_balance_choice=true;state.output_belt_count_choice=1
check(capacity.can_split(state),"two rows can share one output")
state.miner_lanes[3]={{rate=1}}
check(not capacity.can_split(state),"splitting adds feeds when rows alone exceed output budget")
local load=require("mpp.belt_load")
equal(load.loss_percent({{is_output=true,merged_throughput1=4,merged_throughput2=0}},1,8),75,"receiving-lane bottleneck omitted")
equal(load.loss_percent({{is_output=true,merged_throughput1=1,merged_throughput2=1},
 {is_output=true,merged_throughput1=1,merged_throughput2=1}},1,1),50,"final-output bottleneck omitted")
print("Belt capacity: "..cases.." range, migration, merge, grouping, downstream and physical routing checks passed")
