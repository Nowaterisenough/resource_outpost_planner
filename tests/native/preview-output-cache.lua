-- Run in two isolated native-server processes to exercise real save/reload.
local cache_test=require("mpp.preview_output_cache")
local original_refresh=cache_test.refresh
cache_test.refresh=function(state)
 storage.preview_cache_test.refreshes=storage.preview_cache_test.refreshes+1
 return original_refresh(state)
end
local created_save=false
local function snapshot(specs)
 local result={}
 for _,s in ipairs(specs) do if s.name=="entity-ghost" then
  local p=s.position
  result[#result+1]=helpers.table_to_json{name=s.inner_name,x=p.x or p[1],y=p.y or p[2],
   direction=s.direction,quality=s.quality or "normal",kind=s.type,
   input_priority=s.input_priority or "none",output_priority=s.output_priority or "none",filter=s.filter}
 end end
 table.sort(result);return table.concat(result,"\n")
end
local function start()
 local p=game.get_player(1)
 conf.initialize_global(p.index);p.set_controller{type=defines.controllers.god}
 local surface=game.create_surface("preview-output-cache-test",{width=400,height=400,autoplace_controls={}})
 surface.request_to_generate_chunks({0,0},6);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={};for x=-180,180 do for y=-180,180 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 surface.set_tiles(tiles);p.teleport({0,0},surface)
 p.force.research_all_technologies();p.force.mining_drill_productivity_bonus=4;p.force.belt_stack_size_bonus=3
 local d=storage.players[1];local c=d.choices
 c.layout_choice="compact";c.direction_choice="west";c.miner_choice="big-mining-drill";c.miner_quality_choice="normal"
 c.module_choice="speed-module-3";c.module_quality_choice="normal";c.beacon_choice="none"
 c.belt_choice="express-transport-belt";c.belt_quality_choice="normal";c.pole_choice="medium-electric-pole";c.pole_quality_choice="normal"
 c.belt_merge_choice=true;c.belt_load_min_choice=0.8;c.belt_load_max_choice=1.1
 c.belt_planner_choice=true;c.output_balance_choice=true;c.output_belt_count_choice=8;c.output_station_choice=false
 c.terrain_mode_choice="fill";c.cliff_mode_choice="remove";c.remove_entities_choice=false
 local resources={}
 for x=0,39 do for y=0,31 do resources[#resources+1]=surface.create_entity{name="iron-ore",position={x+.5,y+.5},amount=100000} end end
 storage.preview_cache_test={phase="base",refreshes=0,surface=surface,resources=resources,changes=0}
 gui.show_interface(p)
 preview.select{player_index=1,surface=surface,entities=resources}
 game.speed=20
end
script.on_nth_tick(1,function()
 if not storage.preview_cache_test then start();return end
 local t=storage.preview_cache_test;local d=storage.players[1];local v=d.preview;local p=game.get_player(1)
 if t.phase=="done" or t.phase=="saved" and created_save then return end
 if #storage.tasks>0 or v and v.refresh_at then return end
 if t.phase=="base" then
  assert(v.ready and v.output_basis,"initial mining basis missing")
  preview.set_belt_target(d,{position={x=-90.5,y=18.5},direction=defines.direction.west});t.phase="cached"
 elseif t.phase=="cached" then
  assert(v.ready and t.refreshes==1,"initial output did not reuse mining geometry")
  t.expected=snapshot(v.specs);preview.request(d);t.phase="full"
 elseif t.phase=="full" then
  assert(v.ready and snapshot(v.specs)==t.expected,"cached and full planning differ")
  assert(v.output_basis,"full replan did not retain basis")
  t.phase="saved";created_save=true
  game.server_save("preview-output-cache-checkpoint")
  log("OUTPUT CACHE CHECKPOINT REQUESTED")
 elseif t.phase=="saved" then
  assert(v.ready and v.output_basis,"mining basis lost during save/reload")
  t.before=t.refreshes
  preview.set_belt_target(d,{position={x=-94.5,y=20.5},direction=defines.direction.west});t.phase="reloaded"
 elseif t.phase=="reloaded" then
  assert(v.ready and t.refreshes==t.before+1,"reloaded cache was not reusable")
  t.expected=snapshot(v.specs);preview.request(d);t.phase="reload-full"
 elseif t.phase=="reload-full" then
  assert(v.ready and snapshot(v.specs)==t.expected,"reloaded cache changed geometry")
  log("OUTPUT CACHE RELOAD PASS")
  t.phase="mutate"
 elseif t.phase=="mutate" then
  assert(v.ready,"mutation left invalid output: "..helpers.table_to_json(v.error or {}))
  t.changes=t.changes+1
  if t.changes==1 then
   t.blocker=t.surface.create_entity{name="steel-chest",position={x=-15.5,y=-15.5},force=p.force}
  elseif t.changes==2 then p.force.mining_drill_productivity_bonus=p.force.mining_drill_productivity_bonus+0.125
  elseif t.changes==3 then t.resources[1].amount=t.resources[1].amount-1
  elseif t.changes==4 then d.choices.output_belt_count_choice=4
  elseif t.changes==5 then d.choices.belt_load_max_choice=1.2
  else
   t.expected=snapshot(v.specs);assert(preview.apply(d));t.phase="applied";return
  end
  t.before=t.refreshes
  preview.set_belt_target(d,{position={x=-94.5-t.changes,y=20.5},direction=defines.direction.west});t.phase="invalidated"
 elseif t.phase=="invalidated" then
  assert(v.ready and t.refreshes==t.before,"mining change reused stale cache")
  t.expected=snapshot(v.specs);preview.request(d);t.phase="mutation-full"
 elseif t.phase=="mutation-full" then
  assert(v.ready and snapshot(v.specs)==t.expected,"invalidation differs from a full replan")
  t.phase="mutate"
 elseif t.phase=="applied" then
  assert(not v and d.last_state,"Apply did not complete")
  local actual={}
  for _,e in pairs(t.surface.find_entities_filtered{type="entity-ghost"}) do
   actual[#actual+1]={name="entity-ghost",inner_name=e.ghost_name,position=e.position,direction=e.direction,quality=e.quality.name,
    type=e.ghost_type=="underground-belt" and e.belt_to_ground_type or nil,
    input_priority=e.ghost_type=="splitter" and e.splitter_input_priority or nil,
    output_priority=e.ghost_type=="splitter" and e.splitter_output_priority or nil,
    filter=e.ghost_type=="splitter" and e.splitter_filter or nil}
  end
  helpers.write_file("cache-expected.txt",t.expected,false);helpers.write_file("cache-actual.txt",snapshot(actual),false)
  assert(snapshot(actual)==t.expected,"cached preview and Apply differ")
  script.get_event_handler(defines.events.on_gui_click){player_index=1,element=d.gui.undo_button,button=defines.mouse_button_type.left}
  assert(t.surface.count_entities_filtered{type="entity-ghost"}==0,"Undo leaked ghosts")
  t.phase="done"
  log("OUTPUT CACHE COMPLETE: reload, five invalidations, full-plan parity, Apply and Undo")
 end
end)
