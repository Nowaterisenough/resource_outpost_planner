-- Native terrain/obstruction matrix. Run scripts/test-placement.py --suite scenario-matrix.
local matrix_terrain=require("mpp.terrain")
local matrix_obstacles=require("mpp.obstacles")
local matrix_output=require("mpp.output_preview")
local matrix_cases={}
local function add(case) matrix_cases[#matrix_cases+1]=case end
local hazards={
 {"water","fill_water_choice"},{"deepwater","fill_water_choice"},
 {"lava","fill_lava_choice"},{"lava-hot","fill_lava_choice"},
 {"oil-ocean-shallow","fill_oil_ocean_choice"},{"oil-ocean-shallow-2","fill_oil_ocean_choice"},
 {"oil-ocean-deep","fill_oil_ocean_choice"},{"oil-ocean-deep-2","fill_oil_ocean_choice"},
 {"ammoniacal-ocean","fill_water_choice"},{"ammoniacal-ocean-2","fill_water_choice"},
 {"brash-ice","fill_water_choice"},
}
for _,entry in ipairs(hazards) do
 for _,scenario in ipairs{"avoid-route","fill-target","avoid-target"} do
  add{id=entry[1].."-"..scenario,tile=entry[1],fill_flag=entry[2],fill=scenario=="fill-target",
   strip=scenario=="avoid-route",blocked=scenario=="avoid-target",output_only=true}
 end
end
for _,entry in ipairs{{"water","fill_water_choice","landfill"},
 {"lava","fill_lava_choice","foundation"},{"oil-ocean-deep","fill_oil_ocean_choice","foundation"},
 {"ammoniacal-ocean","fill_water_choice","planet-discovery-aquilo"}} do
 add{id=entry[1].."-fill-unresearched",tile=entry[1],fill_flag=entry[2],locked_tech=entry[3],fill=true,output_only=true}
end
for _,entry in ipairs{hazards[1],hazards[3],hazards[7]} do
 for _,mode in ipairs{"forced","superforced"} do
  add{id=entry[1].."-fill-"..mode,tile=entry[1],fill_flag=entry[2],fill=true,mode=mode}
 end
end
for _,entry in ipairs{hazards[1],hazards[3],hazards[5],hazards[7]} do
 add{id=entry[1].."-unrelated-fill",tile=entry[1],fill_flag=entry[2],unrelated_fill=true,blocked=true}
end
for _,entry in ipairs{{"electric-mining-drill","remove_entities_choice"},{"beacon","remove_entities_choice"},
 {"transport-belt","remove_entities_choice"},{"tree-01","remove_trees_choice"},{"big-rock","remove_rocks_choice"},
 {"cliff","cliff_mode_choice"}} do
 for _,clear in ipairs{false,true} do
  add{id="mine-"..entry[1]..(clear and "-clear" or "-retain"),entity=entry[1],clear_flag=entry[2],clear=clear,mine=true}
 end
end
for _,output_only in ipairs{false,true} do
 for _,mode in ipairs{"normal","forced","superforced","clear"} do
  add{id=(output_only and "output-only-" or "full-output-")..mode,entity="steel-chest",output_only=output_only,
   clear_flag="remove_entities_choice",clear=mode=="clear",mode=mode~="clear" and mode~="normal" and mode or nil,
   blocked=mode~="clear",expect_removal=mode=="clear" or mode=="superforced",partial=mode=="forced"}
 end
end
for _,entry in ipairs{{"tree-01","remove_trees_choice"},{"big-rock","remove_rocks_choice"}} do
 for _,mode in ipairs{"normal","forced"} do
  add{id="output-"..entry[1].."-"..mode,entity=entry[1],clear_flag=entry[2],output_only=true,blocked=true,
   mode=mode=="forced" and mode or nil,expect_removal=mode=="forced"}
 end
 add{id="independent-"..entry[1],entity=entry[1],clear_flag=entry[2],mine=true,facility_clear=true}
end
local volcanic_rocks={"big-volcanic-rock","big-volcanic-rock-hot","huge-volcanic-rock","huge-volcanic-rock-hot"}
for _,name in ipairs(volcanic_rocks) do
 for _,mode in ipairs{"forced","superforced"} do
  add{id="volcanic-output-"..name.."-"..mode,entity=name,clear_flag="remove_rocks_choice",output_only=true,
   blocked=true,mode=mode,expect_removal=true}
 end
 add{id="volcanic-mine-"..name.."-clear",entity=name,clear_flag="remove_rocks_choice",clear=true,mine=true}
 for _,mode in ipairs{"forced","superforced"} do
  add{id="volcanic-pipes-"..name.."-"..mode,entity=name,clear_flag="remove_rocks_choice",mine=true,
   force_pipes=true,obstruct_type="pipe-to-ground",mode=mode,blocked=true,expect_removal=true}
 end
end
local direct_cases={}
for _,name in ipairs(volcanic_rocks) do
 for _,count in ipairs{0,1,4} do for _,mode in ipairs{"forced","superforced"} do
  direct_cases[#direct_cases+1]={id="volcanic-direct-"..name.."-"..count.."-"..mode,
   entity=name,clear_flag="remove_rocks_choice",output_only=true,direct_cursor=true,cursor=true,
   mode=mode,balance=count>0,outputs=math.max(1,count),expect_removal=true}
 end end
end
for _,mode in ipairs{"forced","superforced"} do
 direct_cases[#direct_cases+1]={id="direct-facility-"..mode,entity="steel-chest",clear_flag="remove_entities_choice",
  output_only=true,direct_cursor=true,cursor=true,mode=mode,balance=true,outputs=4,
  expect_removal=mode=="superforced",partial=mode=="forced"}
end
for i=#direct_cases,1,-1 do table.insert(matrix_cases,1,direct_cases[i]) end
-- Use the engine's cursor build path, then the actual Shift+Apply handler.
for _,name in ipairs(volcanic_rocks) do
 for _,output_only in ipairs{false,true} do for _,count in ipairs{0,1,4} do
  add{id="volcanic-cursor-"..name..(output_only and "-output" or "-full").."-"..count,
   entity=name,clear_flag="remove_rocks_choice",output_only=output_only,blocked=true,
   mode="forced",shift_apply=true,cursor=true,balance=count>0,outputs=math.max(1,count),expect_removal=true}
 end end
end
for _,tile in ipairs{"out-of-map","empty-space"} do
 add{id=tile.."-unfillable",tile=tile,fill_flag="fill_other_choice",fill=true,blocked=true}
end
add{id="station-oil-fill",tile="oil-ocean-deep",fill_flag="fill_oil_ocean_choice",fill=true,station=true}
add{id="station-oil-avoid",tile="oil-ocean-deep",fill_flag="fill_oil_ocean_choice",station=true,blocked=true}
add{id="preordered-facility",entity="steel-chest",clear_flag="remove_entities_choice",clear=true,preordered=true,output_only=true,expect_removal=true}

for _,direction in ipairs{"north","south","west"} do
 add{id="oil-fill-"..direction,tile="oil-ocean-deep",fill_flag="fill_oil_ocean_choice",fill=true,direction=direction,output_only=true}
 add{id="oil-avoid-"..direction,tile="oil-ocean-shallow",strip=true,direction=direction,output_only=true}
 add{id="facility-force-"..direction,entity="steel-chest",clear_flag="remove_entities_choice",blocked=true,
  mode="superforced",expect_removal=true,direction=direction}
end
add{id="mixed-terrain-fill-all",tile="water",mixed=true,fill=true,all_fill=true,fill_flag="fill_water_choice",output_only=true}
-- A fixed balancer spans several columns: a water-only column under the clicked
-- endpoint cannot authorize its adjacent splitters on lava/oil.
add{id="mixed-terrain-fill-water-only-blocked",tile="water",mixed=true,fill=true,fill_flag="fill_water_choice",output_only=true,blocked=true}
add{id="mixed-route-fill-water-only",tile="water",mixed=true,strip=true,fill=true,fill_flag="fill_water_choice",output_only=true,optional_fill=true}

local matrix
local function transform(x,y)
 local direction=matrix.case.direction
 if direction=="north" then return {x=20+y-16,y=16-(x-20)} end
 if direction=="south" then return {x=20-(y-16),y=16+x-20} end
 if direction=="west" then return {x=40-x,y=32-y} end
 return {x=x,y=y}
end
local function click(data,button,mode,shift)
 script.get_event_handler(defines.events.on_gui_click){player_index=1,element=data.gui[button],
  button=defines.mouse_button_type.left,control=mode=="superforced",shift=shift}
end
local function fail(message)
 error("SCENARIO "..matrix.case.id.." ("..matrix.phase.."): "..message)
end
local function check(value,message) if not value then fail(message) end end
local function overlaps(a,b)
 return a.left_top.x<b.right_bottom.x and a.right_bottom.x>b.left_top.x
  and a.left_top.y<b.right_bottom.y and a.right_bottom.y>b.left_top.y
end
local function ready(data)
 local v=data.preview
 check(v and v.ready,"preview rejected: "..helpers.table_to_json(v and v.error or {}))
 return v
end
local function finish(data,applied)
 local t,case=matrix,matrix.case
 if data.preview then preview.cancel(data,true) end
 -- Successful applications must be undone by the actual GUI handler. Only a
 -- rejected output-only preview needs its base mine cleaned up by the fixture.
 if not applied and data.last_state then algorithm.cleanup_last_state(data);data.last_state=nil end
 check(t.surface.count_entities_filtered{type={"entity-ghost","tile-ghost"}}==0,"Undo leaked ghosts")
 if t.obstruction then
  check(t.obstruction.valid,"existing entity was destroyed before robots arrived")
  check(t.obstruction.to_be_deconstructed(t.player.force)==(case.preordered==true),"Undo changed existing demolition orders")
  t.obstruction.destroy();t.obstruction=nil;t.obstructed_spec=nil
 end
 if t.changed_tiles then
  local tiles={};for _,tile in ipairs(t.changed_tiles) do tiles[#tiles+1]={name="grass-1",position=tile.position} end
  t.surface.set_tiles(tiles);t.changed_tiles=nil
 end
 if case.locked_tech then t.player.force.research_all_technologies() end
 t.report.passed=true;t.report.ticks=game.tick-t.started
 t.results[#t.results+1]=t.report
 log("PLACEMENT SCENARIO PASS "..helpers.table_to_json(t.report))
 helpers.write_file("scenario-matrix.json",helpers.table_to_json(t.results),false)
 t.phase="next"
end
local function configure(data,case)
 if case.locked_tech then matrix.player.force.technologies[case.locked_tech].researched=false end
 local c=data.choices
 c.layout_choice="compact";c.mining_layout_choice="compact";c.direction_choice=case.direction or "east"
 c.miner_choice="big-mining-drill";c.miner_quality_choice="normal"
 c.module_choice="none";c.beacon_choice="none";c.lamp_choice=true
 c.force_pipe_placement_choice=case.force_pipes==true
 c.belt_choice="express-transport-belt";c.belt_quality_choice="normal"
 c.pole_choice="medium-electric-pole";c.pole_quality_choice="normal";c.pipe_choice="pipe"
 c.belt_merge_choice=false;c.belt_planner_choice=true;c.ore_filtering_choice=false
 c.output_balance_choice=case.balance~=false;c.output_belt_count_choice=case.outputs or 4;c.output_station_choice=case.station==true
 c.output_locomotive_count_choice=1;c.output_wagon_count_choice=1;c.output_loading_side_choice="double"
 c.cliff_mode_choice="avoid";c.terrain_mode_choice="avoid"
 c.remove_entities_choice=case.facility_clear==true;c.remove_trees_choice=false;c.remove_rocks_choice=false
 for _,flag in ipairs(matrix_terrain.tile_choices) do c[flag]=case.all_fill==true or case.unrelated_fill==true and flag~=case.fill_flag end
 if case.fill_flag then c[case.fill_flag]=case.fill==true end
 if case.clear_flag then c[case.clear_flag]=case.clear_flag=="cliff_mode_choice" and (case.clear and "remove" or "avoid") or case.clear==true end
 gui.show_interface(matrix.player)
end
local function add_obstruction(data)
 local t,case=matrix,matrix.case
 local pos=transform(100.5,20.5)
 if case.mine then
  for _,s in ipairs(data.preview.specs) do if case.obstruct_type and prototypes.entity[s.inner_name].type==case.obstruct_type
    or not case.obstruct_type and s.inner_name=="big-mining-drill" then
    pos=s.position;t.obstructed_spec=s;break
   end end
 end
 if case.entity then
  local natural=case.clear_flag~="remove_entities_choice"
  t.obstruction=assert(t.surface.create_entity{name=case.entity,position=pos,force=natural and "neutral" or t.player.force,
   cliff_orientation=case.entity=="cliff" and "west-to-east" or nil})
  if case.preordered then t.obstruction.order_deconstruction(t.player.force) end
 elseif case.tile then
  check(prototypes.tile[case.tile],"missing tile prototype")
  local tiles={}
  local x1,x2,y1,y2=94,112,8,34
  if case.strip then x1,x2,y1,y2=62,68,4,36 end
  for x=x1,x2 do for y=y1,y2 do
   local pos=transform(x+.5,y+.5);pos.x=math.floor(pos.x);pos.y=math.floor(pos.y)
   local name=case.mixed and ({"water","lava","oil-ocean-deep"})[(x-x1)%3+1] or case.tile
   tiles[#tiles+1]={name=name,position=pos}
  end end
  t.changed_tiles=tiles;t.surface.set_tiles(tiles)
 end
 t.before_ghosts=t.surface.count_entities_filtered{type={"entity-ghost","tile-ghost"}}
 if case.mine then preview.request(data)
 elseif case.cursor then
  local dir=defines.direction[case.direction or "east"]
  data.belt_cursor_direction=dir
  check(input_mode.output(data,t.player),"output cursor not available")
  local count=#t.player.cursor_stack.get_blueprint_entities()
  local delta=mpp_util.direction_coord[dir]
  local target=transform(100.5,20.5)
  t.player.build_from_cursor{position={x=target.x-delta.y*(count-1)/2,y=target.y+delta.x*(count-1)/2},
   direction=defines.direction.north,build_mode=defines.build_mode[case.mode]}
  if case.direct_cursor then t.phase="applied";return end
  check(data.preview and data.preview.belt_target,"native Shift click never selected the rock-blocked output")
  check(data.preview.belt_target.position.x==target.x and data.preview.belt_target.position.y==target.y,"native output cursor shifted target")
 else preview.set_belt_target(data,{position=transform(100.5,20.5),direction=defines.direction[case.direction or "east"]}) end
 t.phase="preview"
end
local function initialize()
 local p=game.get_player(1);conf.initialize_global(1);p.set_controller{type=defines.controllers.god}
 p.force.research_all_technologies()
 local surface=game.create_surface("scenario-matrix",{width=384,height=384,autoplace_controls={}})
 surface.request_to_generate_chunks({0,0},6);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={};for x=-170,170 do for y=-150,150 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 surface.set_tiles(tiles);p.teleport({0,0},surface)
 for i,name in ipairs(volcanic_rocks) do
  for j,belt in ipairs{"transport-belt","fast-transport-belt","express-transport-belt","turbo-transport-belt"} do
   local pos={x=-140.5+i*10,y=-120.5+j*10}
   local rock=assert(surface.create_entity{name=name,position=pos,force="neutral"})
   p.clear_cursor();p.cursor_stack.set_stack{name=belt,count=1}
   p.build_from_cursor{position=pos,direction=defines.direction.east,build_mode=defines.build_mode.forced}
   local physical=surface.count_entities_filtered{position=pos,radius=.05,name=belt}
   local ghosts=surface.count_entities_filtered{position=pos,radius=.05,type="entity-ghost"}
   assert(physical==0 and ghosts==1 and rock.valid and rock.to_be_deconstructed(p.force),
    "native Shift belt placement failed: "..name.." / "..belt)
   local placed=surface.find_entities_filtered{position=pos,radius=.05,type="entity-ghost"}[1]
   assert(placed.ghost_name==belt and placed.direction==defines.direction.east,"native Shift changed belt type/direction")
   log("PLACEMENT NATIVE BELT PASS "..helpers.table_to_json{rock=name,belt=belt,ghosts=ghosts,demolition=true})
   for _,e in pairs(surface.find_entities_filtered{position=pos,radius=3,type={"entity-ghost","transport-belt","simple-entity"}}) do e.destroy() end
  end
 end
 p.clear_cursor()
 local resources={}
 for x=0,39 do for y=0,31 do
  if x>2+2*math.sin(y/4) and (x-20)^2/400+(y-16)^2/256<1 then
   resources[#resources+1]=surface.create_entity{name="iron-ore",position={x+.5,y+.5},amount=100000}
  end
 end end
 matrix={player=p,surface=surface,resources=resources,index=0,phase="next",results={}}
 game.speed=10
end
script.on_nth_tick(1,function()
 if not matrix then initialize();return end
 local t=matrix;local data=storage.players[1];local case=t.case
 if t.phase=="done" or #storage.tasks>0 or #storage.immediate_tasks>0 or data.preview and (data.preview.refresh_at or data.preview.render_job or data.preview.output_job or data.preview.applying) then return end
 if t.phase=="next" then
  t.index=t.index+1;t.case=matrix_cases[t.index];case=t.case
  if not case then
   t.phase="done";log("PLACEMENT COMPLETE: "..#t.results.." native terrain and obstruction scenarios PASS");return
  end
  t.started=game.tick;t.report={id=case.id};configure(data,case)
  preview.select{player_index=1,surface=t.surface,entities=t.resources};t.phase="mine"
 elseif t.phase=="mine" then
  ready(data)
  if case.output_only then check(preview.apply(data),"base mine did not apply");t.phase="base-applied"
  else add_obstruction(data) end
 elseif t.phase=="base-applied" then
  check(not data.preview and data.last_state,"base mine still pending")
  if not case.direct_cursor then check(matrix_output.begin(data,t.player),"output-only preview unavailable") end
  add_obstruction(data)
 elseif t.phase=="preview" then
  local v=data.preview
  check(v~=nil,"preview disappeared")
  check(t.surface.count_entities_filtered{type={"entity-ghost","tile-ghost"}}==t.before_ghosts,"preview built real ghosts")
  if t.obstruction then check(t.obstruction.to_be_deconstructed(t.player.force)==(case.preordered==true),"preview ordered demolition") end
  t.report.preview_ready=v.ready;t.report.preview_error=v.error;t.report.preview_entities=v.entity_count;t.report.fill_tiles=v.tile_count
  if case.blocked then check(not v.ready and v.error,"blocked target was accepted") else ready(data) end
  if v.ready then
   local fills=0
   for _,s in ipairs(v.specs) do
    if s.name=="tile-ghost" then
     fills=fills+1
     if case.tile then
      local tile=t.surface.get_tile(s.position)
      check(not matrix_terrain.blocks_tile(tile,data.choices),"fill ghost violates independent terrain setting")
      check(s.inner_name==tile.prototype.default_cover_tile.name,"wrong terrain cover")
     end
    elseif case.mine and not case.clear and t.obstruction then
     check(not overlaps(matrix_obstacles.entity_box(s.inner_name,s.position,s.direction),t.obstruction.bounding_box),"retained obstruction overlaps preview")
    elseif case.strip then
     for _,tile in pairs(t.surface.find_tiles_filtered{area=matrix_obstacles.entity_box(s.inner_name,s.position,s.direction)}) do
      check(not matrix_terrain.blocks_tile(tile,data.choices),"route crosses forbidden terrain")
     end
    end
   end
   if case.fill then
    if not case.optional_fill then check(fills>0,"fill enabled but cover ghosts missing") end
   else check(fills==0,"disabled fill generated terrain ghosts") end
  end
  if case.blocked and not case.mode then
   check(not preview.apply(data),"ordinary Apply accepted a blocked preview")
   finish(data);return
  end
  if case.mode then
   if case.blocked then check(not preview.apply(data),"ordinary Apply accepted obstruction before explicit force") end
   check(data.gui.preview_force.enabled,"force button unavailable on blocked preview")
   click(data,case.shift_apply and "preview_apply" or "preview_force",case.mode,case.shift_apply)
  else click(data,"preview_apply") end
  t.phase="applied"
 elseif t.phase=="applied" then
  check(not data.preview and data.last_state,"Apply failed: "..helpers.table_to_json(data.preview and data.preview.error or {}))
  if t.obstruction then
   local removed=case.expect_removal or case.clear or false
   check(t.obstruction.to_be_deconstructed(t.player.force)==removed,"obstruction removal differs from selected mode")
   t.report.demolition=removed
  end
  if case.obstruct_type then
   local expected=t.obstructed_spec
   check(expected and prototypes.entity[expected.inner_name].type==case.obstruct_type,"missing obstructed pipe fixture")
   local found=false
   for _,e in pairs(t.surface.find_entities_filtered{position=expected.position,radius=.05,type="entity-ghost"}) do
    if e.ghost_name==expected.inner_name and e.direction==expected.direction then found=true end
   end
   check(found,"forced Apply silently skipped the rock-blocked underground pipe")
   check(data.choices.remove_rocks_choice==false,"force permanently enabled rock cleanup")
  end
  t.report.ghosts=t.surface.count_entities_filtered{type="entity-ghost"}
  t.report.placed_fill_tiles=t.surface.count_entities_filtered{type="tile-ghost"}
  if case.fill then
   if not case.optional_fill then check(t.report.placed_fill_tiles>0,"Apply lost cover ghosts") end
  else check(t.report.placed_fill_tiles==0,"Apply filled disabled terrain") end
  check(t.report.ghosts>0,"Apply placed no entities")
  if not case.mine and not case.strip and not case.station and not case.partial then
   local found=false
   for _,e in pairs(t.surface.find_entities_filtered{position=transform(100.5,20.5),radius=.05,type="entity-ghost"}) do
    if e.ghost_name=="express-transport-belt" then found=true end
   end
   check(found,"output endpoint missing after Apply")
  end
  click(data,"undo_button");finish(data,true)
 end
end)
