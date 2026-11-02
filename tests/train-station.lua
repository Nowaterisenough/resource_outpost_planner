defines={direction={north=0,east=4,south=8,west=12}}
for i=1,15 do if i%4~=0 then defines.direction["intermediate_"..i]=i end end
script={active_mods={},feature_flags={},register_metatable=function() end}
prototypes={entity={},quality={},item={}}
function table_size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
function table.deepcopy(t)
	if type(t)~="table" then return t end
	local copy={};for k,v in pairs(t) do copy[k]=table.deepcopy(v) end;return copy
end
local function prototype(name,kind,w,h)
	local p={name=name,type=kind,tile_width=w,tile_height=h,belt_speed=.09375,
		collision_box={left_top={x=-w/2+.1,y=-h/2+.1},right_bottom={x=w/2-.1,y=h/2-.1}},
		has_flag=function() return false end,max_underground_distance=9}
	prototypes.entity[name]=p
	return p
end
local belt=prototype("express-transport-belt","transport-belt",1,1)
belt.related_underground_belt=prototype("express-underground-belt","underground-belt",1,1)
prototype("express-splitter","splitter",2,1)
prototype("straight-rail","straight-rail",2,2)
prototype("train-stop","train-stop",2,2)
prototype("rail-signal","rail-signal",1,1)
prototype("rail-chain-signal","rail-chain-signal",1,1)
prototype("locomotive","locomotive",2,6)
prototype("cargo-wagon","cargo-wagon",2,5)
prototype("steel-chest","container",1,1)
prototype("bulk-inserter","inserter",1,1)
prototype("medium-electric-pole","electric-pole",1,1)
local station=require("mpp.train_station")
local util=require("mpp.mpp_util")
local function key(x,y) return x..","..y end
local cases,arms=0,0
for heads=1,8 do for wagons=1,16 do for _,side in ipairs{"single","double"} do
	local choices={output_locomotive_count_choice=heads,output_wagon_count_choice=wagons,output_loading_side_choice=side}
	local layout=assert(station.geometry(4,choices,"express-transport-belt"))
	local cells,counts,poles={},{},{}
	for _,piece in ipairs(layout.specs) do
		counts[piece.name]=(counts[piece.name] or 0)+1
		if piece.name=="medium-electric-pole" then poles[#poles+1]=piece end
		if not piece.station_rail and not piece.station_stock then
			local offsets=prototypes.entity[piece.name].type=="splitter"
				and ((piece.direction==0 or piece.direction==8) and {{-.5,0},{.5,0}} or {{0,-.5},{0,.5}}) or {{0,0}}
			for _,offset in ipairs(offsets) do
				local k=key(piece.x+offset[1],piece.y+offset[2])
				assert(not cells[k],"overlap: "..heads.."-"..wagons.." "..side.." at "..k)
				cells[k]=piece
			end
		end
	end
	local sides=side=="single" and 1 or 2
	assert(not counts.locomotive and not counts["cargo-wagon"],"station creates rolling-stock ghosts")
	assert(layout.locomotives==heads and layout.wagons==wagons,"station lost the requested train dimensions")
	assert(counts["straight-rail"]==math.ceil((7*(heads+wagons)+2)/2)+3,"rail length no longer fits the chosen train")
	assert(layout.outputs==wagons*(side=="double" and 6 or 1) and counts["steel-chest"]==wagons*sides*6)
	assert(counts["bulk-inserter"]==wagons*sides*12 and #layout.loading_inputs==layout.outputs)
	for _,piece in ipairs(layout.specs) do
		if piece.name=="bulk-inserter" then
			local delta=util.direction_coord[piece.direction]
			local pickup=cells[key(piece.x-delta.x,piece.y-delta.y)]
			local drop=cells[key(piece.x+delta.x,piece.y+delta.y)]
			-- The prototype's default hand drops south at direction zero.
			pickup,drop=drop,pickup
			assert(pickup,"missing inserter source")
			if math.abs(piece.y)==3.5 then
				assert(prototypes.entity[pickup.name].type==(side=="double" and "underground-belt" or "splitter") and drop and drop.name=="steel-chest","buffer filling points away from chest")
			else assert(pickup.name=="steel-chest","wagon loading does not pick up from buffer") end
			local supplied=false
			for _,pole in ipairs(poles) do
				if math.abs(pole.x-piece.x)<=3.5 and math.abs(pole.y-piece.y)<=3.5 then supplied=true;break end
			end
			assert(supplied,"loading arm outside pole supply area")
			arms=arms+1
		end
		if piece.type=="input" then
			local delta=util.direction_coord[piece.direction]
			local paired=false
			for distance=1,9 do
				local target=cells[key(piece.x+delta.x*distance,piece.y+delta.y*distance)]
				if target and target.name==piece.name and target.type=="output" and target.direction==piece.direction then paired=true;break end
			end
			assert(paired,"unpaired station underground belt")
		end
	end
	for _,direction in ipairs{0,4,8,12} do for _,mirror in ipairs{false,true} do
		for _,piece in ipairs(layout.specs) do
			if piece.station_control then
				local transformed=station.transform_piece(piece,direction,mirror)
				local train_dir=station.transform_piece({x=0,y=0,direction=12,station_stock=true},direction,mirror).direction
				local delta=util.direction_coord[train_dir]
				assert(transformed.direction==(piece.station_signal and (train_dir+8)%16 or train_dir),"station control direction differs from train")
				assert(transformed.x*(-delta.y)+transformed.y*delta.x>0,"stop moved to the wrong side of the railway")
			end
		end
	end end
	cases=cases+1
end end end
assert(station.output_count({belt_choice="express-transport-belt"})==24 and station.output_count({belt_choice="turbo-transport-belt"})==24)
assert(station.output_count({belt_choice="fast-transport-belt"})==8)
assert(station.output_count({})==8 and station.output_count({output_loading_side_choice="single"})==4)
assert(not station.valid_choices({output_locomotive_count_choice=0}) and not station.valid_choices({output_wagon_count_choice=17}))
local compact=assert(station.geometry(4,{},"express-transport-belt"))
assert(compact.outputs==24 and compact.reference=="4_4 global + 4 x 6-output modules","blue station does not balance to six feeds per wagon")
local three_to_twenty_four=assert(station.geometry(3,{},"express-transport-belt"))
assert(three_to_twenty_four.shared,"three source belts must supply all four modules")
local filtered=assert(station.geometry(4,{output_wagon_count_choice=3,output_loading_side_choice="single"},"express-transport-belt"))
local filters=0
for _,direction in ipairs{0,4,8,12} do for _,mirror in ipairs{false,true} do
	local cursor=station.cursor_entities(filtered,direction,mirror)
	for i,piece in ipairs(filtered.specs) do if piece.filter then
		filters=filters+1
		assert(cursor[i].filter==piece.filter,"station cursor lost splitter filter")
		assert(cursor[i].output_priority==(mirror and "right" or "left"),"mirrored filter outlet is wrong")
	end end
end end
assert(filters==8,"4-to-3 filter blueprint was not retained")
local min_belt_x=math.huge
for _,piece in ipairs(compact.specs) do
	if piece.name=="express-transport-belt" or piece.name=="express-underground-belt" or piece.name=="express-splitter" then
		min_belt_x=math.min(min_belt_x,piece.x)
	end
end
assert(min_belt_x>-4,"small global core exceeds the locomotive section")
for _,direction in ipairs{0,4,8,12} do for _,mirror in ipairs{false,true} do
	local entities=station.cursor_entities(compact,direction,mirror)
	for i,piece in ipairs(compact.specs) do
		local projected=station.transform_piece(piece,direction,mirror)
		assert(entities[i].position.x-1==projected.x and entities[i].position.y-1==projected.y,
			"cursor and ground preview use different rail coordinate origins")
		if piece.station_rail then
			assert(entities[i].position.x%2==1 and entities[i].position.y%2==1,"cursor rail is not on the native odd-tile grid")
		end
	end
end end
for _,tier in ipairs{{"transport-belt","underground-belt","splitter",5,8},{"fast-transport-belt","fast-underground-belt","fast-splitter",7,8},{"turbo-transport-belt","turbo-underground-belt","turbo-splitter",11,24}} do
 local b=prototype(tier[1],"transport-belt",1,1)
 b.related_underground_belt=prototype(tier[2],"underground-belt",1,1)
 b.related_underground_belt.max_underground_distance=tier[4]
 prototype(tier[3],"splitter",2,1)
 local other=assert(station.geometry(4,{},tier[1]))
 assert(other.outputs==tier[5] and #other.loading_inputs==tier[5],"belt tier selected the wrong loading structure")
 local single=assert(station.geometry(4,{output_loading_side_choice="single"},tier[1]))
 assert(single.outputs==4 and not single.through_loading,"single-sided station changed its feed layout")
end
local crossings=0
for _,piece in ipairs(compact.specs) do
	if piece.type=="input" and piece.y>-7.5 then
		assert(piece.y==-4.5 and piece.direction==8,"loading trunks do not enter from the same side")
		crossings=crossings+1
	end
end
assert(crossings==24,"default blue station does not have 24 independent rail crossings")
-- Module size, saturation, and source assignment are separate contracts.
local bank=require("mpp.station_balancers")
for _,w in ipairs{1,2,4,8,16} do for _,n in ipairs{1,2,3,4,5,6,7,8,9,10,12,16,24,30,34,48,64,96,128} do
 local layout=assert(station.geometry(n,{output_wagon_count_choice=w},"express-transport-belt"))
 local cells={}
 for _,p in ipairs(layout.specs) do if not p.station_rail then
  local offsets=prototypes.entity[p.name].type=="splitter" and ((p.direction==0 or p.direction==8) and {{-.5,0},{.5,0}} or {{0,-.5},{0,.5}}) or {{0,0}}
  for _,o in ipairs(offsets) do
   local k=key(p.x+o[1],p.y+o[2])
   assert(not cells[k],n.."/"..w.." module collision at "..k)
   cells[k]=p
  end
 end end
 assert(#layout.inputs==n and #layout.groups==w and layout.outputs==6*w)
end end
for _,n in ipairs{24,30,34} do
 local layout=assert(station.geometry(n,{},"express-transport-belt"))
 local x1,x2,y1,y2=math.huge,-math.huge,math.huge,-math.huge
 for _,p in ipairs(layout.specs) do
  x1=math.min(x1,math.floor(p.x));x2=math.max(x2,math.ceil(p.x))
  y1=math.min(y1,math.floor(p.y));y2=math.max(y2,math.ceil(p.y))
 end
 assert(x2-x1+1<=52 and y2-y1+1<=68 and #layout.specs<=1750,"wagon modules grew into a central balancing yard")
end
-- Source estimates must never change the topology: every input participates
-- in the global balance, even when a mine row becomes depleted later.
local weights={}
for i=1,24 do weights[i]=i<=12 and .05 or .95 end
local weighted=assert(station.geometry(24,{},"express-transport-belt",weights))
local uniform=assert(station.geometry(24,{},"express-transport-belt"))
assert(#weighted.specs==#uniform.specs)
for i,p in ipairs(weighted.specs) do
 local q=uniform.specs[i]
 assert(p.name==q.name and p.x==q.x and p.y==q.y and p.direction==q.direction,"forecast changes physical global balance")
end
for _,g in ipairs(weighted.groups) do assert(math.abs(g.load-3)<1e-8,"wagon groups receive unequal loads") end
assert(bank.channels(7,4)==2 and bank.channels(24,4)==8,"global distribution throttles the incoming bundle")
local obstacle_module=require("mpp.obstacles")
local can_place=obstacle_module.can_place
obstacle_module.can_place=function() return true end
local spec={count=7}
local state={belt_specification=spec,belt_choice="express-transport-belt",direction_choice="west",
 coords={gx=0,gy=0,tw=100,th=100},belt_target={position={x=201,y=201},direction=8},belt_direction=8}
assert(station.plan(state,function(connection)
 assert(connection.interchangeable_belt_inputs,"global balancing should allow compact input routing")
 assert(#connection.belt_input_targets==7)
 return true,{}
end))
obstacle_module.can_place=can_place
print("Train station OK: "..cases.." train/side layouts, "..arms.." loading arms, pole coverage, underground pairs and transforms")
