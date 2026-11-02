-- Facing rows must retain every drill and use both sides of each shared output.
defines={direction={north=0,east=4,south=8,west=12}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},quality={}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
function table.deepcopy(value)
 if type(value)~="table" then return value end
 local copy={};for k,v in pairs(value) do copy[k]=table.deepcopy(v) end;return copy
end
require("mpp.global_extends")
local paired=require("mpp.compact_big_rows")
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function fixture(count,offset,side)
 local lane={}
 for i=1,count do lane[i]={x=(i-1)*5+offset,rate=(i*7+side*11)%29+1,side=side} end
 return lane
end
for a=0,12 do for b=0,12 do for _,offset in ipairs{0,5,15} do
 local top,bottom=fixture(a,0,1),fixture(b,offset,2)
 for _,limit in ipairs{math.huge,30,0} do
  local calls=0
  local groups=paired.groups(top,bottom,function(m) calls=calls+1;return m.rate end,limit)
  check(calls==a+b,"partition repeatedly calculates drill production")
  check(#groups<=2 and (limit~=math.huge or #groups==1),"disabled controller opens a second corridor")
  local seen={}
  for _,g in ipairs(groups) do
   for side,lane in ipairs{g.lane1,g.lane2} do
    local sum,last=0,-math.huge
    for _,m in ipairs(lane) do
     check(not seen[m] and m.side==side and m.x>=last,"partition drops row identity, duplicates or reorders drills")
     seen[m]=true;sum=sum+m.rate;last=m.x
    end
    check(sum==g.rates[side],"reported lane load differs from its miners")
   end
  end
  for _,lane in ipairs{top,bottom} do for _,m in ipairs(lane) do check(seen[m],"missing drill") end end
  if #groups==2 then
   -- Adjacent occupied columns must alternate complete outputs, even with
   -- missing drills. A long half-row split would pass outlet-only flow tests.
   local owners,keys={},{}
   for j,g in ipairs(groups) do for _,lane in ipairs{g.lane1,g.lane2} do for _,m in ipairs(lane) do
    check(not owners[m.x] or owners[m.x]==j,"facing drills feed different outputs")
    if not owners[m.x] then keys[#keys+1]=m.x end
    owners[m.x]=j
   end end end
   table.sort(keys)
   for i=2,#keys do check(owners[keys[i]]~=owners[keys[i-1]],"neighbouring columns do not alternate outputs") end
  end
 end
end end end
local top,bottom=fixture(8,0,1),fixture(8,0,2)
local shared=paired.groups(top,bottom,function() return 1 end,100)
check(#shared==1 and #shared[1].lane1==8 and #shared[1].lane2==8,"low load still sends facing rows to separate outlets")
local split=paired.groups(top,bottom,function() return 1 end,100,2)
check(#split==2 and #split[1].lane1==4 and #split[1].lane2==4 and #split[2].lane1==4 and #split[2].lane2==4,"retained double corridor does not use all four sides")
-- Reproduce a boundary row losing a column after widening. Every occupied
-- physical corridor must publish exactly one independent output per tile.
local function plan_state(counts,gaps,pass)
 local state={miner={size=5,middle=2,extent_negative=0,extent_positive=4,
  output_rotated={[defines.direction.south]={x=2,y=5},[defines.direction.north]={x=2,y=-1}}},
  belt={speed=15},best_attempt={sx=1,sy=1,lane_layout={},miners={}},
  miner_lanes={},miner_lane_count=2*#counts,resource_tiles={},
  _capacity_row_gaps=table.deepcopy(gaps or {}),_capacity_pass=pass or 1}
 local y=1
 for row,count in ipairs(counts) do
  local i=row*2-1
  for side=1,2 do
   local line=i+side-1
   state.best_attempt.lane_layout[line]={y=y}
   local lane=fixture(count,1,side);state.miner_lanes[line]=lane
   for _,m in ipairs(lane) do
    m.y=y;m.direction=side==1 and defines.direction.south or defines.direction.north
    state.best_attempt.miners[#state.best_attempt.miners+1]=m
   end
   y=y+5+(side==1 and (state._capacity_row_gaps[i] or 1) or 0)
  end
 end
 return state
end
local function prepare(state,limit)
 return paired.prepare(state,function() return 30 end,limit or 20,function() error("unexpected spacing diagnostic") end)
end
local first=plan_state({2,2})
check(prepare(first)=="initialize_capacity_layout" and first._capacity_row_gaps[1]==2,"overloaded pair did not reserve two tiles")
local sparse=plan_state({1,2},first._capacity_row_gaps,2)
check(prepare(sparse)=="initialize_capacity_layout" and sparse._capacity_row_gaps[1]==1,
 "single-column edge retained a two-tile corridor with only one output")
check(sparse._capacity_row_gaps[3]==2 and sparse._capacity_single_rows[1],"edge cleanup changed the neighbouring dual corridor")
local stable=plan_state({2,2},sparse._capacity_row_gaps,3)
stable._capacity_single_rows=sparse._capacity_single_rows
check(prepare(stable)=="prepare_pipe_layout","reclaimed boundary oscillates back to two tiles")
check(stable.belt_count==3,"reclaimed boundary lost its independent neighbour outputs")
for a=0,3 do for b=0,3 do for _,gap in ipairs{1,2} do
 local state=plan_state({a,b},{[1]=gap,[3]=gap})
 if prepare(state)=="initialize_capacity_layout" then
  local single=state._capacity_single_rows
  state=plan_state({a,b},state._capacity_row_gaps,2);state._capacity_single_rows=single
  check(prepare(state)=="prepare_pipe_layout","corridor cleanup did not converge")
 end
 local counts,owners={},{}
 for _,belt in ipairs(state.belts) do
  local row=belt.capacity_row;counts[row]=(counts[row] or 0)+1
  check(belt.is_output and #belt.lane1+#belt.lane2>0,"empty or merged collector hides a wasted corridor tile")
  check(not owners[belt.y],"two collectors share the same physical belt")
  owners[belt.y]=true
 end
 for row,count in ipairs{a,b} do if count>0 then
  local i=row*2-1
  local width=state.best_attempt.lane_layout[i+1].y-state.best_attempt.lane_layout[i].y-5
  check(counts[i]==width,"physical corridor width differs from actual independent outputs")
 end end
end end end
local exhausted=plan_state({1},{[1]=2},8)
local reason
check(paired.prepare(exhausted,function() return 30 end,20,function(_,_,_,value) reason=value end)=="prepare_pipe_layout"
 and reason and exhausted.belt_count==0,"exhausted replan published mismatched corridor geometry")
-- An unsupported prototype must produce a diagnostic before any routing.
for _,north in ipairs{{x=2,y=0},{x=1,y=-1},{x=4,y=-1},{}} do
 local state={miner={size=5,output_rotated={[defines.direction.south]={x=2,y=5},[defines.direction.north]=north}},
  best_attempt={sx=1,sy=1}}
 local reason
 local next_step=paired.prepare(state,function() error("unsupported geometry reached production") end,1,
  function(_,_,_,error) reason=error end)
 check(next_step=="prepare_pipe_layout" and state.belt_count==0 and reason[1]=="mpp.belt_capacity_geometry",
  "unsupported facing geometry did not stop routing")
end
-- An independent reachability oracle checks arbitrary reserved tiles. A pipe
-- span must connect its whole interval without putting an endpoint in a tower.
for length=1,12 do for mask=0,2^math.max(0,length-2)-1 do
 local blocked={}
 for x=1,length-2 do if math.floor(mask/2^(x-1))%2==1 then blocked[x]=true end end
 local grid={get_tile=function(_,x) return {built_thing=blocked[x] and "beacon" or nil} end}
 for reach=2,6 do
  local possible={[length]=true}
  for x=length-1,0,-1 do if not blocked[x] then
   possible[x]=possible[x+1]
   for endpoint=x+2,math.min(length-1,x+reach) do
    if not blocked[endpoint] and possible[endpoint+1] then possible[x]=true end
   end
  end end
  local spans=paired.pipe_spans(grid,0,7,length-1,reach)
  check((spans~=nil)==(possible[0]==true),"pipe relay routing differs from exhaustive reachability")
  if spans then
   local cursor=0
   for _,span in ipairs(spans) do
    check(span.x==cursor and span.y==7 and span.w<=reach,"pipe spans disconnect or exceed underground reach")
    check(not blocked[span.x] and not blocked[span.x+span.w],"pipe endpoint overlaps a beacon")
    cursor=span.x+span.w+1
   end
   check(cursor==length,"pipe spans omit the last fluid connection")
  end
 end
end end
local obstacle={get_tile=function(_,x) return {built_thing=x>=67 and x<=69 and "beacon" or nil} end}
local spans=assert(paired.pipe_spans(obstacle,45,30,25,10))
for _,span in ipairs(spans) do
 check(span.x<67 or span.x>69,"long irregular gap puts its input endpoint inside a beacon")
 check(span.x+span.w<67 or span.x+span.w>69,"long irregular gap puts its output endpoint inside a beacon")
end
check(not paired.pipe_spans(obstacle,65,30,6,nil),"surface-only pipes crossed a reserved tower")
print("Compact big rows: "..checks.." facing-side, partition and fluid relay checks passed")
