local common=require("layouts.common")
local capacity=require("mpp.belt_capacity")
local rows=require("mpp.beacon_rows")
local obstacles=require("mpp.obstacles")
local N,S,W=defines.direction.north,defines.direction.south,defines.direction.west
local min,max,floor=math.min,math.max,math.floor
local paired={}

-- Neighbouring drill columns feed alternating complete belts. Each column
-- combines its facing drills beside their drops; the other belt tunnels under
-- that local junction. This keeps all four sides in use throughout the row.
function paired.groups(upper,lower,production,limit,retained)
 local columns,keys,rates,totals={},{},{},{0,0}
 for side,lane in ipairs{upper or {},lower or {}} do
  for _,m in ipairs(lane) do
   local rate=production(m);rates[m]=rate;totals[side]=totals[side]+rate
   if not columns[m.x] then columns[m.x]=true;keys[#keys+1]=m.x end
  end
 end
 table.sort(keys)
 local split=#keys>1 and (retained==2 or max(totals[1],totals[2])>limit+1e-8)
 for i,x in ipairs(keys) do columns[x]=split and (i-1)%2+1 or 1 end
 local result={{lane1={},lane2={},rates={0,0}}}
 if split then result[2]={lane1={},lane2={},rates={0,0}} end
 for side,lane in ipairs{upper or {},lower or {}} do for _,m in ipairs(lane) do
  local g=result[columns[m.x]]
  local target=side==1 and g.lane1 or g.lane2
  target[#target+1]=m;g.rates[side]=g.rates[side]+rates[m]
 end end
 return result
end

function paired.prepare(state,production,limit,issue)
 local M,attempt=state.miner,state.best_attempt
 state._capacity_paired=true
 state._capacity_compact=true
 -- The shared corridor needs matching interior drop columns on opposite edges.
 -- Reject incompatible modded 5x5 drills with the existing geometry diagnostic.
 local south,north=M.output_rotated[S],M.output_rotated[N]
 if not south or not north or south.y~=M.size or north.y~=-1
  or south.x~=north.x or south.x<1 or south.x>=M.size-1 then
  state.belts={};state.belt_count=0
  issue(state,attempt.sx,attempt.sy,{"mpp.belt_capacity_geometry"})
  return "prepare_pipe_layout"
 end
 local groups,resize={},false
 local gaps=table.deepcopy(state._capacity_row_gaps or {})
 local single_rows=state._capacity_single_rows or {}
 state._capacity_single_rows=single_rows
 for i=1,state.miner_lane_count,2 do
  -- A wider pass can leave an edge corridor with just one occupied column.
  -- Reclaim its unused tile and keep that row narrow for this planning run;
  -- otherwise the next placement can alternate between one and two columns.
  local g=paired.groups(state.miner_lanes[i],state.miner_lanes[i+1],production,
   single_rows[i] and math.huge or limit,gaps[i])
  groups[i]=g
  local gap=#g
  if gap<(gaps[i] or 1) then single_rows[i]=true end
  if gap~=(gaps[i] or 1) then gaps[i]=gap;resize=true end
 end
 if resize and state._capacity_pass<8 then
  state._capacity_row_gaps=gaps;state._capacity_gap=2
  return "initialize_capacity_layout"
 end
 if resize then
  -- Never route a different number of collectors than the physical corridor.
  state.belts={};state.belt_count=0
  issue(state,attempt.sx,attempt.sy,{"mpp.belt_capacity_space"})
  return "prepare_pipe_layout"
 end
 state.belts={}
 for i=1,state.miner_lane_count,2 do
  local y=attempt.lane_layout[i].y+M.size
  for j,g in ipairs(groups[i]) do
   local x1,x2=math.huge,-math.huge
   for _,lane in ipairs{g.lane1,g.lane2} do for _,m in ipairs(lane) do
    local x=m.x+M.output_rotated[m.direction].x
    x1,x2=min(x1,x),max(x2,x)
   end end
   if x1<math.huge then
    local a,b=g.rates[1]/state.belt.speed,g.rates[2]/state.belt.speed
    state.belts[#state.belts+1]={index=#state.belts+1,capacity_row=i,capacity_pair=true,
     has_drills=true,is_output=true,lane1=g.lane1,lane2=g.lane2,
     x1=x1,x2=x2,x_entry=x1-M.middle,x_end=x2+M.middle,x_start=attempt.sx-(state._capacity_beacon_width or 0)-(state.beacon_pipe_gap or 0)-5,
     source_y=y,y=y+j-1,turn_x=x1-1,capacity_weave=#groups[i]==2,throughput1=a,throughput2=b,merged_throughput1=a,merged_throughput2=b}
   end
  end
 end
 state.belt_count=#state.belts
 local covered=capacity.coverage(state)
 for _,tile in ipairs(state.resource_tiles) do
  local original=state._capacity_original_coverage and state._capacity_original_coverage[tile.y]
  if original and original[tile.x] and not (covered[tile.y] and covered[tile.y][tile.x]) then
   issue(state,tile.x,tile.y,{"mpp.belt_capacity_space"})
  end
 end
 return "prepare_pipe_layout"
end

local function drop(state,m)
 local p=state.miner.output_rotated[m.direction]
 return m.x+p.x,m.y+p.y
end

-- Long gaps can contain beacon columns. Fixed underground spans may put a
-- relay endpoint inside a tower; move each relay onto two free adjacent tiles.
function paired.pipe_spans(grid,x,y,width,reach)
 local last=x+width
 local function blocked(at)
  local tile=grid:get_tile(at,y)
  return tile and tile.built_thing
 end
 local result={}
 while x<=last do
  if blocked(x) then return nil end
  local right=reach and min(last,x+reach) or x
  while right>x+1 and (blocked(right) or right<last and blocked(right+1)) do right=right-1 end
  if right<=x+1 then right=x end
  result[#result+1]={structure="horizontal",x=x,y=y,w=right-x}
  x=right+1
 end
 return result
end

function paired.poles(state)
 state.builder_power_poles,state.builder_lamps={},{}
 if state.pole_choice=="none" or state.pole_choice=="zero_gap" then return "prepare_belt_layout" end
 local G,M,attempt=state.grid,state.miner,state.best_attempt
 local selected=obstacles.active(state) and obstacles.get(setmetatable({_belt_routing=true},{__index=state}))
 local protected,collector_rows={},{}
 local function reserve(x,y) protected[y]=protected[y] or {};protected[y][x]=true end
 for _,b in ipairs(state.belts) do
  reserve(b.x_start,b.y);reserve(b.x_start+1,b.y)
  for _,lane in ipairs{b.lane1,b.lane2} do for _,m in ipairs(lane) do
   local x,y=drop(state,m);reserve(x,y);reserve(x,b.y)
   if b.capacity_weave then
    collector_rows[b.capacity_row]=collector_rows[b.capacity_row] or {}
    collector_rows[b.capacity_row][m.x]=b.y
    -- Both drops stay horizontal; side-load one tile downstream. The straight
    -- input at the drop prevents the junction becoming a lane-preserving bend.
    reserve(x-1,b.y)
    if y~=b.y then reserve(x-1,y) end
   elseif y~=b.y then reserve(x+1,b.y) end
  end end
 end
 local function place(x,y,thing,name,list)
  local tile=G:get_tile(x,y)
  if not tile or tile.built_thing or protected[y] and protected[y][x] then return false end
  local spec={name=name,thing=thing,grid_x=x,grid_y=y,quality=thing=="pole" and state.pole_quality_choice or nil}
  local _,box=rows.position(state,spec)
  if selected and obstacles.blocked_box(selected,box) then return false end
  list[#list+1]=spec;G:build_thing_simple(x,y,thing)
  return true
 end
 local join_x=attempt.sx-(state._capacity_beacon_width or 0)-(state.beacon_pipe_gap or 0)-2
 local step=max(1,floor(min(state.pole.wire,state.pole.radius*2)))
 local previous
 local columns=state.miner_max_column
 for _,beacon in ipairs(state.builder_beacons or {}) do
  columns=max(columns,math.ceil((beacon.grid_x-attempt.sx)/state.miner_stride)+1)
 end
 local lane_count=state._beacon_rows and #attempt.lane_layout or state.miner_lane_count
 for i=1,lane_count,2 do
  local y=attempt.lane_layout[i].y+M.size
  for column=1,columns do
   local x=attempt.sx+(column-1)*state.miner_stride
   local collector=collector_rows[i] and collector_rows[i][x]
   local py=collector and 2*y+1-collector or y
   place(x,py,"pole",state.pole_choice,state.builder_power_poles)
   if state._beacon_rows and state.beacon_pipe_gap>0 then
    -- Fluid channels widen the column pitch beyond a medium pole's wire.
    place(x+M.size,py,"pole",state.pole_choice,state.builder_power_poles)
   end
  end
  place(join_x,y,"pole",state.pole_choice,state.builder_power_poles)
  if previous then for py=previous+step,y-1,step do
   place(join_x,py,"pole",state.pole_choice,state.builder_power_poles)
  end end
  previous=y
 end
 -- Fill the one-tile gaps in each beacon column. Corridor poles reach
 -- the drills, but cannot supply the middle of a back-to-back drill block.
 for _,beacon in ipairs(state.builder_beacons or {}) do
  local proto=prototypes.entity[beacon.name]
  place(beacon.grid_x,beacon.row_y-1,"pole",state.pole_choice,state.builder_power_poles)
  place(beacon.grid_x,beacon.row_y+proto.tile_height,"pole",state.pole_choice,state.builder_power_poles)
 end
 rows.prune_poles(state)
 if state.lamp_choice then for _,p in ipairs(state.builder_power_poles) do
  -- A west-side lamp leaves the two adjacent tunnel endpoints between drops.
  place(p.grid_x-1,p.grid_y,"lamp","small-lamp",state.builder_lamps)
 end end
 return "prepare_belt_layout"
end

function paired.belts(state,issue)
 local env,built=common.create_belt_building_environment(state)
 local G,feeders,protected=state.grid,{},{}
 local function mark(map,x,y,value) map[y]=map[y] or {};map[y][x]=value end
 for _,b in ipairs(state.belts) do
  for _,lane in ipairs{b.lane1,b.lane2} do for _,m in ipairs(lane) do
   local x,y=drop(state,m)
   mark(protected,x,b.y,true)
   if b.capacity_weave then mark(protected,x-1,b.y,true) end
   if y~=b.y then
    if b.capacity_weave then
     mark(feeders,x,y,W)
     mark(feeders,x-1,y,b.y>y and S or N)
    else mark(feeders,x,y,b.y>y and S or N) end
   end
  end end
 end
 local failed=false
 local function blocked(x,y)
  local tile=G:get_tile(x,y)
  return feeders[y] and feeders[y][x] or tile and tile.built_thing
 end
 local function horizontal(b)
  local x,last,y=b.x_start,b.x2+1,b.y
  while x<=last and not failed do
   if blocked(x,y) then failed=true;issue(state,x,y,{"mpp.belt_capacity_route"});return end
   local through
   if b.y>b.source_y and x>b.x_start+1 and x<b.turn_x-2 and state.belt.related_underground_belt
    and not (protected[y] and protected[y][x]) then
    through=min(b.turn_x-1,x+state.belt.underground_reach)
    for p=x+1,through do if protected[y] and protected[y][p] then through=p-1;break end end
    while through>x+1 and (blocked(through,y) or blocked(through+1,y)) do through=through-1 end
    if through<=x+1 then through=nil end
   end
   if through then
    env.create_underground(x,y,W,"output");env.create_underground(through,y,W,"input");x=through+1
   elseif x<last and blocked(x+1,y) then
    local right=x+1
    while right<=last and (blocked(right,y) or protected[y] and protected[y][right]
     or right<last and blocked(right+1,y)) do right=right+1 end
    if right>last or not state.belt.related_underground_belt or right-x>state.belt.underground_reach then
     failed=true;issue(state,x,y,{"mpp.belt_capacity_route"});return
    end
    for hidden=x+1,right-1 do if protected[y] and protected[y][hidden] then
     failed=true;issue(state,hidden,y,{"mpp.belt_capacity_route"});return
    end end
    if protected[y] and protected[y][x] then
     failed=true;issue(state,x,y,{"mpp.belt_capacity_route"});return
    end
    env.create_underground(x,y,W,"output");env.create_underground(right,y,W,"input");x=right+1
   else env.create_belt(x,y,W);x=x+1 end
  end
 end
 for _,b in ipairs(state.belts) do horizontal(b) end
 for y,row in pairs(feeders) do for x,direction in pairs(row) do
  local tile=G:get_tile(x,y)
  if tile and tile.built_thing then failed=true;issue(state,x,y,{"mpp.belt_capacity_route"})
  else env.create_belt(x,y,direction) end
 end end
 if failed then return false end
 state.builder_belts=built
 common.commit_built_tiles_to_grid(G,built,"belt")
 return true
end

return paired
