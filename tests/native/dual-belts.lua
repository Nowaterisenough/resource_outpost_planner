-- Native saturation test of the actual big-drill router, including belt sides.
local dual_layout=require("layouts.capacity_rows")
local dual_util=require("mpp.mpp_util")
local dual_grid=require("mpp.grid_mt")
local dual_surface,dual_state,dual_outputs,dual_start,dual_counts,dual_supply,dual_drills
local dual_case=0
local dual_sides
local dual_results={}
local function dual_begin()
 dual_case=dual_case+1
 local force=game.forces.player
 force.research_all_technologies();force.mining_drill_productivity_bonus=100;force.belt_stack_size_bonus=3
 dual_surface=game.create_surface("dual-belt-throughput-"..dual_case,{width=96,height=96,autoplace_controls={}})
 dual_surface.request_to_generate_chunks({0,0},2);dual_surface.force_generate_chunk_requests()
 for _,e in pairs(dual_surface.find_entities()) do e.destroy() end
 local tiles={};for y=-32,31 do for x=-32,31 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
 dual_surface.destroy_decoratives{}
 dual_surface.set_tiles(tiles);dual_surface.daytime=0;dual_surface.freeze_daytime=true
 local grid=setmetatable({},dual_grid)
 for y=-10,15 do grid[y]={};for x=-10,30 do grid[y][x]={x=x,y=y} end end
 local S=defines.direction.south
 dual_state={_capacity_rows=true,_capacity_tight_big=true,_capacity_compact=true,belt_merge_choice=true,
  grid=grid,miner=dual_util.miner_struct("big-mining-drill"),belt_choice="express-transport-belt",belt_quality_choice="normal",
  belt=dual_util.belt_struct("express-transport-belt"),belts={}}
 dual_state._capacity_tight_big=dual_case==2
 dual_state.player=game.get_player(1)
 dual_state.belt_load_min_choice=.8
 if dual_case==1 then
  for j=1,2 do
   local x=(j-1)*10+2
   dual_state.belts[j]={index=j,x_start=-6,x1=x,x2=x+5,turn_x=x-1,
    y=4+j,source_y=5,is_output=true,lane1={{x=x-2},{x=x+3}},throughput1=4}
  end
  dual_layout:_prepare_edge_belts(dual_state)
  assert(not dual_state.preview_error,"native baseline routing failed")
 else
  for j=1,4 do
   local x=(j-1)*5+2;local paired=j%2==0
   dual_state.belts[j]={index=j,x_start=-6,x1=x,x2=x,turn_x=paired and x-3 or x-1,
    y=paired and 6 or 4+math.ceil(j/2),source_y=5,is_output=not paired,
    capacity_target=paired and j-1 or nil,lane1={{x=x-2}},throughput1=4}
  end
  assert(dual_layout:_prepare_compact_belts(dual_state),helpers.table_to_json(dual_state._capacity_route_failure or {}))
 end
 dual_outputs={}
 for _,spec in ipairs(dual_state.builder_belts) do
  local e=assert(dual_surface.create_entity{name=spec.name,position={spec.grid_x+.5,spec.grid_y+.5},direction=spec.direction,type=spec.type,force=force})
  if spec.grid_x==-6 and spec.direction==defines.direction.west then dual_outputs[#dual_outputs+1]=e end
 end
 assert(#dual_outputs==dual_case,"independent outlet count differs")
 dual_drills={}
 for j=1,4 do
  local x=(j-1)*5
  for y=0,4 do for dx=0,4 do dual_surface.create_entity{name="iron-ore",position={x+dx+.5,y+.5},amount=1000000} end end
  local miner=assert(dual_surface.create_entity{name="big-mining-drill",position={x+2.5,2.5},direction=dual_util.clamped_rotation(S,dual_state.miner.rotation_bump),force=force})
  miner.get_module_inventory().insert{name="speed-module-3",count=4}
  dual_drills[#dual_drills+1]=miner
 end
 dual_surface.create_entity{name="substation",position={9,-3},force=force}
 dual_supply=dual_surface.create_entity{name="electric-energy-interface",position={9,-6},force=force}
 dual_supply.power_production=1e12;dual_supply.electric_buffer_size=1e12;dual_supply.energy=1e12
 dual_counts={0,0};dual_sides={{0,0},{0,0}};dual_start=game.tick
end
script.on_nth_tick(1,function()
 if dual_case==0 then game.speed=4;dual_begin();return end
 if dual_case>2 then return end
 local elapsed=game.tick-dual_start
 if dual_visual and elapsed==1200 then
  game.take_screenshot{surface=dual_surface,position={6,1},resolution={1600,700},zoom=1.5,
   show_gui=false,show_entity_info=false,anti_alias=true,path="dual-belts-"..dual_case..".png"}
 end
 if elapsed==120 then for _,miner in ipairs(dual_drills) do assert(miner.drop_target,"native mining output has no receiving belt") end end
 for i,belt in ipairs(dual_outputs) do for side=1,2 do
  local n=belt.get_transport_line(side).remove_item{name="iron-ore",count=100}
  if elapsed>600 then dual_counts[i]=dual_counts[i]+n;dual_sides[i][side]=dual_sides[i][side]+n end
 end end
 if elapsed>=1800 then
  local rates={};for i=1,#dual_outputs do rates[i]=dual_counts[i]/20 end
  local total=0;for _,rate in ipairs(rates) do total=total+rate;assert(rate>153,"outlet does not carry its receiving lane: "..rate) end
  for i=1,#dual_outputs do for side=1,2 do
   assert(dual_sides[i][side]>1530,"outlet has an unused belt side")
  end end
  dual_results[#dual_results+1]={outputs=#dual_outputs,items_per_second=rates,total=total,sides=dual_sides}
  log("DUAL BELT THROUGHPUT "..helpers.table_to_json(dual_results[#dual_results]))
  dual_surface.clear(true)
  if dual_case==1 then dual_begin() else
   assert(dual_results[2].total>1.8*dual_results[1].total,"second corridor did not increase throughput")
   helpers.write_file("dual-belt-throughput.json",helpers.table_to_json(dual_results),false)
   dual_case=3;log("PLACEMENT COMPLETE: dual belt native throughput")
  end
 end
end)
