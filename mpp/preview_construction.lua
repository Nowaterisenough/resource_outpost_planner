local builder=require("mpp.builder")
local planner=require("mpp.belt_planner")
local util=require("mpp.mpp_util")
local obstacles=require("mpp.obstacles")
local work={}
work.budget=4096

function work.begin(state,routes,checked)
	return {state=state,routes=routes or {},next_spec=1,checked_tick=checked and game.tick,phase="entities"}
end

local function search_area(job,first,last)
	local state=job.state
	local c=state.coords
	local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
	local margin=0
	job.extents=job.extents or {}
	for i=first,last do
		local spec=job.routes[i]
		local pos=util.revert_world(c.gx,c.gy,state.direction_choice,spec.grid_x,spec.grid_y,c.tw,c.th)
		local x,y=pos[1],pos[2]
		x1,y1,x2,y2=math.min(x1,x),math.min(y1,y),math.max(x2,x),math.max(y2,y)
		local extent=job.extents[spec.name]
		if not extent then
			local box=obstacles.entity_box(spec.name,{x=0,y=0},defines.direction.north)
			extent=math.max(math.abs(box.left_top.x),math.abs(box.left_top.y),math.abs(box.right_bottom.x),math.abs(box.right_bottom.y))+1
			job.extents[spec.name]=extent
		end
		margin=math.max(margin,extent)
	end
	if x1~=math.huge then state._belt_search_area={{x1-margin,y1-margin},{x2+margin,y2+margin}} end
end

function work.step(job,limit)
	local state=job.state
	if job.phase=="entities" then
		local last=math.min(#job.routes,job.next_spec+(limit or work.budget)-1)
		if job.checked_tick~=game.tick then search_area(job,job.next_spec,last) end
		local create=builder.create_entity_builder(state,{diagnostic=true,obstacles_checked=job.checked_tick==game.tick})
		for i=job.next_spec,last do create(job.routes[i]) end
		job.next_spec=last+1
		if last<#job.routes then return false end
		job.phase="fill"
		if #job.routes>work.budget then return false end
	end
	planner.place_landfill(state,job.routes)
	return true
end

return work
