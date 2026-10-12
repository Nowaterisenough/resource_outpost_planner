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
state.miner_lanes=rows;state.output_balance_choice=true;state.output_belt_count_choice=1
check(capacity.can_split(state),"two rows can share one output")
state.miner_lanes[3]={{rate=1}}
check(not capacity.can_split(state),"splitting adds feeds when rows alone exceed output budget")
local load=require("mpp.belt_load")
equal(load.loss_percent({{is_output=true,merged_throughput1=4,merged_throughput2=0}},1,8),75,"receiving-lane bottleneck omitted")
equal(load.loss_percent({{is_output=true,merged_throughput1=1,merged_throughput2=1},
 {is_output=true,merged_throughput1=1,merged_throughput2=1}},1,1),50,"final-output bottleneck omitted")
print("Belt capacity: "..cases.." range, migration, merge, grouping, downstream and physical routing checks passed")
