-- Run from the repository root with Lua 5.2.
defines={direction={},events={on_tick=1},build_check_type={blueprint_ghost=1}}
local names={"north","northnortheast","northeast","eastnortheast","east","eastsoutheast","southeast","southsoutheast",
	"south","southsouthwest","southwest","westsouthwest","west","westnorthwest","northwest","northnorthwest"}
for i,name in ipairs(names) do defines.direction[name]=i-1 end
function table_size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local result={}; for k,v in pairs(t) do result[k]=table.deepcopy(v) end; return result
end
script={active_mods={},feature_flags={quality=true},on_event=function() end,register_metatable=function() end}
game={tick=1}
storage={players={},tasks={},script_inventory={{},{}}}
task_runner_handler=function() end
helpers={is_valid_sprite_path=function() return false end}
rendering={draw_rectangle=function() return {valid=true,destroy=function() end} end,
	draw_sprite=function() return {valid=true,destroy=function() end} end}
prototypes={entity={},quality={}}
local function prototype(name,typ,size)
	local radius=size/2-0.1
	prototypes.entity[name]={name=name,type=typ,tile_width=size,tile_height=size,supports_direction=true,
		collision_box={left_top={x=-radius,y=-radius},right_bottom={x=radius,y=radius}},
		collision_mask={layers={object=true}},has_flag=function() return false end}
end
prototype("transport-belt","transport-belt",1)
prototype("electric-mining-drill","mining-drill",3)
require("mpp.global_extends")
local planner=require("mpp.belt_planner")
local obstacles=require("mpp.obstacles")
local builder=require("mpp.builder")
local common=require("layouts.common")
local preview=require("mpp.preview")
local input_mode=require("mpp.input_mode")
local simple=require("layouts.simple")
local util=require("mpp.mpp_util")
local N,E,S,W=defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west

