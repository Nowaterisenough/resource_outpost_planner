defines={direction={north=0,east=4,south=8,west=12}}
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
	assert(counts.locomotive==heads and counts["cargo-wagon"]==wagons)
	assert(layout.outputs==wagons*sides and counts["steel-chest"]==wagons*sides*6)
	assert(counts["bulk-inserter"]==wagons*sides*12 and #layout.loading_inputs==wagons*sides)
	for _,piece in ipairs(layout.specs) do
		if piece.name=="bulk-inserter" then
			local delta=util.direction_coord[piece.direction]
			local pickup=cells[key(piece.x-delta.x,piece.y-delta.y)]
			local drop=cells[key(piece.x+delta.x,piece.y+delta.y)]
			-- The prototype's default hand drops south at direction zero.
			pickup,drop=drop,pickup
			assert(pickup,"missing inserter source")
			if math.abs(piece.y)==3.5 then
				assert(prototypes.entity[pickup.name].type=="splitter" and drop and drop.name=="steel-chest","buffer filling points away from chest")
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
assert(station.output_count({})==8 and station.output_count({output_loading_side_choice="single"})==4)
assert(not station.valid_choices({output_locomotive_count_choice=0}) and not station.valid_choices({output_wagon_count_choice=17}))
local compact=assert(station.geometry(4,{},"express-transport-belt"))
assert(compact.reference=="4_8" and #compact.specs<=610,"default station acquired a large balancer or long loader loops")
local three_to_eight=assert(station.geometry(3,{},"express-transport-belt"))
assert(three_to_eight.reference=="3_8","3-to-8 station does not match the matrix blueprint")
local min_belt_x=math.huge
for _,piece in ipairs(compact.specs) do
	if piece.name=="express-transport-belt" or piece.name=="express-underground-belt" or piece.name=="express-splitter" then
		min_belt_x=math.min(min_belt_x,piece.x)
	end
end
assert(min_belt_x>3,"belt module wraps around the protruding locomotive section")
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
local crossings=0
for _,piece in ipairs(compact.specs) do
	if piece.type=="input" and piece.y>-7.5 then
		assert(piece.y==-3.5 and piece.direction==8,"loading trunks cross each other underground")
		crossings=crossings+1
	end
end
assert(crossings==4,"default double-sided station needs more than four rail crossings")
print("Train station OK: "..cases.." train/side layouts, "..arms.." loading arms, pole coverage, underground pairs and transforms")
