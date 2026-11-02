-- Real same-side station feeds: transforms, native pickup/drop targets, and
-- measured equal delivery to all six feeds per wagon.
local through_station=require("mpp.train_station")
local through_cases,through_results={},{}
for _,name in ipairs{"express-transport-belt","turbo-transport-belt"} do
 for index,dir in ipairs{0,4,8,12} do for _,mirror in ipairs{false,true} do
  through_cases[#through_cases+1]={belt=name,direction=dir,mirror=mirror,inputs=({1,4,24,8})[index]}
 end end
end
through_cases[#through_cases+1]={belt="express-transport-belt",direction=8,mirror=false,inputs=34}
through_cases[#through_cases+1]={belt="turbo-transport-belt",direction=8,mirror=false,inputs=30}
for _,name in ipairs{"express-transport-belt","turbo-transport-belt"} do
 for _,n in ipairs{2,3,10,20,28,40} do
  through_cases[#through_cases+1]={belt=name,direction=8,mirror=false,inputs=n}
 end
 local weights={}
 for i=1,24 do weights[i]=i<=12 and .05 or .95 end
 through_cases[#through_cases+1]={belt=name,direction=4,mirror=true,inputs=24,weights=weights}
end
through_cases[#through_cases+1]={belt="express-transport-belt",direction=8,mirror=false,inputs=7}
through_cases[#through_cases+1]={belt="express-transport-belt",direction=8,mirror=true,inputs=7,weights={.2,1,.8,.1,.5,.7,.3}}
through_cases[#through_cases+1]={belt="turbo-transport-belt",direction=4,mirror=false,inputs=7,weights={0,0,0,0,0,0,1}}
local partial={}
for i=1,24 do partial[i]=i%6==0 and 0 or 1 end
through_cases[#through_cases+1]={belt="express-transport-belt",direction=0,mirror=true,inputs=24,weights=partial}
if through_visual then through_cases={
 {belt="express-transport-belt",direction=8,mirror=false,inputs=24},
 {belt="turbo-transport-belt",direction=8,mirror=false,inputs=24}}
end
if through_case_filter then through_cases={assert(through_cases[through_case_filter])} end
local through_index,through_phase,through_start=0,"next",0
local through_seen,through_supply
local through_surface,through_layout,through_inputs,through_feeds,through_boxes,through_arms,through_counts,through_wagons
local function through_key(p) return string.format("%.1f,%.1f",p.x,p.y) end
local function through_begin()
 through_index=through_index+1
 local c=through_cases[through_index]
 if not c then through_phase="done";log("PLACEMENT COMPLETE: same-side station feeds and native loading PASS");return end
 local force=game.forces.player;force.research_all_technologies();force.belt_stack_size_bonus=3
 through_layout=assert(through_station.geometry(c.inputs,{output_wagon_count_choice=4},c.belt,c.weights))
 assert(through_layout.outputs==24 and #through_layout.loading_inputs==24)
 through_surface=game.create_surface("station-through-"..through_index,{width=0,height=0,autoplace_controls={}})
 local left,top,right,bottom=-250,-250,250,250
 for _,piece in ipairs(through_layout.specs) do
  local q=through_station.transform_piece(piece,c.direction,c.mirror)
  left=math.min(left,math.floor(q.x)-8);right=math.max(right,math.ceil(q.x)+8)
  top=math.min(top,math.floor(q.y)-8);bottom=math.max(bottom,math.ceil(q.y)+8)
 end
 through_surface.request_to_generate_chunks({(left+right)/2,(top+bottom)/2},math.ceil(math.max(right-left,bottom-top)/64)+1);through_surface.force_generate_chunk_requests()
 for _,e in pairs(through_surface.find_entities()) do e.destroy() end
 local tiles={};for y=top,bottom do for x=left,right do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 through_surface.set_tiles(tiles);through_surface.daytime=0;through_surface.freeze_daytime=true;through_surface.destroy_decoratives{}
 local entities,belts,poles={},{},{}
 through_boxes,through_arms,through_wagons={},{},{};through_seen={};through_supply={}
 for _,p in ipairs(through_layout.specs) do
  local q=through_station.transform_piece(p,c.direction,c.mirror)
  q.x,q.y=q.x+1,q.y+1
  assert(through_surface.can_place_entity{name=q.name,position={q.x,q.y},direction=q.direction,force=force},"station collision: "..helpers.table_to_json(q))
  local e=assert(through_surface.create_entity{name=q.name,position={q.x,q.y},direction=q.direction,type=q.type,force=force})
  if q.input_priority then e.splitter_input_priority=q.input_priority end
  if q.output_priority then e.splitter_output_priority=q.output_priority end
  if q.filter then e.splitter_filter=q.filter end
  entities[#entities+1]=e;belts[through_key(e.position)]=e
  if e.type=="electric-pole" then poles[#poles+1]=e end
  if e.type=="container" then through_boxes[#through_boxes+1]=e end
  if e.type=="inserter" then through_arms[#through_arms+1]=e end
 end
 for _,e in ipairs(entities) do if e.type=="underground-belt" then
  assert(e.underground_belt_neighbour,"unpaired station underground: "..through_key(e.position))
 end end
 local supply=through_surface.create_entity{name="electric-energy-interface",position={-245,-245},force=force}
 local supply_pole=through_surface.create_entity{name="big-electric-pole",position={-245,-243},force=force}
 supply.power_production=1e13;supply.electric_buffer_size=1e13;supply.energy=1e13
 assert(supply_pole.get_wire_connector(defines.wire_connector_id.pole_copper,true).connect_to(poles[1].get_wire_connector(defines.wire_connector_id.pole_copper,true),false,defines.wire_origin.script))
 for i=1,6 do
  local p=through_station.transform_piece({x=3+7*(i-1),y=0,direction=12,station_stock=true},c.direction,c.mirror)
  p.x,p.y=p.x+1,p.y+1
  local e=assert(through_surface.create_entity{name=i<=2 and "locomotive" or "cargo-wagon",position={p.x,p.y},orientation=p.orientation,force=force})
  if i>2 then through_wagons[#through_wagons+1]=e end
 end
 through_inputs,through_feeds,through_counts={},{},{}
 for _,port in ipairs(through_layout.inputs) do
  local p=through_station.transform_piece({x=port.x,y=port.y,direction=8},c.direction,c.mirror)
  p.x,p.y=p.x+1,p.y+1
  local e=belts[through_key(p)] or assert(through_surface.create_entity{name=c.belt,position={p.x,p.y},direction=p.direction,force=force})
  through_inputs[#through_inputs+1]=e
 end
 for i,port in ipairs(through_layout.loading_inputs) do
  local x,y=through_station.transform(port.x,port.y-1,c.direction,c.mirror)
  through_feeds[i]=assert(belts[through_key{x=x+1,y=y+1}]);through_counts[i]=0
 end
 through_phase="flow";through_start=game.tick;game.speed=16
end
script.on_nth_tick(1,function()
 if through_phase=="done" then return end
 if through_phase=="next" then through_begin();return end
 local c=through_cases[through_index]
 local elapsed=game.tick-through_start
 local warmup=#through_layout.specs>2500 and 12000 or 6000
 for i,e in ipairs(through_inputs) do for side=1,2 do
  if c.weights then
   local key=2*i+side
   through_supply[key]=math.min(2,(through_supply[key] or 0)+c.weights[i]*prototypes.entity[c.belt].belt_speed*4)
   if through_supply[key]>=1 and e.get_transport_line(side).insert_at_back{name="iron-ore",count=1} then through_supply[key]=through_supply[key]-1 end
  else e.get_transport_line(side).insert_at_back{name="iron-ore",count=1} end
 end end
 if elapsed==120 then
  for _,e in ipairs(through_arms) do assert(e.pickup_target and e.drop_target and e.energy>0,"native station arm misses power, chest, tunnel or wagon") end
 end
 if through_phase=="flow" then
  for i,e in ipairs(through_feeds) do for side=1,2 do
   local n=e.get_transport_line(side).remove_item{name="iron-ore",count=1000}
   if elapsed>warmup then through_counts[i]=through_counts[i]+n end
  end end
  if elapsed<warmup+1800 then return end
  local low,high,total=math.huge,0,0
  for _,count in ipairs(through_counts) do low=math.min(low,count);high=math.max(high,count);total=total+count end
  assert(low>0 and high-low<=math.max(12,total/24*.03),"all 24 station feeds must balance, including across wagon groups: "..helpers.table_to_json(through_counts))
  local belt_rate=prototypes.entity[c.belt].belt_speed*480
  for group,g in ipairs(through_layout.groups) do
   local a,b,sum=math.huge,0,0
   for i=6*(group-1)+1,6*group do a=math.min(a,through_counts[i]);b=math.max(b,through_counts[i]);sum=sum+through_counts[i] end
   assert(a>0 and b-a<=math.max(12,sum/6*.03),"six feeds are not balanced: "..helpers.table_to_json(through_counts))
   assert(sum/30>.99*belt_rate*math.min(g.load,6),"wagon group lost capacity: "..group.." "..sum/30)
  end
  local units=0
  if c.weights then for _,v in ipairs(c.weights) do units=units+v end else units=c.inputs end
  local rate=belt_rate*math.min(units,24)
  assert(total/30>.99*rate,"station balancer throttles its inputs: "..(total/30).." expected "..rate)
  through_results[#through_results+1]={case=c,feeds=24,counts=through_counts,total_per_second=total/30,groups=through_layout.groups}
  if c.inputs>=24 then through_phase="load";through_start=game.tick else through_phase="finish" end
 elseif through_phase=="load" then
  for i,chest in ipairs(through_boxes) do if chest.get_inventory(defines.inventory.chest).get_item_count("iron-ore")>0 then through_seen[i]=true end end
  if elapsed<900 then return end

  for i,chest in ipairs(through_boxes) do assert(through_seen[i],"one side of the station never receives ore: "..through_key(chest.position)) end
  for _,wagon in ipairs(through_wagons) do assert(wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count("iron-ore")>0,"cargo wagon was not loaded") end
  through_results[#through_results].loaded_boxes=#through_boxes
  if through_visual then game.take_screenshot{surface=through_surface,position={20,-12},resolution={2200,1600},zoom=1.2,
   show_gui=false,show_entity_info=false,anti_alias=true,path=c.belt.."-station.png"} end
  through_phase="finish";through_start=game.tick
 elseif through_phase=="finish" then
  if game.tick-through_start<120 then return end
  log("PLACEMENT THROUGH STATION "..helpers.table_to_json(through_results[#through_results]))
  helpers.write_file("station-through.json",helpers.table_to_json(through_results),false)
  game.delete_surface(through_surface);through_phase="next"
 end
end)
