-- Exercise the real layout callbacks and router with a counted LuaSurface stand-in.
local function copy(t,seen)
  if type(t)~="table" then assert(type(t)~="function"); return t end
  seen=seen or {}
  if seen[t] then return seen[t] end
  local result={}; seen[t]=result
  for k,v in pairs(t) do result[copy(k,seen)]=copy(v,seen) end
  return result
end
table.deepcopy=copy
defines={direction={north=0,east=4,south=8,west=12}}
serpent={line=function() return "" end}
log=function(err) error(err) end
package.loaded["layouts.base"]={restrictions={}}
package.loaded["oil.config"]={module_plan=function() end}
package.loaded["mpp.preview_diagnostics"]={}
package.loaded["mpp.builder"]={record_preview=function(state,spec) table.insert(state._preview_specs,spec) end}
local function box(r) return {left_top={x=-r,y=-r},right_bottom={x=r,y=r}} end
local function proto(name,r)
  -- Factorio returns a fresh bounding box on access.
  return setmetatable({name=name,selection_box=box(r),collision_mask={layers={object=true}}},
    {__index=function(_,k) if k=="collision_box" then return box(r-.1) end end})
end
prototypes={entity={},quality={normal={name="normal",level=0}}}
for _,name in ipairs{"pumpjack","pipe","pipe-to-ground","heat-pipe","beacon","pole"} do
  prototypes.entity[name]=proto(name,(name=="pumpjack" or name=="beacon") and 1.5 or .5)
end
prototypes.entity.pumpjack.fluidbox_prototypes={{production_type="output",pipe_connections={{positions={
  {x=1,y=-1},{x=1,y=1},{x=-1,y=1},{x=-1,y=-1}}}}}}
prototypes.entity["pipe-to-ground"].max_underground_distance=10
prototypes.entity.beacon.get_supply_area_distance=function() return 3 end
prototypes.entity.pole.get_supply_area_distance=function() return 2.5 end
prototypes.entity.pole.get_max_wire_distance=function() return 7.5 end
package.loaded["mpp.obstacles"]={ignored_entities=function() return {} end,collect=function() return {} end,blocked_bounds=function() return false end,
  blocked_box=function() return false end, entity_box=function() return box(.4) end}

local function plan(points,opts)
  local per_tick, total, peak=0,0,0
  local surface={planet={prototype={entities_require_heating=opts.heat}}}
  surface.count_entities_filtered=function(query)
    per_tick=per_tick+1
    return opts.north_blocked and query.position.x==1.5 and query.position.y==-1.5 and 1 or 0
  end
  surface.count_tiles_filtered=function() per_tick=per_tick+1; return 0 end
  surface.find_entities_filtered=function() return {} end
  local created={}
  surface.create_entity=function(spec)
    if opts.fail_after and #created>=opts.fail_after then return nil end
    spec.valid=true
    spec.destroy=function() spec.valid=false end
    created[#created+1]=spec
    return spec
  end
  local state={player={force={valid=true},mod_settings={},print=function() end},surface=surface,resources={},
    preview_only=not opts.build,_preview_specs={},_collected_ghosts={},oil_settings={choices={
      oil_pumpjack_choice="pumpjack",pipe_choice="pipe",["pipe-to-ground_choice"]=opts.underground and "pipe-to-ground" or "none",
      ["heat-pipe_choice"]=opts.heat and "heat-pipe" or "none",beacon_choice=opts.beacons and "beacon" or "none",
      pole_choice=opts.poles and "pole" or "none"},qualities={},min_beacon_utility=1}}
  for _,p in ipairs(points) do table.insert(state.resources,{valid=true,type="resource",name="crude-oil",
    position={x=p[1]+.5,y=p[2]+.5},prototype={resource_category="oil"}}) end
  local layout=require("layouts.oil")
  state._previous_state={_collected_ghosts={{valid=true,order_deconstruction=function()
    error("oil planning scheduled an earlier plan's ghost for removal")
  end}}}
  local callback=layout:start(state)
  local restored={}
  for tick=1,20000 do
    per_tick=0
    local result=layout[callback](layout,state)
    total,peak=total+per_tick,math.max(peak,per_tick)
    assert(per_tick<=768,"unbounded world queries")
    if result==false then
      if opts.fail_after then
        assert(state.preview_error and #state._collected_ghosts==0 and #created==opts.fail_after)
        for _,ghost in ipairs(created) do assert(not ghost.valid,"partial construction survived rollback") end
        return
      end
      assert(not state.preview_error, state.preview_error and state.preview_error[1])
      return opts.build and state._collected_ghosts or state._preview_specs, total, peak, restored
    end
    if result~=true then callback=result end
    local job=state.oil_job
    if opts.reload and job then
      local phase=job.phase
      if job.tree and job.tree.search_target then phase=phase.."-merge"
      elseif job.tree and job.tree.head then phase=phase.."-flood"
      elseif job.scan_x and phase=="scan" then phase="mid-scan" end
      if not restored[phase] then
        restored[phase]=true
        state.oil_job=copy(job)
        package.loaded["layouts.oil"],package.loaded["oil.vendor.planner"]=nil,nil
        layout=require("layouts.oil")
      end
    end
  end
  error("oil planning did not finish")
end

local single=plan({{0,0}},{north_blocked=true,heat=true,reload=true})
local pump,pipe,heated
for _,s in ipairs(single) do
  if s.inner_name=="pumpjack" then pump=s elseif s.inner_name=="pipe" then pipe=s else heated=heated or s.inner_name=="heat-pipe" end
end
local offsets={[4]={2,1},[8]={-1,2},[12]={-2,-1}}
local offset=assert(offsets[pump.direction],"pump remained north")
assert(heated and pipe.position.x==pump.position.x+offset[1] and pipe.position.y==pump.position.y+offset[2])

local function signatures(specs)
  local keys={}
  for _,s in ipairs(specs) do table.insert(keys,s.inner_name..":"..s.position.x..","..s.position.y..":"..(s.direction or 0)) end
  table.sort(keys); return table.concat(keys,"|")
end
local points={{0,0},{32,2},{14,19}}
local preview=plan(points,{underground=true,beacons=true,poles=true})
local build=plan(points,{underground=true,beacons=true,poles=true,reload=true,build=true})
assert(signatures(preview)==signatures(build),"reload or Apply changed the plan")
for _,name in ipairs{"pole","beacon","pipe-to-ground"} do assert(signatures(build):find(name..":",1,true),name) end
local large,total,peak,restored=plan({{0,0},{75,65}},{reload=true})
assert(total>15000 and peak<=768 and restored["mid-scan"] and restored["pipes-flood"] and restored["pipes-merge"])
assert(#large>100,"distant pumps lost their connecting pipeline")
plan({{0,0},{75,65}},{build=true,fail_after=70})
print("Oil planning: bounded scan and routing, save/load, heated outlets, beacons, poles and Apply passed")
