-- Run both grid callbacks on a one-tile-wide ore strip. Each resource must
-- contribute to the outer coverage of exactly 5 x 5 possible drill positions.
defines={direction={north=0,east=4,south=8,west=12}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},quality={}}
function table_size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
function table.deepcopy(value)
	if type(value)~="table" then return value end
	local result={}
	for k,v in pairs(value) do result[k]=table.deepcopy(v) end
	return result
end
require("mpp.global_extends")
local simple=require("layouts.simple")
local layout=setmetatable({prepare_layout_attempts=function() return "done" end},{__index=simple})

local function run_batch(step,state)
	local result
	repeat result=step(layout,state) until result~=true
	return result
end

-- A strip of n resources creates n+4 horizontal convolution entries. Exercise
-- the one-remaining-item boundary independently on the first and second pass.
for _,n in ipairs{0,1,1639,1640,1641,3279,1636,3275} do
	local state={resources={},coords={x1=0,y1=0,gx=0,gy=0,w=n,h=1},direction_choice="west",
		performance_scaling=1,miner={size=3,area=5,area_sq=25,extent_negative=-1,extent_positive=3}}
	for i=1,n do state.resources[i]={valid=true,name="ore",amount=i,position={x=i-.5,y=.5}} end
	layout:initialize_grid(state)
	assert(run_batch(layout.process_grid,state)=="process_grid_convolution")
	assert(#state.resource_tiles==n,"resource skipped in strip of "..n)
	assert(run_batch(layout.process_grid_convolution,state)=="done")
	local coverage=0
	for _,row in pairs(state.grid) do
		for _,tile in pairs(row) do coverage=coverage+tile.neighbors_outer end
	end
	assert(coverage==25*n,"incomplete drill coverage in strip of "..n)
end
print("Grid batching: resource and convolution boundaries passed")
