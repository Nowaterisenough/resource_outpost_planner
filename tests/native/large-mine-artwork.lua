-- Real asynchronous planner + native entities on isolated visual-test surfaces.
local large_common=require("layouts.common")
local large_cases={
 {id="01-compact-iron",ore="iron-ore",shape="lobed",direction="west",quality="normal",module="none",bonus=0,belt="turbo-transport-belt",outputs=24,dense=true},
 {id="02-staggered-copper",ore="copper-ore",shape="crescent",direction="south",quality="legendary",module="productivity-module-3",pole_quality="legendary",lamps=true,bonus=1,belt="turbo-transport-belt",outputs=32,dense=true},
 {id="03-beacon-tungsten",ore="tungsten-ore",shape="islands",direction="east",quality="normal",module="speed-module-3",bonus=4,belt="turbo-transport-belt",outputs=24,beacons=true},
 {id="04-piped-uranium",ore="uranium-ore",shape="branched",direction="north",quality="normal",module="speed-module-3",bonus=4,belt="express-transport-belt",outputs=24,fluid=true},
}
if large_case_overrides then large_cases=large_case_overrides end
if large_dense_matrix or large_capacity_matrix then
 local variants={}
 for _,c in ipairs(large_capacity_matrix and {large_cases[3],large_cases[4]} or {large_cases[1],large_cases[2]}) do for _,direction in ipairs{"north","east","south","west"} do
  local v=table.deepcopy(c);v.direction=direction;v.id=c.id.."-"..direction;variants[#variants+1]=v
 end end
 large_cases=variants
end
if large_case_filter then large_cases={large_cases[large_case_filter]} end
local large_phase,large_index,large_wait="start",0,0
local large_player,large_data,large_surface,large_resources,large_state,large_entities,large_drills,large_poles,large_supply,large_supply_pole
local large_results,large_report={},nil
local large_start_tick,large_timer,large_mine_state,large_failure
local large_flow,large_flow_start
local large_preview_complete=preview.complete
preview.complete=function(state)
 large_state=state
 return large_preview_complete(state)
end
local large_task=task_runner.mining_patch_task
 task_runner.mining_patch_task=function(state)
 if large_timer then large_timer.restart() end
 local result=large_task(state)
 if large_timer then large_timer.stop() end
 return result
end
local function large_key(p) return math.floor(p.x)..","..math.floor(p.y) end
local function large_shape(c,x,y)
 local a=math.atan2(y/72,x/96)
 local edge=1+.09*math.sin(7*a)+.05*math.cos(11*a)
 if c.shape=="lobed" then
  return (x/93)^2+(y/70)^2<edge^2 and not (x>35 and y>10 and y<31+10*math.sin(x/15))
   and not ((x+28)^2+(y+8)^2<55)
 elseif c.shape=="crescent" then
  return (x/96)^2+(y/79)^2<edge^2 and not (((x-75)/65)^2+((y+4)/60)^2<1)
 elseif c.shape=="islands" then
  local t=math.min(((x+50)/53)^2+((y+29)/43)^2,((x-7)/55)^2+((y-18)/59)^2,((x-63)/45)^2+((y+22)/40)^2)
  return t<1+.09*math.sin(x*.27+y*.21) and not ((x+10)^2+(y-6)^2<150)
 else
  local t=math.min(((x+53)/43)^2+((y+26)/61)^2,((x-7)/72)^2+((y-30)/39)^2,((x-59)/42)^2+((y+33)/49)^2)
  return t<1+.1*math.sin(x*.17-y*.19) and not (x>0 and x<26 and y<-28)
 end
end
local function large_capture(suffix,position,resolution,zoom)
 if large_headless then return end
 game.take_screenshot{surface=large_surface,position=position,resolution=resolution,zoom=zoom,
  show_gui=false,show_entity_info=false,anti_alias=true,path=large_cases[large_index].id.."-"..suffix..".png"}
end
local function large_begin()
 large_index=large_index+1
 local c=large_cases[large_index]
 if not c then
  helpers.write_file("large-mine-result.json",helpers.table_to_json(large_results),false)
  if not large_dense_matrix and not large_capacity_matrix then game.auto_save("large-mine-layouts") end
  large_phase="finish";large_wait=game.tick+90;return
 end
 game.speed=c.measure_lanes and 8 or 1
 large_player=game.get_player(1);conf.initialize_global(large_player.index)
 large_player.set_controller{type=defines.controllers.god}
 large_data=storage.players[large_player.index]
 large_data.choices=table.deepcopy(conf.default_config.choices)
 large_surface=game.create_surface(c.id,{width=1024,height=1024,autoplace_controls={},
  default_enable_all_autoplace_controls=false,
  autoplace_settings={entity={treat_missing_as_default=false,settings={}},decorative={treat_missing_as_default=false,settings={}}}})
 large_surface.request_to_generate_chunks({0,0},10);large_surface.force_generate_chunk_requests()
 for _,e in pairs(large_surface.find_entities()) do e.destroy() end
 local tiles={};for y=-450,450 do for x=-450,450 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 large_surface.set_tiles(tiles);large_surface.destroy_decoratives{}
 large_surface.daytime=0;large_surface.freeze_daytime=true
 large_player.teleport({0,0},large_surface)
 large_player.force.research_all_technologies();large_player.force.mining_drill_productivity_bonus=c.bonus
 large_player.force.belt_stack_size_bonus=c.stack_bonus or 3
 large_resources={}
 local min_amount,max_amount=math.huge,0
 for y=-100,100 do for x=-120,120 do
  if large_shape(c,x,y) then
   local density=(.5+.5*math.sin(x*.043+y*.027)*math.cos(y*.037-x*.019))^3
   local amount=math.floor(12000+880000*density)
   min_amount=math.min(min_amount,amount);max_amount=math.max(max_amount,amount)
   large_resources[#large_resources+1]=large_surface.create_entity{name=c.ore,position={x+.5,y+.5},amount=amount}
  end
 end end
 assert(#large_resources>10000,"fixture is not a huge irregular patch")
 local choices=large_data.choices
 choices.layout_choice=c.dense and "super_compact" or "compact";choices.mining_layout_choice=choices.layout_choice;choices.miner_choice="big-mining-drill"
 choices.direction_choice=c.direction;choices.miner_quality_choice=c.quality
 choices.module_choice=c.module;choices.module_quality_choice=c.module_quality or "normal"
 choices.beacon_choice=c.beacons and "beacon" or "none";choices.beacon_quality_choice=c.beacon_quality or "normal"
 choices.beacon_module_choice="speed-module-3";choices.beacon_module_quality_choice=c.beacon_module_quality or "normal"
 choices.belt_choice=c.belt;choices.belt_quality_choice="normal"
 choices.pole_choice=c.pole or "medium-electric-pole";choices.pole_quality_choice=c.pole_quality or "normal";choices.lamp_choice=c.lamps
 if choices.lamp_choice==nil then choices.lamp_choice=not c.dense end
 choices.pipe_choice="pipe";choices.force_pipe_placement_choice=c.fluid or false
 choices.belt_merge_choice=large_auto_belts~=false and c.auto_belts~=false
 choices.belt_load_min_choice=c.lower or .8;choices.belt_load_max_choice=c.upper or 1.1
 choices.belt_planner_choice=true;choices.output_balance_choice=c.balance~=false;choices.output_belt_count_choice=c.outputs
 choices.output_station_choice=false;choices.statistics_choice=false
 choices.terrain_mode_choice="avoid";choices.cliff_mode_choice="avoid";choices.remove_entities_choice=false
 gui.show_interface(large_player)
 large_report={case=c,auto_belts=choices.belt_merge_choice,ore_tiles=#large_resources,min_tile_amount=min_amount,max_tile_amount=max_amount}
 large_capture("ore",{0,0},{2400,1800},.30)
 large_timer=helpers.create_profiler(true);large_start_tick=game.tick
 assert(preview.select{player_index=large_player.index,surface=large_surface,entities=large_resources})
 large_phase="mine"
 log("LARGE MINE START "..c.id.." tiles="..#large_resources)
end
local function large_materialize()
 local c=large_cases[large_index]
 local specs=large_data.preview.specs
 helpers.write_file("large-specs-"..large_index..".json",helpers.table_to_json(specs),false)
 large_report.warning=large_data.preview.warning
 large_report.output_layout=large_state.layout_choice
 large_report.entities=#specs
 large_report.outputs=large_state.balanced_output_count
 if c.balance~=false then assert((large_state.balanced_output_count or c.outputs)<=c.outputs,"output cap exceeded") end
 preview.cancel(large_data,true)
 large_entities,large_drills,large_poles={},{},{}
 local counts={}
 for _,spec in ipairs(specs) do if spec.name=="entity-ghost" then
  if not large_surface.can_place_entity{name=spec.inner_name,position=spec.position,direction=spec.direction,force=large_player.force} then
   local collisions={}
   for _,b in pairs(large_surface.find_entities_filtered{area={{spec.position.x-1,spec.position.y-1},{spec.position.x+1,spec.position.y+1}}}) do
    if b.type~="resource" then collisions[#collisions+1]={name=b.name,position=b.position,direction=b.direction} end
   end
   local collision={case=c,spec=spec,blockers=collisions,report=large_report}
   log("LARGE COLLISION "..helpers.table_to_json(collision))
   helpers.write_file("large-mine-collision.json",helpers.table_to_json(collision),false)
   rendering.draw_rectangle{surface=large_surface,left_top={spec.position.x-1.5,spec.position.y-1.5},
    right_bottom={spec.position.x+1.5,spec.position.y+1.5},color={r=1,g=.05,b=.05,a=1},width=4,filled=false}
   large_capture("collision",spec.position,{1600,1000},2)
   large_failure="native collision: "..helpers.table_to_json(spec)
   large_phase="failure-delay";large_wait=game.tick+90;return
  end
  assert(large_surface.can_place_entity{name=spec.inner_name,position=spec.position,direction=spec.direction,force=large_player.force},
   "native collision: "..helpers.table_to_json(spec))
  local e=large_surface.create_entity{name=spec.inner_name,position=spec.position,direction=spec.direction,
   quality=spec.quality,type=spec.type,force=large_player.force}
  assert(e,"native creation failed: "..helpers.table_to_json(spec))
  large_entities[#large_entities+1]=e;counts[e.name]=(counts[e.name] or 0)+1
  if e.type=="mining-drill" then
   large_drills[#large_drills+1]=e
   assert(e.quality.name==c.quality,"native drill quality differs from requested settings")
   if c.module~="none" then
    local inventory=e.get_module_inventory()
    assert(inventory.insert{name=c.module,quality=c.module_quality or "normal",count=#inventory}==#inventory,"native drill module insertion failed")
   end
   if c.fluid then e.insert_fluid{name="sulfuric-acid",amount=100} end
  elseif e.type=="beacon" then
   local inventory=e.get_module_inventory()
   assert(inventory.insert{name="speed-module-3",quality=c.beacon_module_quality or "normal",count=#inventory}==#inventory,"native beacon module insertion failed")
  elseif e.type=="electric-pole" then large_poles[#large_poles+1]=e end
 end end
 large_report.counts=counts
 large_supply=large_surface.create_entity{name="electric-energy-interface",position={-260,-260},force=large_player.force}
 large_supply_pole=large_surface.create_entity{name="big-electric-pole",position={-260,-258},force=large_player.force}
 large_supply.power_production=1e13;large_supply.electric_buffer_size=1e13;large_supply.energy=1e13
 assert(large_supply_pole.get_wire_connector(defines.wire_connector_id.pole_copper,true).connect_to(
  large_poles[1].get_wire_connector(defines.wire_connector_id.pole_copper,true),false,defines.wire_origin.script))
 large_wait=game.tick+240;large_phase="audit"
end
local function large_audit()
 local belts,reverse,sinks,covered,towers={},{},{},{},{}
 for _,e in ipairs(large_entities) do if e.type=="beacon" then towers[#towers+1]=e end end
 local unpaired={}
 local counts={drills=#large_drills,poles=#large_poles,consumers=0,unpowered=0,uncovered=0,unpaired_underground=0,missing_drop_target=0,unreachable=0,ore_uncovered=0}
 local network,segments=nil,{}
 for _,e in ipairs(large_entities) do
  if e.type=="electric-pole" or e.type=="mining-drill" or e.type=="beacon" or e.type=="lamp" then
   network=network or e.electric_network_id
   if not e.electric_network_id or e.electric_network_id~=network then counts.unpowered=counts.unpowered+1 end
   if e.type~="electric-pole" then
    counts.consumers=counts.consumers+1
    if not e.is_connected_to_electric_network() or e.energy<=0 then counts.unpowered=counts.unpowered+1 end
    local box=e.bounding_box;local supplied=false
    for _,pole in ipairs(large_poles) do
     local r=pole.prototype.get_supply_area_distance(pole.quality.name);local p=pole.position
     if p.x+r>box.left_top.x and p.x-r<box.right_bottom.x and p.y+r>box.left_top.y and p.y-r<box.right_bottom.y then supplied=true;break end
    end
    if not supplied then counts.uncovered=counts.uncovered+1 end
   end
  end
  if e.type=="transport-belt" or e.type=="underground-belt" or e.type=="splitter" then
   belts[large_key(e.position)]=e
   local outgoing={}
   if e.type=="underground-belt" and e.belt_to_ground_type=="input" then
    if e.underground_belt_neighbour then outgoing[1]=e.underground_belt_neighbour else counts.unpaired_underground=counts.unpaired_underground+1 end
   else for _,b in pairs(e.belt_neighbours.outputs) do outgoing[#outgoing+1]=b end end
   if e.type=="underground-belt" and e.belt_to_ground_type=="output" and not e.underground_belt_neighbour then counts.unpaired_underground=counts.unpaired_underground+1 end
   if e.type=="underground-belt" and not e.underground_belt_neighbour then unpaired[#unpaired+1]={position=e.position,direction=e.direction,type=e.belt_to_ground_type} end
   if #outgoing==0 then sinks[#sinks+1]=e end
   for _,b in ipairs(outgoing) do local r=reverse[b.unit_number] or {};reverse[b.unit_number]=r;r[#r+1]=e end
  end
 end
 local c=large_cases[large_index]
 counts.side_loading_junctions=0
 if large_mine_state._capacity_tight_big then
  local coords=large_mine_state.coords
  for _,belt in ipairs(large_mine_state.belts) do if belt.capacity_target then
   local target=large_mine_state.belts[belt.capacity_target]
   local pos=mpp_util.revert_world(coords.gx,coords.gy,large_mine_state.direction_choice,target.x2,belt.source_y,coords.tw,coords.th)
   local junction=assert(belts[large_key{x=pos[1],y=pos[2]}],"missing native side-loading junction")
   assert(junction.belt_shape=="straight" and #junction.belt_neighbours.inputs>=2,"native side loading became a corner")
   counts.side_loading_junctions=counts.side_loading_junctions+1
  end end
 end
 if c.beacons then
  counts.beacon_uncovered=0;counts.beacons_per_drill_min=math.huge;counts.beacons_per_drill_max=0
  for _,drill in ipairs(large_drills) do
   local box,n=drill.bounding_box,0
   for _,tower in ipairs(towers) do
    local b=tower.bounding_box;local r=tower.prototype.get_supply_area_distance(tower.quality.name)
    if b.left_top.x-r<box.right_bottom.x and b.right_bottom.x+r>box.left_top.x
     and b.left_top.y-r<box.right_bottom.y and b.right_bottom.y+r>box.left_top.y then n=n+1 end
   end
   if n==0 then counts.beacon_uncovered=counts.beacon_uncovered+1 end
   counts.beacons_per_drill_min=math.min(counts.beacons_per_drill_min,n)
   counts.beacons_per_drill_max=math.max(counts.beacons_per_drill_max,n)
  end
  assert(counts.beacon_uncovered==0,"drills outside beacon coverage")
 end
 local axis=(c.direction=="west" or c.direction=="east") and "x" or "y"
 local sign=(c.direction=="west" or c.direction=="north") and -1 or 1
 local outer=-math.huge
 for _,e in ipairs(sinks) do outer=math.max(outer,sign*e.position[axis]) end
 local reached,queue,head={},{},1
 for _,e in ipairs(sinks) do if math.abs(sign*e.position[axis]-outer)<.01 then queue[#queue+1]=e end end
 counts.final_outputs=#queue
 assert(#queue==large_report.expected_outputs,"native final output count changed: "..#queue)

 while queue[head] do
  local e=queue[head];head=head+1
  if not reached[e.unit_number] then reached[e.unit_number]=true;for _,up in ipairs(reverse[e.unit_number] or {}) do queue[#queue+1]=up end end
 end
 local disconnected={}

 for _,drill in ipairs(large_drills) do
  local target=belts[large_key(drill.drop_position)]
  if not target or drill.drop_target~=target then counts.missing_drop_target=counts.missing_drop_target+1 end
  if not target or not reached[target.unit_number] then counts.unreachable=counts.unreachable+1;disconnected[#disconnected+1]={drill=drill.position,drop=drill.drop_position} end
  local area=drill.mining_area
  for y=math.floor(area.left_top.y),math.ceil(area.right_bottom.y)-1 do for x=math.floor(area.left_top.x),math.ceil(area.right_bottom.x)-1 do covered[x..","..y]=true end end
  if large_cases[large_index].fluid then segments[drill.get_fluid_segment_id(1)]=true end
 end
 for _,ore in ipairs(large_resources) do if not covered[large_key(ore.position)] then counts.ore_uncovered=counts.ore_uncovered+1 end end
 counts.terminal_belts=#sinks;counts.fluid_segments=table_size(segments)
 if counts.unreachable>0 then
  local stranded={}
  for _,b in pairs(belts) do if not reached[b.unit_number] then stranded[#stranded+1]={name=b.name,position=b.position,direction=b.direction,type=b.type=="underground-belt" and b.belt_to_ground_type or nil} end end
  local terminal={};for _,b in ipairs(sinks) do terminal[#terminal+1]=b.position end
  helpers.write_file("large-disconnected.json",helpers.table_to_json{drills=disconnected,belts=stranded,sinks=terminal},false)
 end
 large_report.audit=counts
 if #unpaired>0 then helpers.write_file("large-unpaired.json",helpers.table_to_json(unpaired),false) end
 local left,top,right,bottom=math.huge,math.huge,-math.huge,-math.huge
 for _,e in ipairs(large_entities) do local b=e.bounding_box;left=math.min(left,b.left_top.x);top=math.min(top,b.left_top.y);right=math.max(right,b.right_bottom.x);bottom=math.max(bottom,b.right_bottom.y) end
 large_report.bounds={left=left,top=top,right=right,bottom=bottom}
 large_results[#large_results+1]=large_report
 helpers.write_file("large-mine-result.json",helpers.table_to_json(large_results),false)
 log("LARGE MINE AUDIT "..helpers.table_to_json(large_report))
 assert(counts.unpowered==0 and counts.uncovered==0,"native power coverage failed")
 assert(counts.unpaired_underground==0 and counts.missing_drop_target==0 and counts.unreachable==0,"native belt connection failed")
 assert(counts.ore_uncovered==0,"native mining area missed ore")
 if large_cases[large_index].fluid then assert(counts.fluid_segments==1 and not segments[0],"disconnected uranium pipes") end
 if c.measure_lanes then
  large_flow={};large_flow_start=game.tick
  local coords=large_mine_state.coords
  for _,belt in ipairs(large_mine_state.belts) do if belt.is_output then
   local p=mpp_util.revert_world(coords.gx,coords.gy,large_mine_state.direction_choice,belt.x_start,belt.y,coords.tw,coords.th)
   local e=assert(belts[large_key{x=p[1],y=p[2]}],"missing internal output flow probe")
   assert(e.type=="transport-belt","flow probe must be a surface belt")
   large_flow[#large_flow+1]={entity=e,row=belt.capacity_row,dual=belt.throughput2>0,counts={0,0}}
  end end
 end
 -- Keep power running, but remove the distant fixture supply wire from photographs.
 if not c.measure_lanes then large_supply_pole.get_wire_connector(defines.wire_connector_id.pole_copper,true).disconnect_all() end
 local pos={x=(left+right)/2,y=(top+bottom)/2}
 local zoom=math.min(2400/((right-left+14)*32),1800/((bottom-top+14)*32),.38)
 large_capture("overview",pos,{2400,1800},zoom)
 large_phase=c.measure_lanes and "flow" or "mine-shot";large_wait=game.tick+1
end
local function large_measure_flow()
 local c=large_cases[large_index]
 local elapsed=game.tick-large_flow_start
 for _,probe in ipairs(large_flow) do for side=1,2 do
  local n=probe.entity.get_transport_line(side).remove_item{name=c.ore,count=1000}
  if elapsed>2400 then probe.counts[side]=probe.counts[side]+n end
 end end
 if elapsed<3600 then return end
 local side_capacity=large_mine_state.belt.speed*large_common.get_belt_capacity_multiplier(large_mine_state)
 local measured={warmup_ticks=2400,sample_ticks=1200,side_capacity=side_capacity,dual_outputs=0,outputs={}}
 for _,probe in ipairs(large_flow) do
  local rates={probe.counts[1]/20,probe.counts[2]/20}
  measured.outputs[#measured.outputs+1]={row=probe.row,dual=probe.dual,items_per_second=rates}
  if probe.dual then
   measured.dual_outputs=measured.dual_outputs+1
   assert(rates[1]>.95*side_capacity and rates[2]>.95*side_capacity,
    "planned dual-side output underfeeds: "..helpers.table_to_json(measured.outputs[#measured.outputs]))
  end
 end
 assert(measured.dual_outputs>=20,"saturation fixture did not exercise enough actual planned double-sided outputs")
 large_report.flow=measured
 helpers.write_file("large-mine-result.json",helpers.table_to_json(large_results),false)
 log("LARGE MINE FLOW "..helpers.table_to_json(measured))
 large_phase="mine-shot";large_wait=game.tick+1
end
local function large_step()
 if game.tick<large_wait then return end
 if large_phase=="start" then large_begin();return end
 if large_phase=="failure-delay" then error(large_failure) end
 if large_phase=="finish" then log("LARGE MINE SCENE COMPLETE");large_phase="done";return end
 if large_phase=="done" then return end
 if #storage.tasks>0 or large_data.preview and (large_data.preview.refresh_at or large_data.preview.render_job or large_data.preview.output_job) then return end
 if large_phase=="mine" then
  large_mine_state=large_state
  assert(large_state,"preview validation failed: "..helpers.table_to_json(large_data.preview.error or {}))
  helpers.write_file("large-mine-plan-"..large_index..".json",helpers.table_to_json{belts=large_state.belts,coords=large_state.coords},false)
  large_report.capacity={gap=large_state._capacity_gap,row_gaps=large_state._capacity_row_gaps,
  separate_power=large_state._capacity_separate_power,passes=large_state._capacity_pass,
  fallback=large_state._capacity_route_failure,beacons=large_state.beacon_summary}
  if large_state._mining_layout_choice=="compact" or large_state.layout_choice=="compact" then
   local previous
   local max_gap=large_data.choices.belt_merge_choice and 2 or 1
   for _,lane in ipairs(large_state.best_attempt.lane_layout) do
    if previous then assert(lane.y-previous-large_state.miner.size<=max_gap,"compact big-drill corridor exceeds the switch-dependent limit") end
    previous=lane.y
   end
   if large_state._capacity_tight_big then
    assert(large_state.miner_stride==5,"compact big-drill columns contain a reserved strip")
    local split_buses=0
    for _,belt in ipairs(large_state.belts) do
     if belt.is_output and belt.y>belt.source_y then
      assert(large_data.choices.belt_merge_choice,"disabled auto belts created a split bus")
      split_buses=split_buses+1
      if belt.turn_x-belt.x_start>=5 then
       local tunneled=false
       for _,spec in ipairs(large_state.builder_belts) do
        if spec.grid_y==belt.y and spec.grid_x>belt.x_start and spec.grid_x<belt.turn_x and spec.type=="input" then tunneled=true;break end
       end
       assert(tunneled,"split bus has no underground bypass")
      end
     end
    end
    local outputs_by_row,groups_by_row={},{}
    for _,belt in ipairs(large_state.belts) do
     local row=belt.capacity_row
     groups_by_row[row]=(groups_by_row[row] or 0)+1
     outputs_by_row[row]=(outputs_by_row[row] or 0)+(belt.is_output and 1 or 0)
    end
    local dual_rows=0
    for row,count in pairs(groups_by_row) do
     assert(outputs_by_row[row]==(count>=2 and 2 or 1),"double corridor was collapsed to one outlet")
     if count>=2 then dual_rows=dual_rows+1 end
     if large_state._capacity_paired then
      assert(count<=2,"facing pair exceeds two physical outputs")
     elseif large_state._capacity_compact and count>=2 then
      assert(count==math.min(4,#large_state.miner_lanes[row]),"double corridor leaves a receiving side unused")
     end
    end
    if large_state._capacity_paired then
     local directions={}
     for _,m in ipairs(large_state.best_attempt.miners) do
      assert(m.direction==(m.line%2==1 and defines.direction.south or defines.direction.north),"big compact row faces away from the shared belt")
      directions[m.direction]=(directions[m.direction] or 0)+1
     end
     assert(table_size(directions)==2,"large compact mine only uses one facing direction")
     large_report.capacity.mining_directions=directions
    end
    large_report.capacity.dual_output_rows=dual_rows
    large_report.capacity.split_buses=split_buses
   end
  end
  large_report.layout=large_state.layout_choice
  large_report.compact=large_state._capacity_compact;large_report.gap=large_state._capacity_gap
  if not large_data.preview.ready then
   helpers.write_file("large-mine-failed.json",helpers.table_to_json{case=large_cases[large_index],report=large_report,error=large_data.preview.error,
    coords=large_state.coords,issues=large_state._preview_issues,belts=large_state.belts,miners=large_state.best_attempt.miners,
    built=large_state.builder_belts,poles=large_state.builder_power_poles,lamps=large_state.builder_lamps,beacons=large_state.builder_beacons,
    gap=large_state._capacity_gap,edge=large_state._capacity_edge,separate=large_state._capacity_separate_power,
    failure=large_state._capacity_route_failure},false)
   large_capture("failed",{0,0},{2400,1800},.27)
  end
  assert(large_data.preview.ready,"mine preview failed: "..helpers.table_to_json(large_data.preview.error or {}))
  large_timer.stop();large_report.mine_ticks=game.tick-large_start_tick;large_report.mine_time=tostring(large_timer)
  log{"","LARGE MINE TIMING ",large_cases[large_index].id," mine ",large_timer}
  local c=large_cases[large_index]
  large_report.incoming_belts=large_data.preview.belt_specification.count
  large_report.expected_outputs=c.balance==false and large_report.incoming_belts or c.outputs
  local distance=c.output_distance or 235.5+2*math.max(0,large_report.incoming_belts-24)
  local target=({west={x=-distance,y=-15.5},east={x=distance,y=-15.5},north={x=-15.5,y=-distance},south={x=-15.5,y=distance}})[c.direction]
  large_report.output_target=target
  large_timer=helpers.create_profiler(true);large_start_tick=game.tick
  assert(preview.set_belt_target(large_data,{position=target,direction=defines.direction[c.direction]}))
  large_phase="output"
 elseif large_phase=="output" then
  if not large_data.preview.ready then
   large_capture("output-failed",{0,0},{2400,1800},.27)
   helpers.write_file("large-mine-output-failed.json",helpers.table_to_json{error=large_data.preview.error,issues=large_data.preview.issues,specs=large_data.preview.specs},false)
  end
  assert(large_data.preview.ready,"output preview failed: "..helpers.table_to_json(large_data.preview.error or {}))
  large_timer.stop();large_report.output_ticks=game.tick-large_start_tick;large_report.output_time=tostring(large_timer)
  log{"","LARGE MINE TIMING ",large_cases[large_index].id," output ",large_timer};large_timer=nil
  large_materialize()
 elseif large_phase=="audit" then large_audit()
 elseif large_phase=="flow" then large_measure_flow()
 elseif large_phase=="mine-shot" then
  large_capture("mine",{0,0},{2400,1800},.30)
  large_phase="detail";large_wait=game.tick+1
 elseif large_phase=="detail" then
  large_capture("detail",{0,0},{1800,1200},1)
  local nearest,distance
  for _,belt in ipairs(large_mine_state.belts) do if belt.capacity_target then
   local target=large_mine_state.belts[belt.capacity_target];local c=large_mine_state.coords
   local p=mpp_util.revert_world(c.gx,c.gy,large_mine_state.direction_choice,target.x2+3,belt.source_y-1,c.tw,c.th)
   local d=p[1]*p[1]+p[2]*p[2]
   if not distance or d<distance then nearest={x=p[1],y=p[2]};distance=d end
  end end
  if nearest then large_capture("dual-junction",nearest,{1600,1000},1.5) end
  local outlet
  for _,belt in ipairs(large_mine_state.belts) do
   if belt.is_output and belt.lane2 and (not outlet or #belt.lane1+#belt.lane2>#outlet.lane1+#outlet.lane2) then outlet=belt end
  end
  if outlet then
   local c=large_mine_state.coords
   local p=mpp_util.revert_world(c.gx,c.gy,large_mine_state.direction_choice,outlet.x_start+18,outlet.y,c.tw,c.th)
   large_capture("outlets",{x=p[1],y=p[2]},{1800,1000},1.4)
  end
  large_phase="next";large_wait=game.tick+75
 elseif large_phase=="next" then
  -- Reconnect the external test supply so the saved demonstrations remain powered.
  large_supply_pole.get_wire_connector(defines.wire_connector_id.pole_copper,true).connect_to(
   large_poles[1].get_wire_connector(defines.wire_connector_id.pole_copper,true),false,defines.wire_origin.script)
  large_begin()
 end
end
script.on_nth_tick(1,function()
 local ok,err=pcall(large_step)
 if not ok then log("LARGE MINE FAILED "..tostring(err));large_phase="done" end
end)
