local perf_preview=require('mpp.preview')
local perf_gui=require('gui.gui')
local perf_conf=require('configuration')
local perf_obstacles=require('mpp.obstacles')
local perf_planner=require('mpp.belt_planner')
local perf_renderer=require('mpp.preview_renderer')
local perf_station=require('mpp.train_station')
local perf_simple=require('layouts.simple')
local perf_active,perf_stats,perf_calls=false,{},{}
local function timing(label,fn,...)
 if not perf_active then return fn(...) end
 local timer=helpers.create_profiler()
 local a,b,c=fn(...)
 timer.stop()
 local stat=perf_stats[label]
 if not stat then stat={timer=helpers.create_profiler(true),count=0};perf_stats[label]=stat end
 stat.timer.add(timer);stat.count=stat.count+1
 return a,b,c
end
local function wrap(module,name,label)
 local fn=module[name];module[name]=function(...) return timing(label,fn,...) end
end
wrap(perf_obstacles,'collect','obstacle_scan')
wrap(perf_planner,'plan','routing_total')
wrap(perf_renderer,'render','render')
wrap(perf_station,'geometry','station_geometry')
wrap(perf_planner,'update_blueprint','cursor')
wrap(perf_preview,'complete','complete')
local old_tick=perf_simple.tick
perf_simple.tick=function(self,state) return timing('mining_'..tostring(state._callback),old_tick,self,state) end
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
local phase,index,player,data,surface,start_tick=0,0
local total
local function initialize()
 player=game.get_player(1);perf_conf.initialize_global(player.index);player.set_controller{type=defines.controllers.god}
 surface=game.create_surface('output-performance',{width=640,height=640,autoplace_controls={}})
 surface.request_to_generate_chunks({0,0},10);surface.force_generate_chunk_requests()
 for _,e in pairs(surface.find_entities()) do e.destroy() end
 local tiles={};for x=-300,300 do for y=-300,300 do tiles[#tiles+1]={name='grass-1',position={x,y}} end end;surface.set_tiles(tiles)
 player.teleport({-10,-10},surface);player.force.research_all_technologies()
 data=storage.players[player.index]
 local c=data.choices;c.layout_choice='simple';c.miner_choice='electric-mining-drill';c.direction_choice='north';c.belt_choice='express-transport-belt';c.pole_choice='medium-electric-pole';c.beacon_choice='none';c.module_choice='none';c.belt_merge_choice=false
 perf_gui.show_interface(player)
 local resources={};for x=0,23 do for y=0,23 do resources[#resources+1]=surface.create_entity{name='iron-ore',position={x+.5,y+.5},amount=50000} end end
 assert(perf_preview.select{player_index=player.index,surface=surface,entities=resources})
 phase=1
end
local function step()
 if phase==0 then initialize();return end
 if phase==4 then return end
 if data.preview.refresh_at or #storage.tasks>0 then return end
 if phase==1 then
  index=index+1;if not cases[index] then log('OUTPUT PERF COMPLETE');phase=4;return end
  local c=cases[index];local choices=data.choices
  choices.output_station_choice=c.station==true;choices.output_balance_choice=c.balance==true;choices.output_belt_count_choice=8;choices.output_locomotive_count_choice=2;choices.output_wagon_count_choice=c.wagons or 4;choices.output_loading_side_choice='double';choices.belt_planner_choice=true
  local tiles={};for x=-40,40 do for y=-15,-5 do tiles[#tiles+1]={name=c.water and 'water' or 'grass-1',position={x,y}} end end;surface.set_tiles(tiles);choices.terrain_mode_choice=c.water and 'avoid' or 'fill';choices.deconstruction_choice=c.blocked==true
  if c.blocked then for x=-27,-21 do for y=-28,-23 do surface.create_entity{name='steel-chest',position={x+.5,y+.5},force=player.force} end end end
  data.preview.belt_target=nil;perf_preview.request(data);phase=2;return
 end
 if phase==2 then
  assert(data.preview.ready,'base mining preview failed')
  perf_preview.give_belt_planner(data)
  local c=cases[index];perf_stats={};perf_calls={};perf_active=true;total=helpers.create_profiler(true);start_tick=game.tick
  timing('click',perf_preview.set_belt_target,data,{position={x=c.x,y=c.y},direction=c.dir,mirror=c.mirror})
  phase=3;return
 end
 if phase==3 then
  perf_active=false
  log({'','OUTPUT PERF ',cases[index].name,' total=',total,' ticks=',game.tick-start_tick,' ready=',tostring(data.preview.ready),' entities=',data.preview.entity_count or 0,' calls=',helpers.table_to_json(perf_calls)})
  local keys={};for k in pairs(perf_stats) do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys) do local s=perf_stats[k];log({'','OUTPUT PERF DETAIL ',cases[index].name,' ',k,' count=',s.count,' time=',s.timer}) end
  phase=1
 end
end
local function performance_tick(event)
 local timer=perf_active and helpers.create_profiler()
 task_runner_handler(event)
 if timer then timer.stop();total.add(timer);log({'','OUTPUT PERF TICK ',cases[index].name,' ',timer}) end
 step()
 if phase~=4 then script.on_event(defines.events.on_tick,performance_tick) end
end
script.on_event(defines.events.on_tick,performance_tick)
