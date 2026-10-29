-- Actual engine recipes, technology events and settings controls; headless.
local terrain_warning_done=false
script.on_nth_tick(1,function()
 if terrain_warning_done then return end
 terrain_warning_done=true
 local p=game.get_player(1)
 conf.initialize_global(p.index)
 p.set_controller{type=defines.controllers.god}
 p.force.research_all_technologies()
 local force=p.force
 local d=storage.players[p.index]
 gui.show_interface(p)
 local function control(name) return d.gui.selections.misc[name] end
 local function expect(name,warning)
  local c=control(name)
  assert(c and c.valid and c.enabled,"unresearched fill must remain enabled: "..name)
  assert((c.caption[1]=="mpp.fill_research_warning_caption")==warning,"wrong research warning: "..name)
 end
 local function research(name,researched)
  local tech=force.technologies[name]
  tech.researched=researched
  script.get_event_handler(researched and defines.events.on_research_finished or defines.events.on_research_reversed){research=tech}
 end
 for _,name in ipairs{"fill_water","fill_lava","fill_oil_ocean"} do expect(name,false) end
 research("landfill",false);research("foundation",false);research("planet-discovery-aquilo",false)
 assert(not force.recipes.landfill.enabled and not force.recipes.foundation.enabled and not force.recipes["ice-platform"].enabled)
 for _,name in ipairs{"fill_water","fill_lava","fill_oil_ocean"} do
  expect(name,true)
  for _,state in ipairs{false,true} do
   local c=control(name);c.state=state
   script.get_event_handler(defines.events.on_gui_checked_state_changed){player_index=p.index,element=c}
   assert(d.choices[name.."_choice"]==state,"warning blocked checkbox")
   expect(name,true)
  end
 end
 -- Research refresh must not rebuild controls or overwrite edits/selections.
 local water=control("fill_water")
 research("landfill",true)
 expect("fill_water",false);expect("fill_lava",true);expect("fill_oil_ocean",true)
 assert(water.valid and water==control("fill_water") and water.state,"research rebuilt or reset checkbox")
 research("foundation",true)
 expect("fill_lava",false);expect("fill_oil_ocean",false)
 research("foundation",false)
 expect("fill_lava",true);expect("fill_oil_ocean",true)
 local origin=p.surface
 local aquilo=game.planets.aquilo.surface or game.planets.aquilo.create_surface()
 p.teleport({0,0},aquilo)
 script.get_event_handler(defines.events.on_player_changed_surface){player_index=p.index,surface_index=origin.index}
 expect("fill_water",true)
 assert(helpers.table_to_json(control("fill_water").tooltip):find("ice-platform",1,true),"Aquilo warning must name ice platform")
 research("planet-discovery-aquilo",true)
 expect("fill_water",false)
 assert(control("fill_water").state,"Aquilo research reset selected fill")
 p.teleport({0,0},origin)
 script.get_event_handler(defines.events.on_player_changed_surface){player_index=p.index,surface_index=aquilo.index}
 expect("fill_water",false)
 local unlocked=game.create_force("terrain-warning-unlocked")
 unlocked.research_all_technologies()
 p.force=unlocked
 script.get_event_handler(defines.events.on_player_changed_force){player_index=p.index,force=force}
 expect("fill_lava",false);expect("fill_oil_ocean",false)
 p.force=force
 script.get_event_handler(defines.events.on_player_changed_force){player_index=p.index,force=unlocked}
 expect("fill_lava",true);expect("fill_oil_ocean",true)
 research("foundation",true)
 -- Oil mode shares the same advisory controls.
 d.choices.layout_choice="oil";gui.show_interface(p)
 research("foundation",false)
 expect("fill_lava",true);expect("fill_oil_ocean",true)
 assert(control("fill_oil_ocean").state,"oil mode reset fill choice")
 log("PLACEMENT COMPLETE: terrain research warnings, editable options, live unlock/reversal, Aquilo, force and oil mode")
end)
