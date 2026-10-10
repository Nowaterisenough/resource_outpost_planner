local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local balancer = require("mpp.output_balancer")
local station = {}
local N,E,S,W = defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west

station.default_locomotives = 2
station.default_wagons = 4
station.max_locomotives = 8
station.max_wagons = 16

local function integer(value,maximum)
	return type(value)=="number" and value==math.floor(value) and value>=1 and value<=maximum
end

function station.valid_choices(choices)
	return integer(choices.output_locomotive_count_choice or 2,station.max_locomotives)
		and integer(choices.output_wagon_count_choice or 4,station.max_wagons)
end

function station.output_count(choices)
	return (choices.output_wagon_count_choice or 4)*(choices.output_loading_side_choice=="single" and 1 or 2)
end

function station.choices(choices)
	return {output_station_choice=true,output_locomotive_count_choice=choices.output_locomotive_count_choice or 2,
		output_wagon_count_choice=choices.output_wagon_count_choice or 4,
		output_loading_side_choice=choices.output_loading_side_choice or "double"}
end

function station.geometry(inputs,choices,belt_name)
	if not station.valid_choices(choices) then return nil,{"mpp.output_station_count_error",station.max_locomotives,station.max_wagons} end
	local heads,wagons=choices.output_locomotive_count_choice or 2,choices.output_wagon_count_choice or 4
	local double=choices.output_loading_side_choice~="single"
	local outputs=station.output_count(choices)
	local reference,err=balancer.geometry(inputs,outputs,belt_name,"matrix")
	if not reference then return nil,err end
	local inserter=prototypes.entity["bulk-inserter"] and "bulk-inserter" or "fast-inserter"
	for _,name in ipairs{"straight-rail","train-stop","locomotive","cargo-wagon","steel-chest","medium-electric-pole",inserter} do
		if not prototypes.entity[name] then return nil,{"mpp.output_station_equipment",name} end
	end
	local specs,keepout={},{}
	local underground=util.belt_struct(belt_name).related_underground_belt
	local function cargo_x(i) return 3+7*(heads+i-1) end
	-- Keep the belt module beside the wagons; locomotives may project beyond it.
	local bx,by=cargo_x(1)-outputs-3.5,-8.5-wagons
	if double and bx<=.5 and bx+wagons-1>=-.5 then bx=-wagons-1.5 end
	local tail=0
	for _,piece in ipairs(reference.specs) do tail=math.max(tail,piece.y-reference.output_y) end
	by=by-tail
	local function add(name,x,y,direction,extra)
		local spec={name=name,x=x,y=y,direction=direction or N,thing="belt"}
		for k,v in pairs(extra or {}) do spec[k]=v end
		specs[#specs+1]=spec
		return spec
	end
	local function belt(x,y,direction) return add(belt_name,x,y,direction) end
	for _,piece in ipairs(reference.specs) do
		add(piece.name,bx+piece.x,by+piece.y-reference.output_y,piece.direction,
			{type=piece.type,input_priority=piece.input_priority,output_priority=piece.output_priority,filter=piece.filter})
	end
	for _,p in ipairs(reference.keepout) do keepout[#keepout+1]={x=bx+p.x,y=by+p.y-reference.output_y} end
	local ports={}
	for _,p in ipairs(reference.inputs) do ports[#ports+1]={x=bx+p.x,y=by+p.y-reference.output_y} end
	for i=0,wagons-1 do
		local sx=bx+(double and wagons or 0)+i
		local row=-8.5-i
		local first=cargo_x(i+1)-.5
		for y=by+1,row-1 do belt(sx,y,S) end
		for x=sx,first-1 do belt(x,row,E) end
		for y=row,-7.5 do belt(first,y,S) end
	end
	if double then
		for i=0,wagons-1 do
			local column=bx+i
			local wagon=wagons-i
			local row=8.5+wagons-1-i
			local first=cargo_x(wagon)-.5
			for y=by+1,-4.5 do belt(column,y,S) end
			add(underground,column,-3.5,S,{type="input"})
			add(underground,column,1.5,S,{type="output"})
			for y=2.5,row-1 do belt(column,y,S) end
			for x=column,first-1 do belt(x,row,E) end
			for y=row,7.5,-1 do belt(first,y,N) end
		end
	end
	local splitter=assert(balancer.equipment(belt_name))
	local loading_inputs={}
	for _,side in ipairs(double and {-1,1} or {-1}) do
		for wagon=1,wagons do
			local center=cargo_x(wagon)
			local function feed(name,x,y,dir)
				if side==1 then y=-y;dir=(S-dir)%16 end
				return add(name,x,y,dir)
			end
			-- Compact loader: branch the wagon's belt, then feed each pair of boxes.
			feed(splitter,center,-6.5,S)
			feed(splitter,center-1,-5.5,S)
			feed(belt_name,center+.5,-5.5,E)
			feed(belt_name,center+1.5,-5.5,S)
			for pair=-2,2,2 do
				feed(splitter,center+pair,-4.5,S)
			end
			for x=center-2.5,center+2.5 do for y=-7.5,-4.5 do
				keepout[#keepout+1]={x=x,y=side==-1 and y or -y}
			end end
			loading_inputs[#loading_inputs+1]={x=center-.5,y=side*7.5,wagon=wagon,side=side}
		end
	end
	local left=-4
	local right=math.ceil((7*(heads+wagons)+2)/2)*2
	for x=left,right,2 do add("straight-rail",x,0,E,{station_rail=true}) end
	add("train-stop",0,-2,W,{station_control=true,station_name="Resource loading"})
	if prototypes.entity["rail-signal"] and prototypes.entity["rail-chain-signal"] then
		add("rail-signal",left+2.5,-1.5,E,{station_control=true,station_signal=true})
		add("rail-chain-signal",right-2.5,-1.5,E,{station_control=true,station_signal=true})
	end
	for i=1,heads+wagons do
		add(i<=heads and "locomotive" or "cargo-wagon",3+7*(i-1),0,W,{station_stock=true})
	end
	for _,side in ipairs(double and {-1,1} or {-1}) do
		-- Vanilla inserters pick up to the north and drop to the south at direction zero.
		local direction=side==-1 and N or S
		for i=1,wagons do
			for offset=-2.5,2.5 do
				local x=cargo_x(i)+offset
				add(inserter,x,side*1.5,direction)
				add("steel-chest",x,side*2.5,N)
				add(inserter,x,side*3.5,direction)
			end
		end
		for i=0,wagons do add("medium-electric-pole",cargo_x(1)-3.5+7*i,side*2.5,N) end
	end
	local extent=0
	for _,p in ipairs(specs) do extent=math.max(extent,math.abs(p.x),math.abs(p.y)) end
	return {specs=specs,inputs=ports,loading_inputs=loading_inputs,keepout=keepout,outputs=outputs,extent=extent,
		locomotives=heads,wagons=wagons,double=double,reference=reference.source_label}
end

function station.transform(x,y,direction,mirror)
	if mirror then x=-x end
	local delta=util.direction_coord[direction]
	return delta.y*x+delta.x*y,-delta.x*x+delta.y*y
end

function station.transform_piece(piece,direction,mirror)
	local result={}
	for k,v in pairs(piece) do result[k]=v end
	local y=piece.station_control and mirror and -piece.y or piece.y
	result.x,result.y=station.transform(piece.x,y,direction,mirror)
	local dir=mirror and (-piece.direction)%16 or piece.direction
	result.direction=(dir+direction-S)%16
	if piece.station_rail then result.direction=result.direction%8 end
	if piece.station_stock then result.orientation=result.direction/16 end
	if mirror then
		for _,field in ipairs{"input_priority","output_priority"} do
			if result[field]=="left" then result[field]="right" elseif result[field]=="right" then result[field]="left" end
		end
	end
	return result
end

function station.cursor_entities(layout,direction,mirror)
	local entities={}
	for i,piece in ipairs(layout.specs) do
		local p=station.transform_piece(piece,direction,mirror)
		-- Rail blueprint coordinates use odd tile centers within the absolute two-tile grid.
		entities[i]={entity_number=i,name=p.name,position={x=p.x+1,y=p.y+1},direction=p.direction,
			orientation=p.orientation,type=p.type,input_priority=p.input_priority,output_priority=p.output_priority,filter=p.filter,
			tags={mpp_station_cursor=true}}
	end
	return entities
end

function station.plan(state,route)
	local layout,err=station.geometry(state.belt_specification.count,state,state.belt_choice)
	if not layout then return false,err,{routes={},issues={{position=state.belt_target.position,reason=err}}} end
	state._belt_search_margin=math.max(state._belt_search_margin or 0,layout.extent+16)
	local anchor=state.belt_target.position
	local direction,mirror=state.belt_target.direction,state.belt_target.mirror==true
	local c=state.coords
	local origin=util.revert_world(c.gx,c.gy,state.direction_choice,0,0,c.tw,c.th)
	local function grid(x,y)
		return util.coord_convert[state.direction_choice](x-math.floor(origin[1])-.5,y-math.floor(origin[2])-.5,0,0)
	end
	local function world_direction(dir) return util.clamped_rotation(-defines.direction[state.direction_choice]-E,dir) end
	local entities,issues={},{}
	for _,piece in ipairs(layout.specs) do
		local p=station.transform_piece(piece,direction,mirror)
		local x,y=grid(anchor.x+p.x,anchor.y+p.y)
		local spec={name=p.name,grid_x=x,grid_y=y,direction=world_direction(p.direction),
			type=p.type,orientation=p.orientation,thing=p.thing,input_priority=p.input_priority,
			output_priority=p.output_priority,filter=p.filter,station_name=p.station_name,station_stock=p.station_stock,station_rail=p.station_rail}
		if not obstacles.can_place(state,p.name,{x=anchor.x+p.x,y=anchor.y+p.y},p.direction) then
			spec.preview_blocked=true
			issues[#issues+1]={position={x=anchor.x+p.x,y=anchor.y+p.y},reason={"mpp.output_station_blocked"}}
		end
		entities[#entities+1]=spec
	end
	local connection={}
	for k,v in pairs(state) do connection[k]=v end
	connection.output_station_choice=false
	connection.output_balance_choice=false
	connection.planned={}
	for _,p in ipairs(state.planned or {}) do connection.planned[#connection.planned+1]=p end
	for _,p in ipairs(entities) do connection.planned[#connection.planned+1]=p end
	for _,p in ipairs(layout.keepout) do
		local x,y=station.transform(p.x,p.y,direction,mirror)
		local gx,gy=grid(anchor.x+x,anchor.y+y)
		connection.planned[#connection.planned+1]={name=state.belt_choice,grid_x=gx,grid_y=gy,direction=N}
	end
	connection.belt_input_targets={}
	for i,p in ipairs(layout.inputs) do
		local x,y=station.transform(p.x,p.y,direction,mirror)
		local gx,gy=grid(anchor.x+x,anchor.y+y)
		connection.belt_input_targets[i]={x=math.floor(gx+.5),y=math.floor(gy+.5)}
	end
	-- Balancer inputs are interchangeable; preserve bundle order after reflection.
	table.sort(connection.belt_input_targets,function(a,b)
		if state.belt_direction==W then return a.y<b.y end
		if state.belt_direction==E then return a.y>b.y end
		if state.belt_direction==N then return a.x>b.x end
		return a.x<b.x
	end)
	local ok,routes,diagnostic=route(connection)
	if not ok and #connection.belt_input_targets>1 then
		-- Either input order has the same balance; reflection can put the shorter ingress on the other side.
		local targets=connection.belt_input_targets
		for i=1,math.floor(#targets/2) do targets[i],targets[#targets-i+1]=targets[#targets-i+1],targets[i] end
		local retry,other,details=route(connection)
		if retry then ok,routes,diagnostic=retry,other,details
		elseif #(details and details.routes or {})>#(diagnostic and diagnostic.routes or {}) then diagnostic=details end
	end
	local combined={}
	for _,p in ipairs(ok and routes or diagnostic and diagnostic.routes or {}) do combined[#combined+1]=p end
	for _,p in ipairs(entities) do combined[#combined+1]=p end
	if not ok or #issues>0 then
		for _,issue in ipairs(diagnostic and diagnostic.issues or {}) do issues[#issues+1]=issue end
		return false,not ok and routes or {"mpp.output_station_blocked"},{routes=combined,issues=issues}
	end
	state.balanced_output_count=layout.outputs
	return true,combined
end

return station
