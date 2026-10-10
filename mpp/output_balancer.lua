local util = require("mpp.mpp_util")
local obstacles = require("mpp.obstacles")
local balancer = {}
local N,E,S,W = defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west
local cache = {}

balancer.default_count = 8
balancer.max_count = 32

function balancer.valid_count(value)
	return type(value)=="number" and value==math.floor(value) and value>=1 and value<=balancer.max_count
end

function balancer.output_count(spec, choices)
	return choices.output_balance_choice and (choices.output_belt_count_choice or balancer.default_count) or spec.count
end

local function key(x,y) return x..","..y end

local function equipment(name)
	local belt = prototypes.entity[name]
	local underground = util.belt_struct(name).related_underground_belt
	local preferred = name:gsub("transport%-belt", "splitter")
	local splitter = prototypes.entity[preferred]
	if not splitter or splitter.type~="splitter" or splitter.belt_speed~=belt.belt_speed then
		splitter = nil
		for _, proto in pairs(prototypes.entity) do
			if proto.type=="splitter" and proto.belt_speed==belt.belt_speed
				and proto.tile_width==2 and proto.tile_height==1 then
				if not splitter or proto.name<splitter.name then splitter=proto end
			end
		end
	end
	if not splitter or not underground then return end
	return splitter.name, underground, prototypes.entity[underground].max_underground_distance
end

local reference_layouts = require("mpp.balancer_blueprints")
local matrix_layouts = require("mpp.balancer_matrix")
local function choose_matrix(inputs,outputs,reach)
	for _,entry in ipairs(matrix_layouts[inputs][outputs]) do
		if entry.reach<=reach then return entry end
	end
end
local function choose_reference(inputs,outputs,reach,matrix)
	local best,best_score
	for _,entry in ipairs(reference_layouts) do
		if not entry.disabled and entry.n>=inputs and entry.m==outputs and entry.reach<=reach then
			local min_x,max_x,min_y,max_y=math.huge,-math.huge,math.huge,-math.huge
			for _,e in ipairs(entry.entities) do min_x=math.min(min_x,e[2]);max_x=math.max(max_x,e[2]);min_y=math.min(min_y,e[3]);max_y=math.max(max_y,e[3]) end
			local area=(max_x-min_x+1)*(max_y-min_y+1)
			local score=matrix and (entry.n-inputs)*1000000+area*100+#entry.entities+(entry.tu and 0 or .1)
				or (entry.n-inputs)*1000000+(entry.tu and 0 or 100000)+area*100+#entry.entities
			if not best_score or score<best_score then best,best_score=entry,score end
		end
	end
	return best
end

