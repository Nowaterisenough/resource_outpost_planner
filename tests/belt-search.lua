-- Run from the repository root with Lua 5.2.
local N,E,S,W=0,4,8,12
local directions={N,E,S,W}
local delta={[N]={x=0,y=-1},[E]={x=1,y=0},[S]={x=0,y=1},[W]={x=-1,y=0}}
package.loaded["mpp.mpp_util"]={directions=function() return E,N,S,W,16 end,direction_coord=delta}
for _,name in ipairs{"builder","obstacles","terrain","output_balancer","train_station"} do
	package.loaded["mpp."..name]={}
end
local planner=require("mpp.belt_planner")
local function upvalue(fn,name)
	for i=1,100 do
		local key,value=debug.getupvalue(fn,i)
		if key==name then return value end
		if not key then break end
	end
	error("Missing search function: "..name)
end
local search=upvalue(upvalue(upvalue(planner.plan,"plan_routes"),"route_bundle"),"path")
local function key(x,y) return x..","..y end

-- Independent Dijkstra oracle: no heuristic, heap, numeric spatial keys or passability cache.
local function shortest_cost(start,finish,facing,allowed,bounds,penalty)
	if start.x==finish.x and start.y==finish.y and W==(facing+S)%16 then return nil end
	local initial=start.x==finish.x and start.y==finish.y and W~=facing and 8 or 0
	local queue={{x=start.x,y=start.y,direction=W,cost=initial}}
	local costs={[key(start.x,start.y)..":"..W]=initial}
	while #queue>0 do
		local index=1
		for i=2,#queue do if queue[i].cost<queue[index].cost then index=i end end
		local node=table.remove(queue,index)
		if node.cost==costs[key(node.x,node.y)..":"..node.direction] then
			if node.x==finish.x and node.y==finish.y then return node.cost end
			for _,direction in ipairs(directions) do
				local step=delta[direction]
				local x,y=node.x+step.x,node.y+step.y
				local goal=x==finish.x and y==finish.y
				if direction~=(node.direction+S)%16 and not (goal and direction==(facing+S)%16)
					and x>=bounds.x1 and x<=bounds.x2 and y>=bounds.y1 and y<=bounds.y2 and allowed(x,y) then
					local cost=node.cost+1+(direction~=node.direction and 8 or 0)+(penalty and penalty(x,y) or 0)
					if goal and direction~=facing then cost=cost+8 end
					local k=key(x,y)..":"..direction
					if not costs[k] or cost<costs[k] then
						costs[k]=cost
						queue[#queue+1]={x=x,y=y,direction=direction,cost=cost}
					end
				end
			end
		end
	end
end

local function route_cost(route,finish,facing,allowed,bounds,penalty)
	local cost=#route==1 and W~=facing and 8 or 0
	local arrival=W
	for i,node in ipairs(route) do
		assert(node.x>=bounds.x1 and node.x<=bounds.x2 and node.y>=bounds.y1 and node.y<=bounds.y2)
		assert(allowed(node.x,node.y),"route enters a blocked cell")
		if i>1 then
			local previous=route[i-1]
			local movement
			for direction,step in pairs(delta) do
				if previous.x+step.x==node.x and previous.y+step.y==node.y then movement=direction end
			end
			assert(movement and movement~=(arrival+S)%16,"route jumps or reverses")
			cost=cost+1+(movement~=arrival and 8 or 0)+(penalty and penalty(node.x,node.y) or 0)
			arrival=movement
		end
	end
	local last=route[#route]
	assert(last.x==finish.x and last.y==finish.y and arrival~=(facing+S)%16,"invalid arrival")
	if #route>1 and arrival~=facing then cost=cost+8 end
	return cost
end

local seed=7193
local function random(n) seed=(seed*48271)%2147483647;return seed%n end
local cases=0
for trial=1,96 do
	local ox,oy=trial%2==0 and -120.5 or 0,trial%3==0 and 200.25 or 0
	local bounds={x1=ox-3,y1=oy-3,x2=ox+3,y2=oy+3}
	local start,finish={x=ox+3,y=oy},{x=ox-3,y=oy-1}
	local facing=directions[(trial-1)%4+1]
	local blocked,weights={},{}
	for x=-3,3 do for y=-3,3 do
		blocked[key(x+ox,y+oy)]=random(5)==0
		weights[key(x+ox,y+oy)]=random(4)*3
	end end
	blocked[key(start.x,start.y)],blocked[key(finish.x,finish.y)]=false,false
	local function allowed(x,y) return not blocked[key(x,y)] end
	local penalty=trial%2==0 and function(x,y) return weights[key(x,y)] or 0 end or nil
	local expected=shortest_cost(start,finish,facing,allowed,bounds,penalty)
	local calls={}
	local function checked(x,y)
		local k=key(x,y);calls[k]=(calls[k] or 0)+1
		assert(calls[k]==1,"a cell was checked again for another arrival direction")
		return allowed(x,y)
	end
	local penalty_calls={}
	local checked_penalty=penalty and function(x,y)
		local k=key(x,y);penalty_calls[k]=(penalty_calls[k] or 0)+1
		assert(penalty_calls[k]==1,"congestion was recalculated for another arrival direction")
		return penalty(x,y)
	end or nil
	local route=search(start,finish,facing,checked,bounds,checked_penalty)
	assert((route~=nil)==(expected~=nil),"search disagrees with reachability oracle")
	if route then
		assert(route[1].x==start.x and route[1].y==start.y,"route lost its source")
		assert(route_cost(route,finish,facing,allowed,bounds,penalty)==expected,"search changed the minimum route cost")
	end
	local repeated=search(start,finish,facing,allowed,bounds,penalty)
	assert((route~=nil)==(repeated~=nil))
	if route then
		assert(#route==#repeated,"repeated search changed length")
		for i,node in ipairs(route) do assert(node.x==repeated[i].x and node.y==repeated[i].y,"tie breaking is unstable") end
	end
	cases=cases+1
end

local bounds={x1=-3,y1=-3,x2=3,y2=3}
local start,finish={x=3,y=0},{x=-3,y=0}
local closed=false
local function corridor(x,y) return not closed and y==0 end
assert(search(start,finish,W,corridor,bounds))
closed=true
assert(not search(start,finish,W,corridor,bounds),"passability cache escaped its search")
closed=false
assert(search(start,finish,W,corridor,bounds),"a negative cache survived another search")
cases=cases+3
local budget={remaining=1}
assert(not search(start,finish,W,corridor,bounds,nil,budget) and budget.remaining==0,"node budget was bypassed")
assert(not search(start,finish,W,function() error("zero-budget search checked cells") end,bounds,nil,{remaining=0}))
cases=cases+2
for _,facing in ipairs(directions) do
	local route=search(start,start,facing,corridor,bounds)
	assert((route==nil)==(facing==E),"coincident endpoint lost its reversal rule")
	if route then assert(#route==1 and route[1].x==start.x and route[1].y==start.y) end
	cases=cases+1
end
local toll=0
local function open() return true end
local function congestion(x,y) return x==0 and y==0 and toll or 0 end
for _,value in ipairs{0,50,0} do
	toll=value
	local route=assert(search(start,finish,W,open,bounds,congestion))
	assert(route_cost(route,finish,W,open,bounds,congestion)==shortest_cost(start,finish,W,open,bounds,congestion),
		"congestion cache survived a replan with changed lane usage")
	cases=cases+1
end

for _,facing in ipairs(directions) do
	local blocked={}
	local goal={x=-60,y=-60}
	for _,direction in ipairs(directions) do
		if direction~=(facing+S)%16 then
			local step=delta[direction]
			blocked[key(goal.x-step.x,goal.y-step.y)]=true
		end
	end
	local probes=0
	local route=search({x=60,y=60},goal,facing,function(x,y)
		probes=probes+1
		assert(probes<=3,"sealed outlet still triggers an exhaustive search")
		return not blocked[key(x,y)]
	end,{x1=-64,y1=-64,x2=64,y2=64},function() error("sealed outlet calculated congestion") end)
	assert(not route,"outlet accepts an entry that reverses its output direction")
	cases=cases+1

	local small_start,small_goal={x=3,y=2},{x=-3,y=-2}
	local small_bounds={x1=-6,y1=-6,x2=6,y2=6}
	local function one_entry(x,y)
		if math.abs(x-small_goal.x)+math.abs(y-small_goal.y)~=1 then return true end
		local step=delta[facing]
		return x==small_goal.x-step.x and y==small_goal.y-step.y
	end
	route=assert(search(small_start,small_goal,facing,one_entry,small_bounds),"single legal entrance was rejected")
	assert(route_cost(route,small_goal,facing,one_entry,small_bounds)==shortest_cost(small_start,small_goal,facing,one_entry,small_bounds))
	cases=cases+1
end

for _,right in ipairs{0,1} do
	local adjacent=search({x=1,y=0},{x=0,y=0},W,function(x,y)
		assert(x~=1 or y~=0,"entry check revalidated the exempt source")
		return true
	end,{x1=-2,y1=0,x2=right,y2=0})
	assert(adjacent and #adjacent==2,"source-adjacent outlet was rejected")
	cases=cases+1
end
assert(#search({x=0,y=0},{x=0,y=0},N,function() error("zero-length route checked neighbors") end,bounds)==1)
cases=cases+1

-- Reference detours from the previous queue, including symmetric equal-cost routes.
local upper="4,0;3,0;2,0;1,0;1,-1;1,-2;0,-2;-1,-2;-2,-2;-3,-2;-4,-2;-4,-1;-4,0"
local lower="4,0;3,0;2,0;1,0;1,1;1,2;0,2;-1,2;-2,2;-3,2;-4,2;-4,1;-4,0"
local expected_paths={[N]=lower,[E]=upper,[S]=upper,[W]=upper}
for _,facing in ipairs(directions) do
	local route=assert(search({x=4,y=0},{x=-4,y=0},facing,function(x,y)
		return x~=0 or math.abs(y)>1
	end,{x1=-6,y1=-4,x2=6,y2=4}))
	local cells={}
	for _,node in ipairs(route) do cells[#cells+1]=key(node.x,node.y) end
	assert(table.concat(cells,";")==expected_paths[facing],"heap changes selected a different equal-cost detour")
	cases=cases+1
end
print("Belt search OK: "..cases.." oracle, weighted detour, fractional bounds, cache lifetime and budget cases")
