local terrain_options_test=require("mpp.terrain")
-- Reproducible visual regression resembling the user's long Vulcanus ore patch.
local shore_obstacles=require("mpp.obstacles")
local shore_started=false
local function shore_error(v) return helpers.table_to_json(v and v.error or {}) end
local function shore_capture(name,position,resolution,zoom)
 local t=storage.shoreline_scene
 game.take_screenshot{surface=t.surface,position=position or {42,44},resolution=resolution or {2200,1840},
  zoom=zoom or .48,show_gui=false,show_entity_info=true,anti_alias=true,path=name..".png"}
end
local function shore_start()
 local p=game.get_player(1)
 conf.initialize_global(p.index);p.set_controller{type=defines.controllers.god}
 local s=game.create_surface("lava-shore-visual-test",{width=384,height=384,autoplace_controls={}})
 s.request_to_generate_chunks({0,0},6);s.force_generate_chunk_requests()
 for _,e in pairs(s.find_entities()) do e.destroy() end
 s.destroy_decoratives{}
 local tiles,land={},{}
 for y=-160,160 do
  local coast=y<16 and -25+3*math.sin(y/4)
   or -5+6*math.sin(y/7)+3*math.sin(y/2.6)+9*math.exp(-((y-47)/21)^2)
  for x=-160,160 do
   local lava=x<coast
   tiles[#tiles+1]={name=lava and "lava" or "volcanic-folds",position={x,y}}
   if not lava then land[x..","..y]=true end
  end
 end
 s.set_tiles(tiles);s.daytime=0;s.freeze_daytime=true
 p.teleport({68,45},s);p.game_view_settings.show_entity_info=true
 p.force.research_all_technologies();p.force.mining_drill_productivity_bonus=1;p.force.belt_stack_size_bonus=1
 local resources={}
 for y=-5,97 do for x=-16,60 do
  local shape=math.min(((x+2)/12)^2+((y-9)/18)^2,((x-14)/24)^2+((y-29)/21)^2,
   ((x-27)/27)^2+((y-53)/24)^2,((x-15)/21)^2+((y-78)/20)^2)
  local edge=1+.11*math.sin(x*.7+y*.29)+.07*math.cos(y*.8-x*.4)
  if shape<edge and land[x..","..y] then
   resources[#resources+1]=s.create_entity{name="tungsten-ore",position={x+.5,y+.5},
    amount=math.floor(15000+380000*(.5+.5*math.sin(x*.12+y*.06))^3)}
  end
 end end
 local d=storage.players[p.index];local c=d.choices
 c.layout_choice="beacon_rows";c.mining_layout_choice="compact";c.direction_choice="east"
 c.miner_choice="big-mining-drill";c.miner_quality_choice="normal"
 c.module_choice="speed-module-3";c.module_quality_choice="normal"
 c.beacon_choice="beacon";c.beacon_quality_choice="normal";c.beacon_module_choice="speed-module-3";c.beacon_module_quality_choice="normal"
 c.belt_choice="fast-transport-belt";c.belt_quality_choice="normal";c.pole_choice="medium-electric-pole";c.pole_quality_choice="normal"
 c.belt_merge_choice=true;c.belt_load_min_choice=.8;c.belt_load_max_choice=1.1
 c.belt_planner_choice=true;c.output_balance_choice=true;c.output_belt_count_choice=8;c.output_station_choice=false
 c.terrain_mode_choice="avoid";c.cliff_mode_choice="avoid";c.remove_entities_choice=false;c.statistics_choice=true
 for _,key in ipairs(terrain_options_test.tile_choices) do c[key]=false end
 c.remove_trees_choice=false;c.remove_rocks_choice=false
 c.lamp_choice=false;c.force_pipe_placement_choice=false
 storage.shoreline_scene={phase="mine",surface=s,resources=resources,report={ore_tiles=#resources}}
 gui.show_interface(p)
 preview.select{player_index=p.index,surface=s,entities=resources}
 game.speed=1
end

script.on_nth_tick(1,function()
 if not shore_started then shore_started=true;shore_start();return end
 local t=storage.shoreline_scene;local d=storage.players[1];local v=d.preview;local p=game.get_player(1)
 if t.phase=="done" or #storage.tasks>0 or v and v.refresh_at or t.wait_until and game.tick<t.wait_until then return end
 if t.phase=="mine" then
  assert(v.ready,"shoreline mine failed: "..shore_error(v))
  preview.set_belt_target(d,{position={x=98.5,y=45.5},direction=defines.direction.east});t.phase="output"
 elseif t.phase=="output" then
  assert(v.ready,"shoreline output failed: "..shore_error(v))
  local towers,miners={},{}
  local index=shore_obstacles.collect(t.surface,{{-35,-15},{110,110}},nil,d.choices)
  local blocked=0
  for _,spec in ipairs(v.specs) do
   if spec.name=="entity-ghost" then
    local b=shore_obstacles.entity_box(spec.inner_name,spec.position,spec.direction)
    if shore_obstacles.blocked_box(index,b) then blocked=blocked+1 end
    if spec.inner_name=="beacon" then towers[#towers+1]=spec
    elseif spec.inner_name=="big-mining-drill" then miners[#miners+1]=spec end
   end
  end
  local useless=0
  for _,tower in ipairs(towers) do
   local b=shore_obstacles.entity_box(tower.inner_name,tower.position,tower.direction)
   local r=prototypes.entity.beacon.get_supply_area_distance(tower.quality or "normal")
   local useful=false
   for _,miner in ipairs(miners) do
    local a=shore_obstacles.entity_box(miner.inner_name,miner.position,miner.direction)
    if b.left_top.x-r<a.right_bottom.x and b.right_bottom.x+r>a.left_top.x
     and b.left_top.y-r<a.right_bottom.y and b.right_bottom.y+r>a.left_top.y then useful=true end
   end
   if not useful then useless=useless+1 end
  end
  assert(blocked==0,"shoreline preview retains blocked footprints: "..blocked)
  assert(useless==0,"shoreline preview retains useless beacons: "..useless)
  assert(#miners>=30 and #towers>=50,"fixture is too small")
  t.report.drills=#miners;t.report.beacons=#towers;t.report.blocked_entities=blocked;t.report.useless_beacons=useless
  t.report.output_count=8;t.report.preview_entities=v.entity_count;t.report.warning=v.warning
  t.original_specs=table.deepcopy(v.specs)
  log("PLACEMENT SHORELINE "..helpers.table_to_json(t.report))
  shore_capture("shoreline-preview")
  t.phase="detail";t.wait_until=game.tick+60
 elseif t.phase=="detail" then
  shore_capture("shoreline-detail",{16,48},{1600,1320},1)
  t.phase="obstruct";t.wait_until=game.tick+60
 elseif t.phase=="obstruct" then
  t.blocker=t.surface.create_entity{name="steel-chest",position=v.belt_target.position,force=p.force}
  assert(t.blocker)
  preview.request(d,true);t.phase="blocked"
 elseif t.phase=="blocked" then
  assert(not v.ready and v.error and d.gui.preview_force.enabled,"fixture did not block the output")
  t.report.blocked_error=v.error
  shore_capture("shoreline-blocked-output",{91,43},{1500,1100},1.35)
  t.phase="force";t.wait_until=game.tick+60
 elseif t.phase=="force" then
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.preview_force,
   control=true,button=defines.mouse_button_type.left}
  t.phase="applied"
 elseif t.phase=="applied" then
  assert(not v and d.last_state,"forced shoreline Apply failed: "..shore_error(v))
  assert(t.blocker.to_be_deconstructed(p.force),"obstructing chest not ordered for removal")
  assert(d.last_state.balanced_output_count==8,"forced output count changed")
  local found,missing={},0
  for _,e in pairs(t.surface.find_entities_filtered{type="entity-ghost"}) do
   local pos=e.position;found[e.ghost_name..":"..pos.x..","..pos.y]=true
  end
  for _,spec in ipairs(t.original_specs) do
   if spec.name=="entity-ghost" then
    local pos=spec.position
    if not found[spec.inner_name..":"..pos.x..","..pos.y] then missing=missing+1 end
   end
  end
  assert(missing==0,"forced layout changed unobstructed preview geometry: "..missing)
  t.report.created_ghosts=#d.last_state._collected_ghosts;t.report.missing_entities=missing
  t.report.obstacle_marked_for_removal=true
  shore_capture("shoreline-applied")
  t.phase="forced-detail";t.wait_until=game.tick+60
 elseif t.phase=="forced-detail" then
  shore_capture("shoreline-forced-output",{91,43},{1500,1100},1.35)
  helpers.write_file("shoreline-result.json",helpers.table_to_json(t.report),false)
  t.phase="finish";t.wait_until=game.tick+90
 elseif t.phase=="finish" then
  t.phase="done";log("PLACEMENT SCENE COMPLETE "..helpers.table_to_json(t.report))
 end
end)
