-- Measure each facing pair immediately after its local merge, before the exit.
local weave=require("mpp.compact_big_rows")
local weave_util=require("mpp.mpp_util")
local weave_grid=require("mpp.grid_mt")
local weave_cases={"transport-belt","fast-transport-belt","express-transport-belt","turbo-transport-belt"}
local weave_index,weave_pair,weave_started,weave_map,weave_state,weave_drills,weave_probes,weave_counts=0
local weave_results={}
local function weave_enable(index)
 for i,m in ipairs(weave_drills[index]) do
  local e=assert(weave_map.create_entity{name="big-mining-drill",position={m.x+2.5,m.y+2.5},
   direction=weave_util.clamped_rotation(m.direction,weave_state.miner.rotation_bump),force=game.forces.player})
  e.get_module_inventory().insert{name="speed-module-3",count=4};weave_drills[index][i]=e
 end
end
local function weave_begin()
 weave_index=weave_index+1
 if not weave_cases[weave_index] then log("PLACEMENT COMPLETE: facing-pair local weave throughput PASS");return end
 local force=game.forces.player;force.research_all_technologies();force.mining_drill_productivity_bonus=100;force.belt_stack_size_bonus=3
 weave_map=game.create_surface("weave-"..weave_index,{width=96,height=96,autoplace_controls={}})
 weave_map.request_to_generate_chunks({0,0},2);weave_map.force_generate_chunk_requests()
 for _,e in pairs(weave_map.find_entities()) do e.destroy() end
 local tiles={};for y=-32,31 do for x=-32,31 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 weave_map.set_tiles(tiles);weave_map.daytime=0;weave_map.freeze_daytime=true;weave_map.destroy_decoratives{}
 local G=setmetatable({},weave_grid)
 for y=-10,20 do G[y]={};for x=-10,30 do G[y][x]={x=x,y=y} end end
 local upper,lower={},{}
 for i=0,3 do
  upper[#upper+1]={x=5*i,y=0,direction=defines.direction.south}
  lower[#lower+1]={x=5*i,y=7,direction=defines.direction.north}
 end
 local name=weave_cases[weave_index]
 weave_state={grid=G,miner=weave_util.miner_struct("big-mining-drill"),belt_choice=name,belt=weave_util.belt_struct(name),belts={}}
 for j,g in ipairs(weave.groups(upper,lower,function() return 1 end,1)) do
  weave_state.belts[j]={lane1=g.lane1,lane2=g.lane2,x_start=-6,x2=g.lane1[#g.lane1].x+2,
   turn_x=g.lane1[1].x+1,y=4+j,source_y=5,capacity_weave=true}
 end
 for i=0,3 do
  local y=6-i%2
  G:build_thing_simple(5*i,y,"pole");G:build_thing_simple(5*i-1,y,"lamp")
  weave_map.create_entity{name="medium-electric-pole",position={5*i+.5,y+.5},force=force}
  weave_map.create_entity{name="small-lamp",position={5*i-.5,y+.5},force=force}
 end
 assert(weave.belts(weave_state,function(_,x,y) error("local weave cannot route "..name.." at "..x..","..y) end))
 local belts={}
 for _,p in ipairs(weave_state.builder_belts) do
  local e=assert(weave_map.create_entity{name=p.name,position={p.grid_x+.5,p.grid_y+.5},direction=p.direction,type=p.type,force=force})
  belts[p.grid_x..","..p.grid_y]=e
 end
 weave_drills,weave_probes={},{}
 for i=0,3 do
  weave_drills[i+1]={}
  weave_probes[i+1]=assert(belts[(5*i)..","..(5+i%2)])
  for _,m in ipairs{upper[i+1],lower[i+1]} do
   for dy=0,4 do for dx=0,4 do weave_map.create_entity{name="iron-ore",position={m.x+dx+.5,m.y+dy+.5},amount=1000000} end end
   weave_drills[i+1][#weave_drills[i+1]+1]=m
  end
 end
 weave_map.create_entity{name="medium-electric-pole",position={-3.5,9.5},force=force}
 local power=weave_map.create_entity{name="electric-energy-interface",position={-4,8},force=force}
 power.power_production=1e12;power.electric_buffer_size=1e12;power.energy=1e12
 weave_pair=0;weave_started=game.tick;weave_counts={0,0}
end
script.on_nth_tick(1,function()
 if weave_index==0 then game.speed=8;weave_begin();return end
 if weave_index>#weave_cases then return end
 if weave_pair==0 then weave_pair=1;weave_enable(1) end
 local elapsed=game.tick-weave_started
 local probe=weave_probes[weave_pair]
 for side=1,2 do
  local n=probe.get_transport_line(side).remove_item{name="iron-ore",count=1000}
  if elapsed>600 then weave_counts[side]=weave_counts[side]+n end
 end
 if elapsed<1800 then return end
 local capacity=weave_state.belt.speed*4
 local rates={weave_counts[1]/20,weave_counts[2]/20}
 assert(rates[1]>.95*capacity and rates[2]>.95*capacity,"facing pair not full on both sides beside the drills: "..helpers.table_to_json(rates))
 weave_results[#weave_results+1]={belt=weave_cases[weave_index],pair=weave_pair,side_capacity=capacity,rates=rates}
 log("PLACEMENT LOCAL WEAVE "..helpers.table_to_json(weave_results[#weave_results]))
 for _,e in ipairs(weave_drills[weave_pair]) do e.destroy() end
 weave_pair=weave_pair+1;weave_counts={0,0};weave_started=game.tick
 if weave_pair>4 then
  helpers.write_file("paired-weave.json",helpers.table_to_json(weave_results),false)
  weave_begin()
 else weave_enable(weave_pair) end
end)
