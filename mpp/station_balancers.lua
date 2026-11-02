-- Globally balance incoming belts before the per-wagon six-output modules.
-- Equal delivery must hold for actual flow, including stopped or depleted rows.
local balancer=require("mpp.output_balancer")
local bank={}
local E,S,W=defines.direction.east,defines.direction.south,defines.direction.west

-- Every wagon receives the same number of equally supplied channels from
-- one global balancer. Use enough channels to preserve all incoming capacity
-- up to the six-belt loading capacity of each wagon.
function bank.channels(inputs,wagons)
 local per_wagon=1
 while per_wagon<math.min(inputs/wagons,6) do per_wagon=per_wagon*2 end
 return per_wagon
end

local function core(inputs,belt_name)
 local n=inputs==2 and 3 or inputs
 local result,err=balancer.geometry(n,6,belt_name,"matrix")
 if not result then return nil,err end
 local copy={specs=result.specs,keepout=result.keepout,inputs={},output_y=result.output_y}
 for i=1,inputs do copy.inputs[i]=result.inputs[i] end
 return copy
end

-- Schedule only the bends that would intersect a neighbour's straight stem.
-- Independent wagon groups share rows instead of using a 24-row staircase.
local function bend_rows(sources,targets)
 local rows,depth={},0
 local function visit(i)
  if rows[i] then return rows[i] end
  local x,tx=sources[i],targets[i]
  local row=x==tx and 0 or 1
  if tx<x then
   for j=i-1,1,-1 do if sources[j]>=tx then row=math.max(row,visit(j)+1) else break end end
  elseif tx>x then
   for j=i+1,#sources do if sources[j]<=tx then row=math.max(row,visit(j)+1) else break end end
  end
  rows[i]=row;depth=math.max(depth,row)
  return row
 end
 for i=1,#sources do visit(i) end
 return rows,depth
end

