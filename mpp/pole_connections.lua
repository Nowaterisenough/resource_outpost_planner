local poles = {}

local function is_pole(e)
	return e.valid and (e.type=="electric-pole" or e.type=="entity-ghost" and e.ghost_type=="electric-pole")
end

-- Script-created pole ghosts do not get native automatic copper connections.
-- Connect the shortest bridges first; a sparse spanning network avoids filling
-- a pole's wire slots with redundant links before other rows can join it.
function poles.connect(state)
	local nodes,by_unit={},{}
	local force=state.player.force
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
	for _,e in pairs(state._collected_ghosts or {}) do
		add(e)
	end
	local edges,seen={},{}
	for i=1,#nodes do
		local e=nodes[i].entity
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
						edges[#edges+1]={a=a,b=b,d=(p.x-q.x)^2+(p.y-q.y)^2}
					end
				end
			end
		end
		nearby(state.surface.find_entities_filtered{position=e.position,radius=reach,force=force,type="electric-pole"})
		nearby(state.surface.find_entities_filtered{position=e.position,radius=reach,force=force,type="entity-ghost",ghost_type="electric-pole"})
	end
	local function root(i)
		while nodes[i].parent~=i do
			nodes[i].parent=nodes[nodes[i].parent].parent;i=nodes[i].parent
		end
		return i
	end
	for i,node in ipairs(nodes) do
		for _,connection in pairs(node.connector.connections) do
			local j=by_unit[connection.target.owner.unit_number]
			if j then nodes[root(j)].parent=root(i) end
		end
	end
	table.sort(edges,function(a,b)
		if a.d~=b.d then return a.d<b.d end
		if a.a~=b.a then return a.a<b.a end
		return a.b<b.b
	end)
	for _,edge in ipairs(edges) do
		local a,b=root(edge.a),root(edge.b)
		if a~=b and nodes[edge.a].connector.connect_to(nodes[edge.b].connector,true) then
			nodes[b].parent=a
		end
	end
end

return poles
