local poles = {}

local function is_pole(e)
	return e and e.valid and (e.type=="electric-pole" or e.type=="entity-ghost" and e.ghost_type=="electric-pole")
end

local function shorter(left,right)
	if left.d~=right.d then return left.d<right.d end
	if left.a~=right.a then return left.a<right.a end
	return left.b<right.b
end

local function push_edge(edges,edge)
	local i=#edges+1
	while i>1 do
		local parent=math.floor(i/2)
		if not shorter(edge,edges[parent]) then break end
		edges[i]=edges[parent]
		i=parent
	end
	edges[i]=edge
end

local function pop_edge(edges)
	local first=edges[1]
	local tail=table.remove(edges)
	if #edges>0 then
		local i=1
		while i*2<=#edges do
			local child=i*2
			if child<#edges and shorter(edges[child+1],edges[child]) then child=child+1 end
			if not shorter(edges[child],tail) then break end
			edges[i]=edges[child]
			i=child
		end
		edges[i]=tail
	end
	return first
end

-- Script-created pole ghosts do not get native automatic copper connections.
-- Connect the shortest bridges first; a sparse spanning network avoids filling
-- a pole's wire slots with redundant links before other rows can join it.
local function step(job)
	if not job.surface.valid or not job.force.valid then return true end
	local nodes,by_unit,force=job.nodes,job.by_unit,job.force
	local function add(e)
		if not is_pole(e) or e.to_be_deconstructed(force) then return end
		local id=by_unit[e.unit_number]
		if id then return id end
		local connector=e.get_wire_connector(defines.wire_connector_id.pole_copper,true)
		if not connector then return end
		id=#nodes+1
		nodes[id]={entity=e,connector=connector,parent=id}
		by_unit[e.unit_number]=id
		return id
	end
	if job.phase=="seed" then
		local last=math.min(job.count,job.index+255)
		for i=job.index,last do add(job.ghosts[i]) end
		job.index=last+1
		if last<job.count then return end
		job.phase,job.index,job.count,job.ghosts="nearby",1,#nodes,nil
	end
	local edges,seen=job.edges,job.seen
	if job.phase=="nearby" then
		local last=math.min(job.count,job.index+31)
		for i=job.index,last do
			local e=nodes[i].entity
			if not is_pole(e) or e.to_be_deconstructed(force) then goto next_pole end
			local proto=e.type=="entity-ghost" and e.ghost_prototype or e.prototype
			local reach=proto.get_max_wire_distance(e.quality)
			local function nearby(list)
				for _,other in pairs(list) do
					local j=add(other)
					if j and i~=j then
						local a,b=math.min(i,j),math.max(i,j)
						local key=a..","..b
						if not seen[key] and e.can_wires_reach(other) then
							seen[key]=true
							local p,q=e.position,other.position
							push_edge(edges,{a=a,b=b,d=(p.x-q.x)^2+(p.y-q.y)^2})
						end
					end
				end
			end
			nearby(job.surface.find_entities_filtered{position=e.position,radius=reach,force=force,type="electric-pole"})
			nearby(job.surface.find_entities_filtered{position=e.position,radius=reach,force=force,type="entity-ghost",ghost_type="electric-pole"})
			::next_pole::
		end
		job.index=last+1
		if last<job.count then return end
		job.phase,job.index="existing",1
	end
	local function root(i)
		while nodes[i].parent~=i do
			nodes[i].parent=nodes[nodes[i].parent].parent;i=nodes[i].parent
		end
		return i
	end
	if job.phase=="existing" then
		local last=math.min(#nodes,job.index+63)
		for i=job.index,last do
			local node=nodes[i]
			if node.entity.valid and node.connector.valid then
				for _,connection in pairs(node.connector.connections) do
					local j=by_unit[connection.target.owner.unit_number]
					if j then nodes[root(j)].parent=root(i) end
				end
			end
		end
		job.index=last+1
		if last<#nodes then return end
		job.phase="link"
	end
	for _=1,math.min(#edges,256) do
		local edge=pop_edge(edges)
		local a,b=root(edge.a),root(edge.b)
		if a~=b and is_pole(nodes[edge.a].entity) and is_pole(nodes[edge.b].entity)
			and not nodes[edge.a].entity.to_be_deconstructed(force) and not nodes[edge.b].entity.to_be_deconstructed(force)
			and nodes[edge.a].connector.connect_to(nodes[edge.b].connector,true) then
			nodes[b].parent=a
		end
	end
	return #edges==0
end

function poles.connect(state)
	local ghosts=state._collected_ghosts or {}
	local job={phase="seed",index=1,count=#ghosts,ghosts=ghosts,surface=state.surface,force=state.player.force,
		nodes={},edges={},seen={},by_unit={}}
	if not step(job) then
		storage.pole_jobs=storage.pole_jobs or {}
		table.insert(storage.pole_jobs,job)
		script.on_event(defines.events.on_tick,task_runner_handler)
	end
end

function poles.tick()
	local jobs=storage.pole_jobs
	if jobs and jobs[1] and step(jobs[1]) then
		table.remove(jobs,1)
		if #jobs==0 then storage.pole_jobs=nil end
	end
end

return poles
