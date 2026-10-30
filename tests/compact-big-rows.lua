-- Facing rows must retain every drill and use both sides of each shared output.
defines={direction={north=0,east=4,south=8,west=12}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},quality={}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
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
  local seen,total,peak={},{0,0},0
  for _,g in ipairs(groups) do
   for side,lane in ipairs{g.lane1,g.lane2} do
    local sum,last=0,-math.huge
    for _,m in ipairs(lane) do
     check(not seen[m] and m.side==side and m.x>=last,"partition drops row identity, duplicates or reorders drills")
     seen[m]=true;sum=sum+m.rate;last=m.x
    end
    check(sum==g.rates[side],"reported lane load differs from its miners")
    peak=math.max(peak,sum);total[side]=total[side]+sum
   end
  end
  for _,lane in ipairs{top,bottom} do for _,m in ipairs(lane) do check(seen[m],"missing drill") end end
  if #groups==2 then
   -- Independently enumerate all physical vertical cuts, including missing
   -- columns; no cut may produce a lower maximum of the four side loads.
   for cut=-1,80 do
    local left,right={0,0},{0,0}
    for side,lane in ipairs{top,bottom} do for _,m in ipairs(lane) do
     local sums=m.x<=cut and left or right;sums[side]=sums[side]+m.rate
    end end
    local candidate=math.max(left[1],left[2],right[1],right[2])
    check(candidate>=peak,"paired cut wastes available belt-side capacity")
   end
  end
 end
end end end
local top,bottom=fixture(8,0,1),fixture(8,0,2)
local shared=paired.groups(top,bottom,function() return 1 end,100)
check(#shared==1 and #shared[1].lane1==8 and #shared[1].lane2==8,"low load still sends facing rows to separate outlets")
local split=paired.groups(top,bottom,function() return 1 end,100,2)
check(#split==2 and #split[1].lane1==4 and #split[1].lane2==4 and #split[2].lane1==4 and #split[2].lane2==4,"retained double corridor does not use all four sides")
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
print("Compact big rows: "..checks.." facing-side and partition checks passed")
