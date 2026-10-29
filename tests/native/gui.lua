local terrain_options_test=require("mpp.terrain")
local gui_oil_config=require("oil.config")
-- Run with scripts/test-placement.py --scene gui. Exercises actual LuaGui controls.
local gui_test_tick, gui_test_phase
local function gui_test_click(p, element)
 script.get_event_handler(defines.events.on_gui_click){player_index=p.index,element=element,button=defines.mouse_button_type.left}
end
local function gui_test_check(p, element, state)
 element.state=state
 script.get_event_handler(defines.events.on_gui_checked_state_changed){player_index=p.index,element=element}
end
local function gui_test_dropdown(p, element, index)
 element.selected_index=index
 script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index=p.index,element=element}
end
local function gui_test_capture(p, name)
 game.take_screenshot{player=p, resolution=p.display_resolution,show_gui=true,show_entity_info=false,
  anti_alias=true,path="gui-"..name..".png"}
end
local function gui_test_quality_badge(button)
 for _,child in pairs(button.children) do
  for _,badge in pairs(child.children) do
   if badge.name=="quality_badge" then return badge.sprite end
  end
 end
end
local function gui_test_oil_placement(p)
 local surface=game.create_surface("gui-oil-quality-test",{width=96,height=96,autoplace_controls={}})
 surface.request_to_generate_chunks({0,0},2);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={}
 for x=-40,40 do for y=-40,40 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 surface.set_tiles(tiles)
 local resources={}
 for _,pos in ipairs{{0,0},{12,8}} do
  resources[#resources+1]=assert(surface.create_entity{name="crude-oil",position=pos,amount=100000})
 end
 for _,preview_only in ipairs{true,false} do
  local state,err=algorithm.on_player_selected_area{player_index=p.index,surface=surface,entities=resources,preview_only=preview_only}
  assert(state,"oil quality test could not select resources: "..helpers.table_to_json(err or {}))
  assert(algorithm.layouts.oil:start(state)==false and not state.preview_error,"oil quality test could not plan")
  local pumps=0
  for _,entry in ipairs(preview_only and state._preview_specs or state._collected_ghosts) do
   if preview_only and entry.inner_name=="pumpjack" or not preview_only and entry.valid and entry.ghost_name=="pumpjack" then
    local quality=preview_only and entry.quality or entry.quality.name
    assert(quality=="epic","oil quality badge differs from placed pumpjack")
    pumps=pumps+1
   end
  end
  assert(pumps==#resources,"oil quality test lost pumpjacks")
  algorithm.cleanup_last_state{last_state=state,gui={}}
 end
 game.delete_surface(surface)
 log("GUI OIL QUALITY PASS: five qualities, independent badges, preview and placed epic pumpjacks")
end
script.on_nth_tick(1,function()
 local p=game.get_player(1)
 if not gui_test_tick then
  conf.initialize_global(p.index)
  p.set_controller{type=defines.controllers.god}
  p.force.research_all_technologies()
  p.teleport({0,0});p.zoom=.5
  local d=storage.players[p.index];local c=d.choices
  c.layout_choice="compact";c.mining_layout_choice="compact"
  c.miner_choice="big-mining-drill";c.miner_quality_choice="legendary"
  c.module_choice="speed-module-3";c.module_quality_choice="legendary"
  c.beacon_choice="beacon";c.beacon_module_choice="speed-module-3"
  c.belt_choice="turbo-transport-belt";c.pole_choice="medium-electric-pole"
  c.terrain_mode_choice="avoid";c.cliff_mode_choice="avoid";c.remove_entities_choice=false
  for _,key in ipairs(terrain_options_test.tile_choices) do c[key]=false end
  c.remove_trees_choice=false;c.remove_rocks_choice=false
  c.output_balance_choice=true;c.output_belt_count_choice=8;c.belt_merge_choice=true
  c.belt_load_min_choice=.8;c.belt_load_max_choice=1.1
  gui.show_interface(p)
  assert(d.gui.settings_body.type=="scroll-pane")
  assert(d.gui.tables.terrain.column_count==2,"terrain options are not in two columns")
  assert(not d.gui.selections.misc.force_pipe_placement,"redundant forced-pipe checkbox is still shown")
  assert(d.gui.section.pipe.visible and d.gui.selections.pipe[c.pipe_choice].type=="sprite-button","pipe icon selection was removed")
  for _,child in pairs(p.gui.screen.mpp_settings_frame.children) do assert(child.type~="tabbed-pane") end
  local old=p.gui.screen.mpp_settings_frame
  d.gui.workflow_version=18;gui.show_interface(p)
  assert(not old.valid and d.gui.workflow_version==23,"old GUI not rebuilt")
  assert(gui_test_quality_badge(d.gui.selections.miner.pumpjack)=="quality/normal","oil equipment quality badge is missing or inherits drill quality")
  assert(gui_test_quality_badge(d.gui.selections.miner["big-mining-drill"])=="quality/legendary","drill quality badge changed")
  assert(c.remove_entities_choice==false and c.belt_load_max_choice==1.1,"GUI migration changed settings")
  assert(d.gui.section.layout.style.minimal_width==d.gui.section.miner.style.minimal_width,"layout and equipment columns are misaligned")
  assert(d.gui.section.direction.style.minimal_width==d.gui.section.module.style.minimal_width,"direction and module columns are misaligned")
  assert(d.gui.section.pipe.style.minimal_width==d.gui.section.module.style.minimal_width,"pipe and module columns are misaligned")
  assert(d.gui.section.beacon_module.style.minimal_width==d.gui.section.module.style.minimal_width,"beacon modules are misaligned")
  local lamp=d.gui.selections.misc.lamp
  assert(lamp.type=="sprite-button" and lamp.sprite=="entity/small-lamp","lamp is not an equipment icon")
  assert(lamp.parent==d.gui.power_options and not c.lamp_choice and lamp.style.name=="slot_button")
  gui_test_click(p,lamp)
  assert(c.lamp_choice and lamp.style.name=="yellow_slot_button","lamp icon did not enable lighting")
  gui.show_interface(p)
  lamp=d.gui.selections.misc.lamp
  assert(c.lamp_choice and lamp.style.name=="yellow_slot_button","lamp icon lost its enabled state on refresh")
  gui_test_click(p,lamp)
  assert(not c.lamp_choice and lamp.style.name=="slot_button","lamp icon did not disable lighting")
  assert(d.gui.selections.misc.remove_entities.type=="checkbox")
  gui_test_check(p,d.gui.selections.misc.remove_entities,true)
  assert(c.remove_entities_choice==true)
  gui_test_check(p,d.gui.selections.misc.remove_entities,false)
  assert(c.remove_entities_choice==false)
  for _,key in ipairs{"cliff_mode","fill_water","fill_lava","fill_oil_ocean","fill_other","remove_trees","remove_rocks"} do
   assert(d.gui.selections.misc[key].type=="checkbox","not a checkbox: "..key)
   gui_test_check(p,d.gui.selections.misc[key],true)
   assert(c[key.."_choice"]==(key=="cliff_mode" and "remove" or true))
   assert(not c.remove_entities_choice,"independent control changed facility removal")
   gui_test_check(p,d.gui.selections.misc[key],false)
  end
  assert(c.cliff_mode_choice=="avoid" and not c.fill_lava_choice and not c.remove_trees_choice)
  gui_test_check(p,d.gui.belt_load_toggle,false)
  assert(not c.belt_merge_choice and not d.gui.belt_load_fields.max.enabled)
  gui_test_check(p,d.gui.belt_load_toggle,true)
  assert(c.belt_merge_choice and d.gui.belt_load_fields.max.enabled)
  gui_test_check(p,d.gui.output_station_toggle,true)
  assert(c.output_station_choice and d.gui.output_train_fields.wagon.enabled and not d.gui.output_count.enabled)
  gui_test_check(p,d.gui.output_station_toggle,false)
  assert(not c.output_station_choice and not d.gui.output_train_fields.wagon.enabled and d.gui.output_count.enabled)
  -- All configuration groups share one visible page.
  assert(d.gui.section.miner.visible and d.gui.section.terrain.visible and d.gui.output_settings_root.visible)
  gui_test_click(p,d.gui.select_tool)
  assert(d.input_mode=="select")
  local close=p.gui.screen.mpp_settings_frame.mpp_titlebar.children[3]
  gui_test_click(p,close)
  assert(not p.gui.screen.mpp_settings_frame.visible and not d.input_mode)
  gui.show_interface(p)
  p.gui.screen.mpp_settings_frame.location={24,64}
  gui_test_tick=game.tick+30;gui_test_phase=1
  log("GUI DISPLAY: "..p.display_resolution.width.."x"..p.display_resolution.height.." scale="..p.display_scale)
  log("GUI CHECKS PASS: migration, checkboxes, independent terrain, output settings, single-page groups and close")
  return
 end
 if game.tick<gui_test_tick then return end
 local d=storage.players[p.index]
 if gui_test_phase==1 then
  gui_test_capture(p,"equipment")
 elseif gui_test_phase==2 then
  gui_test_check(p,d.gui.output_station_toggle,true)
  gui_test_check(p,d.gui.selections.misc.remove_entities,true)
 elseif gui_test_phase==3 then
  gui_test_capture(p,"station")
 elseif gui_test_phase==4 then
  for _,button in pairs(d.gui.selections.miner) do
   if button.tags.mpp_oil_extractor then gui_test_click(p,button);break end
  end
  assert(d.choices.layout_choice=="oil" and d.gui.oil_settings_root.visible and not d.gui.output_settings_root.visible)
  assert(d.gui.tables.oil_extractor_quality.visible and not d.gui.tables.miner_quality.visible,"oil quality selector is hidden")
  local section=gui_oil_config.get_extractor_section(d)
  for _,quality in ipairs{"normal","uncommon","rare","epic","legendary","epic"} do
   local oil=gui_oil_config.get(d)
   gui_test_click(p,oil.gui.selections[section.name.."_quality"][quality])
   assert(oil.qualities[section.name]==quality and oil.choices[section.name.."_quality_choice"]==quality,"oil quality choice not saved")
   assert(gui_test_quality_badge(d.gui.selections.miner.pumpjack)=="quality/"..quality,"oil badge did not follow its quality selector")
   assert(d.choices.miner_quality_choice=="legendary","oil quality changed mining equipment quality")
   assert(gui_test_quality_badge(d.gui.selections.miner["big-mining-drill"])=="quality/legendary","oil quality overwrote drill badge")
  end
  gui_test_oil_placement(p)
 elseif gui_test_phase==5 then
  gui_test_capture(p,"oil")
 elseif gui_test_phase==6 then
  gui_test_click(p,d.gui.selections.miner["big-mining-drill"])
  assert(d.choices.layout_choice~="oil" and d.gui.output_settings_root.visible)
  assert(gui_test_quality_badge(d.gui.selections.miner.pumpjack)=="quality/epic","oil quality badge disappeared when returning to mining")
 elseif gui_test_phase==7 then
  log("GUI SCENE COMPLETE: compact mining, station and oil captured")
 end
 gui_test_phase=gui_test_phase+1;gui_test_tick=game.tick+30
end)
