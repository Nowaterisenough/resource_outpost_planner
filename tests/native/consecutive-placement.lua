-- Consecutive independent plans must retain earlier construction and Undo ownership.
local consecutive_output=require("mpp.output_preview")
local consecutive_terrain=require("mpp.terrain")
local consecutive_cases={{id="normal",extension=true},{id="shift",mode="forced",extension=true},{id="ctrl-shift",mode="superforced"},
 {id="clear",clear=true},{id="station-shift",mode="forced",station=true}}
local consecutive_index,consecutive_phase,consecutive=0,"next",nil
local consecutive_results={}
local function consecutive_check(ok,message)
 assert(ok,"CONSECUTIVE "..consecutive_cases[consecutive_index].id.." ("..consecutive_phase.."): "..message)
end
local function consecutive_preserved()
 local t=consecutive
 for _,e in ipairs(t.first) do consecutive_check(e.valid,"first plan entity disappeared: "..tostring(e)) end
 consecutive_check(t.rock.valid and t.rock.to_be_deconstructed(t.player.force),"first plan demolition order was cancelled")
end
local function consecutive_select(resources)
 local t=consecutive
 consecutive_check(preview.select{player_index=1,surface=t.surface,entities=resources},"selection failed")
 consecutive_preserved()
 consecutive_check(t.data.last_state==t.first_state,"selection discarded the last applied Undo state")
end
local function consecutive_click(button,mode)
 script.get_event_handler(defines.events.on_gui_click){player_index=1,element=consecutive.data.gui[button],
  button=defines.mouse_button_type.left,shift=mode=="forced" or mode=="superforced",control=mode=="superforced"}
