local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local beacon_rows = require("mpp.beacon_rows")
local beacons = {}
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local NORTH = defines.direction.north

local function key(x,y) return x..","..y end

beacons.density_values={1,2,4,0}

function beacons.target_count(state)
	local choice=state.beacon_density_choice
	for _,value in ipairs(beacons.density_values) do if choice==value then return value end end
	return 4
end

function beacons.enabled(state)
	local proto=prototypes.entity[state.beacon_choice or "none"]
	local miner=prototypes.entity[state.miner_choice]
	return proto and proto.type=="beacon" and miner~=nil and state.layout_choice~="blueprints" and state.layout_choice~="oil"
		and not (miner and miner.effect_receiver and not miner.effect_receiver.uses_beacon_effects)
end

function beacons.module_allowed(proto,item)
	if not proto or not item or item.type~="module" then return false end
	if proto.allowed_module_categories and not proto.allowed_module_categories[item.category] then return false end
	for effect,value in pairs(item.get_module_effects("normal")) do
		-- Native restrictions reject bonuses, not penalties such as a speed module's negative quality.
		if value>0 and proto.allowed_effects and not proto.allowed_effects[effect] then return false end
	end
	return true
end

local function settings(state)
	local proto=prototypes.entity[state.beacon_choice]
	local quality=state.beacon_quality_choice or "normal"
	local module=prototypes.item[state.beacon_module_choice or "none"]
	local effects=module and beacons.module_allowed(proto,module)
		and module.get_module_effects(state.beacon_module_quality_choice or "normal") or {}
	local slots=proto.get_inventory_size(defines.inventory.beacon_modules,quality) or 0
	local level=prototypes.quality[quality] and prototypes.quality[quality].level or 0
	local efficiency=proto.distribution_effectivity+(proto.distribution_effectivity_bonus_per_quality_level or 0)*level
	return proto,effects,slots,efficiency
end

