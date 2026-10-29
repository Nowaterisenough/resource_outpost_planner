-- Appended only to an isolated test copy by scripts/test-placement.py --suite ore-filter.
local filter_util=require("mpp.mpp_util")
local filter_common=require("layouts.common")
local filter_output=require("mpp.output_preview")
local filter_forced=require("mpp.forced_build")
local filter_done,filter_feed,filter_deadline
local function filter_run(state)
 for _=1,10000 do
  local layout=algorithm.layouts[state.layout_choice]
  local result=layout[state._callback](layout,state)
  if result==false then return end
  assert(result,"missing filter callback "..state._callback)
  if result~=true then state._callback=result end
 end
 error("ore-filter planning did not terminate")
end
local function filter_plan(p,surface,resources,target)
 local state,err=algorithm.on_player_selected_area{player_index=p.index,surface=surface,entities=resources,
  preview_only=true,belt_target=target}
 assert(state,"resource selection failed: "..helpers.table_to_json(err or {}))
 filter_run(state)
 assert(not state.preview_error,"filter plan failed: "..helpers.table_to_json(state.preview_error or {}))
 local count=0
 for _,spec in ipairs(state._preview_specs) do if spec.filter and spec.filter.name=="iron-ore" then
  count=count+1
  assert(spec.output_priority=="left" and spec.quality=="normal","preview lost filter/quality")
 end end
 local outputs=0;for _,belt in ipairs(state.belts) do if belt.is_output then outputs=outputs+1 end end
 assert(count==outputs and count>0,"missing per-output filters")
 assert(#state.best_attempt.miners>0,"mixed resource patch cannot be mined")
 return state
end
local function filter_start()
 local p=game.get_player(1)
 conf.initialize_global(p.index);p.set_controller{type=defines.controllers.god};p.force.research_all_technologies()
 local surface=game.create_surface("ore-filter-test",{width=512,height=512,autoplace_controls={}})
 surface.request_to_generate_chunks({0,0},8);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={};for x=-240,240 do for y=-240,240 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 surface.set_tiles(tiles);p.teleport({0,0},surface)
 local resources={}
 for x=0,23 do for y=0,23 do
  resources[#resources+1]=surface.create_entity{name=(x+y)%2==0 and "iron-ore" or "copper-ore",position={x+.5,y+.5},amount=100000}
 end end
 local d=storage.players[p.index];local c=d.choices
 c.miner_choice="electric-mining-drill";c.miner_quality_choice="normal";c.module_choice="none";c.beacon_choice="none"
 c.pole_choice="none";c.remove_entities_choice=false;c.remove_trees_choice=false;c.remove_rocks_choice=false
 c.ore_filtering_choice=true;c.ore_filter_resource_choice="iron-ore";c.statistics_choice=false
 c.belt_planner_choice=true;c.output_balance_choice=false;c.belt_merge_choice=false
 gui.show_interface(p)
 for _,variant in ipairs{
  {layout="simple"},{layout="sparse"},{layout="super_compact"},
  {layout="compact",merge=true},{layout="compact",beacon=true,balance=true},
  {layout="compact",station=true},
 } do
  c.layout_choice=variant.layout;c.direction_choice="west";c.belt_choice="express-transport-belt"
  c.beacon_choice=variant.beacon and "beacon" or "none"
  c.belt_merge_choice=variant.merge==true;c.output_balance_choice=variant.balance==true
  c.output_belt_count_choice=8;c.output_station_choice=variant.station==true
  local state=filter_plan(p,surface,resources)
  filter_plan(p,surface,resources,{position={x=variant.station and -160.5 or -90.5,y=15.5},direction=defines.direction.west})
  log("ORE FILTER integration PASS: "..state.layout_choice.." balance="..tostring(c.output_balance_choice).." station="..tostring(c.output_station_choice))
 end
 c.layout_choice="compact";c.beacon_choice="none";c.belt_merge_choice=false;c.output_balance_choice=false;c.output_station_choice=false
 local cases=0
 for _,direction in ipairs{"west","north","east","south"} do
  for _,belt in ipairs{"transport-belt","fast-transport-belt","express-transport-belt","turbo-transport-belt"} do
   c.direction_choice=direction;c.belt_choice=belt;c.layout_choice="compact"
   local state=filter_plan(p,surface,resources)
   local spec=filter_common.create_belt_planner_specification(state)
   assert(spec.ore_filter_reserved and #spec.ore_filter_reserved==spec.count,"saved output lost waste keepout")
   local pos=filter_util.revert_world(state.coords.gx,state.coords.gy,direction,-90,15,state.coords.tw,state.coords.th)
   local target={position={x=pos[1],y=pos[2]},direction=filter_util.bp_direction[direction][defines.direction.west]}
   state=filter_plan(p,surface,resources,target)
   assert(#state.builder_belt_connections>0,"filtered outputs cannot be routed")
   if cases%2==0 then
    assert(filter_forced.apply(state,defines.build_mode.superforced),"forced filter application failed")
   else
    local built,err=algorithm.on_player_selected_area{player_index=p.index,surface=surface,entities=resources,belt_target=cases~=15 and target or nil}
    assert(built,helpers.table_to_json(err or {}));filter_run(built);state=built
   end
   local filters=0
   for _,ghost in ipairs(state._collected_ghosts) do if ghost.valid and ghost.type=="entity-ghost" and ghost.ghost_type=="splitter" then
    filters=filters+1
    assert(ghost.splitter_filter and ghost.splitter_filter.name=="iron-ore" and ghost.splitter_output_priority=="left","Apply lost filter settings")
   end end
   assert(filters==spec.count,"Apply added or lost filtered splitters")
   d.last_state=state
   if cases==15 then
    local output_spec=filter_common.create_belt_planner_specification(state)
    assert(filter_output.begin(d,p),"output-only preview failed")
    preview.set_belt_target(d,{position=target.position,direction=target.direction})
    assert(filter_output.refresh(d),"output-only routing lost filtered sources: "..helpers.table_to_json(d.preview.error or {}))
    local downstream=table.deepcopy(d.preview.specs)
    assert(filter_output.apply(d),"output-only Apply lost filtered sources")
    preview.cancel(d,false,true)
    local live={}
    for _,ghost in ipairs(state._collected_ghosts) do if ghost.valid then
     local _,entity=ghost.silent_revive{raise_revive=true}
     if entity then live[#live+1]=entity end
    end end
    local splitters={}
    for _,entity in ipairs(live) do if entity.type=="splitter" then
     assert(entity.splitter_filter.name=="iron-ore","revival lost filter")
     splitters[#splitters+1]=entity
     local back=filter_util.direction_coord[(entity.direction+8)%16]
     local side=filter_util.direction_coord[(entity.direction+12)%16]
     local input={x=entity.position.x+back.x+side.x*.5,y=entity.position.y+back.y+side.y*.5}
     local belts=surface.find_entities_filtered{position=input,radius=.1,type="transport-belt"}
     assert(#belts==1,"filter input is disconnected")
     for line=1,2 do
      assert(belts[1].get_transport_line(line).insert_at_back{name="iron-ore",count=1})
      assert(belts[1].get_transport_line(line).insert_at(.5,{name="copper-ore",count=1}))
     assert(belts[1].get_transport_line(line).insert_at(.25,{name="iron-ore",quality="uncommon",count=1}))
     end
    end end
    filter_feed={surface=surface,splitters=splitters,live=live,outputs=output_spec.count,downstream=downstream}
   else algorithm.cleanup_last_state(d) end
   cases=cases+1
   log("ORE FILTER PASS: "..direction.." "..belt.." filters="..filters)
  end
 end
 filter_deadline=game.tick+360;game.speed=20
 log("ORE FILTER geometry and Apply matrix PASS: "..cases.." mixed-patch plans")
end
script.on_nth_tick(1,function()
 if filter_done then return end
 if not filter_deadline then filter_start();return end
 if game.tick<filter_deadline then return end
 local iron=0
 for _,spec in ipairs(filter_feed.downstream) do
  for _,entity in pairs(filter_feed.surface.find_entities_filtered{position=spec.position,radius=.05,type="transport-belt"}) do
   for line=1,2 do
    local contents=entity.get_transport_line(line).get_contents()
    for _,stack in pairs(contents) do
     assert(stack.name~="copper-ore","rejected copper leaked into the main output")
     if stack.name=="iron-ore" then iron=iron+stack.count end
    end
   end
  end
 end
 assert(iron>0,"selected ore never passed through filters")
 for _,splitter in ipairs(filter_feed.splitters) do
  assert(splitter.splitter_filter.name=="iron-ore" and splitter.splitter_output_priority=="left")
 end
 filter_done=true
 log("PLACEMENT COMPLETE: ore-filter matrix, normal/forced Apply, revival, output-only reservations and live item flow PASS")
end)