end
local function consecutive_begin()
 consecutive_index=consecutive_index+1
 local case=consecutive_cases[consecutive_index]
 if not case then consecutive_phase="done";log("PLACEMENT COMPLETE: consecutive plans, cancellation, overlap, construction and isolated Undo PASS");return end
 local p=game.get_player(1);conf.initialize_global(1);p.set_controller{type=defines.controllers.god};p.force.research_all_technologies()
 local s=game.create_surface("consecutive-"..consecutive_index,{width=512,height=512,autoplace_controls={}})
 s.request_to_generate_chunks({0,0},6);s.force_generate_chunk_requests()
 for _,e in pairs(s.find_entities()) do e.destroy() end
 local tiles={};for x=-160,160 do for y=-150,150 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 s.set_tiles(tiles);p.teleport({0,0},s)
 local resources={{},{}}
 for i,top in ipairs{-95,45} do for x=-95,-64 do for y=top,top+27 do
  resources[i][#resources[i]+1]=s.create_entity{name="iron-ore",position={x+.5,y+.5},amount=100000}
 end end end
 local d=storage.players[1];local c=d.choices
 c.layout_choice="compact";c.mining_layout_choice="compact";c.direction_choice="east"
 c.miner_choice="big-mining-drill";c.miner_quality_choice="normal";c.module_choice="none";c.beacon_choice="none"
 c.belt_choice="express-transport-belt";c.belt_quality_choice="normal";c.pole_choice="medium-electric-pole";c.pole_quality_choice="normal"
 c.pipe_choice="pipe";c.lamp_choice=true;c.force_pipe_placement_choice=false;c.belt_merge_choice=false
 c.belt_planner_choice=true;c.output_balance_choice=true;c.output_belt_count_choice=4;c.output_station_choice=false
 c.cliff_mode_choice="avoid";c.terrain_mode_choice="avoid";c.remove_entities_choice=true;c.remove_trees_choice=true;c.remove_rocks_choice=true
 for _,flag in ipairs(consecutive_terrain.tile_choices) do c[flag]=flag=="fill_lava_choice" end
 consecutive={player=p,surface=s,data=d,resources=resources,case=case}
 gui.show_interface(p);preview.select{player_index=1,surface=s,entities=resources[1]}
 consecutive_phase="first-preview";game.speed=10
end
script.on_nth_tick(1,function()
 if consecutive_phase=="done" then return end
 if consecutive_phase=="next" then consecutive_begin();return end
 local t=consecutive;local d=t.data;local v=d.preview
 if #storage.tasks>0 or #storage.immediate_tasks>0 or v and (v.refresh_at or v.render_job or v.output_job or v.applying) then return end
 if t.first then consecutive_preserved() end
 if consecutive_phase=="first-preview" then
  consecutive_check(v and v.ready,"first preview failed")
  for _,spec in ipairs(v.specs) do if spec.inner_name=="big-mining-drill" then
   t.rock=t.surface.create_entity{name="big-volcanic-rock",position=spec.position,force="neutral"};break
  end end
  t.surface.set_tiles{{name="lava",position={-20,-80}}}
  preview.set_belt_target(d,{position={x=-19.5,y=-79.5},direction=defines.direction.east})
  consecutive_phase="first-output"
 elseif consecutive_phase=="first-output" then
  consecutive_check(v and v.ready,"first output failed: "..helpers.table_to_json(v and v.error or {}))
  consecutive_click("preview_apply");consecutive_phase="first-applied"
 elseif consecutive_phase=="first-applied" then
  consecutive_check(not v and d.last_state,"first Apply failed")
  t.first_state=d.last_state;t.first={};local tiles,revived=0,false
  for _,e in ipairs(d.last_state._collected_ghosts) do
   if e.type=="tile-ghost" then tiles=tiles+1 end
   if not revived and e.type=="entity-ghost" and e.ghost_type=="transport-belt" then
    local _,built=e.silent_revive{raise_revive=true}
    if built then t.first[#t.first+1]=built;revived=true else t.first[#t.first+1]=e end
   else t.first[#t.first+1]=e end
  end
  consecutive_check(tiles>0 and revived and #t.first>10,"first plan must contain foundation ghosts, entity ghosts and a built belt")
  consecutive_preserved()
  d.choices.remove_entities_choice=false;d.choices.remove_trees_choice=false;d.choices.remove_rocks_choice=false
  consecutive_select(t.resources[2]);consecutive_phase="second-cancel"
 elseif consecutive_phase=="second-cancel" then
  consecutive_check(v and v.ready,"second preview failed")
  consecutive_click("preview_cancel")
  consecutive_preserved();consecutive_check(d.last_state==t.first_state,"Cancel lost first Undo state")
  consecutive_select(t.resources[1]);consecutive_phase="overlap-cancel"
 elseif consecutive_phase=="overlap-cancel" then
  -- Re-selecting the first patch must never delete its placed plan, even if
  -- existing equipment leaves no room for another valid layout.
  consecutive_click("undo_button");consecutive_preserved()
  consecutive_check(not d.preview and d.last_state==t.first_state,"preview Undo affected the applied plan")
  d.choices.remove_entities_choice=t.case.clear==true;d.choices.remove_trees_choice=t.case.clear==true;d.choices.remove_rocks_choice=t.case.clear==true
  d.choices.output_station_choice=t.case.station==true
  d.choices.output_locomotive_count_choice=1;d.choices.output_wagon_count_choice=1;d.choices.output_loading_side_choice="double"
  consecutive_select(t.resources[2]);consecutive_phase="second-preview"
 elseif consecutive_phase=="second-preview" then
  consecutive_check(v and v.ready,"second mine cannot preview")
  if t.case.extension then
   consecutive_click("preview_apply",t.case.mode);consecutive_phase="second-applied"
  else
   preview.set_belt_target(d,{position=t.case.station and {x=20,y=60} or {x=20.5,y=60.5},
    direction=t.case.station and defines.direction.south or defines.direction.east})
   consecutive_phase="second-output"
  end
 elseif consecutive_phase=="second-output" then
  consecutive_check(v and v.ready,"second output failed: "..helpers.table_to_json(v and v.error or {}))
  consecutive_click("preview_apply",t.case.mode);consecutive_phase="second-applied"
 elseif consecutive_phase=="second-applied" then
  consecutive_check(not v and d.last_state and d.last_state~=t.first_state,"second Apply failed")
  for _,e in ipairs(d.last_state._collected_ghosts) do for _,first in ipairs(t.first) do
   consecutive_check(e~=first,"second Undo adopted first plan ghost")
  end end
  for _,e in ipairs(d.last_state._deconstruction_orders or {}) do consecutive_check(e~=t.rock,"second Undo adopted first demolition") end
  t.second={};for _,e in ipairs(d.last_state._collected_ghosts) do t.second[#t.second+1]=e end
  if not t.case.extension then consecutive_phase="second-undo"
  else
   consecutive_check(consecutive_output.begin(d,t.player),"second output-only preview unavailable")
   preview.set_belt_target(d,{position={x=20.5,y=60.5},direction=defines.direction.east});consecutive_phase="output-extension"
  end
 elseif consecutive_phase=="output-extension" then
  consecutive_check(v and v.ready,"output extension cannot preview: "..helpers.table_to_json(v and v.error or {}))
  consecutive_click("preview_apply",t.case.mode)
  consecutive_check(not d.preview,"output extension failed")
  t.second={};for _,e in ipairs(d.last_state._collected_ghosts) do t.second[#t.second+1]=e end
  consecutive_phase="second-undo"
 elseif consecutive_phase=="second-undo" then
  consecutive_click("undo_button");consecutive_preserved()
  for _,e in ipairs(t.second) do consecutive_check(not e.valid,"second Undo left its new ghost") end
  consecutive_check(not d.last_state,"Undo retained second state")
  log("PLACEMENT CONSECUTIVE PASS "..t.case.id..": first="..#t.first..", second="..#t.second)
  consecutive_results[#consecutive_results+1]={case=t.case.id,passed=true,first=#t.first,second=#t.second}
  helpers.write_file("consecutive-placement.json",helpers.table_to_json(consecutive_results),false)
  t.player.teleport({0,0},game.surfaces[1]);game.delete_surface(t.surface);consecutive_phase="next"
 end
end)