local geometry_cache,cache_order={},{}
local function build(inputs,wagons,belt_name,per_wagon)
 local modules,sources,targets={},{},{}
 local cursor=0
 for i=1,wagons do
  local layout,err=core(per_wagon,belt_name)
  if not layout then return nil,err end
  local left,right=math.huge,-math.huge
  for _,p in ipairs(layout.specs) do left=math.min(left,math.floor(p.x));right=math.max(right,math.ceil(p.x)) end
  for _,p in ipairs(layout.inputs) do left=math.min(left,p.x);right=math.max(right,p.x) end
  local x=cursor-left
  modules[i]={layout=layout,x=x}
  for lane=0,5 do sources[#sources+1]=x+lane;targets[#targets+1]=7*(i-1)+lane end
  cursor=cursor+math.max(7,right-left+1)
 end
 local best,offset,best_distance=math.huge,0,math.huge
 for shift=-cursor,7*wagons do
  local moved,distance={},0
  for i,x in ipairs(sources) do moved[i]=x+shift;distance=distance+math.abs(moved[i]-targets[i]) end
  local _,depth=bend_rows(moved,targets)
  if depth<best or depth==best and distance<best_distance then best,offset,best_distance=depth,shift,distance end
 end
 for i,x in ipairs(sources) do sources[i]=x+offset end
 local rows,depth=bend_rows(sources,targets)
 local output_y=-depth
 local specs,keepout,ports={},{},{}
 local function add(name,x,y,direction,extra)
  local p={name=name,x=x,y=y,direction=direction or S}
  for k,v in pairs(extra or {}) do if k~="x" and k~="y" and k~="direction" then p[k]=v end end
  specs[#specs+1]=p
 end
 local function belt(x,y,direction) add(belt_name,x,y,direction) end
 local function connect(xs,xt,levels,from,to)
  for i,x in ipairs(xs) do
   local tx=xt[i]
   if x==tx then for y=from+1,to do belt(x,y) end
   else
    local turn=from+levels[i]
    for y=from+1,turn-1 do belt(x,y) end
    local step=x<tx and 1 or -1
    for col=x,tx-step,step do belt(col,turn,step==1 and E or W) end
    for y=turn,to do belt(tx,y) end
   end
  end
 end
 local front=math.huge
 for g,m in ipairs(modules) do
  local layout=m.layout
  local dx,dy=m.x+offset,output_y-layout.output_y
  for _,p in ipairs(layout.specs) do add(p.name,p.x+dx,p.y+dy,p.direction,p) end
  for _,p in ipairs(layout.keepout) do keepout[#keepout+1]={x=p.x+dx,y=p.y+dy} end
  for _,p in ipairs(layout.inputs) do
   ports[#ports+1]={x=p.x+dx,y=p.y+dy,group=g}
   front=math.min(front,p.y+dy)
  end
 end
 connect(sources,targets,rows,output_y,0)
 for _,p in ipairs(ports) do
  for y=front+1,p.y do belt(p.x,y) end
  p.y=front
 end
 do
  -- All local inputs are supplied by the global stage, not just stations
  -- with fewer input belts than wagons. A large station keeps multiple
  -- channels per wagon instead of throttling the whole station to four.
  local prefix,err=balancer.geometry(inputs,wagons*per_wagon,belt_name,"station")
  if not prefix then return nil,err end
  if wagons>1 and wagons*per_wagon<=8 and inputs<=8 then
   -- Small global cores fit beside the wagon modules, in front of the
   -- locomotive section. Turn their outputs east and fan directly into
   -- the local inputs; this avoids stacking two cores and a tall fan-out.
   local dx,dy=ports[1].x-2,front-2
   local left,top=math.huge,math.huge
   local function rotated(p) return dx+p.y-prefix.output_y,dy-p.x end
   for _,p in ipairs(prefix.specs) do
    local x,y=rotated(p)
    left=math.min(left,math.floor(x));top=math.min(top,math.floor(y))
    add(p.name,x,y,(p.direction-4)%16,p)
   end
   for _,p in ipairs(prefix.keepout) do
    local x,y=rotated(p);keepout[#keepout+1]={x=x,y=y}
   end
   for i,port in ipairs(ports) do
    local row=dy-(i-1)
    for x=dx+1,port.x-1 do belt(x,row,E) end
    for y=row,front do belt(port.x,y) end
   end
   local inlets={}
   for i,p in ipairs(prefix.inputs) do
    local x,y=rotated(p);inlets[i]={x=x,y=y}
    left=math.min(left,x);top=math.min(top,y)
   end
   ports={}
   for i,p in ipairs(inlets) do
    local x=left-inputs+i-1
    for y=top-1,p.y-1 do belt(x,y) end
    for col=x,p.x do belt(col,p.y,E) end
    ports[i]={x=x,y=top-2}
   end
  else
   local xs,xt={},{}
   local dx=ports[1].x
   for i,p in ipairs(ports) do xs[i]=dx+i-1;xt[i]=p.x end
   local levels,d=bend_rows(xs,xt)
   local tail=0
   for _,p in ipairs(prefix.specs) do tail=math.max(tail,p.y-prefix.output_y) end
   local bottom=front-d-tail-1
   local dy=bottom-prefix.output_y
   for _,p in ipairs(prefix.specs) do add(p.name,p.x+dx,p.y+dy,p.direction,p) end
   for _,p in ipairs(prefix.keepout) do keepout[#keepout+1]={x=p.x+dx,y=p.y+dy} end
   for i,x in ipairs(xs) do for y=bottom+1,bottom+tail do belt(x,y) end end
   connect(xs,xt,levels,bottom+tail,front)
   ports={}
   for _,p in ipairs(prefix.inputs) do ports[#ports+1]={x=p.x+dx,y=p.y+dy} end
  end
 end
 return {specs=specs,keepout=keepout,inputs=ports,output_y=0,channels_per_wagon=per_wagon,shared=true,
  source_label=inputs.."_"..(wagons*per_wagon).." global + "..wagons.." x 6-output modules"}
end

function bank.geometry(inputs,wagons,belt_name,weights)
 local per_wagon=bank.channels(inputs,wagons)
 local key=belt_name..":"..inputs..":"..wagons
 local layout=geometry_cache[key]
 if not layout then
  local err
  layout,err=build(inputs,wagons,belt_name,per_wagon)
  if not layout then return nil,err end
  geometry_cache[key]=layout;cache_order[#cache_order+1]=key
  if #cache_order>16 then geometry_cache[table.remove(cache_order,1)]=nil end
 end
 local result={}
 for k,v in pairs(layout) do result[k]=v end
 local total=0
 for i=1,inputs do total=total+(weights and weights[i] or 1) end
 result.groups={}
 for i=1,wagons do result.groups[i]={count=per_wagon,load=total/wagons} end
 return result
end

return bank
