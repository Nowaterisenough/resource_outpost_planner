-- Compose equal square cores with a full-width interleave/mix stage. Routing
-- crossings use two-tile underground spans; the cores retain their own reach.
-- Lower belt tiers and outputs beyond the 32-output book use this composition.
local wide={}
local S,E,W=defines.direction.south,defines.direction.east,defines.direction.west
function wide.reference(width,core,belt_name,splitter,underground,mixer)
 local entities,inputs,outputs,cells={},{},{},{}
 local function key(x,y) return x..","..y end
 local function add(kind,x,y,direction,extra)
  local e={kind,x,y,direction or S}
  if extra then for i=5,8 do e[i]=extra[i] end end
  entities[#entities+1]=e
  if kind~="splitter" then cells[key(x,y)]=e end
 end
 local factor=mixer and #mixer.inputs or 2
 local half=width/factor
 local left,right=0,0
 for _,p in ipairs(core.specs) do left=math.min(left,p.x-1);right=math.max(right,p.x+1) end
 local offset=math.max(3*half,right-left+3)
 local source={}
 local bottom=core.output_y
 for _,p in ipairs(core.specs) do bottom=math.max(bottom,p.y) end
 for side=0,factor-1 do
  local dx=side*offset
  for _,p in ipairs(core.specs) do
   add(p.name==belt_name and "belt" or p.name==splitter and "splitter" or "underground",p.x+dx,p.y,p.direction,
    {[5]=p.type,[6]=p.input_priority,[7]=p.output_priority,[8]=p.filter})
  end
  for _,p in ipairs(core.inputs) do inputs[#inputs+1]={dx+p.x,p.y} end
  for i=0,half-1 do
   local x,row=dx+3*i,bottom+half-i+1
   for y=core.output_y+1,row-1 do add("belt",dx+i,y) end
   for cx=dx+i,x-1 do add("belt",cx,row,E) end
   for y=row,bottom+half+1 do add("belt",x,y) end
   source[#source+1]=x
  end
 end
 local top=bottom+half+2
 local target_x=(factor-1)*offset+3*half+3
 local end_y=top+3*width
 local targets={}
 -- Route all vertical trunks first. Horizontal crossings tunnel beneath them.
 for i=0,width-1 do
  local perm=factor*(i%half)+math.floor(i/half)
  local sx,tx,row=source[i+1],target_x+3*perm,top+3*i
  targets[i+1]=tx
  for y=top,row-1 do add("belt",sx,y) end
  for y=row+1,end_y do add("belt",tx,y) end
 end
 for i=0,width-1 do
  local x,tx,row=source[i+1],targets[i+1],top+3*i
  while x<tx do
   if cells[key(x+1,row)] then
    assert(not cells[key(x,row)] and not cells[key(x+2,row)],"wide balancer crossing overlaps a trunk")
    add("underground",x,row,E,{[5]="input"})
    add("underground",x+2,row,E,{[5]="output"});x=x+3
   else add("belt",x,row,E);x=x+1 end
  end
  add("belt",tx,row)
 end
 local last=end_y+width+1
 local destinations={}
 local mix_left,mix_right=0,0
 if mixer then for _,p in ipairs(mixer.specs) do mix_left=math.min(mix_left,p.x-1);mix_right=math.max(mix_right,p.x+1) end end
 local stride=math.ceil(mix_right-mix_left+3)
 for i=0,width-1 do
  local port=mixer and mixer.inputs[i%factor+1]
  destinations[i+1]=port and math.floor(i/factor)*stride-mix_left+port.x or i
 end
 for i=0,width-1 do
  local x,row=target_x+3*i,end_y+i+1
  local dest=destinations[i+1]
  for y=end_y+1,row-1 do add("belt",x,y) end
  for cx=x,dest+1,-1 do add("belt",cx,row,W) end
  for y=row,last-1 do add("belt",dest,y) end
 end
 if mixer then
  local origin=last-mixer.inputs[1].y
  for group=0,half-1 do
   local dx=group*stride-mix_left
   for _,p in ipairs(mixer.specs) do
    -- Output port belts are supplied by geometry(), not the raw entry.
    if p.y~=mixer.output_y or p.x<0 or p.x>=factor then
     add(p.name==belt_name and "belt" or p.name==splitter and "splitter" or "underground",dx+p.x,origin+p.y,p.direction,
      {[5]=p.type,[6]=p.input_priority,[7]=p.output_priority,[8]=p.filter})
    end
   end
   for _,port in ipairs(mixer.inputs) do add("belt",dx+port.x,origin+port.y) end
   for i=0,factor-1 do outputs[#outputs+1]={dx+i,origin+mixer.output_y} end
  end
 else
  for i=0,width-1,2 do add("splitter",i+.5,last,S) end
  for i=0,width-1 do outputs[#outputs+1]={i,last+1} end
 end
 return {label=width.."_"..width.."_expanded",n=width,m=width,reach=prototypes.entity[underground].max_underground_distance,entities=entities,inputs=inputs,outputs=outputs}
end
-- Return spare square-core outputs directly to its unused inputs. Nested
-- loops preserve belt order and need no interleaving grid or input fan-out.
function wide.feedback(outputs,core,belt_name,splitter,underground)
 local entities,inputs,ports={},{},{}
 local right,bottom,top=0,core.output_y,math.huge
 for _,p in ipairs(core.specs) do
  right=math.max(right,math.ceil(p.x));bottom=math.max(bottom,p.y)
  entities[#entities+1]={p.name==belt_name and "belt" or p.name==splitter and "splitter" or "underground",
   p.x,p.y,p.direction,p.type,p.input_priority,p.output_priority,p.filter}
 end
 for _,p in ipairs(core.inputs) do top=math.min(top,p.y) end
 local count=#core.inputs-outputs
 local finish=bottom+count+2
 local function belt(x,y,dir) entities[#entities+1]={"belt",x,y,dir or S} end
 for i=0,outputs-1 do
  local target=core.inputs[i+1]
  inputs[#inputs+1]={target.x,top-count-2}
  for y=top-count-1,target.y do belt(target.x,y) end
  for y=core.output_y+1,finish-1 do belt(i,y) end
  ports[#ports+1]={i,finish}
 end
 for i=0,count-1 do
  local sx,turn=outputs+i,bottom+count-i+1
  local column=right+count-i+1
  local target=core.inputs[outputs+i+1]
  local front=top-count+i-1
  for y=core.output_y+1,turn-1 do belt(sx,y) end
  for x=sx,column-1 do belt(x,turn,E) end
  belt(column,turn,defines.direction.north)
  for y=turn-1,front+1,-1 do belt(column,y,defines.direction.north) end
  for x=column,target.x+1,-1 do belt(x,front,W) end
  for y=front,target.y do belt(target.x,y) end
 end
 return {label=outputs.."_"..outputs.."_compact_feedback",n=outputs,m=outputs,compact_input_folds=true,
  reach=prototypes.entity[underground].max_underground_distance,entities=entities,inputs=inputs,outputs=ports}
end
return wide
