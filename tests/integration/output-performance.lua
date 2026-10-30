local perf_preview=require('mpp.preview')
local perf_output=require('mpp.output_preview')
local perf_gui=require('gui.gui')
local perf_conf=require('configuration')
local perf_obstacles=require('mpp.obstacles')
local perf_planner=require('mpp.belt_planner')
local perf_renderer=require('mpp.preview_renderer')
local perf_station=require('mpp.train_station')
local perf_simple=require('layouts.simple')
local perf_cache=require('mpp.preview_output_cache')
local perf_balancer=require('mpp.output_balancer')
local perf_util=require('mpp.mpp_util')
local scenario=output_performance_scenario or 'outputs'
local first_station=scenario=='station-first'
local applied_station=scenario=='station-output-only'
local dense_scenario=scenario=='dense-repeat' or scenario=='dense-station' or first_station or applied_station
local load_scenario=scenario=='load' or scenario=='load-repeat' or scenario=='load-output-only' or dense_scenario
local capture_snapshots=output_performance_capture~=false
local perf_active,perf_stats,perf_calls=false,{},{}
local function timing(label,fn,...)
 if not perf_active then return fn(...) end
 local timer=helpers.create_profiler()
 local a,b,c=fn(...)
 timer.stop()
 local stat=perf_stats[label]
 if not stat then stat={timer=helpers.create_profiler(true),count=0};perf_stats[label]=stat end
 stat.timer.add(timer);stat.count=stat.count+1
 if label=='render' or label=='render_step' and a then
  local reused=b and table_size(b) or 0
  perf_calls.render_created=(perf_calls.render_created or 0)+#a-reused
  perf_calls.render_reused=(perf_calls.render_reused or 0)+reused
 end
 return a,b,c
end
local function wrap(module,name,label)
 local fn=module[name];module[name]=function(...) return timing(label,fn,...) end
