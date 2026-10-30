-- Run from the repository root with Lua 5.2.
defines={direction={north=0,east=4,south=8,west=12}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},quality={}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
require("mpp.global_extends")
local rows=require("mpp.beacon_rows")
local function prototype(name,electric)
	return {name=name,tile_width=1,tile_height=1,electric_energy_source_prototype=electric and {},
		collision_box={left_top={x=-0.4,y=-0.4},right_bottom={x=0.4,y=0.4}},has_flag=function() return false end}
end
prototypes={entity={pole=prototype("pole"),drill=prototype("drill",true),beacon=prototype("beacon",true)}}
local cases=0
local function fixture(rotation,positions,drills,beacons,radius,reach)
	local state={direction_choice=rotation,coords={gx=-20,gy=-30,tw=60,th=60},
		pole={radius=radius or 1,wire=reach or 4.1},builder_power_poles={},builder_miners={},builder_beacons={}}
	local occupied={}
	state.grid={build_thing_simple=function(_,x,y,thing) occupied[x..","..y]=thing end}
	for _,p in ipairs(positions) do
		state.builder_power_poles[#state.builder_power_poles+1]={name="pole",grid_x=p[1],grid_y=p[2]}
		occupied[p[1]..","..p[2]]="pole"
	end
	for _,pair in ipairs{{drills,state.builder_miners,"drill"},{beacons,state.builder_beacons,"beacon"}} do
		for _,p in ipairs(pair[1]) do pair[2][#pair[2]+1]={name=pair[3],grid_x=p[1],grid_y=p[2]} end
	end
	return state,occupied
end
local function verify(state)
	local positions={}
	for _,spec in ipairs(state.builder_power_poles) do positions[#positions+1]=rows.position(state,spec) end
	for _,list in ipairs{state.builder_miners,state.builder_beacons} do for _,spec in ipairs(list) do
		local _,box=rows.position(state,spec)
		local supplied=false
		for _,p in ipairs(positions) do
			local r=state.pole.radius
			if p.x+r>box.left_top.x and p.x-r<box.right_bottom.x
				and p.y+r>box.left_top.y and p.y-r<box.right_bottom.y then supplied=true end
		end
		assert(supplied,"pruning disconnected a consumer")
	end end
	local queue,seen={1},{[1]=true}
	for i=1,#positions do
		local p=positions[queue[i]];if not p then break end
		for j,q in ipairs(positions) do
			if not seen[j] and (p.x-q.x)^2+(p.y-q.y)^2<=state.pole.wire^2 then
				seen[j]=true;queue[#queue+1]=j
			end
		end
	end
	assert(#queue==#positions,"pruning broke the wire network")
end
for _,rotation in ipairs{"north","east","south","west"} do
	local state,occupied=fixture(rotation,{{0,0},{4,0},{8,0},{12,0},{16,0},{20,0},{24,0},{50,0},{54,0}},{{0,0}},{{16,0}})
	rows.prune_poles(state)
	assert(#state.builder_power_poles==5,"empty tails and isolated empty components remain")
	for _,x in ipairs{0,4,8,12,16} do assert(occupied[x..",0"],"a necessary wire bridge was removed") end
	for _,x in ipairs{20,24,50,54} do assert(not occupied[x..",0"],"removed poles still obstruct belt routing") end
	verify(state);cases=cases+1
	state=fixture(rotation,{{0,0},{4,0},{0,4},{4,4}},{{0,0}},{{4,4}})
	rows.prune_poles(state)
	assert(#state.builder_power_poles==3,"an empty cycle keeps a redundant bridge")
	verify(state);cases=cases+1
	state=fixture(rotation,{{0,0},{4,0},{8,0}},{{2,0}},{{6,0}},2.5,4.1)
	rows.prune_poles(state)
	assert(#state.builder_power_poles==1,"redundant coverage poles remain")
	verify(state);cases=cases+1
	state=fixture(rotation,{{0,0},{4,0}},{{0,0}},{{7,0}},3.5,4.1)
	rows.prune_poles(state)
	assert(#state.builder_power_poles==2,"edge overlap supply was lost")
	verify(state);cases=cases+1
	state=fixture(rotation,{{0,0},{4,0}},{{0,0}},{{7,0}},2.5,4.1)
	state.pole.supply_area_distance=3.5
	rows.prune_poles(state)
	assert(#state.builder_power_poles==2,"exact supply distance was replaced by rounded tile coverage")
	verify({builder_power_poles=state.builder_power_poles,builder_miners=state.builder_miners,
		builder_beacons=state.builder_beacons,direction_choice=state.direction_choice,coords=state.coords,pole={radius=3.5,wire=4.1}})
	cases=cases+1
	state=fixture(rotation,{{0,0},{4,0},{8,0}},{{0,0}},{{8,0}},1,8.1)
	rows.prune_poles(state)
	assert(#state.builder_power_poles==2,"longer quality wire reach was ignored")
	verify(state);cases=cases+1
end
-- Repeated articulation probes and single-supplier locks on a larger mesh.
for _,rotation in ipairs{"north","east","south","west"} do
 local poles,drills,beacons={},{},{}
 for x=0,10 do for y=0,8 do
  poles[#poles+1]={x*4,y*4}
  if (x*13+y*7)%11==0 then drills[#drills+1]={x*4,y*4} end
  if (x*7+y*13)%19==0 then beacons[#beacons+1]={x*4,y*4} end
 end end
 local state=fixture(rotation,poles,drills,beacons,3.5,5.7)
 rows.prune_poles(state);verify(state)
 local count=#state.builder_power_poles
 rows.prune_poles(state);verify(state)
 assert(#state.builder_power_poles==count,"pruning leaves removable poles after scratch reuse")
 cases=cases+1
end
print("Beacon poles: "..cases.." coverage/connectivity cases passed")
