-- Verify the generated entities, not an abstract network separate from the layout.
defines={direction={north=0,east=4,south=8,west=12}}
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},quality={},item={}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
local function prototype(name,kind,w,h)
	prototypes.entity[name]={name=name,type=kind,tile_width=w,tile_height=h,belt_speed=0.03125,
		collision_box={left_top={x=-w/2+0.1,y=-h/2+0.1},right_bottom={x=w/2-0.1,y=h/2-0.1}},
		has_flag=function() return false end,max_underground_distance=5}
end
prototype("transport-belt","transport-belt",1,1)
prototype("underground-belt","underground-belt",1,1)
prototype("splitter","splitter",2,1)
prototypes.entity["transport-belt"].related_underground_belt=prototypes.entity["underground-belt"]
prototype("express-transport-belt","transport-belt",1,1)
prototype("express-underground-belt","underground-belt",1,1)
prototype("express-splitter","splitter",2,1)
for _,name in ipairs{"express-transport-belt","express-underground-belt","express-splitter"} do prototypes.entity[name].belt_speed=0.09375 end
prototypes.entity["express-underground-belt"].max_underground_distance=9
prototypes.entity["express-transport-belt"].related_underground_belt=prototypes.entity["express-underground-belt"]
require("mpp.global_extends")
local balancer=require("mpp.output_balancer")
local util=require("mpp.mpp_util")
local N,E,S,W=defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west
local cases=0
local priority_cases=0
local function key(x,y) return x..","..y end
local function verify(n,m,belt_name,preference)
	belt_name=belt_name or "express-transport-belt"
	local layout,err=balancer.geometry(n,m,belt_name,preference)
	assert(layout,"cannot generate "..n.." -> "..m..": "..tostring(err and err[1]))
	if belt_name=="express-transport-belt" and n<=8 and m<=8 and math.max(n,m)>2 then
		local rn,rm=layout.source_label:match("^(%d+)_(%d+)")
		assert(tonumber(rn)==n and tonumber(rm)==m,"matrix substituted "..n.." -> "..m.." with "..layout.source_label)
	end
	local cells,nodes,exits={}, {},{}
	local function kind(entity) return entity and prototypes.entity[entity.name].type end
	local function ports(entity)
		if kind(entity)~="splitter" then return {{entity.x,entity.y}} end
		if entity.direction==N or entity.direction==S then return {{entity.x-.5,entity.y},{entity.x+.5,entity.y}} end
		return {{entity.x,entity.y-.5},{entity.x,entity.y+.5}}
	end
	for _,entity in ipairs(layout.specs) do
		for _,point in ipairs(ports(entity)) do
			local k=key(point[1],point[2])
			assert(not cells[k],"overlap in "..n.." -> "..m.." at "..k)
			cells[k]=entity
		end
		if kind(entity)=="splitter" then nodes[#nodes+1]=entity;entity.node=#nodes end
	end
	for i=0,m-1 do exits[cells[key(i,layout.output_y)]]=i+1 end
	local function accepts(entity,dir)
		if not entity then return false end
		if kind(entity)=="splitter" or entity.type=="input" then return entity.direction==dir end
		return entity.direction~=(dir+S)%16
	end
	local function step(entity)
		local delta=util.direction_coord[entity.direction]
		if entity.type=="input" then
			for distance=1,prototypes.entity[entity.name].max_underground_distance do
				local target=cells[key(entity.x+delta.x*distance,entity.y+delta.y*distance)]
				if target and target.type=="output" and target.direction==entity.direction then return target end
			end
			error("underground input is unpaired in "..n.." -> "..m.." at "..key(entity.x,entity.y))
		end
		local target=cells[key(entity.x+delta.x,entity.y+delta.y)]
		return accepts(target,entity.direction) and target or nil
	end
	local function trace(entity)
		local seen={}
		while entity and kind(entity)~="splitter" and not exits[entity] do
			assert(not seen[entity],"belt-only loop in "..n.." -> "..m)
			seen[entity]=true;entity=step(entity)
		end
		assert(entity,"unconnected belt in "..n.." -> "..m)
		return entity
	end
	local matrix={}
	for i,node in ipairs(nodes) do
		local row={};matrix[i]=row
		for j=1,#nodes+m do row[j]=0 end
		row[i]=1
		local targets={}
		local delta=util.direction_coord[node.direction]
		for _,port in ipairs(ports(node)) do
			local target=cells[key(port[1]+delta.x,port[2]+delta.y)]
			if accepts(target,node.direction) then targets[#targets+1]=trace(target) end
		end
		assert(#targets>0,"splitter has no connected exit")
		for _,target in ipairs(targets) do
			if exits[target] then row[#nodes+exits[target]]=row[#nodes+exits[target]]+1/#targets
			else row[target.node]=row[target.node]-1/#targets end
		end
	end
	-- Solve absorption probabilities through the physical feedback circuits.
	for column=1,#nodes do
		local pivot=column
		for i=column+1,#nodes do if math.abs(matrix[i][column])>math.abs(matrix[pivot][column]) then pivot=i end end
		matrix[column],matrix[pivot]=matrix[pivot],matrix[column]
		local scale=matrix[column][column]
		assert(math.abs(scale)>1e-12,"feedback has no reachable exit")
		for j=column,#nodes+m do matrix[column][j]=matrix[column][j]/scale end
		for i=1,#nodes do
			if i~=column then
				local amount=matrix[i][column]
				for j=column,#nodes+m do matrix[i][j]=matrix[i][j]-amount*matrix[column][j] end
			end
		end
	end
	local priority=false
	for _,entity in ipairs(layout.specs) do if entity.output_priority and entity.output_priority~="none" then priority=true end end
	for _,port in ipairs(layout.inputs) do
		local first=cells[key(port.x,port.y+1)]
		local target=trace(first)
		for output=1,m do
			local share=exits[target] and (exits[target]==output and 1 or 0) or matrix[target.node][#nodes+output]
			if not priority then
				assert(math.abs(share-1/m)<1e-9,"unequal flow in "..n.." -> "..m..": "..share)
				cases=cases+1
			else priority_cases=priority_cases+1 end
		end
	end
end
for n=1,8 do for m=1,8 do verify(n,m) end end
for n=1,8 do verify(n,8,"transport-belt") end
for _,pair in ipairs{{1,16},{4,16},{8,16},{16,8},{16,16},{3,12},{12,6},{9,8},{8,9},{1,32},{32,8}} do verify(pair[1],pair[2]) end
for n=1,8 do for m=10,32,2 do verify(n,m,"express-transport-belt","matrix") end end
assert(not balancer.valid_count(0) and not balancer.valid_count(33) and not balancer.valid_count(1.5))
assert(balancer.output_count({count=5},{output_balance_choice=false})==5)
assert(balancer.output_count({count=5},{output_balance_choice=true})==8)
local compact=assert(balancer.geometry(6,8,"transport-belt"))
assert(compact.source_label=="6_8_alt_yellow" and compact.reference_count==77,"6-to-8 reference blueprint was replaced by a generated matrix")
assert(#compact.specs==85,"reference layout acquired unnecessary stages")
local three_to_eight=assert(balancer.geometry(3,8,"transport-belt"))
assert(three_to_eight.source_label=="3_8" and three_to_eight.reference_count==44,
	"3-to-8 output does not match the matrix blueprint")
local three_to_ten=assert(balancer.geometry(3,10,"express-transport-belt","matrix"))
assert(three_to_ten.source_label=="3_5 + 1_2" and #three_to_ten.specs<150,
	"five double-sided wagons use an oversized feedback adapter")
print("Output balancer OK: "..cases.." physical flow shares, tunnel pairing, rotations-ready geometry and configurable outputs")
