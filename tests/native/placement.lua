local forced_test=require("mpp.forced_build")
local obstacle_test=require("mpp.obstacles")
local output_test=require("mpp.output_preview")

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
 local d=storage.players[1];local c=d.choices
 c.layout_choice="beacon_rows";c.direction_choice="east";c.miner_choice="big-mining-drill";c.miner_quality_choice="normal"
 c.module_choice="speed-module-3";c.module_quality_choice="normal"
 c.beacon_choice="beacon";c.beacon_quality_choice="normal";c.beacon_module_choice="speed-module-3";c.beacon_module_quality_choice="normal"
 c.belt_choice="express-transport-belt";c.belt_quality_choice="normal";c.pole_choice="medium-electric-pole";c.pole_quality_choice="normal"
 c.belt_merge_choice=false;c.belt_planner_choice=true;c.output_balance_choice=true;c.output_belt_count_choice=4;c.output_station_choice=false
 c.terrain_mode_choice="avoid";c.cliff_mode_choice="avoid";c.deconstruction_choice=true
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
  assert(d.last_state.balanced_output_count==4,"force changed requested output count")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.undo_button,button=defines.mouse_button_type.left}
  assert(not t.chest.to_be_deconstructed(p.force) and t.surface.count_entities_filtered{type="entity-ghost"}==0,"full force Undo failed")
  preview.select{player_index=1,surface=t.surface,entities=t.resources}
  t.phase="mine-ready"
 elseif t.phase=="mine-ready" then
  assert(v.ready and preview.apply(d));t.phase="mine-applied"
 elseif t.phase=="mine-applied" then
  assert(not v and d.last_state)
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
  t.chest.destroy();t.second_chest.destroy()
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
  t.phase="done";log("PLACEMENT COMPLETE: coherent forced output, output-only, station and Undo PASS")
 end
end)
