-- Appended to the mod in an isolated test copy by scripts/test-belt-capacity.py.
local cap_common=require("layouts.common")
local cap_capacity=require("mpp.belt_capacity")
local cap_matrix={}
for _,direction in ipairs{"west","north","east","south"} do
	for _,beacon in ipairs{false,true} do
		for _,fluid in ipairs{false,true} do
			cap_matrix[#cap_matrix+1]={direction=direction,beacon=beacon,fluid=fluid,upper=1.1}
		end
	end
end
for _,direction in ipairs{"west","north","east","south"} do
	cap_matrix[#cap_matrix+1]={direction=direction,beacon=true,fluid=false,upper=1.1,quality="legendary",bonus=0,belt="turbo-transport-belt"}
end
for _,direction in ipairs{"west","north","east","south"} do
 for _,fluid in ipairs{false,true} do
  cap_matrix[#cap_matrix+1]={direction=direction,beacon=false,fluid=fluid,upper=1.1,budget=4}
 end
end
local cap_player,cap_surface,cap_resources,cap_pending
local cap_index=0
local function cap_run(state)
	for _=1,10000 do
		local l=algorithm.layouts[state.layout_choice]
		local result=l[state._callback](l,state)
		if result==false then return end
		assert(result,"missing callback "..state._callback)
		if result~=true then state._callback=result end
	end
	error("capacity planning did not terminate")
end
local function cap_init()
	cap_player=game.get_player(1)
	conf.initialize_global(cap_player.index)
	cap_player.set_controller{type=defines.controllers.god}
	cap_surface=game.create_surface("capacity-integration-"..game.tick,{width=180,height=180,autoplace_controls={}})
	cap_surface.request_to_generate_chunks({0,0},3);cap_surface.force_generate_chunk_requests()
	for _,e in pairs(cap_surface.find_entities()) do e.destroy() end
	local tiles={};for x=-80,80 do for y=-80,80 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
	cap_surface.set_tiles(tiles)
	cap_player.teleport({0,0},cap_surface)
	cap_player.force.research_all_technologies()
	cap_player.force.mining_drill_productivity_bonus=4
	cap_player.force.belt_stack_size_bonus=3
	cap_resources={}
	for x=0,39 do for y=0,31 do
		cap_resources[#cap_resources+1]=cap_surface.create_entity{name="iron-ore",position={x+.5,y+.5},amount=100000}
	end end
	gui.show_interface(cap_player)
	assert(storage.players[cap_player.index].gui.workflow_version==16,"GUI migration was not applied")
	assert(storage.players[cap_player.index].gui.belt_load_toggle.valid,"capacity checkbox missing")
end
local function cap_start(v)
	local choices=storage.players[cap_player.index].choices
	local resource=v.fluid and "uranium-ore" or "iron-ore"
	cap_player.force.mining_drill_productivity_bonus=v.bonus or (v.fluid and 9 or 4)
	if cap_resources[1].name~=resource then
		for i,ore in ipairs(cap_resources) do
			local p=ore.position;ore.destroy()
			cap_resources[i]=cap_surface.create_entity{name=resource,position=p,amount=100000}
		end
	end
	choices.layout_choice="compact";choices.miner_choice="big-mining-drill";choices.direction_choice=v.direction
	choices.beacon_choice=v.beacon and "beacon" or "none";choices.beacon_quality_choice=v.quality or "normal"
	choices.beacon_module_choice="speed-module-3";choices.beacon_module_quality_choice=v.quality or "normal"
	choices.module_choice="speed-module-3";choices.module_quality_choice=v.quality or "normal";choices.miner_quality_choice=v.quality or "normal"
	choices.belt_choice=v.belt or "express-transport-belt";choices.belt_quality_choice="normal"
	choices.pole_choice="medium-electric-pole";choices.pole_quality_choice="normal";choices.lamp_choice=true
	choices.pipe_choice="pipe";choices.force_pipe_placement_choice=v.fluid
	choices.belt_load_min_choice=0.8;choices.belt_load_max_choice=v.upper
	choices.belt_merge_choice=true;choices.belt_planner_choice=false;choices.output_balance_choice=v.budget~=nil;choices.output_station_choice=false
	choices.output_belt_count_choice=v.budget or 8
	local state,err=algorithm.on_player_selected_area{player_index=cap_player.index,surface=cap_surface,entities=cap_resources,preview_only=true}
	assert(state,helpers.table_to_json(err or {}))
	cap_run(state)
	log("CAPACITY PLAN "..helpers.table_to_json{case=v,layout=state.layout_choice,miners=#state.best_attempt.miners,
		belts=#state.belts,error=state.preview_error,passes=state._capacity_pass})
	if state.preview_error then helpers.write_file("capacity-failed.json",helpers.table_to_json{coords=state.coords,
		issues=state._preview_issues,belts=state.builder_belts,poles=state.builder_power_poles,pipes=state.builder_pipes,
		beacons=state.builder_beacons},false) end
	assert(not state.preview_error,helpers.table_to_json(state.preview_error or {}))
	assert(state.layout_choice=="capacity_rows","fixture did not exercise splitting")
	if v.budget then
  local count=0;for _,b in ipairs(state.belts) do if b.is_output then count=count+1 end end
  assert(count<=v.budget,"automatic collection splitting exceeds output count")
  assert(state.preview_warning and state.output_belt_count_choice==v.budget,"fixed count lost its bottleneck warning")
 else assert(not cap_capacity.overloaded(state),"split belt exceeds load limit") end
	assert(cap_surface.count_entities_filtered{type="entity-ghost"}==0,"preview placed ghosts")
	local entities,drills,belts={},{},{}
	local function key(p) return math.floor(p.x)..","..math.floor(p.y) end
	for _,spec in ipairs(state._preview_specs) do if spec.name=="entity-ghost" then
		assert(cap_surface.can_place_entity{name=spec.inner_name,position=spec.position,direction=spec.direction,force=cap_player.force},
			"collision: "..helpers.table_to_json(spec))
		local e=assert(cap_surface.create_entity{name=spec.inner_name,position=spec.position,direction=spec.direction,
			quality=spec.quality,type=spec.type,force=cap_player.force})
		entities[#entities+1]=e
		if e.type=="mining-drill" then
			drills[#drills+1]=e;e.get_module_inventory().insert{name=choices.module_choice,quality=choices.module_quality_choice,count=#e.get_module_inventory()}
		elseif e.type=="beacon" then e.get_module_inventory().insert{name=choices.beacon_module_choice,quality=choices.beacon_module_quality_choice,count=#e.get_module_inventory()}
		elseif e.type=="transport-belt" or e.type=="underground-belt" then belts[key(e.position)]=e end
	end end
	cap_pending={state=state,entities=entities,drills=drills,belts=belts,v=v}
end
local function cap_check()
	local state=cap_pending.state
	local function key(p) return math.floor(p.x)..","..math.floor(p.y) end
	local function world(x,y)
		local c=state.coords;local p=mpp_util.revert_world(c.gx,c.gy,state.direction_choice,x,y,c.tw,c.th)
		return {x=p[1],y=p[2]}
	end
	local destinations,expected={},{}
	for i,belt in ipairs(state.belts) do if belt.is_output then
		destinations[key(world(belt.x_start,belt.y))]=i
		for _,lane in ipairs{belt.lane1 or {},belt.lane2 or {}} do
			for _,m in ipairs(lane) do expected[key(world(m.origin_x,m.origin_y))]=i end
		end
	end end
	local network
	for _,e in ipairs(cap_pending.entities) do
		if e.type=="mining-drill" or e.type=="beacon" or e.type=="electric-pole" then
			assert(e.electric_network_id,"no power for "..e.name.." "..key(e.position))
			network=network or e.electric_network_id
			assert(network==e.electric_network_id,"disconnected power grid")
		elseif e.type=="underground-belt" then assert(e.underground_belt_neighbour,"unpaired underground") end
	end
	local fluid_segment
	for _,drill in ipairs(cap_pending.drills) do
		local first=assert(cap_pending.belts[key(drill.drop_position)],"missing drill receiving belt")
		local queue,seen,reached,head={first},{},{},1
		while queue[head] do
			local e=queue[head];head=head+1
			if not seen[e.unit_number] then
				seen[e.unit_number]=true
				local out=destinations[key(e.position)]
				if out then reached[out]=true
				elseif e.type=="underground-belt" and e.belt_to_ground_type=="input" then queue[#queue+1]=e.underground_belt_neighbour
				else for _,b in pairs(e.belt_neighbours.outputs) do queue[#queue+1]=b end end
			end
		end
		assert(table_size(reached)==1 and reached[expected[key(drill.position)]],"drill does not reach its independent outlet")
		if cap_pending.v.fluid then
			local segment=drill.get_fluid_segment_id(1)
			assert(segment~=0,"disconnected drill fluid input")
			fluid_segment=fluid_segment or segment
			assert(fluid_segment==segment,"drills have separate fluid networks")
		end
	end
	for _,m in ipairs(state.best_attempt.miners) do
		local pos=world(m.origin_x,m.origin_y)
		local e
		for _,drill in ipairs(cap_pending.drills) do if key(drill.position)==key(pos) then e=drill;break end end
		assert(e,"planned drill missing from native placement")
		local rate=e.prototype.mining_speed/prototypes.entity[state.resource_counts[1].name].mineable_properties.mining_time
			*(1+e.speed_bonus)*(1+e.productivity_bonus)
		assert(math.abs(rate-cap_common.get_mining_drill_production_from_state(state,nil,m))<1e-6,"native production differs from capacity estimate")
	end
	for _,e in ipairs(cap_pending.entities) do e.destroy() end
	for _,r in pairs(state._render_objects) do if r.valid then r.destroy() end end
	if state._preview_rectangle and state._preview_rectangle.valid then state._preview_rectangle.destroy() end
	cap_pending=nil
	log("CAPACITY PASS "..cap_index)
end
local function cap_snapshot(specs)
	local result={}
	for _,s in ipairs(specs) do
		result[#result+1]=helpers.table_to_json{name=s.inner_name,position=s.position,direction=s.direction,quality=s.quality,type=s.type,items=s.insert_plan}
	end
	table.sort(result);return table.concat(result,"\n")
end
local function cap_regressions()
	local d=storage.players[cap_player.index];local c=d.choices
	c.beacon_choice="none";c.module_choice="none";c.miner_choice="electric-mining-drill";c.direction_choice="west"
	c.miner_quality_choice="normal";c.module_quality_choice="normal";c.belt_choice="express-transport-belt"
	c.belt_planner_choice=false;c.output_balance_choice=false;c.output_station_choice=false;c.force_pipe_placement_choice=false
	cap_player.force.mining_drill_productivity_bonus=0
	local function plan()
		local s=assert(algorithm.on_player_selected_area{player_index=cap_player.index,surface=cap_surface,entities=cap_resources,preview_only=true})
		cap_run(s);preview.dispose_task(s);return s
	end
	for _,name in ipairs{"simple","compact","super_compact","sparse","pipe","logistics"} do
		c.layout_choice=name;c.belt_merge_choice=false;c.belt_load_min_choice=0
		local before=plan();assert(not before.preview_error,"baseline failed: "..name)
		c.belt_merge_choice=true
		local after=plan();assert(not after.preview_error,"unchanged layout failed: "..name)
		assert(cap_snapshot(before._preview_specs)==cap_snapshot(after._preview_specs),"low-load/off regression: "..name)
	end
	c.layout_choice="compact";c.belt_load_min_choice=0
	local unmerged=plan()
	c.belt_load_min_choice=0.8
	local merged=plan()
	local function outputs(s) local n=0;for _,b in ipairs(s.belts) do if b.is_output then n=n+1 end end;return n end
	assert(not merged.preview_error and outputs(merged)<outputs(unmerged),"lower load bound did not enable merging")
	assert(not cap_capacity.overloaded(merged),"merging exceeded upper load bound")
	c.layout_choice="compact";c.miner_choice="big-mining-drill";c.module_choice="speed-module-3"
	cap_player.force.mining_drill_productivity_bonus=0
	local reference=plan()
	cap_player.force.mining_drill_productivity_bonus=32/cap_common.get_mining_drill_production_from_state(reference)-1
	c.belt_load_max_choice=1;local strict=plan();assert(not strict.preview_error,"100% limit failed")
	c.belt_load_max_choice=1.1;local tolerant=plan();assert(not tolerant.preview_error,"110% limit failed")
	assert(not cap_capacity.overloaded(strict) and not cap_capacity.overloaded(tolerant),"load bound broken")
	assert(#tolerant.belts<#strict.belts,"maximum load setting did not change grouping")
	cap_player.force.mining_drill_productivity_bonus=100
	local single=plan();assert(single.preview_error and single.preview_error[1]=="mpp.belt_capacity_single","single-drill limit missed")
	c.miner_choice="electric-mining-drill";cap_player.force.mining_drill_productivity_bonus=5
	local space=plan();assert(space.preview_error and space.preview_error[1]=="mpp.belt_capacity_space","lost ore was silently accepted")
	c.miner_choice="big-mining-drill";cap_player.force.mining_drill_productivity_bonus=4
	c.output_balance_choice=true;c.output_belt_count_choice=1
	local downstream=plan();assert(not downstream.preview_error and downstream.preview_warning and downstream.output_belt_count_choice==1,"fixed output cap should warn and allow placement")
	c.output_station_choice=true;c.output_wagon_count_choice=1;c.output_loading_side_choice="single"
	local station=plan();assert(not station.preview_error and station.preview_warning,"station capacity should warn and allow placement")
	c.output_station_choice=false;c.output_balance_choice=false;c.belt_planner_choice=true
	gui.show_interface(cap_player)
	d.gui.workflow_version=15;gui.show_interface(cap_player)
	assert(d.gui.workflow_version==16 and d.gui.belt_load_toggle.state and d.gui.belt_load_fields.max.text=="1.1","GUI migration lost choices")
	log("CAPACITY REGRESSIONS PASS: six disabled/in-range layouts, lower-bound merging, upper-bound splitting, single-drill limit, ore coverage, fixed outputs, station, GUI migration")
	script.get_event_handler(defines.events.on_player_selected_area){player_index=cap_player.index,item="resource-outpost-planner",surface=cap_surface,entities=cap_resources}
end
local cap_phase,cap_expected,cap_count=0,{},0
local function cap_key(name,p,d,q,kind) return table.concat({name,p.x,p.y,d or 0,q or "normal",kind or ""},":") end
local function cap_click(element)
	script.get_event_handler(defines.events.on_gui_click){player_index=cap_player.index,element=element,button=defines.mouse_button_type.left}
end
local function cap_workflow()
	local d=storage.players[cap_player.index]
	if cap_phase==0 then cap_regressions();cap_phase=1;return end
	if #storage.tasks>0 or d.preview and d.preview.refresh_at then return end
	if cap_phase==1 then
		assert(d.preview.ready,"initial GUI preview failed")
		local field=d.gui.belt_load_fields.max
		field.text="0";script.get_event_handler(defines.events.on_gui_text_changed){player_index=cap_player.index,element=field}
		assert(d.belt_load_invalid and not d.gui.preview_apply.enabled,"invalid range did not block Apply")
		field.text="0.7";script.get_event_handler(defines.events.on_gui_text_changed){player_index=cap_player.index,element=field}
		assert(d.belt_load_invalid and not d.gui.preview_apply.enabled,"reversed range did not block Apply")
		field.text="1.1";script.get_event_handler(defines.events.on_gui_text_changed){player_index=cap_player.index,element=field}
		assert(not d.belt_load_invalid,"valid range not recovered")
		cap_phase=2
	elseif cap_phase==2 then
		assert(d.preview.ready,"valid range did not rebuild")
		assert(input_mode.output(d,cap_player),"cannot activate the output cursor")
		d.gui.output_balance_toggle.state=true
		script.get_event_handler(defines.events.on_gui_checked_state_changed){player_index=cap_player.index,element=d.gui.output_balance_toggle}
		assert(not d.preview.error and d.preview.refresh_at,"fixed output cap prevented replanning")
		assert(#cap_player.cursor_stack.get_blueprint_entities()==1,"output count changed without updating the held blueprint")
		d.gui.output_balance_toggle.state=false
		script.get_event_handler(defines.events.on_gui_checked_state_changed){player_index=cap_player.index,element=d.gui.output_balance_toggle}
		assert(#cap_player.cursor_stack.get_blueprint_entities()==d.preview.belt_specification.count,"turning balancing off retained the old cursor count")
		assert(preview.set_belt_target(d,{position={x=-85,y=18},direction=defines.direction.west}),"output targeting failed")
		cap_phase=3
	elseif cap_phase==3 then
		assert(d.preview.ready,helpers.table_to_json(d.preview.error or {}))
		-- Check routing first, then apply the mine alone so the output-only test
		-- connects free outlets rather than colliding with an existing output route.
		d.choices.belt_planner_choice=false;preview.request(d);cap_phase=31
	elseif cap_phase==31 then
		assert(d.preview.ready,helpers.table_to_json(d.preview.error or {}))
		for _,s in ipairs(d.preview.specs) do if s.name=="entity-ghost" then
			local k=cap_key(s.inner_name,s.position,s.direction,s.quality,s.type)
			assert(not cap_expected[k],"duplicate preview entity")
			cap_expected[k]=true;cap_count=cap_count+1
		end end
		cap_click(d.gui.preview_apply)
		assert(d.preview.applying and not d.gui.belt_load_toggle.enabled,"capacity can change during Apply")
		cap_phase=4
	elseif cap_phase==4 then
		assert(not d.preview,"Apply did not finish")
		local seen,count={},0
		for _,e in pairs(cap_surface.find_entities_filtered{type="entity-ghost"}) do
			local k=cap_key(e.ghost_name,e.position,e.direction,e.quality.name,e.ghost_type=="underground-belt" and e.belt_to_ground_type or nil)
			assert(cap_expected[k] and not seen[k],"applied entity differs from preview")
			seen[k]=true;count=count+1
		end
		assert(count==cap_count,"Apply lost preview entities")
		assert(d.last_state.belt_merge_choice and cap_capacity.output_warning(d.last_state,{output_balance_choice=true,output_belt_count_choice=1}),"applied state lost capacity constraints")
		d.choices.output_balance_choice=true;d.choices.output_belt_count_choice=1
		d.choices.belt_planner_choice=true
		assert(input_mode.begin_output_preview(d,cap_player),"applied output preview failed")
		assert(not d.gui.belt_load_toggle.enabled,"collection controls enabled for output-only changes")
		assert(preview.set_belt_target(d,{position={x=-60,y=18},direction=defines.direction.west}))
		cap_phase=5
	elseif cap_phase==5 then
		assert(d.preview.ready and not d.preview.error and d.preview.warning,"applied output bottleneck should warn without blocking: "..helpers.table_to_json{ready=d.preview.ready,error=d.preview.error,warning=d.preview.warning})
		cap_click(d.gui.preview_apply)
		assert(not d.preview and d.last_state.balanced_output_count==1,"warning prevented output-only Apply")
		cap_click(d.gui.undo_button)
		assert(cap_surface.count_entities_filtered{type="entity-ghost"}==0,"Undo left capacity entities")
		log("CAPACITY WORKFLOW PASS: invalid/valid range input, output routing, Apply parity ("..cap_count.." entities), applied-output capacity, Undo")
		log("CAPACITY COMPLETE "..cap_index);script.on_nth_tick(19,nil)
	end
end
script.on_nth_tick(19,function()
	if not cap_player then cap_init() end
	if cap_pending then cap_check() end
	if cap_index==#cap_matrix then cap_workflow();return end
	cap_index=cap_index+1;cap_start(cap_matrix[cap_index])
end)
