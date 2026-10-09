-- Run from the repository root with Lua 5.2.
local terrain = require("mpp.terrain")
local cases = 0
local function check(value, message) assert(value, message); cases = cases + 1 end
local function tile(name, layers, cover)
	return {name=name, position={x=0,y=0}, prototype={collision_mask={layers=layers},default_cover_tile=cover}}
end
local landfill, foundation = {name="landfill"}, {name="foundation"}
local hazards = {
	tile("water", {water_tile=true}, landfill),
	tile("lava", {water_tile=true,lava_tile=true}, foundation),
	tile("oil-ocean-shallow", {water_tile=true}, foundation),
	tile("mod-lightning-pool", {object=true}, foundation),
}
for _, cliff in ipairs{"avoid", "remove"} do
	for _, mode in ipairs{"avoid", "fill"} do
		for _, keep in ipairs{true,false} do
			local choices = {cliff_mode_choice=cliff,terrain_mode_choice=mode,deconstruction_choice=keep}
			check(terrain.blocks_entity({type="cliff"}, choices) == (cliff=="avoid"), "entity retention overrides cliff mode")
			check(terrain.blocks_entity({type="assembling-machine"}, choices) == keep, "terrain mode overrides entity retention")
			for _, hazard in ipairs(hazards) do
				check(terrain.blocks_tile(hazard, choices) == (mode=="avoid"), "hazard does not follow terrain mode")
			end
			check(terrain.blocks_tile(tile("out-of-map", {water_tile=true,out_of_map=true}, foundation), choices), "map edge can be filled")
			check(terrain.blocks_tile(tile("unfillable-pool", {water_tile=true}), choices), "unfillable terrain accepted")
			check(not terrain.blocks_tile(tile("grass-1", {ground_tile=true}), choices), "ordinary ground blocked")
		end
	end
end
prototypes = {tile={scaffold={name="scaffold"}}}
check(terrain.cover_tile(tile("se-space", {}), {space_landfill_choice="scaffold"}).name=="scaffold", "selected space platform ignored")
check(terrain.cover_tile(hazards[2], {}).name=="foundation", "lava uses landfill instead of foundation")
check(terrain.avoid_tiles({landfill_choice=true}), "old omit-fill setting not migrated to avoidance")
check(terrain.avoid_cliffs({avoid_obstacles_choice=true}), "old broad avoidance loses cliffs")

local force = {}
local function entity(kind, ordered)
	local result = {valid=true,type=kind,prototype={collision_mask={layers={object=true}}},ordered=ordered}
	result.to_be_deconstructed=function() return result.ordered end
	result.order_deconstruction=function() result.ordered=true end
	return result
end
local cliff, machine, already = entity("cliff"), entity("assembling-machine"), entity("tree",true)
local state = {player={force=force},cliff_mode_choice="remove",terrain_mode_choice="avoid",deconstruction_choice=true,
	surface={find_entities_filtered=function() return {cliff,machine,already} end}}
state.preview_only=true
terrain.deconstruct(state, {})
check(not cliff.ordered and not machine.ordered and not state._deconstruction_orders, "preview issues demolition orders")
state.preview_only=false
terrain.deconstruct(state, {})
check(cliff.ordered and not machine.ordered, "cliff demolition ignores independent retention")
check(#state._deconstruction_orders==1 and state._deconstruction_orders[1]==cliff, "Undo contains existing or retained demolition")
state.cliff_mode_choice="avoid";state.deconstruction_choice=false
terrain.deconstruct(state, {})
check(machine.ordered and #state._deconstruction_orders==2, "facility demolition fails in avoid-cliff mode")
terrain.deconstruct(state, {})
check(#state._deconstruction_orders==2, "repeated footprints duplicate demolition orders")

local own_rail,other_rail,own_stock=entity("entity-ghost"),entity("entity-ghost"),entity("entity-ghost")
for i,ghost in ipairs{own_rail,other_rail,own_stock} do
	ghost.unit_number=1000+i;ghost.ghost_prototype=ghost.prototype
end
local building={player={force=force},deconstruction_choice=false,_collected_ghosts={own_rail},
	surface={find_entities_filtered=function() return {own_rail,other_rail} end}}
terrain.deconstruct(building,{})
check(not own_rail.ordered and other_rail.ordered,"stock placement demolishes its own rail ghost")
check(#building._deconstruction_orders==1,"owned ghost added to demolition Undo")
building._collected_ghosts[#building._collected_ghosts+1]=own_stock
building.surface.find_entities_filtered=function() return {own_rail,other_rail,own_stock} end
terrain.deconstruct(building,{})
check(not own_stock.ordered,"ownership cache misses a newly created ghost")
check(#building._deconstruction_orders==1,"repeated station placement duplicates demolition")

package.loaded["util"] = {}
package.loaded["mpp.preview"] = {}
defines = {events={on_player_created=1,on_player_removed=2}}
script = {on_event=function() end}
local configuration = require("configuration")
for _, old in ipairs{
	{avoid_cliffs_choice=true}, {avoid_water_choice=true}, {landfill_choice=true},
	{avoid_obstacles_choice=true}, {avoid_cliffs_choice=false,avoid_water_choice=false},
} do
	local cliff, tiles = terrain.avoid_cliffs(old), terrain.avoid_tiles(old)
	configuration.migrate_terrain_choices(old)
	check((old.cliff_mode_choice=="avoid")==cliff and (old.terrain_mode_choice=="avoid")==tiles, "legacy terrain preference lost")
	check(old.avoid_cliffs_choice==nil and old.avoid_water_choice==nil and old.landfill_choice==nil and old.avoid_obstacles_choice==nil, "redundant flags survive migration")
end
local current = {cliff_mode_choice="remove",terrain_mode_choice="avoid",deconstruction_choice=false}
configuration.migrate_terrain_choices(current)
check(current.cliff_mode_choice=="remove" and current.terrain_mode_choice=="avoid" and current.deconstruction_choice==false, "migration overwrites current modes or false retention")
print("Terrain OK: "..cases.." independent modes, hazard covers and demolition ownership checks")