local function surface(tiles,entities)
	local result={valid=true,created={},deconstructions=0}
	result.find_tiles_filtered=function() return tiles or {} end
	result.find_entities_filtered=function() return entities or {} end
	result.get_tile=function(pos)
		for _,tile in ipairs(tiles or {}) do
			if tile.position.x==math.floor(pos.x) and tile.position.y==math.floor(pos.y) then return tile end
		end
		return {name="grass-1",position={x=math.floor(pos.x),y=math.floor(pos.y)},prototype={collision_mask={layers={ground_tile=true}}}}
	end
	result.create_entity=function(spec)
		local entity={valid=true,type=spec.name,position=spec.position,direction=spec.direction}
		result.created[#result.created+1]=entity
		return entity
	end
	result.deconstruct_area=function() result.deconstructions=result.deconstructions+1 end
	return result
end
local function player(map)
	local stack={valid_for_read=false}
	stack.set_stack=function(name) stack.name=name; stack.valid_for_read=true; stack.entities=nil end
	stack.set_blueprint_entities=function(entities) stack.entities=#entities>0 and table.deepcopy(entities) or nil end
	stack.get_blueprint_entities=function() return stack.entities and table.deepcopy(stack.entities) end
	local result={index=1,force={},surface=map,cursor_stack=stack,print=function() end}
	result.clear_cursor=function() stack.valid_for_read=false; return true end
	game.get_player=function() return result end
	return result
end
local function fixture(direction,count,map)
	map=map or surface()
	local ply=player(map)
	storage.players[1]={choices={belt_planner_choice=true},belt_planner_stack={}}
	local vertical=direction=="north" or direction=="south"
	local coords={gx=-0.5,gy=-0.5,x1=0.5,y1=0.5,x2=29.5,y2=45.5,w=30,h=46,
		tw=vertical and 46 or 30,th=vertical and 30 or 46}
	local spec={player=ply,surface=map,coords=coords,direction_choice=direction or "west",belt_choice="transport-belt",
		belt_quality_choice="legendary",count=count or 1}
	for i=1,spec.count do spec[i]={x_start=6,y=5+(i-1)*4,is_output=true} end
	return spec,storage.players[1]
end
local function target(spec,x,y,dir)
	local c=spec.coords
	local pos=util.revert_world(c.gx,c.gy,spec.direction_choice,x,y,c.tw,c.th)
	return {position={x=math.floor(pos[1])+0.5,y=math.floor(pos[2])+0.5},direction=util.bp_direction[spec.direction_choice][dir]}
end
local function verify(state,specs)
	local by_position={}
	local destinations,used_destinations={},{}
	if state.interchangeable_belt_inputs then
		for _,p in ipairs(state.belt_input_targets) do destinations[p.x..","..p.y]=true end
	end
	for _,piece in ipairs(specs) do
		local k=piece.grid_x..","..piece.grid_y
		assert(not by_position[k],"lanes overlap at "..k)
		assert(piece.quality=="legendary","belt quality lost")
		by_position[k]=piece
	end
	for source_index,source in ipairs(state.belt_specification) do
		local node=by_position[(source.x_start-1)..","..source.y]
		assert(node,"source disconnected")
		local seen={}
		local arrival=W
		while node do
			assert(not seen[node],"belt route loops")
			assert(node.direction~=(arrival+S)%16,"belt makes a 180-degree reversal")
			seen[node]=true
			local delta=util.direction_coord[node.direction]
			local next=by_position[(node.grid_x+delta.x)..","..(node.grid_y+delta.y)]
			if not next then
				assert(node.direction==state.belt_direction,"wrong output direction")
				if state.interchangeable_belt_inputs then
					local k=node.grid_x..","..node.grid_y
					assert(destinations[k] and not used_destinations[k],"route misses or shares an interchangeable input")
					used_destinations[k]=true
				elseif state.belt_input_targets then
					local destination=state.belt_input_targets[source_index]
					assert(node.grid_x==destination.x and node.grid_y==destination.y,"route misses the balancer input")
				elseif node.direction==N then
					assert(node.grid_y==state.belt_y and node.grid_x>=state.belt_x
						and node.grid_x<state.belt_x+state.belt_specification.count,"route misses the output band")
				elseif node.direction==S then
					assert(node.grid_y==state.belt_y and node.grid_x<=state.belt_x
						and node.grid_x>state.belt_x-state.belt_specification.count,"route misses the output band")
				elseif node.direction==W then
					assert(node.grid_x==state.belt_x and node.grid_y<=state.belt_y
						and node.grid_y>state.belt_y-state.belt_specification.count,"route misses the output band")
				else
					assert(node.grid_x==state.belt_x and node.grid_y>=state.belt_y
						and node.grid_y<state.belt_y+state.belt_specification.count,"route misses the output band")
				end
			end
			arrival=node.direction
			node=next
		end
	end
end

local function route_stats(state,specs)
	local by_position,stats={},{}
	for _,piece in ipairs(specs) do by_position[piece.grid_x..","..piece.grid_y]=piece end
	for i,source in ipairs(state.belt_specification) do
		local node=by_position[(source.x_start-1)..","..source.y]
		local turns,length,first_turn=0,0
		while node do
			length=length+1
			if not first_turn and node.direction~=W then first_turn={x=node.grid_x,y=node.grid_y} end
			local delta=util.direction_coord[node.direction]
			local next=by_position[(node.grid_x+delta.x)..","..(node.grid_y+delta.y)]
			if next and node.direction~=next.direction then turns=turns+1 end
			node=next
		end
		stats[i]={turns=turns,length=length,first_turn=first_turn}
	end
	return stats
end

local cases=0
local function upvalue(fn,name)
	for i=1,100 do
		local key,value=debug.getupvalue(fn,i)
		if key==name then return value,i end
		if not key then break end
	end
	error("missing routing function: "..name)
end
local bundle=upvalue(upvalue(planner.plan,"plan_routes"),"route_bundle")

for _,rotation in ipairs{"west","north","east","south"} do
	local spec=fixture(rotation,1)
	local state=assert(planner.create_state(spec,target(spec,1,3,E),{}))
	state.interchangeable_belt_inputs=true
	state.belt_input_targets={{x=1,y=3}}
	state.grid={get_tile=function(_,x,y) if x==4 and y==5 then return {built_thing="obstacle"} end end}
	local ok,route=planner.plan(state)
	assert(ok,"endpoint-corner negotiation was lost when no alternate input exists")
	verify(state,route)
	for _,piece in ipairs(route) do assert(not state.grid:get_tile(piece.grid_x,piece.grid_y),"fallback crosses the blocked source exit") end
	cases=cases+1
end

for _,rotation in ipairs{"west","north","east","south"} do
	for _,dir in ipairs{N,E,S,W} do
		for _,count in ipairs{1,3} do
			local spec=fixture(rotation,count)
			local positions={[N]={-5,-8},[E]={35,-8},[S]={-5,25},[W]={-12,12}}
			local pos=positions[dir]
			local state=assert(planner.create_state(spec,target(spec,pos[1],pos[2],dir),{}))
			assert(state.belt_x==pos[1] and state.belt_y==pos[2],"target shifts when rotating")
			local ok,route=planner.plan(state)
			assert(ok,"open terrain route failed: "..rotation.."/"..dir.."/"..count)
			verify(state,route)
			cases=cases+1
		end
	end
end

for _,rotation in ipairs{"west","north","east","south"} do
	for _,dir in ipairs{N,E,S,W} do
		local spec=fixture(rotation,3)
		local positions={[N]={-12,-10},[E]={35,-10},[S]={-12,25},[W]={-12,12}}
		local pos=positions[dir]
		local state=assert(planner.create_state(spec,target(spec,pos[1],pos[2],dir),{}))
		local ok,route=planner.plan(state)
		assert(ok,"tidy route failed")
		verify(state,route)
		for i,stat in ipairs(route_stats(state,route)) do
			if dir==W then
				local finish_y=state.belt_y+i-spec.count
				assert(stat.length==spec[i].x_start-1-state.belt_x+math.abs(spec[i].y-finish_y)+1,"compact gathering lengthens an open route")
			else
				assert(stat.turns<=((dir==N or dir==S) and 1 or 2),"open route has unnecessary turns: "..rotation.."/"..dir.."/"..stat.turns)
			end
		end
		local repeated,route_again=planner.plan(state)
		assert(repeated and #route_again==#route,"routing is not deterministic")
		for i,piece in ipairs(route) do
			local other=route_again[i]
			assert(piece.grid_x==other.grid_x and piece.grid_y==other.grid_y and piece.direction==other.direction,"equal-cost route changes between previews")
		end
		cases=cases+1
	end
end
for _,y in ipairs{-15,35} do
	local spec=fixture("west",4)
	local state=assert(planner.create_state(spec,target(spec,35,y,E),{}))
	local ok,route=planner.plan(state)
	assert(ok,"parallel gathering corridor failed")
	verify(state,route)
	for _,stat in ipairs(route_stats(state,route)) do assert(stat.turns==2,"opposite-facing belts fail to gather in parallel corridors") end
	cases=cases+1
end

for _,rotation in ipairs{"west","north","east","south"} do
	for _,exit_x in ipairs{-20,-60} do
		local spec=fixture(rotation,6)
		for i,belt in ipairs(spec) do belt.y=5+(i-1)*10 end
		local state=assert(planner.create_state(spec,target(spec,exit_x,25,W),{}))
		local ok,route=planner.plan(state)
		assert(ok,"middle outlet cannot gather lanes from both sides")
		verify(state,route)
		for i,stats in ipairs(route_stats(state,route)) do
			assert(stats.first_turn.x==5,"middle outlet leaves an empty margin before turning")
			assert(stats.length==5-exit_x+math.abs(spec[i].y-(19+i))+1,"early turns lengthen the open route")
		end
		state.grid={get_tile=function(_,x,y)
			if x==5 and y==18 then return {built_thing="obstacle"} end
		end}
		ok,route=planner.plan(state)
		assert(ok,"preferred early bend prevents an available detour")
		verify(state,route)
		for _,p in ipairs(route) do assert(not state.grid:get_tile(p.grid_x,p.grid_y),"early bend crosses an obstacle") end
		cases=cases+2
	end
end

for _,rotation in ipairs{"west","north","east","south"} do
	local spec=fixture(rotation,3)
	local starts={10,5,20}
	for i,belt in ipairs(spec) do belt.x_start=starts[i]+1;belt.y=(i-1)*10 end
	local state=assert(planner.create_state(spec,target(spec,-12,-8,W),{}))
	state.grid={get_tile=function(_,x,y)
		if (x>=11 and x<=30 and ((y>=-5 and y<=-1) or (y>=1 and y<=5)))
			or (x>=6 and x<=30 and ((y>=6 and y<=9) or (y>=11 and y<=14)))
			or (x>=21 and x<=35 and ((y>=15 and y<=19) or (y>=21 and y<=25))) then
			return {built_thing="miner"}
		end
	end}
	local ok,route=planner.plan(state)
	assert(ok,"contour gathering cannot connect an uneven mining boundary")
	verify(state,route)
	local cells={}
	for _,p in ipairs(route) do
		assert(not state.grid:get_tile(p.grid_x,p.grid_y),"contour gathering enters a miner")
		cells[p.grid_x..","..p.grid_y]=p
	end
	assert(cells["20,19"] and cells["5,14"] and cells["4,10"],"outside lane does not follow the mining and inner-lane boundaries")
	for i,stats in ipairs(route_stats(state,route)) do
		assert(stats.first_turn.x==starts[i],"contour gathering extends a tail before its first bend")
		assert(stats.length==starts[i]+12+math.abs(spec[i].y-(-11+i))+1,"contour gathering adds belt length")
	end
	cases=cases+1
end

do
	local function trim(options,pole_x,first_drop)
		local belt={is_output=true,x_start=0,x_entry=12,x1=first_drop or 14,y=4}
		local state={belts={belt},miner={},belt={related_underground_belt="underground-belt"},
			belt_choice="transport-belt",direction_choice="west",belt_planner_choice=true,belt_target={direction=W},
			grid={get_tile=function(_,x,y) if y==4 and x==pole_x then return {built_thing="pole"} end end}}
		for k,v in pairs(options or {}) do state[k]=v end
		common.create_belt_building_environment(state)
		return belt.x_start
	end
	assert(trim()==12,"ordinary connected mining row retains its aligned empty tail")
	assert(trim(nil,11)==10,"trimmed output collides with an inline pole or severs its underground bypass")
	assert(trim(nil,nil,10)==10,"trimming removes the first drill's receiving belt")
	for _,options in ipairs{{belt_merge_choice=true},{output_balance_choice=true},{output_station_choice=true},
		{belt_target=false},{belt_target={direction=E}}} do
		assert(trim(options)==0,"tail trimming changes an unsupported or unconnected layout")
	end
	cases=cases+8
end

local cliff={valid=true,type="cliff",prototype={collision_mask={layers={}}},
	bounding_box={left_top={x=-1.5,y=2},right_bottom={x=1.5,y=7}}}
local water={name="water",position={x=-4,y=4},prototype={collision_mask={layers={water_tile=true}},default_cover_tile={name="landfill"}}}
for _,choices in ipairs{{avoid_cliffs_choice=true},{avoid_water_choice=true},{avoid_obstacles_choice=true}} do
	local spec=fixture("west",1,surface({water},{cliff}))
	local state=assert(planner.create_state(spec,target(spec,-12,5,W),choices))
	local ok,route=planner.plan(state)
	assert(ok,"obstacle detour failed")
	verify(state,route)
	for _,piece in ipairs(route) do
		local pos=util.revert_world(state.coords.gx,state.coords.gy,"west",piece.grid_x,piece.grid_y,30,30)
		assert(obstacles.can_place(state,piece.name,{x=pos[1],y=pos[2]},piece.direction),"route enters selected obstacle")
	end
	assert(#spec.surface.created==0 and spec.surface.deconstructions==0,"planning modifies the world")
	assert(route_stats(state,route)[1].turns<=4,"obstacle detour zigzags unnecessarily")
	cases=cases+1
end

local spec=fixture("west",1,surface(nil,{cliff}))
local state=assert(planner.create_state(spec,target(spec,0,5,W),{avoid_cliffs_choice=true}))
local ok,err=planner.plan(state)
assert(not ok and err[1]=="mpp.msg_obstacle_route_failed","blocked destination accepted")
assert(#spec.surface.created==0,"failed route partially built")
assert(not planner.create_state(spec,{position={x=500,y=500},direction=W},{}),"distance limit lost")
cases=cases+2

for _,rotation in ipairs{"west","north","east","south"} do
	local large=fixture(rotation,26)
	local c=large.coords
	c.gx,c.gy,c.w,c.h=-250.5,-180.5,300,220
	local vertical=rotation=="north" or rotation=="south"
	c.tw,c.th=vertical and c.h or c.w,vertical and c.w or c.h
	for _,p in ipairs{{x=c.gx-60,y=c.gy+100},{x=c.gx+c.w+60,y=c.gy+100},
		{x=c.gx+150,y=c.gy-60},{x=c.gx+150,y=c.gy+c.h+60}} do
		assert(planner.create_state(large,{position=p,direction=W},{}),"large patch rejected an outlet near its boundary")
		cases=cases+1
	end
	assert(not planner.create_state(large,{position={x=c.gx-101,y=c.gy},direction=W},{}),"ordinary output lost its bounded margin")
	assert(planner.create_state(large,{position={x=c.gx-500,y=c.gy},direction=W},{output_balance_choice=true}),"balancer margin is measured from the centre")
	cases=cases+2
end

spec=fixture()
state=assert(planner.create_state(spec,target(spec,-12,5,W),{}))
state.planned={{name="electric-mining-drill",grid_x=-2,grid_y=5,direction=N},
	{name="none",grid_x=1,grid_y=1}}
ok,err=planner.plan(state)
assert(ok,"planned footprint detour failed")
verify(state,err)
local box=obstacles.entity_box("electric-mining-drill",{x=-3,y=4},N)
for _,piece in ipairs(err) do
	local pos=util.revert_world(state.coords.gx,state.coords.gy,"west",piece.grid_x,piece.grid_y,30,30)
	assert(not obstacles.blocked_box({tiles={},boxes={box}},obstacles.entity_box(piece.name,{x=pos[1],y=pos[2]},piece.direction)),"route enters planned miner")
end
cases=cases+1

spec=fixture("west",1)
state=assert(planner.create_state(spec,target(spec,-12,5,W),{}))
state.planned={}
for y=-28,28 do state.planned[#state.planned+1]={name="transport-belt",grid_x=0,grid_y=y,direction=N} end
ok,err=planner.plan(state)
assert(ok,"ingress cannot detour around a station wider than the endpoint search window")
verify(state,err)
local around=false
for _,piece in ipairs(err) do
	assert(piece.grid_x~=0 or math.abs(piece.grid_y)>28,"ingress enters the planned station")
	if math.abs(piece.grid_y)>28 then around=true end
end
assert(around,"station ingress did not reach the outside corridor")
cases=cases+1

spec=fixture("west",3)
state=assert(planner.create_state(spec,target(spec,151,-177,N),{output_balance_choice=true}))
state.output_balance_choice=false
state.belt_input_targets={{x=145,y=-145},{x=144,y=-145},{x=143,y=-145}}
local can_place,probes=obstacles.can_place,0
obstacles.can_place=function(...)
	probes=probes+1
	return can_place(...)
end
ok,err=planner.plan(state)
obstacles.can_place=can_place
assert(ok,"offset station input band cannot be routed")
verify(state,err)
assert(probes<2000,"open station ingress falls back to an expansive search")
for _,stat in ipairs(route_stats(state,err)) do assert(stat.turns<=3,"offset input band adds unnecessary bends") end
cases=cases+1

spec=fixture("west",3)
state=assert(planner.create_state(spec,target(spec,65,-42,W),{}))
state.belt_input_targets={{x=87,y=-52},{x=87,y=-51},{x=87,y=-50}}
state.planned={}
for x=60,86 do for y=-85,-42 do
	state.planned[#state.planned+1]={name="transport-belt",grid_x=x,grid_y=y,direction=N}
end end
ok,err=planner.plan(state)
assert(ok,"parallel ingress is trapped by the compact station's inward-facing port band")
verify(state,err)
for _,piece in ipairs(err) do
	assert(piece.grid_x<60 or piece.grid_x>86 or piece.grid_y<-85 or piece.grid_y>-42,"ingress crosses the compact station")
end
cases=cases+1

for _,rotation in ipairs{"west","north","east","south"} do
	for _,dir in ipairs{N,S} do
		local spec=fixture(rotation,13)
		local port_y=dir==N and 17 or 41
		local state=assert(planner.create_state(spec,target(spec,65,port_y,dir),{}))
		state.belt_input_targets={};state.planned={}
		for i=1,spec.count do
			state.belt_input_targets[i]={x=dir==N and 95-i or 81+i,y=port_y}
		end
		local station_top,station_bottom=dir==N and -5 or 42,dir==N and 16 or 70
		for x=6,29 do for y=2,56 do
			state.planned[#state.planned+1]={name="transport-belt",grid_x=x,grid_y=y,direction=W}
		end end
		for x=80,96 do for y=station_top,station_bottom do
			state.planned[#state.planned+1]={name="transport-belt",grid_x=x,grid_y=y,direction=W}
		end end
		local ok,route=planner.plan(state)
		assert(ok,"inward-facing station ports trap the large mining bundle: "..rotation.."/"..dir)
		verify(state,route)
		for _,piece in ipairs(route) do
			local x,y=piece.grid_x,piece.grid_y
			assert(not (x>=6 and x<=29 and y>=2 and y<=56),"outer corridor crosses the mine")
			assert(not (x>=80 and x<=96 and y>=station_top and y<=station_bottom),"outer corridor crosses the station")
		end
		local finish=state.belt_input_targets[1]
		state.grid={get_tile=function(_,x,y)
			if x==finish.x and y==finish.y then return {built_thing="obstacle"} end
		end}
		assert(not planner.plan(state),"outer corridor bypasses a blocked station port")
		cases=cases+2
	end
end

for _,rotation in ipairs{"west","north","east","south"} do
	local spec=fixture(rotation,13)
	for i,belt in ipairs(spec) do belt.x_start=0;belt.y=3+(i-1)*8 end
	local state=assert(planner.create_state(spec,target(spec,63,1,E),{}))
	local targets={}
	for i=1,13 do targets[i]={x=63,y=2-i} end
	state.belt_input_targets=targets
	local blocked_port
	state.grid={get_tile=function(_,x,y)
		if (x>=0 and x<=46 and y>=0 and y<=99) or (x>=64 and x<=95 and y>=-11 and y<=4)
			or (blocked_port and x==blocked_port.x and y==blocked_port.y) then return {built_thing="obstacle"} end
	end}
	assert(not planner.plan(state),"fixed input assignments were silently changed")
	state.interchangeable_belt_inputs=true
	local search,search_index=upvalue(bundle,"path")
	local weighted_searches=0
	debug.setupvalue(bundle,search_index,function(start,finish,dir,allowed,bounds,penalty,budget)
		if penalty then weighted_searches=weighted_searches+1 end
		return search(start,finish,dir,allowed,bounds,penalty,budget)
	end)
	local ok,route=planner.plan(state)
	debug.setupvalue(bundle,search_index,search)
	assert(ok,"split bundle cannot reach interchangeable station inputs: "..rotation)
	assert(weighted_searches==0,"available bounded ingress was delayed by congestion negotiation")
	verify(state,route)
	assert(state.belt_input_targets==targets,"routing replaced the caller's target array")
	for i,p in ipairs(targets) do assert(p.x==63 and p.y==2-i,"routing reordered the caller's inputs") end
	for _,piece in ipairs(route) do
		assert(not state.grid:get_tile(piece.grid_x,piece.grid_y),"backward ingress crosses an obstacle")
	end
	if rotation=="west" then
		local again,repeated=planner.plan(state)
		assert(again and #route==#repeated,"repeated split routing changed length")
		for i,p in ipairs(route) do
			local q=repeated[i]
			assert(p.grid_x==q.grid_x and p.grid_y==q.grid_y and p.direction==q.direction,"input reassignment is nondeterministic")
		end
		cases=cases+1
	end
	blocked_port=targets[5]
	assert(not planner.plan(state),"input reassignment bypasses a blocked station port")
	cases=cases+3
end

spec,data=fixture()
local resource={valid=true}
data.gui={preview_apply={valid=true},preview_cancel={},undo_button={},preview_status={}}
data.preview={player_index=1,surface=spec.surface,revision=1,resources={resource},renderings={}}
local layout_state={player=spec.player,surface=spec.surface,coords=spec.coords,direction_choice="west",belt_choice=spec.belt_choice,
	belt_quality_choice=spec.belt_quality_choice,belts=spec,preview_revision=1,_preview_specs={{name="entity-ghost",inner_name="transport-belt",position={0.5,0.5}}},resources={resource}}
preview.complete(layout_state)
assert(data.preview.ready and not spec.player.cursor_stack.valid_for_read,"preview automatically activates output")
data.choices.belt_planner_choice=false
preview.complete(layout_state)
assert(data.preview.belt_specification and not spec.player.cursor_stack.valid_for_read,"disabled legacy choice hides output or activates cursor")
assert(preview.give_belt_planner(data) and data.input_mode=="output","explicit output activation failed")
local cursor=spec.player.cursor_stack
assert(#cursor.entities==data.preview.belt_specification.count and spec.player.cursor_stack_temporary,"cursor does not show all output lanes")
assert(cursor.entities[1].name==spec.belt_choice and cursor.entities[1].quality=="legendary","cursor loses belt type or quality")
local widened=table.deepcopy(data.preview.belt_specification)
widened.count=3
planner.update_blueprint(spec.player,widened)
assert(#cursor.entities==3 and cursor.entities[3].position.x-cursor.entities[1].position.x==2,"cursor lane count does not refresh")
local picked=planner.take_cursor_target(spec.player,{position={x=10.2,y=10.7},direction=E})
assert(picked.position.x==10.5 and picked.position.y==9.5 and picked.direction==E,"blueprint anchor does not match its footprint")
assert(not cursor.entities and planner.has_pending_cursor(),"target click is allowed to build ghosts")
planner.restore_cursors()
assert(not cursor.entities,"cursor restored before construction ended")
game.tick=game.tick+1
planner.restore_cursors()
assert(#cursor.entities==3 and not planner.has_pending_cursor(),"blueprint cursor was not restored")
picked=planner.take_cursor_target(spec.player,{position={x=-10.2,y=-10.7},direction=E,flip_vertical=true})
assert(picked.direction==S and picked.position.x==-9.5 and picked.position.y==-10.5,"flipped cursor target points the wrong way")
planner.update_blueprint(spec.player,data.preview.belt_specification)
assert(#cursor.entities==data.preview.belt_specification.count and not planner.has_pending_cursor(),"cursor refresh restores stale lanes")
cases=cases+1

local chosen=target(spec,-12,5,W)
data.preview.belt_target=chosen
input_mode.idle(data,spec.player)
assert(not cursor.valid_for_read and not data.input_mode and data.preview.belt_target==chosen,"leaving output loses target or activates selection")
preview.complete(layout_state)
assert(not cursor.valid_for_read,"recompute reactivates an exited tool")
assert(preview.give_belt_planner(data) and cursor.entities[1].direction==S,"reentering output loses rotation")
spec.player.clear_cursor()
input_mode.reconcile(data,spec.player)
preview.complete(layout_state)
assert(not cursor.valid_for_read and not data.input_mode,"Q followed by recompute restores output")
assert(input_mode.select(data,spec.player) and cursor.name=="resource-outpost-planner","explicit selection activation failed")
preview.complete(layout_state)
assert(cursor.name=="resource-outpost-planner" and data.input_mode=="select","recompute replaces selection cursor")
input_mode.idle(data,spec.player)
cursor.set_stack("iron-plate")
input_mode.idle(data,spec.player)
assert(cursor.valid_for_read and cursor.name=="iron-plate","idle clears a player's normal item")
spec.player.clear_cursor()
assert(preview.give_belt_planner(data),"cannot return to output")
cases=cases+1

assert(preview.set_belt_target(data,target(spec,-12,5,W)),"cannot set preview target")
assert(not data.preview.ready and not data.gui.preview_apply.enabled,"target change leaves stale Apply enabled")
local revision=data.preview.revision
preview.complete(layout_state)
assert(data.preview.revision==revision and not data.preview.ready,"stale route replaced new preview")
data.choices.belt_planner_choice=false
planner.take_cursor_target(spec.player,{position={x=10,y=10},direction=N})
preview.request(data)
assert(not data.preview.belt_target and not spec.player.cursor_stack.valid_for_read,"disabling planner keeps target tool")
assert(not planner.has_pending_cursor(),"disabled planner can restore its old cursor")
cases=cases+1
data.choices.belt_planner_choice=true
data.preview.belt_specification=spec
data.preview.belt_target=target(spec,-12,5,W)
data.preview.ready=true; data.preview.refresh_at=nil
data.last_state={_collected_ghosts={}}
local saved_undo=data.last_state
local calls={}
algorithm={clear_selection=function() end,on_player_selected_area=function(event)
	calls[#calls+1]=event
	local next_state=table.deepcopy(layout_state)
	next_state.player=spec.player; next_state.surface=spec.surface
	next_state.preview_revision=event.preview_revision
	next_state.belt_target=event.belt_target
	return next_state
end}
assert(preview.apply(data),"Apply does not start validation")
local preflight=storage.tasks[#storage.tasks]
assert(calls[#calls].preview_only and data.last_state==saved_undo,"Apply consumes undo before validating")
preflight.preview_error={"mpp.msg_obstacle_route_failed"}
preview.complete(preflight)
assert(not data.preview.ready and not data.preview.applying and #calls==1,"failed validation commits a route")
preflight.preview_error=nil
preflight._apply_after_preview=nil
preview.complete(preflight)
assert(preview.apply(data),"valid preview does not start another validation")
preflight=storage.tasks[#storage.tasks]
preview.complete(preflight)
assert(not calls[#calls].preview_only and calls[#calls].belt_target,"Apply loses the selected target")
assert(storage.tasks[#storage.tasks]._from_preview,"validated route does not commit")
storage.tasks={}
data.preview.applying=false
preview.cancel(data)
assert(not data.preview and data.last_state==saved_undo,"Cancel changes the previous undo record")
cases=cases+1

spec,data=fixture("west",1,surface({water}))
state=assert(planner.create_state(spec,target(spec,-12,5,W),{}))
state.preview_only=true; state._preview_specs={}
ok,err=planner.plan(state)
assert(ok)
for _,piece in ipairs(err) do builder.create_entity_builder(state)(piece) end
planner.place_landfill(state,err)
assert(#spec.surface.created==0 and spec.surface.deconstructions==0,"preview created construction orders")
local tiles=0
for _,piece in ipairs(state._preview_specs) do if piece.name=="tile-ghost" then tiles=tiles+1 end end
assert(tiles==1,"external water connection omits landfill")
state.preview_only=false; state._collected_ghosts={}; state._belt_landfill=nil
assert(planner.layout(state))
assert(#state._collected_ghosts==#spec.surface.created and #state._collected_ghosts>#err,"connection ghosts missing from undo")
cases=cases+1
for _,base in ipairs{N,E,S,W} do
	for _,rotation in ipairs{N,E,S,W} do
		for _,horizontal in ipairs{false,true} do for _,vertical in ipairs{false,true} do
			local cursor_spec,cursor_data=fixture("west",3)
			planner.give_blueprint({player=cursor_spec.player},cursor_spec)
			for i=1,base/E do planner.rotate_cursor(cursor_spec.player,{cursor_direction=(i-1)*E},false) end
			cursor_spec.count=4
			planner.update_blueprint(cursor_spec.player,cursor_spec)
			assert(cursor_spec.player.cursor_stack.entities[1].direction==base,"lane regeneration loses unplaced R rotation")
			local direction=base
			if horizontal then direction=(-direction)%16 end
			if vertical then direction=(S-direction)%16 end
			direction=(direction+rotation)%16
			local click={position={x=10.2,y=-10.7},direction=rotation,flip_horizontal=horizontal,flip_vertical=vertical}
			local first=planner.take_cursor_target(cursor_spec.player,click)
			assert(first.direction==direction,"rotated or flipped intrinsic blueprint points the wrong way")
			game.tick=game.tick+1
			planner.restore_cursors()
			assert(cursor_spec.player.cursor_stack.entities[1].direction==direction,"click resets the held blueprint direction")
			local repeated=planner.take_cursor_target(cursor_spec.player,{position=click.position,direction=N})
			assert(repeated.direction==first.direction and repeated.position.x==first.position.x
				and repeated.position.y==first.position.y,"consecutive clicks change orientation or anchor")
			cursor_spec.count=2; cursor_spec.belt_choice="fast-transport-belt"; cursor_spec.belt_quality_choice="rare"
			planner.update_blueprint(cursor_spec.player,cursor_spec)
			local entities=cursor_spec.player.cursor_stack.entities
			assert(#entities==2 and entities[1].direction==direction and entities[1].quality=="rare"
				and entities[1].name=="fast-transport-belt" and not planner.has_pending_cursor(),"pending cursor refresh loses direction, type or quality")
			planner.rotate_cursor(cursor_spec.player,{cursor_direction=N},true)
			cursor_spec.count=3
			planner.update_blueprint(cursor_spec.player,cursor_spec)
			assert(cursor_spec.player.cursor_stack.entities[1].direction==(direction-E)%16,"Shift+R is lost on regeneration")
			planner.release_cursor(cursor_data,cursor_spec.player)
			assert(not cursor_spec.player.cursor_stack.valid_for_read and cursor_data.belt_cursor_direction==(direction-E)%16,
				"released cursor remains active or loses its saved orientation")
			cases=cases+1
		end end
	end
end
for _,base in ipairs{N,E,S,W} do for _,horizontal in ipairs{false,true} do
	local cursor_spec,cursor_data=fixture("west",3)
	planner.give_blueprint({player=cursor_spec.player},cursor_spec)
	for i=1,base/E do planner.rotate_cursor(cursor_spec.player,{cursor_direction=(i-1)*E},false) end
	planner.flip_cursor(cursor_spec.player,horizontal)
	cursor_spec.count=2
	planner.update_blueprint(cursor_spec.player,cursor_spec)
	local expected=((horizontal and 0 or S)-base)%16
	local picked=planner.take_cursor_target(cursor_spec.player,{position={x=10,y=10},direction=N})
	assert(picked.direction==expected,"regeneration loses unplaced blueprint flip")
	planner.release_cursor(cursor_data)
	cases=cases+1
end end

prototype("big-mining-drill","mining-drill",5)

local function mining_detour(rotation,x,y,dir,blocks)
	local spec=fixture(rotation,3)
	for i,belt in ipairs(spec) do belt.x_start=-5; belt.y=2+(i-1)*11 end
	local state=assert(planner.create_state(spec,target(spec,x,y,dir),{}))
	state.planned={}
	for _,row in ipairs{-1,5,10,16,21} do for x=-3,22,5 do
		if x~=-3 or (row~=-1 and row~=21) then
			state.planned[#state.planned+1]={name="big-mining-drill",grid_x=x,grid_y=row}
		end
	end end
	for _,row in ipairs{2,13,24} do for x=-5,24 do
		state.planned[#state.planned+1]={name="transport-belt",grid_x=x,grid_y=row,direction=W}
	end end
	state.grid={get_tile=function(_,x,y)
		for _,box in ipairs(blocks or {}) do
			if x>=box[1] and x<=box[2] and y>=box[3] and y<=box[4] then return {built_thing="obstacle"} end
		end
	end}
	return state
end

for _,rotation in ipairs{"west","north","east","south"} do
	-- Reproduces the live game's three-row mine and west-facing world outlet at (-34.5,-0.5).
	for _,exit in ipairs{{8,55,S},{8,-30,N}} do
		local state=mining_detour(rotation,exit[1],exit[2],exit[3])
		local ok,route=planner.plan(state)
		assert(ok,"reachable perpendicular bundle rejected")
		verify(state,route)
		for _,stat in ipairs(route_stats(state,route)) do assert(stat.turns==3,"perpendicular bundle has unnecessary bends") end
		cases=cases+1
	end
	local state=mining_detour(rotation,8,55,S,{{4,5,52,56},{-10,-8,50,50},{-3,1,34,34}})
	local ok,route=planner.plan(state)
	assert(ok,"earlier lanes are not replanned around blocked gathering corridors")
	verify(state,route)
	for _,piece in ipairs(route) do
		assert(not state.grid:get_tile(piece.grid_x,piece.grid_y),"replanned lane enters an obstacle")
	end
	local again,repeat_route=planner.plan(state)
	assert(again and #repeat_route==#route,"replanning changes between identical previews")
	for i,piece in ipairs(route) do
		assert(piece.grid_x==repeat_route[i].grid_x and piece.grid_y==repeat_route[i].grid_y
			and piece.direction==repeat_route[i].direction,"replanning is not deterministic")
	end
	cases=cases+1
	for _,blocked in ipairs{{4,5},{-11,5}} do
		local spec=fixture(rotation,1)
		local p=target(spec,blocked[1],blocked[2],W).position
		local cliff={valid=true,type="cliff",prototype={collision_mask={layers={}}},
			bounding_box={left_top={x=p.x-0.45,y=p.y-0.45},right_bottom={x=p.x+0.45,y=p.y+0.45}}}
		spec.surface.find_entities_filtered=function() return {cliff} end
		local state=assert(planner.create_state(spec,target(spec,-12,5,W),{avoid_cliffs_choice=true}))
		local ok,route=planner.plan(state)
		assert(ok,"a valid corner at the source or outlet is rejected")
		verify(state,route)
		for _,piece in ipairs(route) do
			local p=target(spec,piece.grid_x,piece.grid_y,W).position
			assert(obstacles.can_place(state,piece.name,p,piece.direction),"corner enters the selected cliff")
		end
		cases=cases+1
	end
	for _,dir in ipairs{N,E,S,W} do
		local spec=fixture(rotation,1)
		local state=assert(planner.create_state(spec,target(spec,5,5,dir),{}))
		local ok,route=planner.plan(state)
		assert(ok==(dir~=E),"outlet on the source handles a reversal incorrectly")
		if ok then assert(#route==1,"source outlet creates a loop");verify(state,route) end
		cases=cases+1
	end
	local spec=fixture(rotation,1)
	local state=assert(planner.create_state(spec,target(spec,-12,5,W),{}))
	state.grid={get_tile=function(_,x,y)
		if x==0 and y>=-30 and y<=30 then return {built_thing="obstacle"} end
	end}
	local ok,route=planner.plan(state)
	assert(ok,"detour outside the initial search rectangle is rejected")
	verify(state,route)
	for _,piece in ipairs(route) do assert(not state.grid:get_tile(piece.grid_x,piece.grid_y),"long detour enters obstacle") end
	cases=cases+1
end

do
	local spec=fixture("west",1)
	local destination=target(spec,-12,5,W)
	local water={name="water",position={x=math.floor(destination.position.x),y=math.floor(destination.position.y)},
		prototype={collision_mask={layers={water_tile=true}},default_cover_tile={name="landfill"}}}
	local scanned={}
	spec.surface.find_tiles_filtered=function(filter) scanned[#scanned+1]=filter.area;return {water} end
	local state=assert(planner.create_state(spec,destination,{avoid_water_choice=true}))
	assert(not planner.plan(state),"expanded search ignores a selected water obstacle")
	assert(#scanned==1,"a known blocked destination triggers redundant obstacle scans")
	cases=cases+1
end

do
	local spec=fixture("west",1)
	local water={}
	for _,y in ipairs{-31,31} do
		local p=target(spec,0,y,W).position
		water[#water+1]={name="water",position={x=math.floor(p.x),y=math.floor(p.y)},
			prototype={collision_mask={layers={water_tile=true}},default_cover_tile={name="landfill"}}}
	end
	local scanned={}
	spec.surface.find_tiles_filtered=function(filter)
		local area=filter.area;scanned[#scanned+1]=area
		local found={}
		for _,tile in ipairs(water) do
			local p=tile.position
			if p.x>=area[1][1] and p.x<area[2][1] and p.y>=area[1][2] and p.y<area[2][2] then found[#found+1]=tile end
		end
		return found
	end
	local state=assert(planner.create_state(spec,target(spec,-12,5,W),{avoid_water_choice=true}))
	local grid_calls={}
	state.grid={get_tile=function(_,x,y)
		local k=x..","..y
		assert(not grid_calls[k],"immutable grid occupancy is queried again during a retry")
		grid_calls[k]=true
		if x==0 and y>=-30 and y<=30 then return {built_thing="obstacle"} end
	end}
	local ok,route=planner.plan(state)
	assert(ok,"expanded search cannot route around the wall and newly scanned water")
	verify(state,route)
	assert(#scanned==2 and scanned[2][1][1]<scanned[1][1][1],"expanded search reused the smaller obstacle index")
	for _,piece in ipairs(route) do
		assert(piece.grid_x~=0 or math.abs(piece.grid_y)>31,"retry cache hides an obstacle outside the initial search area")
	end
	cases=cases+1
end

for _,rotation in ipairs{"west","north","east","south"} do for _,y in ipairs{-30,79} do
	local spec=fixture(rotation,3)
	for i,belt in ipairs(spec) do belt.x_start=-5; belt.y=2+(i-1)*11 end
	local state=assert(planner.create_state(spec,target(spec,35,y,W),{}))
	state.planned={}
	for _,row in ipairs{-1,5,10,16,21} do for _,x in ipairs{2,7,12,17,22} do
		state.planned[#state.planned+1]={name="big-mining-drill",grid_x=x,grid_y=row,direction=N}
	end end
	local ok,route=planner.plan(state)
	assert(ok,"reachable output behind the mine is rejected")
	verify(state,route)
	for _,stat in ipairs(route_stats(state,route)) do assert(stat.turns==4,"nested gathering corridors have extra bends") end
	cases=cases+1
end end

do
	local spec,data=fixture("west",3)
	local destination=target(spec,-12,12,W)
	local p=destination.position
	local blocked={valid=true,type="cliff",prototype={collision_mask={layers={}}},
		bounding_box={left_top={x=p.x-0.45,y=p.y-0.45},right_bottom={x=p.x+0.45,y=p.y+0.45}}}
	spec.surface.find_entities_filtered=function() return {blocked} end
	local state=assert(planner.create_state(spec,destination,{avoid_cliffs_choice=true}))
	state.preview_only=true
	local ok,err,diagnostic=planner.plan(state)
	assert(not ok and diagnostic and #diagnostic.issues>0,"blocked route lacks spatial diagnostics")
	local red,green=0,0
	for _,piece in ipairs(diagnostic.routes) do
		if piece.preview_blocked then red=red+1 else green=green+1 end
	end
	assert(red>0 and green>0,"failed preview loses either tentative or completed connections")
	local rendered={}
	local function object(kind)
		local o={valid=true,type=kind};o.destroy=function() o.valid=false end
		rendered[#rendered+1]=o;return o
	end
	rendering.draw_circle=function() return object("circle") end
	rendering.draw_text=function() return object("text") end
	rendering.draw_rectangle=function() return object("rectangle") end
	data.gui={preview_apply={valid=true},preview_cancel={},undo_button={},preview_status={}}
	data.preview={player_index=1,surface=spec.surface,revision=1,resources={},renderings={}}
	state.preview_revision=1;state.preview_error=err;state.resources={}
	state._preview_specs={};state._preview_issues=diagnostic.issues;state.builder_belt_connections=diagnostic.routes
	state.belts=spec;state.miner={rotation_bump=0};state.miner_choice="electric-mining-drill"
	state.best_attempt={miners={{origin_x=6,origin_y=8,line=1}}}
	preview.complete(state)
	assert(not data.preview.ready and not data.gui.preview_apply.enabled,"diagnostic route can be applied")
	assert(#data.preview.specs>#diagnostic.routes and #data.preview.renderings>0,"failed preview clears the mining layout or error markers")
	for _,issue in ipairs(data.preview.issues) do
		local matched=false
		for _,s in ipairs(data.preview.specs) do
			if s.preview_blocked and s.position.x==issue.position.x and s.position.y==issue.position.y then matched=true end
		end
		assert(matched,"diagnostic marker does not align with the red belt artwork")
	end
	assert(data.preview.belt_specification and not spec.player.cursor_stack.valid_for_read,"failed preview automatically activates output")
	assert(preview.give_belt_planner(data),"failed preview loses target adjustment tool")
	assert(not preview.apply(data),"failed preview starts construction")
	assert(#spec.surface.created==0 and spec.surface.deconstructions==0,"diagnostic preview modifies the world")
	local old=data.preview.renderings
	preview.invalidate(data,{"mpp.msg_obstacle_route_failed"})
	for _,o in ipairs(old) do assert(not o.valid,"failure leaves stale error markers") end
	assert(#data.preview.renderings>0,"validation failure hides the preview")
	preview.cancel(data)
	for _,o in ipairs(rendered) do assert(not o.valid,"cancel leaks diagnostic rendering") end
	cases=cases+1
	local spec,data=fixture()
	data.gui={preview_apply={valid=true},preview_cancel={},undo_button={},preview_status={}}
	data.preview={player_index=1,surface=spec.surface,revision=1,renderings={}}
	preview.complete{player=spec.player,surface=spec.surface,preview_only=true,preview_revision=1,
		preview_error={"mpp.msg_err_unable_to_create_a_layout"},resources={{valid=true,position={x=2.5,y=3.5}}},_preview_specs={}}
	assert(#data.preview.issues==1 and #data.preview.renderings==2,"no-miner failure does not highlight the selected resource")
	preview.cancel(data)
	cases=cases+1
end

do
	local spec,data=fixture()
	local saved_algorithm=algorithm
	data.gui={}
	local cleanups=0
	algorithm={
		cleanup_last_state=function(d) cleanups=cleanups+1; d.last_state=nil end,
		clear_selection=function(d) d.selection_collection={} end,
		select_resource_layout=function() end,
	}
	local function resource(x)
		return {valid=true,type="resource",name="iron-ore",surface=spec.surface,position={x=x,y=0.5}}
	end
	local function marker()
		local object={valid=true}
		object.destroy=function() object.valid=false end
		return object
	end
	local first,second=resource(0.5),resource(1.5)
	local old_marker,pending_marker=marker(),marker()
	data.preview={player_index=1,surface=spec.surface,revision=4,resources={first},renderings={old_marker}}
	data.last_state={_collected_ghosts={}}
	local previous=data.preview
	local other_task={preview_only=true,player={index=2}}
	storage.tasks={{preview_only=true,player=spec.player,_render_objects={pending_marker}},other_task}
	local event={player_index=1,surface=spec.surface,entities={}}
	assert(not preview.select(event,false) and data.preview==previous and cleanups==0,"empty selection clears the previous plan")
	previous.applying=true;event.entities={second}
	assert(not preview.select(event,false) and cleanups==0,"selection interrupts Apply")
	previous.applying=false
	assert(input_mode.select(data,spec.player))
	assert(preview.select(event,false) and cleanups==1 and not data.last_state,"reselection keeps the previous unfinished plan")
	assert(#data.preview.resources==1 and data.preview.resources[1]==second,"normal selection retains old resources")
	assert(not old_marker.valid and not pending_marker.valid,"reselection leaks old preview or pending task renderings")
	assert(#storage.tasks==1 and storage.tasks[1]==other_task,"reselection cancels another player's task")
	assert(data.input_mode=="select" and spec.player.cursor_stack.name=="resource-outpost-planner","reselection exits the selection tool")
	event.entities={first,second}
	assert(preview.select(event,true) and #data.preview.resources==2,"Shift selection fails to append or deduplicate resources")
	preview.cancel(data)
	storage.tasks={}
	algorithm=saved_algorithm
	cases=cases+3
end
do
	local station=require("mpp.train_station")
	local original_geometry=station.geometry
	local layout={locomotives=2,wagons=4,outputs=8,specs={
		{name="straight-rail",x=0,y=0,direction=E,station_rail=true},
		{name="train-stop",x=0,y=-2,direction=W,station_control=true},
		{name="locomotive",x=3,y=0,direction=W,station_stock=true},
	}}
	station.geometry=function() return layout end
	local spec,data=fixture("west",3)
	spec.station_choices={}
	local stack=spec.player.cursor_stack
	local set_entities=stack.set_blueprint_entities
	stack.set_blueprint_entities=function(entities)
		set_entities(entities)
		if #entities==0 then
			stack.blueprint_snap_to_grid=nil;stack.blueprint_absolute_snapping=false
			stack.blueprint_position_relative_to_grid=nil
		end
	end
	local function snapped()
		local grid,offset=stack.blueprint_snap_to_grid,stack.blueprint_position_relative_to_grid
		return grid and grid.x==2 and grid.y==2 and stack.blueprint_absolute_snapping
			and offset and offset.x==0 and offset.y==0
	end
	assert(planner.give_blueprint({player=spec.player},spec) and snapped(),"station cursor starts without rail grid alignment")
	for _,base in ipairs{N,E,S,W} do
		data.belt_cursor_direction=base
		planner.update_blueprint(spec.player,spec)
		for _,action in ipairs{"click","rotate","reverse","horizontal","vertical"} do
			if action=="click" then planner.take_cursor_target(spec.player,{position={x=-10.2,y=10.7},direction=N})
			elseif action=="rotate" then planner.rotate_cursor(spec.player,{cursor_direction=N},false)
			elseif action=="reverse" then planner.rotate_cursor(spec.player,{cursor_direction=N},true)
			else planner.flip_cursor(spec.player,action=="horizontal") end
			assert(not snapped() and not stack.entities,"test did not reproduce native clearing of snap settings")
			game.tick=game.tick+1;planner.restore_cursors()
			assert(snapped() and #stack.entities==#layout.specs,"station restoration loses its absolute rail grid")
			local expected=station.cursor_entities(layout,data.belt_cursor_direction,data.belt_cursor_mirror)
			for i,entity in ipairs(stack.entities) do
				assert(entity.position.x==expected[i].position.x and entity.position.y==expected[i].position.y,"cursor restoration changes the station origin")
			end
			cases=cases+1
		end
	end
	planner.take_cursor_target(spec.player,{position={x=10,y=10},direction=N})
	data.belt_cursor_restore.station=nil
	game.tick=game.tick+1;planner.restore_cursors()
	assert(snapped(),"old pending station cursor loses snapping after reload")
	stack.blueprint_snap_to_grid=nil;stack.blueprint_absolute_snapping=false;stack.blueprint_position_relative_to_grid=nil
	planner.update_blueprint(spec.player,spec)
	assert(snapped(),"unchanged layout shortcut retains an already offset cursor")
	planner.release_cursor(data,spec.player)
	station.geometry=original_geometry
	cases=cases+2
end
print("Belt planner OK: "..cases.." route and preview cases")
