local matrix_balancer=require("mpp.output_balancer")
local matrix_station=require("mpp.train_station")
local matrix_common=require("layouts.common")
local matrix_builder=require("mpp.builder")
local fixtures={}
local ticks,checks=0,0
local phase_ticks=4096

local function initialize_matrix()
	local force=game.get_player(1).force
	local surface=game.create_surface("balancer-matrix",{autoplace_controls={}})
	surface.request_to_generate_chunks({-64,-64},1);surface.force_generate_chunk_requests()
	local tiles={};for x=-68,-60 do for y=-68,-60 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end;surface.set_tiles(tiles)
	for _,e in pairs(surface.find_entities_filtered{area={{-68,-68},{-60,-60}}}) do e.destroy() end
	local state={player=game.get_player(1),surface=surface,coords={gx=-64,gy=-64,tw=32,th=32},direction_choice="west",
		preview_only=true,_preview_specs={}}
	local filtered=matrix_balancer.geometry(4,3,"express-transport-belt")
	local filter
	for _,p in ipairs(filtered.specs) do if p.filter then filter=p.filter end end
	assert(filter,"4-to-3 source filter was lost")
	local function filter_spec()
		return {name="express-splitter",grid_x=1.5,grid_y=1,direction=8,filter=filter,output_priority="left"}
	end
	matrix_builder.create_entity_builder(state)(filter_spec())
	assert(state._preview_specs[1].filter==filter,"preview lost filter")
	state.preview_only=false
	local ghost=assert(matrix_builder.create_entity_builder(state)(filter_spec()))
	assert(ghost.splitter_filter.name=="deconstruction-planner" and ghost.splitter_output_priority=="left","Apply lost filter")
	local _,built=ghost.revive{raise_revive=false}
	assert(built and built.splitter_filter.name=="deconstruction-planner" and built.splitter_output_priority=="left","revived splitter lost filter")
	built.destroy()
	local inventory=game.create_inventory(1)
	inventory[1].set_stack{name="blueprint"}
	local station=matrix_station.geometry(4,{output_wagon_count_choice=3,output_loading_side_choice="single"},"express-transport-belt")
	for _,dir in ipairs{0,4,8,12} do for _,mirror in ipairs{false,true} do
		inventory[1].set_blueprint_entities(matrix_station.cursor_entities(station,dir,mirror))
		local count=0
		for _,e in ipairs(inventory[1].get_blueprint_entities()) do if e.filter then
			count=count+1
			assert(e.filter.name=="deconstruction-planner" and e.output_priority==(mirror and "right" or "left"),"cursor lost filter")
		end end
		assert(count==1,"cursor filter count differs")
	end end
	inventory.destroy()
	log("BALANCER MATRIX FILTERS PASSED: preview, Apply, revival and eight cursor transforms")
	local specification=matrix_common.create_belt_planner_specification{
		belts={{is_output=true,x_start=2,y=1},{is_output=false,x_start=2,y=2},{is_output=true,x_start=2,y=3}},
		coords={gx=0,gy=0,tw=32,th=32},direction_choice="north",surface=surface,player=game.get_player(1),
		belt_choice="express-transport-belt",output_balance_choice=true,output_belt_count_choice=8}
	assert(specification.count==2,"mining rows were counted as output belts")
	assert(matrix_balancer.geometry(specification.count,8,"express-transport-belt").source_label=="2_8_balancer")
	for tier,belt in ipairs{"transport-belt","fast-transport-belt","express-transport-belt"} do
		for n=1,8 do for m=1,8 do
			local layout,err=matrix_balancer.geometry(n,m,belt)
			if not layout then
				assert(tier==1 and (n==5 and m==8 or n==6 and m==5 or n==7 and m==5 or n==8 and m==7)
					and err[1]=="mpp.output_balance_reference_equipment","unexpected missing template")
			else
				local index=#fixtures
				local ox,oy=64*(index%16),64*math.floor(index/16)
				local dir=((n+m+tier)%4)*4
				local fixture={label=belt..":"..n.."->"..m..":"..layout.source_label,n=n,m=m,inputs={},outputs={},counts={},sent={},entities={}}
				surface.request_to_generate_chunks({ox,oy},1);surface.force_generate_chunk_requests()
				for _,entity in pairs(surface.find_entities_filtered{area={{ox-24,oy-24},{ox+24,oy+24}}}) do entity.destroy() end
				local tiles={};for x=ox-24,ox+24 do for y=oy-24,oy+24 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
				surface.set_tiles(tiles)
				local function create(piece)
					local p=matrix_station.transform_piece(piece,dir,false)
					local spec={name=p.name,position={x=ox+p.x+.5,y=oy+p.y+.5},direction=p.direction,type=p.type,force=force}
					assert(surface.can_place_entity(spec),"collision: "..fixture.label.." "..helpers.table_to_json(spec))
					local e=assert(surface.create_entity(spec))
					fixture.entities[#fixture.entities+1]=e
					if p.input_priority then e.splitter_input_priority=p.input_priority end
					if p.output_priority then e.splitter_output_priority=p.output_priority end
					if p.filter then e.splitter_filter=p.filter end
					return e
				end
				local tunnels={}
				for _,piece in ipairs(layout.specs) do
					local e=create(piece)
					if piece.type=="input" then tunnels[#tunnels+1]=e end
					if piece.y==layout.output_y and piece.x>=0 and piece.x<m then fixture.outputs[piece.x+1]=e end
				end
				for _,tunnel in ipairs(tunnels) do assert(tunnel.underground_belt_neighbour,"unpaired underground: "..fixture.label) end
				for _,port in ipairs(layout.inputs) do fixture.inputs[#fixture.inputs+1]=create{name=belt,x=port.x,y=port.y,direction=8} end
				assert(#fixture.outputs==m and #fixture.inputs==n,fixture.label)
				for i=1,m do fixture.counts[i]=0 end
				for i=1,2*n do fixture.sent[i]=0 end
				fixtures[#fixtures+1]=fixture
			end
		end end
	end
	log("BALANCER MATRIX START: "..#fixtures.." native layouts; 2 mining outputs select literal 2_8_balancer")
end

script.on_event(defines.events.on_tick,function()
	if ticks==0 then initialize_matrix() end
	ticks=ticks+1
	local phase=math.floor((ticks-1)/phase_ticks)
	if phase>16 then return end
	local tick=(ticks-1)%phase_ticks+1
	for _,f in ipairs(fixtures) do
		if phase==0 or phase<=2*f.n then
			if tick==1 then
				for _,e in ipairs(f.entities) do for line=1,e.get_max_transport_line_index() do e.get_transport_line(line).clear() end end
			end
			if tick%8==0 then
				for input,e in ipairs(f.inputs) do for lane=1,2 do
					local id=2*(input-1)+lane
					if phase==0 or id==phase then
						if e.get_transport_line(lane).insert_at_back{name="iron-ore",count=1} then f.sent[id]=f.sent[id]+1 end
					end
				end end
			end
			for output,e in ipairs(f.outputs) do for lane=1,2 do
				f.counts[output]=f.counts[output]+e.get_transport_line(lane).remove_item{name="iron-ore",count=100}
			end end
			-- Lane filters intentionally retain items against a blocked half-lane.
			-- Measure steady flow after those buffers and feedback paths have filled.
			if tick==2048 then
				for i=1,f.m do f.counts[i]=0 end
				for i=1,2*f.n do f.sent[i]=0 end
			end
			if tick==phase_ticks then
				local total,sent,min,max=0,0,math.huge,0
				for _,v in ipairs(f.sent) do sent=sent+v end
				for _,v in ipairs(f.counts) do total=total+v;min=math.min(min,v);max=math.max(max,v) end
				local detail=f.label.." phase="..phase.." sent="..sent.." outputs="..helpers.table_to_json(f.counts)
				-- Compact non-TU source designs can restrict a single active input.
				assert(total>=64,"flow stalled: "..detail)
				assert(math.abs(total-sent)<=16,"flow did not stabilize: "..detail)
				assert(min>0 and max-min<=4,"unequal output: "..detail)
				checks=checks+1
				for i=1,f.m do f.counts[i]=0 end
				for i=1,2*f.n do f.sent[i]=0 end
			end
		end
	end
	if tick==phase_ticks then log("BALANCER MATRIX PHASE "..phase.." PASSED; checks="..checks) end
	if ticks==17*phase_ticks then log("BALANCER MATRIX COMPLETE: "..checks.." all-input and individual-input/lane flow checks") end
end)
