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
-- Extra geometry cases exercise short tunnels, ordinary drills and unmerged feeds.
for _,miner in ipairs{"big-mining-drill","electric-mining-drill"} do
	for _,belt in ipairs{"transport-belt","fast-transport-belt","express-transport-belt"} do
		cap_matrix[#cap_matrix+1]={direction="west",beacon=false,fluid=false,upper=1.1,miner=miner,belt=belt,bonus=miner=="big-mining-drill" and 1 or 2,allow_space=miner=="electric-mining-drill"}
	end
end
cap_matrix[#cap_matrix+1]={direction="east",beacon=false,fluid=false,upper=1.1,lower=0}
cap_matrix[#cap_matrix+1]={direction="south",beacon=true,fluid=true,upper=1.1,lower=0.35}
cap_matrix[#cap_matrix+1]={direction="west",beacon=false,fluid=false,upper=1.1,lower=0,budget=32,no_merge=true}
-- Default/off layouts must use facing pairs too, across all orientations and
-- optional fluid/beacon infrastructure, not just the high-load split fallback.
for _,direction in ipairs{"west","north","east","south"} do
 for _,beacon in ipairs{false,true} do for _,fluid in ipairs{false,true} do
  cap_matrix[#cap_matrix+1]={direction=direction,beacon=beacon,fluid=fluid,upper=1.1,auto_belts=false}
 end end
end
if cap_case_limit then for i=#cap_matrix,cap_case_limit+1,-1 do cap_matrix[i]=nil end end
if cap_visual then cap_matrix={cap_matrix[1]} end
local cap_player,cap_surface,cap_resources,cap_pending
local cap_index=0
local function cap_run(state)
	local total=helpers.create_profiler()
	local stages={}
	for _=1,10000 do
		local l=algorithm.layouts[state.layout_choice]
		local name=state._callback
		local timer=stages[name]
		if not timer then timer=helpers.create_profiler(true);stages[name]=timer end
		timer.restart()
		if cap_fresh_grid and name=="initialize_capacity_layout" then state.grid=nil;state.resource_tiles=nil end
		local result=l[name](l,state)
		timer.stop()
		if result==false then
			total.stop()
			log{"", "CAPACITY TIMING total ", total}
			for k,v in pairs(stages) do log{"", "CAPACITY STAGE "..k.." ",v} end
			return
		end
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
	assert(storage.players[cap_player.index].gui.workflow_version>=20,"GUI migration was not applied")
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
	for _,ore in ipairs(cap_resources) do ore.amount=100000 end
	choices.layout_choice="compact";choices.miner_choice=v.miner or "big-mining-drill";choices.direction_choice=v.direction
	choices.beacon_choice=v.beacon and "beacon" or "none";choices.beacon_quality_choice=v.quality or "normal"
	choices.beacon_module_choice="speed-module-3";choices.beacon_module_quality_choice=v.quality or "normal"
	choices.module_choice="speed-module-3";choices.module_quality_choice=v.quality or "normal";choices.miner_quality_choice=v.quality or "normal"
	choices.belt_choice=v.belt or "express-transport-belt";choices.belt_quality_choice="normal"
	choices.pole_choice="medium-electric-pole";choices.pole_quality_choice="normal";choices.lamp_choice=true
	choices.pipe_choice="pipe";choices.force_pipe_placement_choice=v.fluid
	choices.belt_load_min_choice=v.lower or 0.8;choices.belt_load_max_choice=v.upper
	choices.belt_merge_choice=v.auto_belts~=false;choices.belt_planner_choice=false;choices.output_balance_choice=v.budget~=nil;choices.output_station_choice=false
	choices.output_belt_count_choice=v.budget or 8
	local state,err=algorithm.on_player_selected_area{player_index=cap_player.index,surface=cap_surface,entities=cap_resources,preview_only=true}
	assert(state,helpers.table_to_json(err or {}))
	cap_run(state)
	log("CAPACITY PLAN "..helpers.table_to_json{case=v,layout=state.layout_choice,miners=#state.best_attempt.miners,
		belts=#state.belts,error=state.preview_error,passes=state._capacity_pass,gap=state._capacity_gap,compact=state._capacity_compact,separate_power=state._capacity_separate_power,fallback=state._capacity_route_failure,entities=#state.builder_belts})
	if state.preview_error then helpers.write_file("capacity-failed.json",helpers.table_to_json{coords=state.coords,
		issues=state._preview_issues,belts=state.builder_belts,poles=state.builder_power_poles,pipes=state.builder_pipes,
		beacons=state.builder_beacons},false) end
	if v.allow_space and state.preview_error then
		assert(state.preview_error and state.preview_error[1]=="mpp.belt_capacity_space","infeasible receiving lanes must report space without crashing")
		preview.dispose_task(state)
		log("CAPACITY EXPECTED SPACE "..cap_index)
		return
	end
	assert(not state.preview_error,helpers.table_to_json(state.preview_error or {}))
	assert(state.layout_choice=="capacity_rows","fixture did not exercise splitting")
	helpers.write_file("capacity-case-"..cap_index..".json",helpers.table_to_json(state._preview_specs),false)
	if v.budget then
  local count=0;for _,b in ipairs(state.belts) do if b.is_output then count=count+1 end end
  if not state._capacity_tight_big then assert(count<=v.budget,"automatic collection splitting exceeds output count") end
  -- Big compact rows retain independent feeds; the final output stage enforces this explicit budget.
  assert(state.output_belt_count_choice==v.budget,"fixed output count changed")
  if not v.no_merge then assert(state.preview_warning,"fixed count lost its bottleneck warning") end
 elseif state._capacity_tight_big then
  assert(state._capacity_gap<=2 and not state._capacity_separate_power,"big compact drill spacing exceeds two tiles")
  if choices.belt_merge_choice and cap_capacity.overloaded(state) then
   assert(state.preview_warning and state.preview_warning[1]=="mpp.belt_capacity_dense","spacing cap hides belt overload")
  end
 else assert(not cap_capacity.overloaded(state),"split belt exceeds load limit") end
	if v.no_merge then for _,belt in ipairs(state.belts) do
  -- Side-loading inside an independent big-drill outlet is collection, not
  -- merging two completed outputs. A zero lower bound must retain both buses.
  assert(belt.is_output or state._capacity_tight_big and belt.capacity_target,
   "unused output budget overrides the zero merge threshold")
 end end
	if state._capacity_tight_big then
  assert(state._capacity_paired,"big compact reverted to single-facing rows")
  local directions,dual={},0
  for _,m in ipairs(state.best_attempt.miners) do
   local direction=m.line%2==1 and defines.direction.south or defines.direction.north
   assert(m.direction==direction,"adjacent big-drill rows do not face their shared corridor")
   directions[m.direction]=true
  end
  assert(table_size(directions)==2,"big compact has only one mining direction")
  for i,lane in ipairs(state.best_attempt.lane_layout) do if i>1 then
   local gap=lane.y-state.best_attempt.lane_layout[i-1].y-state.miner.size
   assert(i%2==0 and gap>=1 and gap<=(choices.belt_merge_choice and 2 or 1)
    or i%2==1 and gap==0,"facing pairs do not pack back-to-back")
  end end
  for _,b in ipairs(state.belts) do
   for side,lane in ipairs{b.lane1,b.lane2} do for _,m in ipairs(lane) do
    assert(m.direction==(side==1 and defines.direction.south or defines.direction.north),"outlet sides mix facing rows")
   end end
   if #b.lane1>0 and #b.lane2>0 then dual=dual+1 end
  end
  assert(dual>0,"facing rows still use separate single-sided outlets")
 end
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
			drills[#drills+1]=e;if v.fluid then e.insert_fluid{name="sulfuric-acid",amount=100} end;e.get_module_inventory().insert{name=choices.module_choice,quality=choices.module_quality_choice,count=#e.get_module_inventory()}
		elseif e.type=="beacon" then e.get_module_inventory().insert{name=choices.beacon_module_choice,quality=choices.beacon_module_quality_choice,count=#e.get_module_inventory()}
		elseif e.type=="transport-belt" or e.type=="underground-belt" then belts[key(e.position)]=e end
	end end
	local supply=cap_surface.create_entity{name="electric-energy-interface",position={-60,-60},force=cap_player.force}
	local supply_pole=cap_surface.create_entity{name="big-electric-pole",position={-60,-58},force=cap_player.force}
	supply.power_production=1000000000;supply.electric_buffer_size=1000000000;supply.energy=1000000000
	for _,e in ipairs(entities) do if e.type=="electric-pole" then
		assert(supply_pole.get_wire_connector(defines.wire_connector_id.pole_copper,true).connect_to(
			e.get_wire_connector(defines.wire_connector_id.pole_copper,true),false,defines.wire_origin.script))
		break
	end end
	cap_pending={ready_tick=game.tick+120,state=state,entities=entities,drills=drills,belts=belts,v=v,supply=supply,supply_pole=supply_pole}
end
local function cap_check()
	local state=cap_pending.state
	local function key(p) return math.floor(p.x)..","..math.floor(p.y) end
	local function world(x,y)
		local c=state.coords;local p=mpp_util.revert_world(c.gx,c.gy,state.direction_choice,x,y,c.tw,c.th)
		return {x=p[1],y=p[2]}
	end
	if state._capacity_tight_big then
		for _,belt in ipairs(state.belts) do if belt.capacity_target then
			local target=state.belts[belt.capacity_target]
			local junction=assert(cap_pending.belts[key(world(target.x2,belt.source_y))],"missing side-loading junction")
			assert(junction.belt_shape=="straight" and #junction.belt_neighbours.inputs>=2,
				"native side-loading junction curves onto the occupied belt side")
		end end
	end
	local destinations,expected={},{}
	for i,belt in ipairs(state.belts) do if belt.is_output then
		destinations[key(world(belt.x_start,belt.y))]=i
		for _,lane in ipairs{belt.lane1 or {},belt.lane2 or {}} do
			for _,m in ipairs(lane) do expected[key(world(m.origin_x,m.origin_y))]=i end
		end
	end end
	local network
	local poles,coverage={},{}
	local counts={miners=0,lamps=0,beacons=0,poles=0,uncovered=0}
	for _,e in ipairs(cap_pending.entities) do if e.type=="electric-pole" then
		local radius=e.prototype.get_supply_area_distance(e.quality.name)
		poles[#poles+1]={entity=e,radius=radius};counts.poles=counts.poles+1
	end end
	for _,e in ipairs(cap_pending.entities) do
		if e.type=="mining-drill" or e.type=="beacon" or e.type=="electric-pole" or e.type=="lamp" then
			assert(e.electric_network_id,"no power for "..e.name.." "..key(e.position))
			network=network or e.electric_network_id
			assert(network==e.electric_network_id,"disconnected power grid")
			if e.type~="electric-pole" then
				assert(e.is_connected_to_electric_network(),"no powered network for "..e.name.." "..key(e.position))
				assert(e.energy>0,"empty electrical buffer for "..e.name.." "..key(e.position))
				local box,covered=e.bounding_box,{}
				for _,pole in ipairs(poles) do
					local p,r=pole.entity.position,pole.radius
					if p.x+r>box.left_top.x and p.x-r<box.right_bottom.x
						and p.y+r>box.left_top.y and p.y-r<box.right_bottom.y then
						covered[#covered+1]=pole.entity.position
					end
				end
				assert(#covered>0,"no planned pole covers "..e.name.." "..key(e.position))
				local kind=e.type=="mining-drill" and "miners" or e.type=="beacon" and "beacons" or "lamps"
				counts[kind]=counts[kind]+1
				coverage[#coverage+1]={name=e.name,position=e.position,energy=e.energy,network=e.electric_network_id,poles=covered}
			end
		elseif e.type=="underground-belt" then assert(e.underground_belt_neighbour,"unpaired underground") end
	end
	helpers.write_file("capacity-power-"..cap_index..".json",helpers.table_to_json{counts=counts,consumers=coverage},false)
	log("CAPACITY POWER "..cap_index.." "..helpers.table_to_json(counts))
	local fluid_segment
	for _,drill in ipairs(cap_pending.drills) do
		local first=assert(cap_pending.belts[key(drill.drop_position)],"missing drill receiving belt")
		assert(drill.drop_target==first,"native drill receiving target: "..helpers.table_to_json{position=drill.position,receiver=first.name,receiver_type=first.type=="underground-belt" and first.belt_to_ground_type or nil,target=drill.drop_target and drill.drop_target.name,energy=drill.energy,status=drill.status})
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
	cap_pending.supply.destroy();cap_pending.supply_pole.destroy()
	if cap_visual then
		if cap_power_visual then
			for _,pole in ipairs(poles) do
				local p,r=pole.entity.position,pole.radius
				rendering.draw_rectangle{surface=cap_surface,left_top={p.x-r,p.y-r},right_bottom={p.x+r,p.y+r},
					color={r=0.08,g=0.25,b=0.5,a=0.24},filled=true,draw_on_ground=true}
				rendering.draw_rectangle{surface=cap_surface,left_top={p.x-r,p.y-r},right_bottom={p.x+r,p.y+r},
					color={r=0.2,g=0.65,b=1,a=0.8},width=2,filled=false,draw_on_ground=true}
			end
			for _,drill in ipairs(cap_pending.drills) do
				rendering.draw_rectangle{surface=cap_surface,left_top=drill.bounding_box.left_top,right_bottom=drill.bounding_box.right_bottom,
					color={r=0.1,g=1,b=0.2,a=0.9},width=2,filled=false}
			end
		end
		cap_surface.daytime=0;cap_surface.freeze_daytime=true;cap_surface.destroy_decoratives{}
		game.take_screenshot{surface=cap_surface,position={18,16},resolution={1800,1250},zoom=0.85,
			show_gui=false,show_entity_info=false,path="capacity-layout.png",anti_alias=true}
		log("CAPACITY SCENE COMPLETE")
		script.on_nth_tick(19,nil)
		return
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
	-- Big compact drills use the single-corridor router even below the split
	-- threshold. Enabling the controller alone must not reserve a second tile.
	c.layout_choice="compact";c.miner_choice="big-mining-drill";c.belt_choice="turbo-transport-belt";c.belt_load_max_choice=100
	for _,beacon in ipairs{"none","beacon"} do
		c.beacon_choice=beacon;c.belt_merge_choice=false
		local before=plan();assert(not before.preview_error,"big single-corridor baseline failed")
		c.belt_merge_choice=true
		local after=plan();assert(not after.preview_error,"big low-load corridor failed")
		assert(before._capacity_tight_big and after._capacity_tight_big,"big compact skipped its inline router")
		assert(before._capacity_gap==1 and after._capacity_gap==1,"low-load/off big layout reserved a second tile")
		assert(cap_snapshot(before._preview_specs)==cap_snapshot(after._preview_specs),"enabling automatic belts widened an in-range big layout")
	end
	c.miner_choice="electric-mining-drill";c.beacon_choice="none";c.belt_choice="express-transport-belt";c.belt_load_max_choice=1.1

	c.layout_choice="compact";c.belt_load_min_choice=0
	local unmerged=plan()
	c.belt_load_min_choice=0.8
	local merged=plan()
	local function outputs(s) local n=0;for _,b in ipairs(s.belts) do if b.is_output then n=n+1 end end;return n end
	assert(not merged.preview_error and outputs(merged)<outputs(unmerged),"lower load bound did not enable merging")
	assert(not cap_capacity.overloaded(merged),"merging exceeded upper load bound")
	c.layout_choice="compact";c.miner_choice="big-mining-drill";c.module_choice="speed-module-3"
	cap_player.force.mining_drill_productivity_bonus=0
	c.layout_choice="simple" -- The unrestricted layout still honors the throughput range before spacing.
	local reference=plan()
	cap_player.force.mining_drill_productivity_bonus=32/cap_common.get_mining_drill_production_from_state(reference)-1
	c.belt_load_max_choice=1;local strict=plan();assert(not strict.preview_error,"100% limit failed")
	c.belt_load_max_choice=1.1;local tolerant=plan();assert(not tolerant.preview_error,"110% limit failed")
	assert(not cap_capacity.overloaded(strict) and not cap_capacity.overloaded(tolerant),"load bound broken")
	assert(#tolerant.belts<#strict.belts,"maximum load setting did not change grouping")
	c.layout_choice="compact"
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
	assert(d.gui.workflow_version>=20 and d.gui.belt_load_toggle.state and d.gui.belt_load_fields.max.text=="1.1","GUI migration lost choices")
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
	if #storage.tasks>0 or d.preview and (d.preview.refresh_at or d.preview.render_job or d.preview.output_job) then return end
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
	if cap_pending then
		if game.tick<cap_pending.ready_tick then return end
		cap_check();if cap_visual then return end
	end
	if cap_index==#cap_matrix then cap_workflow();return end
	cap_index=cap_index+1;cap_start(cap_matrix[cap_index])
end)