end
wrap(perf_obstacles,'collect','obstacle_scan')
wrap(perf_planner,'plan','routing_total')
wrap(perf_planner,'place_landfill','landfill')
wrap(perf_renderer,'render','render')
if perf_renderer.begin then wrap(perf_renderer,'begin','render_begin');wrap(perf_renderer,'step','render_step') end
wrap(perf_station,'geometry','station_geometry')
wrap(perf_planner,'update_blueprint','cursor')
wrap(perf_preview,'complete','complete')
wrap(perf_output,'refresh','output_refresh')
wrap(perf_cache,'resume','cache_validate')
wrap(perf_cache,'refresh','cache_refresh')
local function verify_station_ingress(state,route)
 local cells,ports,used={},{},{}
 local function key(x,y) return x..','..y end
 for _,p in ipairs(route) do
  local k=key(p.grid_x,p.grid_y);assert(not cells[k],'station ingress overlaps');cells[k]=p
 end
 for _,p in ipairs(state.belt_input_targets) do ports[key(p.x,p.y)]=true end
 for _,source in ipairs(state.belt_specification) do
  local node=cells[key(source.x_start-1,source.y)]
  assert(node,'station source disconnected')
  local seen,arrival={},defines.direction.west
  while node do
   local k=key(node.grid_x,node.grid_y)
   assert(not seen[k] and node.direction~=(arrival+8)%16,'station ingress loops or reverses')
   seen[k]=true
   local delta=perf_util.direction_coord[node.direction]
   local next=cells[key(node.grid_x+delta.x,node.grid_y+delta.y)]
   if not next then
    assert(node.direction==state.belt_direction and ports[k] and not used[k],'station ingress misses or shares a port')
    used[k]=true
   end
   arrival=node.direction;node=next
  end
 end
 assert(table_size(used)==#state.belt_input_targets,'unconnected station port')
 if perf_active then perf_calls.verified_station_lanes=(perf_calls.verified_station_lanes or 0)+#state.belt_input_targets end
end
local perf_station_plan=perf_station.plan
perf_station.plan=function(state,route)
 return timing('station_total',perf_station_plan,state,function(connection)
  local ok,result,diagnostic=timing('routing_bundle',route,connection)
  if ok and capture_snapshots then verify_station_ingress(connection,result) end
  return ok,result,diagnostic
 end)
end
local perf_balance_plan=perf_balancer.plan
perf_balancer.plan=function(state,route)
 return timing('balancer_total',perf_balance_plan,state,function(...) return timing('routing_bundle',route,...) end)
end
local profiled={}
for _,layout in pairs(algorithm.layouts) do if not profiled[layout] then
 local old_tick=layout.tick
 layout.tick=function(self,state) return timing('mining_'..tostring(state._callback),old_tick,self,state) end
 profiled[layout]=true
end end
for _,name in ipairs{'can_place','blocked_box','shared_entity'} do
 local fn=perf_obstacles[name]
 perf_obstacles[name]=function(...) if perf_active then perf_calls[name]=(perf_calls[name] or 0)+1 end;return fn(...) end
end
local cases={
 {name='belts-near',x=-25,y=-25,dir=0},
 {name='belts-moved',x=-27,y=-23,dir=0},
 {name='balance-3-8',balance=true,x=13,y=-43,dir=0},
 {name='station-3-8',station=true,x=65,y=65,dir=0},
 {name='station-mirrored',station=true,x=65,y=65,dir=0,mirror=true},
 {name='station-3-10',station=true,wagons=5,x=13,y=-43,dir=0,mirror=true},
 {name='station-far',station=true,wagons=5,x=201,y=151,dir=4},
 {name='station-over-mine',station=true,x=13,y=13,dir=0},
 {name='belts-water-wall',x=-25,y=-25,dir=0,water=true},
 {name='blocked-output',x=-25,y=-25,dir=0,blocked=true},
}
if scenario=='fill' then cases={
 {name='belts-water-fill',x=-25,y=-25,dir=0,water=true,fill=true},
 {name='balance-lava-fill',balance=true,x=13,y=-43,dir=0,water=true,fill=true,tile='lava'},
 {name='station-oil-fill',station=true,x=13,y=-43,dir=0,water=true,fill=true,tile='oil-ocean-deep'},
} elseif scenario=='large' then cases={
 {name='large-belts',x=-25,y=-25,dir=0},
 {name='large-balanced',balance=true,x=13,y=-43,dir=0},
 {name='large-station',station=true,x=101,y=101,dir=0},
} elseif scenario=='move' then cases={
 {name='station-initial',station=true,x=101,y=101,dir=0},
 {name='station-moved',station=true,x=105,y=103,dir=0},
 {name='station-rotated',station=true,x=101,y=105,dir=4},
 {name='station-flipped',station=true,x=103,y=101,dir=4,mirror=true},
} elseif scenario=='irregular' then
 cases={}
 for _,mirror in ipairs{false,true} do for _,dir in ipairs{0,4,8,12} do
  cases[#cases+1]={name='irregular-'..dir..(mirror and '-mirrored' or ''),station=true,x=65,y=65,dir=dir,mirror=mirror}
 end end
elseif scenario=='contour' then cases={
 {name='contour-top',x=75.5,y=-41.5,dir=4},
 {name='contour-middle',x=71.5,y=-16.5,dir=4},
 {name='contour-bottom',x=75.5,y=55.5,dir=4},
}
elseif scenario=='load' then cases={
 {name='load-initial',balance=true,x=-130.5,y=-16.5,dir=12},
 {name='load-moved',balance=true,x=-136.5,y=-12.5,dir=12},
 {name='load-rotated',balance=true,x=-138.5,y=-10.5,dir=0},
 {name='load-moved-again',balance=true,x=-134.5,y=-14.5,dir=12},
}
elseif scenario=='apply' then cases={{name='station-apply',station=true,x=65,y=65,dir=0}} end
if scenario=='load-repeat' or scenario=='load-output-only' or dense_scenario then
 cases={}
 for i=1,24 do cases[#cases+1]={name='load-repeat-'..i,balance=true,
  x=(dense_scenario and -275.5 or -130.5)-2*((i-1)%5),y=-16.5+2*((i-1)%3),dir=i%6==0 and 0 or 12} end
end
if scenario=='dense-station' then
 cases={}
 for i=1,8 do cases[#cases+1]={name='dense-station-'..i,station=true,
  x=-300+2*((i-1)%2),y=-180+2*((i-1)%3),dir=({0,0,4,4,8,8,12,12})[i],mirror=i%2==0} end
end
if first_station or applied_station then
 cases={}
 for _,name in ipairs{'first','repeat-1','repeat-2'} do
  cases[#cases+1]={name=name,station=true,x=-300,y=-180,dir=0}
 end
end
local phase,index,player,data,surface,start_tick=0,0
local total
local function snapshot(name,specs)
 if not capture_snapshots then return end
 local rows={}
 for _,s in ipairs(specs) do
  local p=s.position
  rows[#rows+1]={name=s.inner_name or s.name,x=p.x or p[1],y=p.y or p[2],direction=s.direction,
   type=s.type,filter=s.filter,input_priority=s.input_priority,output_priority=s.output_priority,blocked=s.preview_blocked}
 end
 helpers.write_file('output-performance/'..name..'.json',helpers.table_to_json(rows),false)
end
local function snapshot_sprites(name,objects)
 if not capture_snapshots then return end
 local rows,seen={},{}
 for _,object in ipairs(objects) do if object.valid and object.type=='sprite' then
  assert(not seen[object.id],'one sprite handle is used by multiple preview layers')
  seen[object.id]=true
  local target=object.target
  assert(target.type=='position','unexpected entity-targeted preview sprite')
  rows[#rows+1]={sprite=object.sprite,position=target.position,color=object.color,
   orientation=object.orientation,x_scale=object.x_scale,y_scale=object.y_scale}
 end end
 for _,object in pairs(rendering.get_all_objects(script.mod_name)) do
  if object.surface==surface and object.type=='sprite' then assert(seen[object.id],'obsolete preview sprite leaked') end
 end
 helpers.write_file('output-performance/'..name..'-sprites.json',helpers.table_to_json(rows),false)
end
local function report(name,ready,entities)
 log({'','OUTPUT PERF ',name,' total=',total,' ticks=',game.tick-start_tick,' ready=',tostring(ready),' entities=',entities,' calls=',helpers.table_to_json(perf_calls)})
 local keys={};for k in pairs(perf_stats) do keys[#keys+1]=k end;table.sort(keys)
 for _,k in ipairs(keys) do local s=perf_stats[k];log({'','OUTPUT PERF DETAIL ',name,' ',k,' count=',s.count,' time=',s.timer}) end
end
local function initialize()
 player=game.get_player(1);perf_conf.initialize_global(player.index);player.set_controller{type=defines.controllers.god}
 surface=game.create_surface('output-performance',{width=dense_scenario and 2048 or 640,height=dense_scenario and 2048 or 640,
  autoplace_controls={},default_enable_all_autoplace_controls=false,
  autoplace_settings={entity={treat_missing_as_default=false,settings={}},decorative={treat_missing_as_default=false,settings={}}}})
 surface.request_to_generate_chunks({0,0},dense_scenario and 20 or 10);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={};local span=dense_scenario and 600 or 300;for x=-span,span do for y=-span,span do tiles[#tiles+1]={name='grass-1',position={x,y}} end end;surface.set_tiles(tiles)
 player.teleport({-10,-10},surface);player.force.research_all_technologies()
 data=storage.players[player.index]
 local c=data.choices;c.layout_choice='simple';c.miner_choice='electric-mining-drill';c.direction_choice='north';c.belt_choice='express-transport-belt';c.pole_choice='medium-electric-pole';c.beacon_choice='none';c.module_choice='none';c.belt_merge_choice=false
 if scenario=='contour' then
  c.layout_choice='compact';c.miner_choice='big-mining-drill';c.direction_choice='east';c.belt_choice='turbo-transport-belt'
  c.beacon_choice='beacon';c.beacon_module_choice='speed-module-3';c.beacon_quality_choice='normal';c.beacon_module_quality_choice='normal'
 end
 if load_scenario then
  c.layout_choice='compact';c.miner_choice='big-mining-drill';c.miner_quality_choice='legendary';c.direction_choice='west'
  c.belt_choice='turbo-transport-belt';c.pole_quality_choice='legendary';c.module_choice='productivity-module-3'
  c.beacon_choice='beacon';c.beacon_module_choice='speed-module-3';c.beacon_quality_choice='normal';c.beacon_module_quality_choice='normal'
  c.belt_merge_choice=true;c.belt_load_min_choice=0.8;c.belt_load_max_choice=1.1
  c.output_balance_choice=true;c.output_belt_count_choice=8
  player.force.mining_drill_productivity_bonus=4;player.force.belt_stack_size_bonus=3
 end
 if dense_scenario then
  c.miner_quality_choice='normal';c.pole_quality_choice='normal';c.beacon_choice='none'
  c.module_choice='speed-module-3';c.module_quality_choice='normal';c.belt_choice='express-transport-belt'
  c.output_belt_count_choice=24;c.lamp_choice=true
  if first_station then
   c.output_balance_choice=false;c.output_station_choice=false;c.output_locomotive_count_choice=2
   c.output_wagon_count_choice=4;c.output_loading_side_choice='double';c.terrain_mode_choice='fill'
  end
 end
 perf_gui.show_interface(player)
 local edge=(scenario=='large' or scenario=='move') and 63 or 23
 local resources={}
 if scenario=='irregular' or scenario=='contour' or load_scenario then
  local scale=dense_scenario and 2 or 1
  for gx=-48*scale,48*scale-1 do for gy=-37*scale,39*scale-1 do
   local x,y=gx/scale,gy/scale
   local angle=math.atan2(y/35,x/46)
   local radius=1+0.15*math.sin(angle*5)+0.09*math.cos(angle*9)
   local inside=(x/46)^2+(y/35)^2<radius*radius
   local notch=x>14 and y>4 and y<18+7*math.sin(x/9)
   local hole=(x+11)^2+(y+4)^2<25 or (x-4)^2+(y-19)^2<12
   if inside and not notch and not hole then
    resources[#resources+1]=surface.create_entity{name='iron-ore',position={gx+.5,gy+.5},amount=50000}
   end
  end end
  assert(dense_scenario and #resources==17965 or not dense_scenario and #resources==4508,'irregular fixture changed')
 else
  for x=0,edge do for y=0,edge do resources[#resources+1]=surface.create_entity{name='iron-ore',position={x+.5,y+.5},amount=50000} end end
 end
 assert(perf_preview.select{player_index=player.index,surface=surface,entities=resources})
 phase=(scenario=='load-output-only' or applied_station) and 6 or 1
end
local function step()
 if phase==0 then initialize();return end
 if phase==4 then return end
 if phase==6 then
  if perf_preview.has_pending() or #storage.tasks>0 then return end
  assert(data.preview.ready and perf_preview.apply(data),'initial mine Apply failed')
  phase=7;return
 end
 if phase==7 then
  if data.preview or #storage.tasks>0 then return end
  assert(perf_output.begin(data,player),'applied mine output did not start')
  phase=1;return
 end
 if phase==5 then
  if data.preview or #storage.tasks>0 then return end
  perf_active=false
  local actual={}
  for _,e in pairs(surface.find_entities_filtered{type='entity-ghost'}) do
   actual[#actual+1]={name=e.ghost_name,position=e.position,direction=e.direction,
    type=e.ghost_type=='underground-belt' and e.belt_to_ground_type or nil,
    filter=e.ghost_type=='splitter' and e.splitter_filter or nil,
    input_priority=e.ghost_type=='splitter' and e.splitter_input_priority or nil,
    output_priority=e.ghost_type=='splitter' and e.splitter_output_priority or nil}
  end
  snapshot('apply-final',actual)
  report('apply-final',true,#actual)
  log('OUTPUT PERF COMPLETE');phase=4;return
 end
 if perf_preview.has_pending() or #storage.tasks>0 then return end
 if phase==1 then
  index=index+1;if not cases[index] then log('OUTPUT PERF COMPLETE');phase=4;return end
  local c=cases[index];local choices=data.choices
  choices.output_station_choice=c.station==true;choices.output_balance_choice=c.balance==true;choices.output_belt_count_choice=dense_scenario and 24 or 8;choices.output_locomotive_count_choice=2;choices.output_wagon_count_choice=c.wagons or 4;choices.output_loading_side_choice='double';choices.belt_planner_choice=true
  local tiles={};for x=-40,40 do for y=-15,-5 do tiles[#tiles+1]={name=c.water and (c.tile or 'water') or 'grass-1',position={x,y}} end end;surface.set_tiles(tiles);choices.terrain_mode_choice=c.water and not c.fill and 'avoid' or 'fill';if not first_station then choices.deconstruction_choice=c.blocked==true end
  if c.blocked then for x=-27,-21 do for y=-28,-23 do surface.create_entity{name='steel-chest',position={x+.5,y+.5},force=player.force} end end end
  if first_station or applied_station or (scenario=='move' or load_scenario) and index>1 then phase=2;return end
  data.preview.belt_target=nil;perf_preview.request(data);phase=2;return
 end
 if phase==2 then
  assert(data.preview.ready or data.preview.output_only,'base mining preview failed')
  perf_preview.give_belt_planner(data)
  local c=cases[index];perf_stats={};perf_calls={};perf_active=true;total=helpers.create_profiler(true);start_tick=game.tick
  if first_station or applied_station then data.preview.belt_target=nil end -- measure real recalculation, not the no-op guard
  timing('click',perf_preview.set_belt_target,data,{position={x=c.x,y=c.y},direction=c.dir,mirror=c.mirror})
  phase=3;return
 end
 if phase==3 then
  perf_active=false
  snapshot(cases[index].name,data.preview.specs)
  snapshot_sprites(cases[index].name,data.preview.renderings)
  report(cases[index].name,data.preview.ready,data.preview.entity_count or 0)
  if scenario=='apply' then
   perf_stats={};perf_calls={};perf_active=true;total=helpers.create_profiler(true);start_tick=game.tick
   assert(timing('apply_click',perf_preview.apply,data),'Apply refused the measured preview')
   phase=5
  else phase=1 end
 end
end
local function performance_tick(event)
 local timer=perf_active and helpers.create_profiler()
 task_runner_handler(event)
 if timer then timer.stop();total.add(timer);log({'','OUTPUT PERF TICK ',phase==5 and 'apply-final' or cases[index].name,' ',timer}) end
 step()
 if phase~=4 then script.on_event(defines.events.on_tick,performance_tick) end
end
script.on_event(defines.events.on_tick,performance_tick)
