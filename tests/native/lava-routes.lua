-- Real terrain, planner, cursor events, blueprint revival and end-to-end item flow.
local lava_terrain=require("mpp.terrain")
local lava_obstacles=require("mpp.obstacles")
local lava_balancer=require("mpp.output_balancer")
local lava_cases={}
for _,tile in ipairs{"lava","lava-hot"} do
 for _,shape in ipairs{"barrier","neck","winding"} do
  for _,direction in ipairs{"east","north","south","west"} do
   lava_cases[#lava_cases+1]={id=tile.."-"..shape.."-"..direction,tile=tile,shape=shape,direction=direction,
    direct=direction=="south",mode=direction=="south" and "forced" or nil,auto=direction=="west"}
  end
 end
 for _,shape in ipairs{"sealed","endpoint"} do
  for _,fill in ipairs{false,true} do
   lava_cases[#lava_cases+1]={id=tile.."-"..shape..(fill and "-fill" or "-avoid"),tile=tile,
    shape=shape,direction="east",fill=fill,blocked=not fill}
  end
 end
end
for _,tile in ipairs{"lava","lava-hot"} do
 lava_cases[#lava_cases+1]={id=tile.."-neck-superforced",tile=tile,shape="neck",direction="east",direct=true,mode="superforced"}
end
if lava_internal then
 lava_cases={}
 for _,tile in ipairs{"lava","lava-hot"} do
  for _,shape in ipairs{"pools","channels","peninsulas"} do
   for _,auto in ipairs{false,true} do
    for _,direction in ipairs{"east","north","south","west"} do
     lava_cases[#lava_cases+1]={id=tile.."-internal-"..shape.."-"..direction..(auto and "-auto" or "-single"),
      tile=tile,shape=shape,direction=direction,auto=auto}
    end
   end
  end
 end
 for _,tile in ipairs{"lava","lava-hot"} do
  lava_cases[#lava_cases+1]={id=tile.."-internal-channels-fill",tile=tile,shape="channels",direction="east",fill=true,auto=true}
 end
end
-- Exploratory terrain survey: failure and partial coverage are results,
-- not passes. Keep the strict regression matrices above fail-fast.
if lava_diverse then
 lava_cases={}
 for shape_index,shape in ipairs{"pockmarks","diagonal","branching","crescent","islands","maze"} do
  for _,setting in ipairs{{"east",true},{"west",true},{"north",false}} do
   for _,fill in ipairs{false,true} do
    lava_cases[#lava_cases+1]={id="survey-"..shape.."-"..setting[1]..(fill and "-fill" or "-avoid"),
     tile=shape_index%2==0 and "lava-hot" or "lava",shape=shape,direction=setting[1],auto=setting[2],fill=fill}
   end
  end
 end
end
if lava_case_start or lava_case_end then
 local remaining={}
 local first,last=lava_case_start or 1,lava_case_end or #lava_cases
 assert(lava_cases[first] and lava_cases[last] and first<=last,"invalid lava case range")
 for i=first,last do remaining[#remaining+1]=lava_cases[i] end
 lava_cases=remaining
end
if lava_case_filter then lava_cases={(assert(lava_cases[lava_case_filter],"invalid lava case"))}
elseif lava_visual then lava_cases=lava_diverse and {lava_cases[1],lava_cases[7],lava_cases[13],lava_cases[19],lava_cases[25],lava_cases[31]} or lava_internal and {lava_cases[1],lava_cases[13],lava_cases[21]} or {lava_cases[5],lava_cases[9]} end
local lava_index,lava_phase,lava_test=0,"next",nil
local lava_results={}
local lava_items={"iron-plate","copper-plate","steel-plate","stone","coal","iron-ore","copper-ore",
 "stone-brick","electronic-circuit","advanced-circuit","processing-unit","plastic-bar","sulfur","battery",
 "iron-gear-wheel","copper-cable","pipe","engine-unit","electric-engine-unit","solid-fuel","uranium-235","uranium-238"}
local function lava_transform(x,y)
 local d=lava_test.case.direction
 if d=="north" then return {x=y,y=-x} end
 if d=="south" then return {x=-y,y=x} end
 if d=="west" then return {x=-x,y=-y} end
 return {x=x,y=y}
end
local function lava_error(message)
 error("LAVA ROUTE "..lava_test.case.id.." ("..lava_phase.."): "..message)
end
local function lava_check(ok,message) if not ok then lava_error(message) end end
local function lava_hazard(c,x,y)
 if c.shape=="pockmarks" then
  for ix=0,5 do for iy=0,3 do
   local cx,cy=15+16*ix+3*math.sin(iy*2+ix),13+18*iy+3*math.cos(ix*1.7+iy)
   local radius=2.2+(ix+iy*2)%3
   if ((x-cx)/radius)^2+((y-cy)/(radius*.85))^2<1+.12*math.sin(x+y) then return true end
  end end
  return false
 elseif c.shape=="diagonal" then
  return x>=8 and x<=104 and math.abs(y-(.66*x+5+4*math.sin(x*.12)))<3.5
 elseif c.shape=="branching" then
  local stem=y>=39 and y<=78 and math.abs(x-(55+4*math.sin(y*.13)))<3.2
  local left=y>=8 and y<=43 and math.abs(x-(16+y*.95))<3.2
  local right=y>=8 and y<=43 and math.abs(x-(96-y*.95))<3.2
  return stem or left or right
 elseif c.shape=="crescent" then
  local ring=((x-57)/34)^2+((y-42)/28)^2
  local inner=((x-59)/22)^2+((y-42)/17)^2
  -- A narrow dry opening links the inner basin to the outer shore.
  return ring<1+.05*math.sin(x*.3+y*.2) and inner>1 and not (x>=57 and math.abs(y-42)<2)
 elseif c.shape=="islands" then
  if x<12 or x>100 or y<6 or y>78 then return false end
  for _,island in ipairs{{29,22,7},{54,19,6},{83,24,8},{25,54,6},{53,45,8},{82,59,7},{51,69,4}} do
   if (x-island[1])^2+(y-island[2])^2<island[3]^2 then return false end
  end
  return true
 elseif c.shape=="maze" then
  for i=0,4 do
   local center=22+17*i+2*math.sin(y*.15+i)
   if math.abs(x-center)<3.2 and y>=6+(i%2)*17 and y<=60+(i%2)*17 then return true end
  end
  return false
 elseif c.shape=="pools" then
  for _,pool in ipairs{{25,22,10,7},{56,43,13,9},{84,23,9,12},{31,62,9,6}} do
   if ((x-pool[1])/pool[3])^2+((y-pool[2])/pool[4])^2 < 1+.17*math.sin(x*.6+y*.3) then return true end
  end
  return false
 elseif c.shape=="channels" then
  return y>=8 and y<=73 and (math.abs(x-(33+9*math.sin(y*.09)))<3.2 or math.abs(x-(76+8*math.sin(y*.12)))<4)
 elseif c.shape=="peninsulas" then
  return (x>=16 and x<=83 and math.abs(y-(26+6*math.sin(x*.1)))<4)
   or (x>=35 and x<=109 and math.abs(y-(57+5*math.sin(x*.1)))<4)
 elseif c.shape=="barrier" then
  return x>=78 and x<=86 and y>=-24+2*math.sin(x) and y<=72+2*math.cos(x)
 elseif c.shape=="neck" or c.shape=="sealed" then
  local outer=x>=-20 and x<=88 and y>=-24 and y<=72
  local inner=x>=-12 and x<=78 and y>=-16 and y<=64
  local opening=c.shape=="neck" and x>=78 and y>=16 and y<=33
  return outer and not inner and not opening
 elseif c.shape=="winding" then
  local center=20+14*math.sin((x-76)*math.pi/46)
  return x>=76 and x<=122 and y>=-96 and y<=128 and (y<math.floor(center)-9 or y>math.floor(center)+9)
 else return x>=148 and x<=168 and y>=4 and y<=42 end
end
local function lava_click(button,mode)
 script.get_event_handler(defines.events.on_gui_click){player_index=1,element=lava_test.data.gui[button],
  button=defines.mouse_button_type.left,control=mode=="superforced",shift=mode=="forced"}
end
local function lava_capture(path)
 if not lava_visual then return end
 local distance=lava_test.report.output_distance or 160.5
 local center=lava_internal and math.floor(distance/2) or 70
 local zoom=lava_internal and math.min(.38,2400/(32*(distance+36))) or .38
 game.take_screenshot{surface=lava_test.surface,position=lava_transform(center,lava_internal and 40 or 24),resolution={2400,1500},
  zoom=zoom,show_gui=false,show_entity_info=false,anti_alias=true,path=path or lava_test.case.id..".png"}
end
local function lava_finish()
 local t=lava_test
 t.report.passed=t.report.error==nil
 if lava_diverse then
  t.report.transport_ok=t.report.passed
  t.report.full_coverage=t.report.passed and t.report.ore_uncovered==0
  if t.report.ore_uncovered then t.report.coverage_percent=100*(1-t.report.ore_uncovered/t.report.ore_tiles) end
  t.report.status=t.report.error and (t.report.failure_phase=="mine" or t.report.failure_phase=="preview") and "rejected"
   or t.report.error and "invalid" or t.report.full_coverage and "complete" or "partial"
 end
 lava_results[#lava_results+1]=t.report
 helpers.write_file(lava_diverse and "lava-terrain.json" or lava_internal and "lava-mine.json" or "lava-routes.json",helpers.table_to_json(lava_results),false)
 log("PLACEMENT LAVA "..(t.report.passed and "PASS " or "FAIL ")..helpers.table_to_json(t.report))
 if t.data.preview then preview.cancel(t.data,true) end
 algorithm.cleanup_last_state(t.data)
 belt_planner.clear_belt_planner_stack(t.data)
 t.player.clear_cursor()
 t.player.teleport({0,0},game.surfaces[1]);game.delete_surface(t.surface)
 lava_phase="next"
end
local function lava_begin()
 lava_index=lava_index+1
 local c=lava_cases[lava_index]
 if not c then lava_phase="done";log("PLACEMENT COMPLETE: "..#lava_results..(lava_diverse and " exploratory lava scenarios recorded; see lava-terrain.json for coverage and failures" or " native lava routing and live item flow scenarios PASS"));return end
 local p=game.get_player(1);conf.initialize_global(p.index);p.set_controller{type=defines.controllers.god}
 p.force.research_all_technologies();p.force.mining_drill_productivity_bonus=lava_internal and c.auto and 3 or 0;p.force.belt_stack_size_bonus=0
 local s=game.create_surface("lava-routes-"..lava_index,{width=512,height=512,autoplace_controls={}})
 s.request_to_generate_chunks({0,0},8);s.force_generate_chunk_requests()
 for _,e in pairs(s.find_entities()) do e.destroy() end
 s.destroy_decoratives{};s.daytime=0;s.freeze_daytime=true
 lava_test={case=c,player=p,surface=s,data=storage.players[p.index],report={id=c.id,shape=c.shape,direction=c.direction,tile=c.tile,fill=c.fill==true,auto=c.auto==true}}
 local tiles={}
 for x=-192,192 do for y=-160,160 do
  local pos=lava_transform(x+.5,y+.5);pos.x=math.floor(pos.x);pos.y=math.floor(pos.y)
  tiles[#tiles+1]={name=lava_hazard(c,x,y) and c.tile or "volcanic-folds",position=pos}
 end end
 s.set_tiles(tiles);p.teleport(lava_transform(32,24),s)
 local resources={}
 local width,height=lava_internal and 112 or 64,lava_internal and 84 or 48
 for x=0,width-1 do for y=0,height-1 do
  if ((x-width/2)/(width/2-1))^2+((y-height/2)/(height/2-1))^2<1+.1*math.sin(y*.6+x*.2)
   and (not lava_internal or not lava_hazard(c,x,y)) then
   resources[#resources+1]=s.create_entity{name="tungsten-ore",position=lava_transform(x+.5,y+.5),amount=100000}
  end
 end end
 lava_test.resources=resources;lava_test.report.ore_tiles=#resources
 local v=lava_test.data.choices
 v.layout_choice="compact";v.mining_layout_choice="compact";v.direction_choice=c.direction
 v.miner_choice="big-mining-drill";v.miner_quality_choice="normal";v.module_choice="none";v.beacon_choice="none"
 v.belt_choice="express-transport-belt";v.belt_quality_choice="normal";v.pole_choice="medium-electric-pole";v.pole_quality_choice="normal"
 v.pipe_choice="pipe";v.lamp_choice=true;v.force_pipe_placement_choice=false
 v.belt_merge_choice=c.auto==true;v.belt_load_min_choice=.8;v.belt_load_max_choice=1.1
 v.belt_planner_choice=true;v.output_balance_choice=true;v.output_belt_count_choice=4;v.output_station_choice=false
 v.cliff_mode_choice="avoid";v.terrain_mode_choice="avoid";v.remove_entities_choice=false;v.remove_trees_choice=false;v.remove_rocks_choice=false
 for _,flag in ipairs(lava_terrain.tile_choices) do v[flag]=flag=="fill_lava_choice" and c.fill==true end
 gui.show_interface(p)
 lava_test.target={position=lava_transform(160.5,20.5),direction=defines.direction[c.direction]}
 if lava_visual and lava_diverse then lava_capture(c.id.."-terrain.png") end
 lava_phase="mine";preview.select{player_index=p.index,surface=s,entities=resources}
 log("PLACEMENT LAVA START "..c.id)
 game.speed=20
end
local function lava_audit_specs(specs)
 local t=lava_test;local entities,fills=0,0
 for _,spec in ipairs(specs) do
  if spec.name=="tile-ghost" then
   fills=fills+1
   lava_check(t.case.fill and spec.inner_name=="foundation","unexpected terrain cover")
  elseif spec.name=="entity-ghost" then
   entities=entities+1
   for _,tile in pairs(t.surface.find_tiles_filtered{area=lava_obstacles.entity_box(spec.inner_name,spec.position,spec.direction)}) do
    lava_check(not lava_terrain.blocks_tile(tile,t.data.choices),"entity footprint crosses forbidden lava: "..helpers.table_to_json{spec=spec,tile={name=tile.name,position=tile.position}})
   end
  end
 end
 t.report.preview_entities=entities;t.report.foundation_tiles=fills
 if t.case.fill then lava_check(fills>0,"fill requested but foundation missing") end
end
local function lava_start_flow()
 local t=lava_test
 lava_check(not t.data.preview and t.data.last_state,"Apply failed")
 local fills=t.surface.find_entities_filtered{type="tile-ghost"}
 t.report.placed_foundations=#fills
 if t.case.fill then lava_check(#fills>0,"Apply lost foundations") else lava_check(#fills==0,"avoid lava built foundations") end
 -- Revive the actual applied ghosts, so real native collision and underground pairing apply.
 for _,e in pairs(fills) do local ok=e.revive();lava_check(ok,"foundation revival failed") end
 local ghosts=t.surface.find_entities_filtered{type="entity-ghost"}
 t.report.placed_entities=#ghosts
 local undergrounds=0
 t.drills={};t.poles={};t.worked={}
 for _,e in pairs(ghosts) do
  local name,pos=e.ghost_name,e.position
  local _,built=e.silent_revive{raise_revive=true}
  lava_check(built and built.valid,"cannot revive "..name.." at "..helpers.table_to_json(pos))
  if built.type=="underground-belt" then undergrounds=undergrounds+1 end
  if built.type=="mining-drill" then t.drills[#t.drills+1]=built end
  if built.type=="electric-pole" then t.poles[#t.poles+1]=built end
 end
 t.report.undergrounds=undergrounds
 t.outlets={};t.received={};t.outlet_counts={}
 local delta=mpp_util.direction_coord[t.target.direction]
 for i=0,3 do
  local p={x=t.target.position.x-delta.y*i,y=t.target.position.y+delta.x*i}
  local e=t.surface.find_entities_filtered{position=p,radius=.05,type="transport-belt"}[1]
  lava_check(e and e.direction==t.target.direction,"missing or reversed output "..i)
  t.outlets[#t.outlets+1]=e;t.outlet_counts[#t.outlet_counts+1]=0
 end
 t.report.inputs=t.spec.count;t.report.outputs=#t.outlets
 if lava_internal then
  local supply=t.surface.create_entity{name="electric-energy-interface",position={-180,-145},force=t.player.force}
  local pole=t.surface.create_entity{name="big-electric-pole",position={-180,-143},force=t.player.force}
  supply.power_production=1e13;supply.electric_buffer_size=1e13;supply.energy=1e13
  lava_check(pole.get_wire_connector(defines.wire_connector_id.pole_copper,true).connect_to(
   t.poles[1].get_wire_connector(defines.wire_connector_id.pole_copper,true),false,defines.wire_origin.script),"supply connection failed")
  t.flow_start=game.tick;lava_phase="mining";return
 end
 lava_check(t.spec.count*2<=#lava_items,"not enough distinct input markers")
 t.expected={}
 for i,source in ipairs(t.spec) do
  local e=t.surface.find_entities_filtered{position={math.floor(source.world_x)+.5,math.floor(source.world_y)+.5},radius=.05,type="transport-belt"}[1]
  lava_check(e,"source belt missing: "..i.." "..source.world_x..","..source.world_y)
  for side=1,2 do
   local name=lava_items[(i-1)*2+side];t.expected[name]=4
   for _,pos in ipairs{0,.25,.5,.75} do
    lava_check(e.get_transport_line(side).insert_at(pos,{name=name,count=1}),"input injection failed")
   end
  end
 end
 lava_capture();t.flow_start=game.tick;lava_phase="flow"
end
local function lava_tick()
 if lava_phase=="done" then return end
 if lava_phase=="next" then lava_begin();return end
 local t=lava_test;local d=t.data;local v=d.preview
 if #storage.tasks>0 or #storage.immediate_tasks>0 or v and (v.refresh_at or v.render_job or v.output_job or v.applying) then return end
 if lava_phase=="mine" then
  if not (v and v.ready) then helpers.write_file("lava-mine-failed.json",helpers.table_to_json{case=t.case,error=v and v.error,issues=v and v.issues,specs=v and v.specs},false) end
  lava_check(v and v.ready,"mine preview failed: "..helpers.table_to_json(v and v.error or {}))
  t.spec=v.belt_specification
  lava_check(t.spec and t.spec.count>1,"fixture needs multiple mine outputs")
  if lava_internal then
   -- Larger balancers can extend back into the mine at a fixed output
   -- distance. Leave an empty input corridor so this fixture tests lava
   -- detours, rather than asking two planned structures to overlap.
   local layout=assert(lava_balancer.geometry(t.spec.count,4,"express-transport-belt"))
   local depth=0
   for _,port in ipairs(layout.inputs) do depth=math.max(depth,layout.output_y-port.y) end
   local delta=mpp_util.direction_coord[t.target.direction]
   local source=0
   for _,input in ipairs(t.spec) do source=math.max(source,(input.world_x+.5)*delta.x+(input.world_y+.5)*delta.y) end
   local distance=math.max(160.5,source+depth+t.spec.count+4)
   t.target.position=lava_transform(distance,20.5);t.report.output_distance=distance
  end
  if t.case.direct then
   lava_check(preview.apply(d),"base mine Apply failed");lava_phase="direct"
  else preview.set_belt_target(d,t.target);lava_phase="preview" end
 elseif lava_phase=="direct" then
  lava_check(not d.preview and d.last_state,"base mine not applied")
  d.belt_cursor_direction=t.target.direction
  lava_check(input_mode.output(d,t.player),"output cursor unavailable")
  local count=#t.player.cursor_stack.get_blueprint_entities()
  local delta=mpp_util.direction_coord[t.target.direction]
  t.player.build_from_cursor{position={x=t.target.position.x-delta.y*(count-1)/2,y=t.target.position.y+delta.x*(count-1)/2},
   direction=defines.direction.north,build_mode=defines.build_mode[t.case.mode]}
  lava_phase="applied"
 elseif lava_phase=="preview" then
  lava_check(v~=nil,"output preview disappeared")
  lava_check(t.surface.count_entities_filtered{type={"entity-ghost","tile-ghost"}}==0,"preview mutated world")
  if t.case.blocked then
   lava_check(not v.ready and v.error,"sealed/blocked target accepted")
   lava_check(not preview.apply(d),"blocked Apply succeeded")
   t.report.expected_blocked=true;t.report.error=v.error
   lava_click("preview_force");lava_phase="blocked-forced";return
  end
  if not v.ready then
   local tiles={}
   for x=60,170 do for y=-40,90 do local tile=t.surface.get_tile(x,y);tiles[#tiles+1]={x=x,y=y,name=tile.name} end end
   local inputs={}
   for _,input in ipairs(t.spec) do inputs[#inputs+1]={x=input.world_x,y=input.world_y} end
   helpers.write_file("lava-failed-preview.json",helpers.table_to_json{case=t.case,inputs=inputs,specs=v.specs,issues=v.issues,tiles=tiles},false)
  end
  lava_check(v.ready,"output cannot route: "..helpers.table_to_json(v.error or {}))
  lava_audit_specs(v.specs)
  if lava_internal then helpers.write_file("lava-mine-specs.json",helpers.table_to_json(v.specs),false) end
  lava_click("preview_apply");lava_phase="applied"
 elseif lava_phase=="blocked-forced" or lava_phase=="blocked-superforced" then
  lava_check(v and not v.ready and v.error,"forced placement bypassed forbidden terrain")
  lava_check(t.surface.count_entities_filtered{type={"entity-ghost","tile-ghost"}}==0,"blocked force mutated world")
  if lava_phase=="blocked-forced" then lava_click("preview_force","superforced");lava_phase="blocked-superforced"
  else t.report.force_rejected=true;lava_finish() end
 elseif lava_phase=="applied" then
  -- Audit direct cursor paths too, which have no preview to inspect.
  local specs={}
  for _,e in pairs(t.surface.find_entities_filtered{type={"entity-ghost","tile-ghost"}}) do
   specs[#specs+1]={name=e.type,inner_name=e.ghost_name,position=e.position,direction=e.direction}
  end
  lava_audit_specs(specs);lava_start_flow()
 elseif lava_phase=="mining" then
  for i,belt in ipairs(t.outlets) do for side=1,2 do
   t.outlet_counts[i]=t.outlet_counts[i]+belt.get_transport_line(side).remove_item{name="tungsten-ore",count=100}
  end end
  for _,drill in ipairs(t.drills) do
   if drill.status==defines.entity_status.working then t.worked[drill.unit_number]=true end
  end
  if game.tick-t.flow_start==300 then
   local reverse,reached,queue={}, {}, {}
   local bad={unpaired={},unpowered={},disconnected={}};local native_belts={}
   for _,e in pairs(t.surface.find_entities_filtered{type={"transport-belt","underground-belt","splitter"}}) do
    local outgoing={}
    native_belts[#native_belts+1]={name=e.name,position=e.position,direction=e.direction,type=e.type=="underground-belt" and e.belt_to_ground_type or nil,force=e.force.name,quality=e.quality.name}
    if e.type=="underground-belt" and not e.underground_belt_neighbour then bad.unpaired[#bad.unpaired+1]={position=e.position,direction=e.direction,type=e.belt_to_ground_type} end
    if e.type=="underground-belt" and e.belt_to_ground_type=="input" then
     if e.underground_belt_neighbour then outgoing[1]=e.underground_belt_neighbour end
    else outgoing=e.belt_neighbours.outputs end
    for _,b in pairs(outgoing) do local r=reverse[b.unit_number] or {};reverse[b.unit_number]=r;r[#r+1]=e end
   end
   for _,e in ipairs(t.outlets) do queue[#queue+1]=e end
   local head=1
   while queue[head] do
    local e=queue[head];head=head+1
    if not reached[e.unit_number] then reached[e.unit_number]=true;for _,up in ipairs(reverse[e.unit_number] or {}) do queue[#queue+1]=up end end
   end
   for _,e in pairs(t.surface.find_entities_filtered{type={"mining-drill","electric-pole","lamp"}}) do
    if e.electric_network_id~=t.poles[1].electric_network_id or (e.type~="electric-pole" and e.energy<=0) then bad.unpowered[#bad.unpowered+1]={name=e.name,position=e.position,network=e.electric_network_id,energy=e.energy,status=e.status} end
   end
   local covered={}
   for _,drill in ipairs(t.drills) do
    local area=drill.mining_area
    for y=math.floor(area.left_top.y),math.ceil(area.right_bottom.y)-1 do for x=math.floor(area.left_top.x),math.ceil(area.right_bottom.x)-1 do covered[x..","..y]=true end end
    if not drill.drop_target or not reached[drill.drop_target.unit_number] then bad.disconnected[#bad.disconnected+1]={position=drill.position,drop=drill.drop_position} end
   end
   helpers.write_file("lava-mine-audit.json",helpers.table_to_json{case=t.case,bad=bad,native_belts=native_belts,first_network=t.poles[1].electric_network_id},false)
   lava_check(#bad.unpaired==0 and #bad.unpowered==0 and #bad.disconnected==0,"internal mine audit: "..helpers.table_to_json(bad))
   t.report.drills=#t.drills;t.report.unpaired=0;t.report.unpowered=0;t.report.disconnected=0
   t.report.ore_uncovered=0
   for _,ore in ipairs(t.resources) do if not covered[math.floor(ore.position.x)..","..math.floor(ore.position.y)] then t.report.ore_uncovered=t.report.ore_uncovered+1 end end
  end
  if game.tick-t.flow_start>=3600 then
   local n=0;for _ in pairs(t.worked) do n=n+1 end
   lava_check(n==#t.drills,"some drills never mined: "..n.."/"..#t.drills)
   t.report.working_drills=n;t.report.outlet_ore=t.outlet_counts
   for _,count in ipairs(t.outlet_counts) do lava_check(count>0,"an output carries no mined ore") end
   local total=0;for _,count in ipairs(t.outlet_counts) do total=total+count end
   lava_check(total>100,"no actual ore delivered");t.report.ore_delivered=total
   if lava_visual then
    lava_capture()
    if lava_index==#lava_cases then lava_capture("lava-routing-complete.png") end
    t.capture_until=game.tick+120;lava_phase="capture"
   else lava_finish() end
  end
 elseif lava_phase=="flow" then
  for i,belt in ipairs(t.outlets) do for side=1,2 do
   local line=belt.get_transport_line(side)
   for name in pairs(t.expected) do
    local count=line.remove_item{name=name,count=100}
    t.received[name]=(t.received[name] or 0)+count;t.outlet_counts[i]=t.outlet_counts[i]+count
   end
  end end
  local total,expected=0,0
  for name,n in pairs(t.expected) do total=total+(t.received[name] or 0);expected=expected+n end
  -- Splitters can retain a few items in their native internal buffers with
  -- intermittent input. Require every source *side* to reach the outlet, and
  -- account for every remaining marker; belts/tunnels must drain completely.
  local delivered=true
  for name in pairs(t.expected) do if (t.received[name] or 0)<2 then delivered=false end end
  local buffered,remaining={},{}
  if delivered and game.tick-t.flow_start>2400 or game.tick-t.flow_start>6000 then
   for _,e in pairs(t.surface.find_entities_filtered{type={"transport-belt","underground-belt","splitter"}}) do
    for line=1,e.get_max_transport_line_index() do
     local contents=e.get_transport_line(line).get_contents()
     if #contents>0 then
      remaining[#remaining+1]={name=e.name,position=e.position,direction=e.direction,line=line,contents=contents}
      for _,item in pairs(contents) do buffered[item.name]=(buffered[item.name] or 0)+item.count end
      if e.type~="splitter" then delivered=false end
     end
    end
   end
   for name,n in pairs(t.expected) do
    if (t.received[name] or 0)+(buffered[name] or 0)~=n or (buffered[name] or 0)>2 then delivered=false end
   end
  else delivered=total==expected end
  if delivered then
   for i,n in ipairs(t.outlet_counts) do lava_check(n>0,"output "..i.." carries no items") end
   t.report.items_injected=expected;t.report.items_delivered=total;t.report.splitter_buffered=expected-total
   t.report.outlet_items=t.outlet_counts;t.report.flow_ticks=game.tick-t.flow_start
   if lava_visual then
    if lava_index==#lava_cases then
     game.take_screenshot{surface=t.surface,position=lava_transform(70,24),resolution={2400,1500},zoom=.38,
      show_gui=false,show_entity_info=false,anti_alias=true,path="lava-routing-complete.png"}
    end
    t.capture_until=game.tick+120;lava_phase="capture"
   else lava_finish() end
  elseif game.tick-t.flow_start>6000 then
   helpers.write_file("lava-stalled.json",helpers.table_to_json{case=t.case,remaining=remaining},false)
   lava_error("items did not reach output: "..helpers.table_to_json{expected=t.expected,received=t.received,outlets=t.outlet_counts})
  end
 elseif lava_phase=="capture" and game.tick>=t.capture_until then lava_finish()
 end
end
script.on_nth_tick(1,function()
 if not lava_diverse then return lava_tick() end
 local ok,err=pcall(lava_tick)
 if not ok then
  if not lava_test or lava_test.report.error then error(err) end
  local t=lava_test
  t.report.error=tostring(err);t.report.failure_phase=lava_phase
  local v=t.data.preview
  t.report.preview_error=v and v.error;t.report.issues=v and v.issues
  if lava_visual then
   lava_capture()
   if lava_index==#lava_cases then lava_capture("lava-routing-complete.png") end
   t.capture_until=game.tick+120;lava_phase="capture"
  else lava_finish() end
 end
end)
