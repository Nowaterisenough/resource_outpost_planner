-- Run from the repository root with Lua 5.2.
defines={direction={north=0,east=4,south=8,west=12},inventory={beacon_modules=2}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},item={},quality={}}
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
require("mpp.global_extends")
local util=require("mpp.mpp_util")
local rows=require("mpp.beacon_rows")
local obstacles=require("mpp.obstacles")
local cases=0
local function check(value,label) assert(value,label);cases=cases+1 end
local function fixture(direction,size,area,gap)
	local function proto(name,w,h)
		return {name=name,tile_width=w,tile_height=h,
			collision_box={left_top={x=-w/2+0.1,y=-h/2+0.1},right_bottom={x=w/2-0.1,y=h/2-0.1}},
			has_flag=function() return false end,get_supply_area_distance=function() return 3 end}
	end
	prototypes={entity={beacon=proto("beacon",3,3),drill=proto("drill",size,size)}}
	local state={beacon_choice="beacon",beacon_quality_choice="normal",beacon_pipe_gap=gap or 0,
		miner_choice="drill",direction_choice=direction,coords={gx=-20,gy=-30,tw=24,th=24},
		miner={size=size,extent_negative=-(area-size)/2,extent_positive=(area+size)/2-1},
		best_attempt={sy=1,miners={}},resource_tiles={},grid={build_thing_simple=function() end}}
	local step=size+3+2*(gap or 0)
	for y=1,24,size+1 do for x=1,24,step do
		state.best_attempt.miners[#state.best_attempt.miners+1]={x=x,y=y,origin_x=x+(size-1)/2,origin_y=y+(size-1)/2}
	end end
	for y=1,24 do for x=1,24 do
		local p=util.revert_world(-20,-30,direction,x,y,24,24)
		state.resource_tiles[#state.resource_tiles+1]={x=x,y=y,gx=p[1],gy=p[2]}
	end end
	return state
end

for _,direction in ipairs{"north","east","south","west"} do
	for _,size in ipairs{3,5} do
		local state=fixture(direction,size,size==5 and 13 or 5)
		rows.reserve(state)
		local strips,footprints={},{}
		for _,spec in ipairs(state.builder_beacons) do
			local strip=strips[spec.row_x] or {};strips[spec.row_x]=strip;strip[#strip+1]=spec.row_y
			local _,box=rows.position(state,spec)
			for _,other in ipairs(footprints) do
				check(not (box.left_top.x<other.right_bottom.x and other.left_top.x<box.right_bottom.x
					and box.left_top.y<other.right_bottom.y and other.left_top.y<box.right_bottom.y),"rotated rows do not overlap")
			end
			footprints[#footprints+1]=box
		end
		for _,strip in pairs(strips) do for i=2,#strip do
			check(strip[i]-strip[i-1]==3,"towers form an uninterrupted full row")
		end end
		for _,miner in ipairs(state.best_attempt.miners) do
			check(strips[miner.x-3] and strips[miner.x+size],"every drill column has rows on both sides")
			local _,box=rows.position(state,{name="drill",grid_x=miner.origin_x,grid_y=miner.origin_y})
			for _,tower in ipairs(footprints) do
				check(not (box.left_top.x<tower.right_bottom.x and tower.left_top.x<box.right_bottom.x
					and box.left_top.y<tower.right_bottom.y and tower.left_top.y<box.right_bottom.y),"drills do not overlap the reserved rows")
			end
		end
		local selected=#state.best_attempt.miners
		rows.finish(state)
		check(#state.best_attempt.miners==selected,"row placement does not prune drills after routing")
		check(state.beacon_summary[2]==selected,"both side rows cover every drill")
		check(state.beacon_summary[4]>=4,"full rows keep multiple towers per drill")
		if size==5 then check(not state._preview_issues,"big drill rows preserve the entire ore patch")
		else check(state._preview_issues and #state._preview_issues>0,"unreachable ore under ordinary drill rows is marked") end
	end
end

local state=fixture("west",5,13,1)
local specs=rows.specifications(state,state.best_attempt)
for _,miner in ipairs(state.best_attempt.miners) do
	local left,right=false,false
	for _,spec in ipairs(specs) do
		left=left or spec.row_x==miner.x-4;right=right or spec.row_x==miner.x+6
	end
	check(left and right,"pipe channels stay between each drill and its two beacon rows")
end

-- A selected obstacle keeps its slot in the row as a red diagnostic instead of scattering a replacement.
state=fixture("west",5,13)
state.avoid_cliffs_choice=true
local original_get=obstacles.get
local original_blocked=obstacles.blocked_box
local blocked_position=rows.position(state,rows.specifications(state,state.best_attempt)[2])
obstacles.get=function() return {} end
obstacles.blocked_box=function(_,box)
	return blocked_position.x>box.left_top.x and blocked_position.x<box.right_bottom.x
		and blocked_position.y>box.left_top.y and blocked_position.y<box.right_bottom.y
end
rows.reserve(state)
check(state.preview_error and state.preview_error[1]=="mpp.beacon_row_blocked","blocked row is actionable")
check(state.builder_beacons[2].preview_blocked,"blocked tower is retained for red blueprint artwork")
check(#state.builder_beacons==32,"blocked slot does not change full-row geometry")
rows.finish(state)
check(state.beacon_summary[1]==31,"blocked towers do not count toward actual effects")
check(state._preview_issues and #state._preview_issues==1,"diagnostic identifies the obstructed footprint")
obstacles.get=original_get;obstacles.blocked_box=original_blocked

local baseline=rows.specifications(state,state.best_attempt)
for _,density in ipairs{0,1,2,4} do
	state.beacon_density_choice=density
	local other=rows.specifications(state,state.best_attempt)
	check(#other==#baseline,"legacy density settings migrate to complete rows")
	for i,spec in ipairs(other) do check(spec.row_x==baseline[i].row_x and spec.row_y==baseline[i].row_y,"legacy density cannot punch holes in a row") end
end
print("Beacon rows: "..cases.." assertions passed")