local function influence(proto,count)
	if count==0 then return 0 end
	local profile=proto.profile or {1}
	return count*(profile[min(count,#profile)] or 1)
end

function beacons.effects(state,miner)
	if not beacons.enabled(state) then return {} end
	local proto,effects,slots,efficiency=settings(state)
	local amount
	if state._beacons_prepared then
		amount=influence(proto,miner and state._beacon_counts[miner] or 0)
	else
		-- Until placements are known, keep merging safe even if every free beacon position is used.
		local drill=prototypes.entity[state.miner_choice]
		local distance=proto.get_supply_area_distance(state.beacon_quality_choice or "normal")
		local count=(ceil((drill.tile_width+2*distance)/proto.tile_width)+2)
			*(ceil((drill.tile_height+2*distance)/proto.tile_height)+2)
		amount=0
		for n=1,count do amount=max(amount,influence(proto,n)) end
	end
	return {speed=(state._beacons_prepared and (effects.speed or 0) or max(0,effects.speed or 0))*slots*efficiency*amount,
		productivity=max(0,effects.productivity or 0)*slots*efficiency*amount}
end

local function position(state,spec)
	local c=state.coords
	local pos=util.revert_world(c.gx,c.gy,state.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
	local box=obstacles.entity_box(spec.name,{x=pos[1],y=pos[2]},util.bp_direction[state.direction_choice][spec.direction or NORTH])
	return {x=(box.left_top.x+box.right_bottom.x)/2,y=(box.left_top.y+box.right_bottom.y)/2},box
end

local function grid_position(state,pos)
	local c=state.coords
	local origin=util.revert_world(c.gx,c.gy,state.direction_choice,0,0,c.tw,c.th)
	return util.coord_convert[state.direction_choice](pos.x-floor(origin[1])-0.5,pos.y-floor(origin[2])-0.5,0,0)
end

local function overlaps(a,b)
	return a.left_top.x<b.right_bottom.x and a.right_bottom.x>b.left_top.x
		and a.left_top.y<b.right_bottom.y and a.right_bottom.y>b.left_top.y
end

function beacons.prepare(state, production)
	if state._beacon_rows then return beacon_rows.finish(state) end
	if not beacons.enabled(state) then
		state.builder_beacons={}
		state._beacon_counts={}
		state._beacons_prepared=true
		return
	end
	local proto=prototypes.entity[state.beacon_choice]
	local quality=state.beacon_quality_choice or "normal"
	local distance=proto.get_supply_area_distance(quality)
	local target_count=beacons.target_count(state)
	local fill=target_count==0
	local planning=state._beacon_planning
	local initializing=not planning
	if initializing then
		planning={occupied={},miner_cells={},miners={},candidates={},seen={},regular={},resources={},
			miner_index=1,regular_pass=true,removed={},selected={}}
		state._beacon_planning=planning
		state.builder_beacons={}
		state._beacon_counts={}
	end
	local occupied,miner_cells,miners=planning.occupied,planning.miner_cells,planning.miners
	local function cells(box,fn)
		for x=floor(box.left_top.x+0.001),ceil(box.right_bottom.x-0.001)-1 do
			for y=floor(box.left_top.y+0.001),ceil(box.right_bottom.y-0.001)-1 do fn(x,y,key(x,y)) end
		end
	end
	local function occupy(box,value)
		cells(box,function(_,_,k) occupied[k]=value end)
	end
	if initializing then
		for _,list in pairs{state.builder_pipes or {},state.builder_belts or {},state.builder_belt_connections or {},
			state.builder_power_poles or {},state.builder_lamps or {}} do
			for _,spec in ipairs(list) do
				if prototypes.entity[spec.name] then local _,box=position(state,spec);occupy(box,true) end
			end
		end
		for _,tile in ipairs(state.resource_tiles or {}) do
			planning.resources[key(tile.x,tile.y)]={count=0}
		end
		local M=state.miner
		for _,miner in ipairs(state.best_attempt.miners) do
			local pos,box=position(state,{name=state.miner_choice,grid_x=miner.origin_x,grid_y=miner.origin_y,direction=miner.direction})
			local target={placement=miner,box=box,pos=pos,resources={}}
			miners[#miners+1]=target
			state._beacon_counts[miner]=0
			occupy(box,target)
			cells(box,function(_,_,k) miner_cells[k]=target end)
			if miner.x and miner.y and M.area then
				for y=miner.y+M.extent_negative,miner.y+M.extent_positive do
					for x=miner.x+M.extent_negative,miner.x+M.extent_positive do
						local resource=planning.resources[key(x,y)]
						if resource then resource.count=resource.count+1;target.resources[#target.resources+1]=resource end
					end
				end
			end
			local dx=(box.right_bottom.x-box.left_top.x+proto.tile_width)/2
			local dy=(box.right_bottom.y-box.left_top.y+proto.tile_height)/2
			-- Repeated anchors keep shared towers aligned with the drill rows, even after rotation.
			for _,offset in ipairs{{-dx,0},{dx,0},{0,-dy},{0,dy},{-1,-dy},{1,-dy},{-1,dy},{1,dy}} do
				local x=floor(pos.x+offset[1]-proto.tile_width/2+0.5)
				local y=floor(pos.y+offset[2]-proto.tile_height/2+0.5)
				planning.regular[key(x,y)]=true
			end
		end
		-- Cache native, clamped production at each tower count for the joint-layout objective.
		planning.production={}
		local _,effects=settings(state)
		planning.productive=(effects.speed or 0)>0 or (effects.productivity or 0)>0
		local sample=miners[1] and miners[1].placement
		if sample then
			state._beacons_prepared=true
			local drill=prototypes.entity[state.miner_choice]
			local bound=(ceil((drill.tile_width+2*distance)/proto.tile_width)+2)
				*(ceil((drill.tile_height+2*distance)/proto.tile_height)+2)
			for count=0,bound do
				state._beacon_counts[sample]=count
				planning.production[count]=production and production(state,nil,sample) or max(0.2,1+(beacons.effects(state,sample).speed or 0))
			end
			state._beacon_counts[sample]=0
			state._beacons_prepared=nil
		end
		-- Keep exits clear even when connecting the output belts is disabled.
		for _,belt in ipairs(state.belts or {}) do
			if belt.is_output then for step=1,2 do
				local _,box=position(state,{name=state.belt_choice,grid_x=belt.x_start-step,grid_y=belt.y})
				occupy(box,true)
			end end
		end
		if state.belt_target and state.belt_planner_choice then
			local count=0;for _,belt in ipairs(state.belts or {}) do if belt.is_output then count=count+1 end end
			local delta=util.direction_coord[state.belt_target.direction]
			for lane=0,count-1 do for step=-1,1 do
				local p=state.belt_target.position
				occupy(obstacles.entity_box(state.belt_choice,{x=p.x-delta.y*lane+delta.x*step,
					y=p.y+delta.x*lane+delta.y*step},state.belt_target.direction),true)
			end end
		end
	end
	local safety=setmetatable({_belt_routing=true},{__index=state})
	if initializing and (obstacles.active(state)) then
		planning.obstacles=obstacles.get(safety)
	end
	local function free(name,pos,ignore)
		local box=obstacles.entity_box(name,pos,NORTH)
		local clear=true
		cells(box,function(x,y,k)
			if occupied[k] and occupied[k]~=ignore then clear=false end
			local gx,gy=grid_position(state,{x=x+0.5,y=y+0.5})
			if state.grid and not state.grid:get_tile(floor(gx+0.5),floor(gy+0.5)) then clear=false end
		end)
		return clear and (not planning.obstacles or not obstacles.blocked_box(planning.obstacles,box)),box
	end
	local poles=state.builder_power_poles or {}
	state.builder_power_poles=poles
	local function power(pos,box)
		if state.pole_choice=="none" or state.pole_choice=="zero_gap" then return true end
		local pole=prototypes.entity[state.pole_choice]
		local pole_quality=state.pole_quality_choice or "normal"
		local supply=pole.get_supply_area_distance(pole_quality)
		local reach=pole.get_max_wire_distance(pole_quality)
		local nearby={}
		for _,spec in ipairs(poles) do
			local p=position(state,spec)
			if overlaps(box,{left_top={x=p.x-supply,y=p.y-supply},right_bottom={x=p.x+supply,y=p.y+supply}}) then return true end
			if (p.x-pos.x)^2+(p.y-pos.y)^2<=(reach+supply+max(proto.tile_width,proto.tile_height))^2 then nearby[#nearby+1]=p end
		end
		local radius=ceil(supply+max(proto.tile_width,proto.tile_height)/2)
		local best
		for y=floor(pos.y)-radius,floor(pos.y)+radius do for x=floor(pos.x)-radius,floor(pos.x)+radius do
			local p={x=x+(pole.tile_width%2)/2,y=y+(pole.tile_height%2)/2}
			if overlaps(box,{left_top={x=p.x-supply,y=p.y-supply},right_bottom={x=p.x+supply,y=p.y+supply}}) then
				local wired=#poles==0
				local wire_distance=math.huge
				for _,other in ipairs(nearby) do
					local d=(other.x-p.x)^2+(other.y-p.y)^2
					if d<=reach^2 then wired=true;wire_distance=min(wire_distance,d) end
				end
				local clear,pole_box=free(state.pole_choice,p)
				local score=(p.x-pos.x)^2+(p.y-pos.y)^2+(wired and wire_distance~=math.huge and wire_distance/100 or 0)
				if wired and clear and (not best or score<best.score) then best={position=p,box=pole_box,score=score} end
			end
		end end
		if not best then return false end
		local x,y=grid_position(state,best.position)
		poles[#poles+1]={name=state.pole_choice,quality=pole_quality,thing="pole",grid_x=x,grid_y=y,
			extent_w=pole.tile_width/2,extent_h=pole.tile_height/2}
		occupy(best.box,true)
		return true
	end
	local candidates,seen=planning.candidates,planning.seen
	local function candidate_at(pos,remove,regular)
		local clear,footprint=free(state.beacon_choice,pos,remove)
		if not clear then return end
		local area={left_top={x=pos.x-proto.tile_width/2-distance,y=pos.y-proto.tile_height/2-distance},
			right_bottom={x=pos.x+proto.tile_width/2+distance,y=pos.y+proto.tile_height/2+distance}}
		local targets,found={},{}
		cells(area,function(_,_,cell)
			local target=miner_cells[cell]
			if target and target~=remove and not found[target] and overlaps(area,target.box) then
				found[target]=true;targets[#targets+1]=target
			end
		end)
		if #targets>0 then candidates[#candidates+1]={pos=pos,box=footprint,targets=targets,remove=remove,regular=regular} end
	end
	local budget=max(1,floor(4*(state.performance_scaling or 1)))
	local last=min(#miners,planning.miner_index+budget-1)
	for i=planning.miner_index,last do
		local miner=miners[i]
		local box=miner.box
		-- A tower may replace a redundant drill only if every previously mined resource stays reachable.
		if state.resource_tiles and #miner.resources>0
			and proto.tile_width<=prototypes.entity[state.miner_choice].tile_width
			and proto.tile_height<=prototypes.entity[state.miner_choice].tile_height then
			local pos={x=floor(miner.pos.x-proto.tile_width/2+0.5)+proto.tile_width/2,
				y=floor(miner.pos.y-proto.tile_height/2+0.5)+proto.tile_height/2}
			candidate_at(pos,miner,true)
		end
		for y=floor(box.left_top.y-distance-proto.tile_height),ceil(box.right_bottom.y+distance) do
			for x=floor(box.left_top.x-distance-proto.tile_width),ceil(box.right_bottom.x+distance) do
				local k=key(x,y)
				if not seen[k] then
					seen[k]=true
					local pos={x=x+proto.tile_width/2,y=y+proto.tile_height/2}
					candidate_at(pos,nil,planning.regular[k])
				end
			end
		end
	end
	planning.miner_index=last+1
	if planning.miner_index<=#miners then return true end
	local processed=0
	while true do
		local best,score
		for _,candidate in ipairs(candidates) do
			if not candidate.used and (not planning.regular_pass or candidate.regular) then
				local uncovered,needed,gain=0,0,0
				for _,target in ipairs(candidate.targets) do if not target.removed then
					local count=state._beacon_counts[target.placement]
					if count==0 then uncovered=uncovered+1 end
					if fill or count<target_count then needed=needed+1 end
					gain=gain+planning.production[count+1]-planning.production[count]
				end end
				local remove=candidate.remove
				local safe=not planning.productive or gain>0.000001
				if remove then
					safe=not remove.removed
					for _,resource in ipairs(remove.resources) do if resource.count<=1 then safe=false;break end end
					if safe then gain=gain-planning.production[state._beacon_counts[remove.placement]] end
					safe=safe and gain>0.000001
				end
				local value=uncovered*(#miners+1)+needed+gain/(1+planning.production[1])
				if safe and needed>0 and (not score or value>score) then
					local clear=free(state.beacon_choice,candidate.pos,remove)
					if clear then best,score=candidate,value else candidate.used=true end
				end
			end
		end
		if not best then
			if planning.regular_pass then planning.regular_pass=false else break end
		else
			best.used=true
			if best.remove then occupy(best.remove.box,nil) end
			occupy(best.box,true)
			if power(best.pos,best.box) then
				local x,y=grid_position(state,best.pos)
				local spec={name=state.beacon_choice,quality=quality,thing="beacon",
					grid_x=x,grid_y=y,extent_w=proto.tile_width/2,extent_h=proto.tile_height/2}
				state.builder_beacons[#state.builder_beacons+1]=spec
				planning.selected[#planning.selected+1]={candidate=best,spec=spec}
				if best.remove then
					local target=best.remove
					target.removed=true;planning.removed[target.placement]=true
					state._beacon_counts[target.placement]=nil
					for _,resource in ipairs(target.resources) do resource.count=resource.count-1 end
					cells(target.box,function(x,y,k)
						miner_cells[k]=nil
						local gx,gy=grid_position(state,{x=x+0.5,y=y+0.5})
						state.grid:build_thing_simple(floor(gx+0.5),floor(gy+0.5),nil)
					end)
				end
				for _,target in ipairs(best.targets) do if not target.removed then
					local miner=target.placement
					state._beacon_counts[miner]=state._beacon_counts[miner]+1
				end end
			else
				occupy(best.box,nil)
				if best.remove then occupy(best.remove.box,best.remove) end
			end
			processed=processed+1
			if processed>=budget then return true end
		end
	end
	local function keep(list,predicate)
		local n=0
		for _,item in ipairs(list) do if predicate(item) then n=n+1;list[n]=item end end
		for i=#list,n+1,-1 do list[i]=nil end
	end
	local function retained(miner) return not planning.removed[miner] end
	local total=0
	for _,target in ipairs(miners) do if not target.removed then total=total+planning.production[state._beacon_counts[target.placement]] end end
	local redundant={}
	-- Retain the requested density when pruning; fill mode keeps all useful placements.
	for _,regular in ipairs{false,true} do for i=#planning.selected,1,-1 do
		local selected=planning.selected[i]
		local candidate=selected.candidate
		if not fill and not candidate.remove and (candidate.regular or false)==regular then
			local removable,loss=true,0
			for _,target in ipairs(candidate.targets) do if not target.removed then
				local count=state._beacon_counts[target.placement]
				if count<=target_count then removable=false;break end
				loss=loss+planning.production[count]-planning.production[count-1]
			end end
			if removable and total-loss>=#miners*planning.production[0] then
				redundant[selected.spec]=true;total=total-loss
				for _,target in ipairs(candidate.targets) do if not target.removed then
					local miner=target.placement;state._beacon_counts[miner]=state._beacon_counts[miner]-1
				end end
			end
		end
	end end
	keep(state.builder_beacons,function(spec) return not redundant[spec] end)
	local removed_positions={}
	for _,target in ipairs(miners) do if target.removed then
		local miner=target.placement
		removed_positions[key(miner.origin_x,miner.origin_y)]=true
	end end
	keep(state.best_attempt.miners,retained)
	keep(state.builder_miners,function(spec) return not removed_positions[key(spec.grid_x,spec.grid_y)] end)
	for _,lane in pairs(state.miner_lanes or {}) do keep(lane,retained) end
	for _,belt in ipairs(state.belts or {}) do
		if belt.lane1 then keep(belt.lane1,retained) end
		if belt.lane2 then keep(belt.lane2,retained) end
	end
	if state.best_attempt.heuristics then state.best_attempt.heuristics.drill_count=#state.best_attempt.miners end
	for _,list in ipairs{state.builder_beacons,poles} do for _,spec in ipairs(list) do
		if prototypes.entity[spec.name] then
		local _,box=position(state,spec)
		cells(box,function(x,y)
			local gx,gy=grid_position(state,{x=x+0.5,y=y+0.5})
			state.grid:build_thing_simple(floor(gx+0.5),floor(gy+0.5),spec.thing)
		end)
		end
	end end
	local covered,lowest,highest=0,math.huge,0
	for _,count in pairs(state._beacon_counts) do
		if count>0 then covered=covered+1 end
		lowest=min(lowest,count);highest=max(highest,count)
	end
	state.beacon_summary={#state.builder_beacons,covered,#state.best_attempt.miners,lowest==math.huge and 0 or lowest,highest}
	state._beacons_prepared=true
	state._beacon_planning=nil
end

function beacons.module_plan(state)
	local proto=prototypes.entity[state.beacon_choice]
	local item=prototypes.item[state.beacon_module_choice or "none"]
	if not item or not beacons.module_allowed(proto,item) then return end
	local slots=proto.get_inventory_size(defines.inventory.beacon_modules,state.beacon_quality_choice or "normal") or 0
	if slots==0 then return end
	local plan={}
	for slot=0,slots-1 do plan[#plan+1]={inventory=defines.inventory.beacon_modules,stack=slot} end
	return {{id={name=item.name,quality=state.beacon_module_quality_choice or "normal"},items={in_inventory=plan}}}
end

return beacons