local function geometry(inputs, outputs, belt_name, preference)
	local splitter, underground, reach = equipment(belt_name)
	if not splitter or not reach or reach<2 then return nil,{"mpp.output_balance_equipment"} end
	local matrix=preference=="matrix" or inputs<=8 and outputs<=8
	local cache_key = inputs..":"..outputs..":"..belt_name..":"..tostring(matrix)
	if cache[cache_key] then return cache[cache_key] end
	local exact=inputs<=8 and outputs<=8
	local entry
	if exact then entry=choose_matrix(inputs,outputs,reach)
	else entry=choose_reference(inputs,outputs,reach,matrix) end
	if exact and not entry then return nil,{"mpp.output_balance_reference_equipment",inputs,outputs} end
	-- Extend the small matrix with equal two-way branches instead of oversized feedback loops.
	if matrix and inputs<=8 and outputs>8 and outputs%2==0 and (not entry or entry.n~=inputs) then
		local core,err=geometry(inputs,outputs/2,belt_name,"matrix")
		if not core then return nil,err end
		local specs,keepout={},{}
		for _,piece in ipairs(core.specs) do specs[#specs+1]=piece end
		for _,p in ipairs(core.keepout) do keepout[#keepout+1]=p end
		local channels=outputs/2
		local start_y=core.output_y
		for _,piece in ipairs(core.specs) do start_y=math.max(start_y,math.ceil(piece.y)) end
		local branch_y=start_y+channels
		for i=0,channels-1 do
			local row=start_y+channels-i
			for y=core.output_y+1,row-1 do specs[#specs+1]={name=belt_name,x=i,y=y,direction=S} end
			for x=i,2*i-1 do specs[#specs+1]={name=belt_name,x=x,y=row,direction=E} end
			for y=row,branch_y do specs[#specs+1]={name=belt_name,x=2*i,y=y,direction=S} end
			specs[#specs+1]={name=splitter,x=2*i+.5,y=branch_y+1,direction=S}
			for x=2*i,2*i+1 do specs[#specs+1]={name=belt_name,x=x,y=branch_y+2,direction=S} end
		end
		local output_y=branch_y+2
		local result={specs=specs,inputs=core.inputs,output_y=output_y,width=outputs,keepout=keepout,
			source_label=core.source_label.." + 1_2",reference_count=core.reference_count+channels,
			extent=math.max(core.extent+output_y-core.output_y,outputs)}
		cache[cache_key]=result
		return result
	end
	local adapting=entry==nil
	local width=1
	while width<math.max(inputs,outputs) do width=width*2 end
	if adapting then entry=choose_reference(width,width,reach,matrix) end
	if not entry then return nil,{"mpp.output_balance_reference_equipment",inputs,outputs} end
	local specs,occupied,keepout={},{},{}
	local names={belt=belt_name,splitter=splitter,underground=underground}
	local function add(name,x,y,direction,kind,input_priority,output_priority,filter)
		local spec={name=name,x=x,y=y,direction=direction or S,type=kind,input_priority=input_priority,output_priority=output_priority,filter=filter}
		local cells={{x,y}}
		if name==splitter then
			cells=(spec.direction==N or spec.direction==S) and {{x-.5,y},{x+.5,y}} or {{x,y-.5},{x,y+.5}}
		end
		for _,p in ipairs(cells) do assert(not occupied[key(p[1],p[2])],"overlapping blueprint entities");occupied[key(p[1],p[2])]=true end
		specs[#specs+1]=spec
		return spec
	end
	local function belt(x,y,dir) return add(belt_name,x,y,dir) end
	local function tunnel(x1,y1,x2,y2,dir)
		add(underground,x1,y1,dir,"input");add(underground,x2,y2,dir,"output")
	end
	for _,e in ipairs(entry.entities) do add(names[e[1]],e[2],e[3],e[4],e[5],e[6],e[7],e[8]) end
	local y=entry.outputs[1][2]
	local output_y=y
	local power=outputs
	while power>1 and power%2==0 do power=power/2 end
	local reducing=adapting and entry.m>outputs and power==1
	local contiguous=true
	for i=1,outputs do if entry.outputs[i][1]~=i-1 then contiguous=false end end
	if not contiguous then output_y=y+outputs+1 end
	if reducing then
		local channels=entry.outputs
		while #channels>outputs do
			local count=#channels/2
			for i=0,count-1 do
				local x=channels[2*i+1][1]
				assert(channels[2*i+2][1]==x+1,"reference outputs are not adjacent")
				add(splitter,x+.5,y,S)
				keepout[#keepout+1]={x=x+1,y=y+1}
			end
			for i=0,count-1 do
				local x=channels[2*i+1][1]
				for row=y+1,y+i do belt(x,row) end
				for column=x,i+1,-1 do belt(column,y+i+1,W) end
				for row=y+i+1,y+count+1 do belt(i,row) end
			end
			channels={}
			for i=0,count-1 do channels[#channels+1]={i,y+count+2} end
			y=y+count+2
		end
		output_y=y
		for i=0,outputs-1 do belt(i,output_y) end
	else for i=0,outputs-1 do
		local x=entry.outputs[i+1][1]
		if contiguous then belt(x,y)
		else
			for row=y,y+i-1 do belt(x,row) end
			for column=x,i+1,-1 do belt(column,y+i,W) end
			for row=y+i,output_y do belt(i,row) end
		end
	end end
	local input_ports={}
	for i=1,inputs do input_ports[i]={x=entry.inputs[i][1],y=entry.inputs[i][2]} end
	if adapting and entry.m>outputs and not reducing then
		width=entry.n
		local prefix_y=entry.inputs[1][2]-width-3
		local prefix_x=0
		for i=0,width-1 do prefix_x=math.max(prefix_x,entry.inputs[i+1][1]-4*i) end
		for i=0,width-1 do
			local x=prefix_x+4*i
			add(splitter,x+.5,prefix_y,S)
			keepout[#keepout+1]={x=x+1,y=prefix_y+1}
			local turn=prefix_y+1+i
			local destination=entry.inputs[i+1]
			for row=prefix_y+1,turn-1 do belt(x,row) end
			for column=x,destination[1]+1,-1 do belt(column,turn,W) end
			for row=turn,destination[2] do belt(destination[1],row) end
			if i<inputs then input_ports[i+1]={x=x,y=prefix_y-1} end
		end
		local free={}
		for i=inputs,width-1 do free[#free+1]=i end
		for i=0,inputs-1 do free[#free+1]=i end
		local selected_ports={}
		for i=1,width-outputs do selected_ports[i]=free[i] end
		table.sort(selected_ports)
		local feedback={}
		for i=outputs,width-1 do
			local port=selected_ports[i-outputs+1]
			local target={x=prefix_x+4*port+(port<inputs and 1 or 0),y=prefix_y-1}
			local source=entry.outputs[i+1]
			local row=y+1+width-1-i
			local column=4*width+4*(i-outputs)+2
			for r=source[2],row-1 do belt(source[1],r) end
			for x=source[1],column-1 do belt(x,row,E) end
			for r=row,y+width-outputs+2 do belt(column,r) end
			feedback[#feedback+1]={source={x=column,y=y+width-outputs+2},target=target}
		end
		for i,connection in ipairs(feedback) do
			local source,target=connection.source,connection.target
			local column=8*width+4*i+4
			local row=source.y+3*(#feedback-i)+1
			local top=prefix_y-3-3*i
			for y1=source.y+1,row-1 do belt(source.x,y1) end
			for x=source.x,column-1 do belt(x,row,E) end
			belt(column,row,N)
			local crossings={}
			for j=i+1,#feedback do crossings[feedback[j].source.y+3*(#feedback-j)+1]=true end
			local cursor=row-1
			while cursor>top do
				if crossings[cursor-1] then tunnel(column,cursor,column,cursor-2,N);cursor=cursor-3
				else belt(column,cursor,N);cursor=cursor-1 end
			end
			belt(column,top,W);crossings={}
			for j=i+1,#feedback do crossings[feedback[j].target.x]=true end
			cursor=column-1
			while cursor>target.x do
				if crossings[cursor-1] then tunnel(cursor,top,cursor-2,top,W);cursor=cursor-3
				else belt(cursor,top,W);cursor=cursor-1 end
			end
			for y1=top,target.y do belt(target.x,y1) end
		end
	end
	if outputs==1 and inputs==2 then keepout[#keepout+1]={x=1,y=1} end
	-- Reserve the reference footprint so ingress routes cannot enter an empty splitter outlet.
	local min_x,max_x,min_y,max_y=math.huge,-math.huge,math.huge,-math.huge
	for _,piece in ipairs(specs) do min_x=math.min(min_x,math.floor(piece.x));max_x=math.max(max_x,math.ceil(piece.x));min_y=math.min(min_y,math.floor(piece.y));max_y=math.max(max_y,math.ceil(piece.y)) end
	local reserve_x1,reserve_x2,reserve_y1,reserve_y2=math.huge,-math.huge,math.huge,-math.huge
	for _,e in ipairs(entry.entities) do reserve_x1=math.min(reserve_x1,math.floor(e[2]));reserve_x2=math.max(reserve_x2,math.ceil(e[2]));reserve_y1=math.min(reserve_y1,math.floor(e[3]));reserve_y2=math.max(reserve_y2,math.ceil(e[3])) end
	for x=reserve_x1,reserve_x2 do for row=reserve_y1,reserve_y2 do
		if not occupied[key(x,row)] then keepout[#keepout+1]={x=x,y=row} end
	end end
	local extent=math.max(math.abs(min_x),math.abs(max_x),math.abs(min_y-output_y),math.abs(max_y-output_y))
	local result={specs=specs,inputs=input_ports,output_y=output_y,width=width,keepout=keepout,source_label=entry.label,
		source=entry.source,lane=entry.lane,reference_count=#entry.entities,extent=extent}
	cache[cache_key]=result
	return result
end

function balancer.plan(state, route)
	local inputs,outputs=state.belt_specification.count,state.output_belt_count_choice or balancer.default_count
	local function failure(err)
		return false,err,{routes={},issues={{position=state.belt_target.position,reason=err}}}
	end
	if not balancer.valid_count(outputs) or inputs>balancer.max_count then
		return failure{"mpp.output_balance_count_error",balancer.max_count}
	end
	local layout,err=geometry(inputs,outputs,state.belt_choice)
	if not layout then return failure(err) end
	state._belt_search_margin=math.max(state._belt_search_margin or 0,layout.extent+16)
	local delta=util.direction_coord[state.belt_direction]
	local function grid(x,y)
		local lateral=outputs-1-x
		return state.belt_x-delta.y*lateral+delta.x*(y-layout.output_y),
			state.belt_y+delta.x*lateral+delta.y*(y-layout.output_y)
	end
	local entities,issues={},{}
	for _,piece in ipairs(layout.specs) do
		local x,y=grid(piece.x,piece.y)
		local dir=(piece.direction+state.belt_direction-S)%16
		local spec={name=piece.name,quality=state.belt_quality_choice,grid_x=x,grid_y=y,direction=dir,type=piece.type,thing="belt",input_priority=piece.input_priority,output_priority=piece.output_priority,filter=piece.filter}
		local c=state.coords
		local pos=util.revert_world(c.gx,c.gy,state.direction_choice,x,y,c.tw,c.th)
		local world_direction=util.bp_direction[state.direction_choice][dir]
		if not obstacles.can_place(state,piece.name,{x=pos[1],y=pos[2]},world_direction) then
			spec.preview_blocked=true
			local box=obstacles.entity_box(piece.name,{x=pos[1],y=pos[2]},world_direction)
			issues[#issues+1]={position={x=(box.left_top.x+box.right_bottom.x)/2,y=(box.left_top.y+box.right_bottom.y)/2},reason={"mpp.output_balance_blocked"}}
		end
		entities[#entities+1]=spec
	end
	local connection={}
	for k,v in pairs(state) do connection[k]=v end
	connection.output_balance_choice=false
	connection.planned={}
	for _,piece in ipairs(state.planned or {}) do connection.planned[#connection.planned+1]=piece end
	for _,piece in ipairs(entities) do connection.planned[#connection.planned+1]=piece end
	for _,point in ipairs(layout.keepout) do
		local x,y=grid(point.x,point.y)
		connection.planned[#connection.planned+1]={name=state.belt_choice,grid_x=x,grid_y=y,direction=N}
	end
	connection.belt_input_targets={}
	for i,port in ipairs(layout.inputs) do
		local x,y=grid(port.x,port.y)
		connection.belt_input_targets[i]={x=x,y=y}
	end
	local ok,routes,diagnostic=route(connection)
	local combined={}
	for _,piece in ipairs(ok and routes or diagnostic and diagnostic.routes or {}) do combined[#combined+1]=piece end
	for _,piece in ipairs(entities) do combined[#combined+1]=piece end
	if not ok or #issues>0 then
		for _,issue in ipairs(diagnostic and diagnostic.issues or {}) do issues[#issues+1]=issue end
		return false,not ok and routes or {"mpp.output_balance_blocked"},{routes=combined,issues=issues}
	end
	state.balanced_output_count=outputs
	return true,combined
end

balancer.geometry = geometry
balancer.equipment = equipment
return balancer
