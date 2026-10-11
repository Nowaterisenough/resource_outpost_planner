local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local rows = {}
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

function rows.position(state, spec)
	local c = state.coords
	local p = util.revert_world(c.gx,c.gy,state.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
	local box = obstacles.entity_box(spec.name,{x=p[1],y=p[2]},
		util.bp_direction[state.direction_choice][spec.direction or defines.direction.north])
	return {x=(box.left_top.x+box.right_bottom.x)/2,y=(box.left_top.y+box.right_bottom.y)/2},box
end

local function overlap(a,b)
	return a.left_top.x<b.right_bottom.x and b.left_top.x<a.right_bottom.x
		and a.left_top.y<b.right_bottom.y and b.left_top.y<a.right_bottom.y
end

function rows.specifications(state, attempt)
	local proto = prototypes.entity[state.beacon_choice]
	local w,h,gap = proto.tile_width,proto.tile_height,state.beacon_pipe_gap
	local strips = {}
	for _,miner in ipairs(attempt.miners) do
		for _,x in ipairs{miner.x-w-gap,miner.x+state.miner.size+gap} do
			local strip = strips[x] or {x=x,y1=miner.y,y2=miner.y+state.miner.size}
			strip.y1,strip.y2 = min(strip.y1,miner.y),max(strip.y2,miner.y+state.miner.size)
			strips[x] = strip
		end
	end
	local ordered = {}
	for _,strip in pairs(strips) do ordered[#ordered+1] = strip end
	table.sort(ordered,function(a,b) return a.x<b.x end)
	local specs = {}
	for _,strip in ipairs(ordered) do
		local y1 = attempt.sy+floor((strip.y1-attempt.sy)/h)*h
		local y2 = attempt.sy+ceil((strip.y2-attempt.sy)/h)*h
		for y=y1,y2-1,h do
			specs[#specs+1] = {name=state.beacon_choice,quality=state.beacon_quality_choice,thing="beacon",
				grid_x=strip.x+(w-1)/2,grid_y=y+(h-1)/2,extent_w=w/2,extent_h=h/2,
				row_x=strip.x,row_y=y}
		end
	end
	return specs
end

function rows.reserve(state)
	state.builder_beacons = rows.specifications(state,state.best_attempt)
	local selected
	if obstacles.active(state) then
		selected = obstacles.get(setmetatable({_belt_routing=true},{__index=state}))
	end
	for _,spec in ipairs(state.builder_beacons) do
		if selected then
			local p,box = rows.position(state,spec)
			if obstacles.blocked_box(selected,box) then
				spec.preview_blocked = true
				state.preview_error = {"mpp.beacon_row_blocked"}
				state._preview_issues = state._preview_issues or {}
				state._preview_issues[#state._preview_issues+1] = {position=p,left_top=box.left_top,
					right_bottom=box.right_bottom,reason=state.preview_error}
			end
		end
		for y=spec.row_y,spec.row_y+prototypes.entity[state.beacon_choice].tile_height-1 do
			for x=spec.row_x,spec.row_x+prototypes.entity[state.beacon_choice].tile_width-1 do
				state.grid:build_thing_simple(x,y,"beacon")
			end
		end
	end
	-- A narrow drill cannot reach ore underneath the centre of a full beacon strip.
	local reachable = {}
	local M = state.miner
	for _,miner in ipairs(state.best_attempt.miners) do
		for y=miner.y+M.extent_negative,miner.y+M.extent_positive do
			for x=miner.x+M.extent_negative,miner.x+M.extent_positive do reachable[x..","..y] = true end
		end
	end
	for _,tile in ipairs(state.resource_tiles or {}) do
		if not reachable[tile.x..","..tile.y] then
			local c = state.coords
			local p = util.revert_world(c.gx,c.gy,state.direction_choice,tile.x,tile.y,c.tw,c.th)
			state._preview_issues = state._preview_issues or {}
			state._preview_issues[#state._preview_issues+1] = {position={x=floor(p[1])+0.5,y=floor(p[2])+0.5},
				left_top={x=floor(p[1]),y=floor(p[2])},right_bottom={x=floor(p[1])+1,y=floor(p[2])+1},
				reason={"mpp.beacon_row_unreachable"}}
		end
	end
end

function rows.prune_poles(state)
	local poles = state.builder_power_poles
	if #poles==0 then return end
	local radius,reach = state.pole.supply_area_distance or state.pole.radius,state.pole.wire
	local size = max(1,reach)
	local nodes,buckets,counts = {},{},{}
	local function bucket(x,y) return x..","..y end
	for i,spec in ipairs(poles) do
		local p = rows.position(state,spec)
		local node = {position=p,neighbors={},consumers={},active=true}
		nodes[i] = node
		local x,y = floor(p.x/size),floor(p.y/size)
		for bx=x-1,x+1 do for by=y-1,y+1 do
			for _,j in ipairs(buckets[bucket(bx,by)] or {}) do
				local q = nodes[j].position
				if (p.x-q.x)^2+(p.y-q.y)^2<=reach^2 then
					node.neighbors[#node.neighbors+1]=j
					nodes[j].neighbors[#nodes[j].neighbors+1]=i
				end
			end
		end end
		local k = bucket(x,y)
		buckets[k]=buckets[k] or {};buckets[k][#buckets[k]+1]=i
	end
	for _,list in ipairs{state.builder_miners or {},state.builder_beacons or {}} do
		for _,spec in ipairs(list) do
			if prototypes.entity[spec.name].electric_energy_source_prototype then
				local _,box = rows.position(state,spec)
				local c = #counts+1;counts[c]=0
				for x=floor((box.left_top.x-radius)/size),floor((box.right_bottom.x+radius)/size) do
					for y=floor((box.left_top.y-radius)/size),floor((box.right_bottom.y+radius)/size) do
						for _,i in ipairs(buckets[bucket(x,y)] or {}) do
							local p = nodes[i].position
							if p.x+radius>box.left_top.x and p.x-radius<box.right_bottom.x
								and p.y+radius>box.left_top.y and p.y-radius<box.right_bottom.y then
								nodes[i].consumers[#nodes[i].consumers+1]=c;counts[c]=counts[c]+1
							end
						end
					end
				end
			end
		end
	end
	-- Delete sparse outer poles first, retaining every consumer and every necessary wire bridge.
	local order = {};for i=1,#nodes do order[i]=i end
	table.sort(order,function(a,b)
		local na,nb=nodes[a],nodes[b]
		if #na.consumers~=#nb.consumers then return #na.consumers<#nb.consumers end
		if #na.neighbors~=#nb.neighbors then return #na.neighbors<#nb.neighbors end
		return a<b
	end)
	local budget = max(65536,#nodes*64)
	local function removable(i)
		local node=nodes[i]
		for _,c in ipairs(node.consumers) do if counts[c]<=1 then return false end end
		local wanted,remaining,first={},0
		for _,j in ipairs(node.neighbors) do if nodes[j].active then
			wanted[j]=true;remaining=remaining+1;first=first or j
		end end
		if remaining<=1 then return true end
		local queue,seen,head={first},{[first]=true,[i]=true},1
		wanted[first]=nil;remaining=remaining-1
		while head<=#queue do
			if budget<=0 then return false end
			budget=budget-1
			local current=nodes[queue[head]];head=head+1
			for _,j in ipairs(current.neighbors) do
				if nodes[j].active and not seen[j] then
					seen[j]=true;queue[#queue+1]=j
					if wanted[j] then
						wanted[j]=nil;remaining=remaining-1
						if remaining==0 then return true end
					end
				end
			end
		end
		return false
	end
	local changed=true
	while changed do
		changed=false
		for _,i in ipairs(order) do
			local node=nodes[i]
			if node.active and removable(i) then
				node.active=false;changed=true
				for _,c in ipairs(node.consumers) do counts[c]=counts[c]-1 end
			end
		end
	end
	local kept={}
	for i,spec in ipairs(poles) do
		if nodes[i].active then kept[#kept+1]=spec
		else state.grid:build_thing_simple(spec.grid_x,spec.grid_y,nil) end
	end
	state.builder_power_poles=kept
end

function rows.finish(state)
	local proto = prototypes.entity[state.beacon_choice]
	local distance = proto.get_supply_area_distance(state.beacon_quality_choice or "normal")
	local counts = {}
	local covered,lowest,highest,total = 0,math.huge,0,0
	local towers = {}
	for _,spec in ipairs(state.builder_beacons or {}) do
		if not spec.preview_blocked then
			local _,box = rows.position(state,spec)
			towers[#towers+1] = {left_top={x=box.left_top.x-distance,y=box.left_top.y-distance},
				right_bottom={x=box.right_bottom.x+distance,y=box.right_bottom.y+distance}}
			total = total+1
		end
	end
	for _,miner in ipairs(state.best_attempt.miners) do
		local _,box = rows.position(state,{name=state.miner_choice,grid_x=miner.origin_x,grid_y=miner.origin_y})
		local count = 0
		for _,area in ipairs(towers) do if overlap(area,box) then count=count+1 end end
		counts[miner] = count
		if count>0 then covered=covered+1 end
		lowest,highest = min(lowest,count),max(highest,count)
	end
	state._beacon_counts = counts
	state._beacons_prepared = true
	state.beacon_summary = {total,covered,#state.best_attempt.miners,lowest==math.huge and 0 or lowest,highest}
end

return rows
