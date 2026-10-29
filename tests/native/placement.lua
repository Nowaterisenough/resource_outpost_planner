local forced_test=require("mpp.forced_build")
local obstacle_test=require("mpp.obstacles")
local output_test=require("mpp.output_preview")
local cleanup_clicks={
 {name="Apply",button="preview_apply"},
 {name="Shift Apply",button="preview_apply",shift=true},
 {name="Force Apply",button="preview_force"},
 {name="Ctrl Force Apply",button="preview_force",control=true},
 {name="Ctrl Shift Apply",button="preview_apply",shift=true,control=true},
}
local function cleanup_apply(d,t)
 local click=cleanup_clicks[t.cleanup_case or 1]
 script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui[click.button],
  button=defines.mouse_button_type.left,shift=click.shift,control=click.control}
end

-- Let real construction robots finish a demolition job, including chest contents.
local function robot_cleanup(p,t)
 local surface=t.surface
 t.cleanup_port=surface.create_entity{name="roboport",position={-70,85},force=p.force}
 t.cleanup_port.energy=100000000
 t.cleanup_port.get_inventory(defines.inventory.roboport_robot).insert{name="construction-robot",count=20}
 t.cleanup_storage=surface.create_entity{name="storage-chest",position={-75.5,85.5},force=p.force}
 t.cleanup_entities={}
 local specs={}
 for i,name in ipairs{"electric-mining-drill","steel-chest","beacon","transport-belt","tree-01","big-rock"} do
  local position={x=-85.5+i*5,y=100.5}
  local e=surface.create_entity{name=name,position=position,force=i>4 and "neutral" or p.force}
  assert(e,"robot cleanup fixture could not create "..name)
  if name=="steel-chest" then e.insert{name="iron-plate",count=100} end
  t.cleanup_entities[#t.cleanup_entities+1]=e
  specs[#specs+1]={name="entity-ghost",inner_name="assembling-machine-2",
   position=position,direction=defines.direction.east}
 end
 assert(forced_test.apply({player=p,surface=surface,_preview_specs=specs},defines.build_mode.superforced))
 for _,e in ipairs(t.cleanup_entities) do assert(e.to_be_deconstructed(p.force),"robot cleanup order missing: "..e.name) end
 t.cleanup_started=game.tick;t.phase="robots"
end

local function native_modes(p,surface) local function ghost(name,x,y,extra)
  local spec={name="entity-ghost",inner_name=name,position={x=x,y=y},direction=defines.direction.east}
  for k,v in pairs(extra or {}) do spec[k]=v end
  return spec
 end
 local function run(mode)
  local chest=surface.create_entity{name="steel-chest",position={-80.5,-80.5},force=p.force}
  local tree=surface.create_entity{name="tree-01",position={-76.5,-80.5},force="neutral"}
  local existing=surface.create_entity{name="entity-ghost",inner_name="transport-belt",position={-72.5,-80.5},direction=defines.direction.east,force=p.force}
  local state={player=p,surface=surface,coords={},_render_objects={},_preview_specs={
   ghost("transport-belt",-80.5,-80.5),ghost("transport-belt",-76.5,-80.5),ghost("transport-belt",-72.5,-80.5),
   ghost("underground-belt",-68.5,-80.5,{type="input"}),ghost("underground-belt",-64.5,-80.5,{type="output"}),
   ghost("beacon",-60.5,-80.5,{direction=0,quality="legendary",insert_plan={{id={name="speed-module-3",quality="epic"},items={in_inventory={{inventory=defines.inventory.beacon_modules,stack=0}}}}}}),
   ghost("splitter",-54.5,-80,{input_priority="left",output_priority="right",filter="iron-ore"}),
   ghost("straight-rail",-49,-79),ghost("train-stop",-49,-81,{direction=defines.direction.west,station_name="Forced test"}),
  }}
  assert(forced_test.apply(state,mode),"native build failed")
  assert(chest.to_be_deconstructed(p.force)==(mode==defines.build_mode.superforced),"force mode confused building removal")
  assert(tree.to_be_deconstructed(p.force),"forced build did not order natural obstacle removal")
  local function at(name,x,y)
   for _,e in pairs(surface.find_entities_filtered{position={x,y},radius=.05,type="entity-ghost"}) do
    if e.ghost_name==name then return e end
   end
   error("missing or shifted native ghost "..name.." at "..x..","..y)
  end
  local a,b=at("underground-belt",-68.5,-80.5),at("underground-belt",-64.5,-80.5)
  assert(a.direction==defines.direction.east and b.direction==defines.direction.east)
  assert(a.belt_to_ground_type=="input" and b.belt_to_ground_type=="output")
  local beacon=at("beacon",-60.5,-80.5)
  assert(beacon.quality.name=="legendary" and beacon.insert_plan[1].id.quality=="epic","quality/module request lost")
  local splitter=at("splitter",-54.5,-80)
  assert(splitter.splitter_input_priority=="left" and splitter.splitter_output_priority=="right" and splitter.splitter_filter.name=="iron-ore","splitter configuration lost")
  at("straight-rail",-49,-79)
  assert(at("train-stop",-49,-81).backer_name=="Forced test","station settings lost")
  for _,e in pairs(state._collected_ghosts) do assert(e~=existing,"existing ghost was claimed for Undo") end
  algorithm.cleanup_last_state{last_state=state,gui={}}
  assert(chest.valid and not chest.to_be_deconstructed(p.force) and not tree.to_be_deconstructed(p.force),"Undo failed to cancel new demolition")
  assert(existing.valid and surface.count_entities_filtered{type="entity-ghost"}==1,"Undo leaked or stole ghosts")
  chest.destroy();tree.destroy();existing.destroy()
 end
 run(defines.build_mode.forced);run(defines.build_mode.superforced)
 local water={};for x=-120,-115 do for y=-120,-115 do water[#water+1]={name="water",position={x,y}} end end
 surface.set_tiles(water)
 local state={player=p,surface=surface,_render_objects={},_preview_specs={
  ghost("transport-belt",-118.5,-118.5),{name="tile-ghost",inner_name="landfill",position={x=-119,y=-119}},
 }}
 assert(forced_test.apply(state,defines.build_mode.superforced),"superforced water placement failed")
 assert(surface.count_entities_filtered{type="tile-ghost"}>0,"fill ghost missing")
 assert(surface.count_entities_filtered{type="entity-ghost"}>0,"belt on fill missing")
 algorithm.cleanup_last_state{last_state=state,gui={}}
 assert(surface.count_entities_filtered{type={"tile-ghost","entity-ghost"}}==0,"fill Undo leaked ghosts")
 log("PLACEMENT native modes, world coordinates, qualities, modules, splitter, rails, station and Undo PASS")
end

local wire_test=require("mpp.pole_connections")
local builder_test=require("mpp.builder")

local function connected_poles(entities)
 local wanted,first,count={},nil,0
 for _,e in pairs(entities) do
  if e.valid and (e.type=="electric-pole" or e.type=="entity-ghost" and e.ghost_type=="electric-pole") then
   wanted[e.unit_number]=true;first=first or e;count=count+1
  end
 end
 assert(count>1,"not enough poles to check")
 local queue,seen={first},{[first.unit_number]=true}
 local i=1
 while i<=#queue do
  local e=queue[i];i=i+1
  local connector=e.get_wire_connector(defines.wire_connector_id.pole_copper,false)
  assert(connector,"pole has no copper connector")
  for _,c in pairs(connector.connections) do
   local other=c.target.owner
   assert(e.can_wires_reach(other),"connected poles outside their quality wire reach")
   if not seen[other.unit_number] then seen[other.unit_number]=true;queue[#queue+1]=other end
  end
 end
 for id in pairs(wanted) do assert(seen[id],"pole network disconnected; reached "..#queue.." / "..count) end
 return count
end

local function native_poles(p,surface)
 for _,mode in ipairs{"normal","forced"} do
  local external=surface.create_entity{name="medium-electric-pole",position={-158.5,-140.5},force=p.force,auto_connect=false}
  local far=surface.create_entity{name="medium-electric-pole",position={-160.5,-160.5},force=p.force,auto_connect=false}
  local state={player=p,surface=surface,direction_choice="west",coords={gx=-150,gy=-140,tw=80,th=80},
   _collected_ghosts={},_render_objects={},_preview_specs={},preview_only=mode=="forced"}
  local create=builder_test.create_entity_builder(state)
  for _,pos in ipairs{{0,0},{8,0},{16,0},{0,8},{8,8},{16,8}} do
   assert(create{name="medium-electric-pole",grid_x=pos[1],grid_y=pos[2],quality="normal"})
  end
  -- Quality poles must bridge farther than the normal prototype reach.
  local quality_reach=math.floor(prototypes.entity["medium-electric-pole"].get_max_wire_distance("legendary"))
  assert(quality_reach>prototypes.entity["medium-electric-pole"].get_max_wire_distance("normal"))
  for _,x in ipairs{24,24+quality_reach} do assert(create{name="medium-electric-pole",grid_x=x,grid_y=0,quality="legendary"}) end
  if mode=="forced" then assert(forced_test.apply(state,defines.build_mode.superforced))
  else wire_test.connect(state) end
  assert(connected_poles(state._collected_ghosts)==8)
  assert(#external.get_wire_connector(defines.wire_connector_id.pole_copper,false).connections>0,"nearby existing grid not connected")
  assert(not far.get_wire_connector(defines.wire_connector_id.pole_copper,false) or
   #far.get_wire_connector(defines.wire_connector_id.pole_copper,false).connections==0,"out-of-reach pole connected")
  local revived={}
  for _,e in ipairs(state._collected_ghosts) do
   local _,built=e.silent_revive{raise_revive=true}
   assert(built and built.valid,"could not build pole ghost");revived[#revived+1]=built
  end
  assert(connected_poles(revived)==8,"revival lost wires")
  for _,e in ipairs(revived) do e.destroy() end
  assert(#external.get_wire_connector(defines.wire_connector_id.pole_copper,false).connections==0,"ghost removal left dangling external wires")
  external.destroy();far.destroy()
  log("PLACEMENT "..mode.." poles PASS: connected ghosts, mixed quality reach, existing grid and revived wires")
 end
end

local function start()
 local p=game.get_player(1)
 conf.initialize_global(p.index);p.set_controller{type=defines.controllers.god}
 local surface=game.create_surface("placement-test",{width=400,height=400,autoplace_controls={}})
 surface.request_to_generate_chunks({0,0},6);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={};for x=-180,180 do for y=-180,180 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 surface.set_tiles(tiles);p.teleport({0,0},surface)
 p.force.research_all_technologies()

 native_modes(p,surface)
 native_poles(p,surface)
 local d=storage.players[1];local c=d.choices
 c.layout_choice="beacon_rows";c.direction_choice="east";c.miner_choice="big-mining-drill";c.miner_quality_choice="normal"
 c.module_choice="speed-module-3";c.module_quality_choice="normal"
 c.beacon_choice="beacon";c.beacon_quality_choice="normal";c.beacon_module_choice="speed-module-3";c.beacon_module_quality_choice="normal"
 c.belt_choice="express-transport-belt";c.belt_quality_choice="normal";c.pole_choice="medium-electric-pole";c.pole_quality_choice="normal"
 c.belt_merge_choice=false;c.belt_planner_choice=true;c.output_balance_choice=true;c.output_belt_count_choice=4;c.output_station_choice=false
 c.terrain_mode_choice="avoid";c.cliff_mode_choice="avoid";c.remove_entities_choice=false
 local lava={};local resources={}
 for x=0,39 do for y=0,39 do
  if x<8+math.floor(5*math.sin(y/5)) then lava[#lava+1]={name="lava",position={x,y}}
  else resources[#resources+1]=surface.create_entity{name="iron-ore",position={x+.5,y+.5},amount=100000} end
 end end
 surface.set_tiles(lava)
 storage.placement_test={phase="shore",surface=surface,resources=resources}
 gui.show_interface(p)
 preview.select{player_index=1,surface=surface,entities=resources}
 game.speed=10
end

script.on_nth_tick(1,function()
 if not storage.placement_test then start();return end
 local t=storage.placement_test;local d=storage.players[1];local v=d.preview;local p=game.get_player(1)
 if t.phase=="done" or #storage.tasks>0 or v and v.refresh_at then return end
 if t.phase=="shore" then
  assert(v.ready,"lava shore preview rejected: "..helpers.table_to_json(v.error or {}))
  local towers,miners={},{}
  local index=obstacle_test.collect(t.surface,{{-20,-20},{70,70}},nil,d.choices)
  for _,s in ipairs(v.specs) do
   if s.inner_name=="beacon" then towers[#towers+1]=s
   elseif s.inner_name=="big-mining-drill" then miners[#miners+1]=s end
  end
  assert(#towers>0 and #miners>0)
  for _,s in ipairs(towers) do
   local b=obstacle_test.entity_box(s.inner_name,s.position,s.direction)
   assert(not obstacle_test.blocked_box(index,b),"retained lava beacon")
   local useful=false
   local r=prototypes.entity.beacon.get_supply_area_distance(s.quality or "normal")
   for _,m in ipairs(miners) do local a=obstacle_test.entity_box(m.inner_name,m.position,m.direction)
    if b.left_top.x-r<a.right_bottom.x and b.right_bottom.x+r>a.left_top.x
     and b.left_top.y-r<a.right_bottom.y and b.right_bottom.y+r>a.left_top.y then useful=true end
   end
   assert(useful,"retained useless tower")
  end
  log("PLACEMENT irregular lava shoreline PASS: "..#miners.." drills, "..#towers.." useful clear beacons")
  preview.set_belt_target(d,{position={x=100.5,y=20.5},direction=defines.direction.east});t.phase="clear-output"
 elseif t.phase=="clear-output" then
  assert(v.ready,"clear output failed: "..helpers.table_to_json(v.error or {}))
  t.chest=t.surface.create_entity{name="steel-chest",position=v.belt_target.position,force=p.force}
  preview.request(d,true);t.phase="blocked"
 elseif t.phase=="blocked" then
  assert(not v.ready and v.error and d.gui.preview_force.enabled,"blocked preview cannot force apply")
  assert(preview.apply(d,defines.build_mode.superforced));t.phase="applied"
 elseif t.phase=="applied" then
  assert(not v and d.last_state,"force apply failed: "..helpers.table_to_json(v and v.error or {}))
  assert(t.chest.to_be_deconstructed(p.force),"forced output did not remove conflicting chest")
  log("PLACEMENT forced mine copper network PASS: "..connected_poles(d.last_state._collected_ghosts).." poles")
  assert(d.last_state.balanced_output_count==4,"force changed requested output count")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.undo_button,button=defines.mouse_button_type.left}
  assert(not t.chest.to_be_deconstructed(p.force) and t.surface.count_entities_filtered{type="entity-ghost"}==0,"full force Undo failed")
  preview.select{player_index=1,surface=t.surface,entities=t.resources}
  t.phase="mine-ready"
 elseif t.phase=="mine-ready" then
  assert(v.ready)
  for _,spec in ipairs(v.specs) do if spec.inner_name=="big-mining-drill" then
   if not t.natural then t.natural=t.surface.create_entity{name="tree-01",position=spec.position,force="neutral"}
   else t.rock=t.surface.create_entity{name="big-rock",position=spec.position,force="neutral"};break end
  end end
  assert(t.natural and t.rock);preview.request(d,true);t.phase="mine-natural"
 elseif t.phase=="mine-natural" then
  assert(v.ready and not t.natural.to_be_deconstructed(p.force) and not t.rock.to_be_deconstructed(p.force),"unchecked cleanup demolished trees or rocks")
  for _,spec in ipairs(v.specs) do if spec.name=="entity-ghost" then
   local box=obstacle_test.entity_box(spec.inner_name,spec.position,spec.direction)
   assert(t.surface.count_entities_filtered{area=box,name={"tree-01","big-rock"}}==0,"unchecked cleanup did not avoid natural obstacles")
  end end
  assert(preview.apply(d));t.phase="mine-applied"
 elseif t.phase=="mine-applied" then
  assert(not v and d.last_state)
  assert(not t.natural.to_be_deconstructed(p.force) and not t.rock.to_be_deconstructed(p.force),"unchecked cleanup removed trees or rocks")
  log("PLACEMENT unchecked cleanup PASS: trees and rocks retained and avoided")
  log("PLACEMENT normal mine copper network PASS: "..connected_poles(d.last_state._collected_ghosts).." poles")
  t.original_count=#d.last_state._collected_ghosts
  assert(output_test.begin(d,p))
  preview.set_belt_target(d,{position={x=120.5,y=20.5},direction=defines.direction.east})
  t.phase="output-only"
 elseif t.phase=="output-only" then
  assert(#v.specs>0,"output-only preview missing")
  t.second_chest=t.surface.create_entity{name="steel-chest",position=v.belt_target.position,force=p.force}
  preview.request(d,true);t.phase="output-only-blocked"
 elseif t.phase=="output-only-blocked" then
  assert(v.error and not v.ready and d.gui.preview_force.enabled)
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.preview_force,
   control=true,button=defines.mouse_button_type.left}
  assert(not d.preview and t.second_chest.to_be_deconstructed(p.force),"Ctrl force button failed for output-only preview: "..helpers.table_to_json(d.preview and d.preview.error or {}))
  assert(#d.last_state._collected_ghosts>t.original_count,"output-only build lost mining ownership")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.undo_button,button=defines.mouse_button_type.left}
  assert(t.chest.valid and not t.chest.to_be_deconstructed(p.force),"full plan Undo left demolition")
  assert(t.surface.count_entities_filtered{type="entity-ghost"}==0,"full plan Undo left ghosts")
  assert(not t.second_chest.to_be_deconstructed(p.force),"output-only Undo left demolition")
  assert(not t.natural.to_be_deconstructed(p.force),"natural obstruction Undo left demolition")
  t.natural.destroy();t.rock.destroy();t.chest.destroy();t.second_chest.destroy()
  d.choices.layout_choice="compact";d.choices.beacon_choice="none"
  d.choices.output_station_choice=true;d.choices.output_locomotive_count_choice=1;d.choices.output_wagon_count_choice=1
  d.choices.output_loading_side_choice="double"
  preview.select{player_index=1,surface=t.surface,entities=t.resources}
  t.phase="station-base"
 elseif t.phase=="station-base" then
  assert(v.ready)
  preview.set_belt_target(d,{position={x=101,y=21},direction=defines.direction.south});t.phase="station-ready"
 elseif t.phase=="station-ready" then
  assert(v.ready,"station preview failed: "..helpers.table_to_json(v.error or {}))
  t.station_expected={}
  for _,spec in ipairs(v.specs) do
   if spec.inner_name=="straight-rail" or spec.inner_name=="train-stop" then t.station_expected[#t.station_expected+1]=spec end
  end
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.preview_apply,
   shift=true,control=true,button=defines.mouse_button_type.left}
  t.phase="station-applied"
 elseif t.phase=="station-applied" then
  assert(not v,"station force failed")
  assert(#t.station_expected>0)
  for _,s in ipairs(t.station_expected) do
   local found=false
   for _,e in pairs(t.surface.find_entities_filtered{type="entity-ghost",position=s.position,radius=.05}) do
    if e.ghost_name==s.inner_name and e.direction==s.direction then found=true end
   end
   assert(found,"native forced station differs from preview: "..helpers.table_to_json(s))
  end
  log("PLACEMENT station Apply modifier and rail/stop preview parity PASS")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.undo_button,button=defines.mouse_button_type.left}
  d.choices.output_station_choice=false;d.choices.remove_entities_choice=true
  gui.show_interface(p)
  assert(d.gui.selections.misc.remove_entities.style.name=="yellow_slot_button","facility button selection is inverted")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.selections.misc.remove_entities,button=defines.mouse_button_type.left}
  assert(d.choices.remove_entities_choice==false and d.gui.selections.misc.remove_entities.style.name=="slot_button")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.selections.misc.remove_entities,button=defines.mouse_button_type.left}
  assert(d.choices.remove_entities_choice==true)
  preview.select{player_index=1,surface=t.surface,entities=t.resources};t.phase="facility-clear"
 elseif t.phase=="facility-clear" then
  assert(v.ready)
  for _,spec in ipairs(v.specs) do
   if spec.inner_name=="big-mining-drill" then
    if not t.facility then t.facility=t.surface.create_entity{name="electric-mining-drill",position=spec.position,force=p.force}
    elseif not t.clear_tree then t.clear_tree=t.surface.create_entity{name="tree-01",position=spec.position,force="neutral"}
    elseif not t.clear_rock then t.clear_rock=t.surface.create_entity{name="big-rock",position=spec.position,force="neutral"}
    elseif not t.clear_beacon then t.clear_beacon=t.surface.create_entity{name="beacon",position=spec.position,force=p.force}
    else t.clear_belt=t.surface.create_entity{name="transport-belt",position=spec.position,force=p.force};break end
   end
  end
  assert(t.facility and t.clear_tree and t.clear_rock and t.clear_beacon and t.clear_belt)
  preview.request(d,true);t.phase="facility-preview"
 elseif t.phase=="facility-preview" then
  assert(v.ready,"facility-removal checkbox still blocks mine")
  assert(not t.facility.to_be_deconstructed(p.force) and not t.clear_tree.to_be_deconstructed(p.force) and not t.clear_rock.to_be_deconstructed(p.force),"preview demolished an obstruction")
  cleanup_apply(d,t);t.phase="facility-applied"
 elseif t.phase=="facility-applied" then
  assert(not v and t.facility.to_be_deconstructed(p.force) and t.clear_tree.to_be_deconstructed(p.force) and t.clear_rock.to_be_deconstructed(p.force),"checked cleanup did not remove facilities, trees and rocks")
  assert(t.clear_beacon.to_be_deconstructed(p.force) and t.clear_belt.to_be_deconstructed(p.force),"checked cleanup leaves existing beacon or belt")
  log("PLACEMENT checked cleanup "..cleanup_clicks[t.cleanup_case or 1].name.." PASS: built drill, beacon, belt, tree and rock marked")
  log("PLACEMENT automatic facility removal and copper network PASS: "..connected_poles(d.last_state._collected_ghosts).." poles")
  assert(output_test.begin(d,p))
  preview.set_belt_target(d,{position={x=120.5,y=20.5},direction=defines.direction.east})
  t.phase="facility-output-clear"
 elseif t.phase=="facility-output-clear" then
  assert(v.ready)
  t.output_facility=t.surface.create_entity{name="steel-chest",position=v.belt_target.position,force=p.force}
  preview.request(d,true);t.phase="facility-output-blocked"
 elseif t.phase=="facility-output-blocked" then
  assert(v.ready,"output-only cleanup preview invalid")
  cleanup_apply(d,t)
  assert(not d.preview and t.output_facility.to_be_deconstructed(p.force))
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.undo_button,button=defines.mouse_button_type.left}
  assert(t.facility.valid and not t.facility.to_be_deconstructed(p.force) and not t.output_facility.to_be_deconstructed(p.force))
  assert(t.surface.count_entities_filtered{type="entity-ghost"}==0,"automatic facility removal Undo left ghosts")
  assert(not t.clear_tree.to_be_deconstructed(p.force) and not t.clear_rock.to_be_deconstructed(p.force),"cleanup Undo left natural demolition")
  assert(not t.clear_beacon.to_be_deconstructed(p.force) and not t.clear_belt.to_be_deconstructed(p.force),"cleanup Undo left facility demolition")
  t.clear_tree.destroy();t.clear_rock.destroy();t.facility.destroy();t.output_facility.destroy();t.clear_beacon.destroy();t.clear_belt.destroy()
  t.clear_tree=nil;t.clear_rock=nil;t.facility=nil;t.output_facility=nil;t.clear_beacon=nil;t.clear_belt=nil
  t.cleanup_case=(t.cleanup_case or 1)+1
  if cleanup_clicks[t.cleanup_case] then
   preview.select{player_index=1,surface=t.surface,entities=t.resources};t.phase="facility-clear";return
  end
  robot_cleanup(p,t)
 elseif t.phase=="robots" then
  t.cleanup_port.energy=100000000
  assert(game.tick-t.cleanup_started<3600,"construction robots failed to finish cleanup")
  for _,e in ipairs(t.cleanup_entities) do if e.valid then return end end
  if t.cleanup_storage.get_inventory(defines.inventory.chest).get_item_count("iron-plate")<100 then return end
  log("PLACEMENT robot cleanup PASS: built facilities removed and chest contents recovered")
  t.phase="done";log("PLACEMENT COMPLETE: cleanup click modes, robot demolition, copper wires, output-only, station and Undo PASS")
 end
end)
