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
			local choices = {cliff_mode_choice=cliff,terrain_mode_choice=mode,remove_entities_choice=not keep}
			check(terrain.blocks_entity({type="cliff"}, choices) == (cliff=="avoid"), "entity retention overrides cliff mode")
			check(terrain.blocks_entity({type="assembling-machine"}, choices) == keep, "terrain mode overrides entity retention")
			check(terrain.blocks_entity({type="tree"}, choices)==keep, "tree retention differs from facility retention")
			check(terrain.blocks_entity({type="simple-entity"}, choices)==keep, "rock retention differs from facility retention")
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
	{deconstruction_choice=true}, {deconstruction_choice=false},
} do
	local cliff, tiles, keep = terrain.avoid_cliffs(old), terrain.avoid_tiles(old), terrain.retain_entities(old)
	configuration.migrate_terrain_choices(old)
	check((old.cliff_mode_choice=="avoid")==cliff and (old.terrain_mode_choice=="avoid")==tiles, "legacy terrain preference lost")
	check(old.remove_entities_choice == not keep, "legacy facility setting reversed")
	check(old.avoid_cliffs_choice==nil and old.avoid_water_choice==nil and old.landfill_choice==nil and old.avoid_obstacles_choice==nil, "redundant flags survive migration")
end
local current = {cliff_mode_choice="remove",terrain_mode_choice="avoid",deconstruction_choice=false}
configuration.migrate_terrain_choices(current)
check(current.cliff_mode_choice=="remove" and current.terrain_mode_choice=="avoid" and current.remove_entities_choice==true and current.deconstruction_choice==nil, "migration overwrites current modes or false retention")
for _,remove in ipairs{false,true} do
	local saved={remove_entities_choice=remove,deconstruction_choice=remove}
	configuration.migrate_terrain_choices(saved)
	check(saved.remove_entities_choice==remove and saved.deconstruction_choice==nil, "new facility choice overwritten")
end
-- Exercise the complete default merge, not just the legacy field conversion.
local function deepcopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}; for key, item in pairs(value) do copy[key] = deepcopy(item) end
	return copy
end
table.deepcopy = deepcopy
configuration.get_locked_qualities = function() return {} end
game = {get_player=function() return {} end, create_inventory=function() return {} end}
for _, keep in ipairs{false,true} do
	local saved = deepcopy(configuration.default_config)
	saved.choices.remove_entities_choice = nil
	saved.choices.deconstruction_choice = keep
	storage = {players={[1]=saved}}
	configuration.update_player_data(1)
	check(storage.players[1].choices.remove_entities_choice == not keep, "full upgrade loses legacy retention preference")
	check(storage.players[1].choices.deconstruction_choice == nil, "full upgrade retains deprecated control")
	configuration.update_player_data(1)
	check(storage.players[1].choices.remove_entities_choice == not keep, "repeated upgrade resets cleanup preference")
end
local saved = deepcopy(configuration.default_config)
saved.choices.remove_entities_choice = "false"
storage = {players={[1]=saved}}
configuration.update_player_data(1)
check(storage.players[1].choices.remove_entities_choice == true, "invalid choice type bypasses default")

for mask=0,127 do
	local c={cliff_mode_choice="avoid",terrain_mode_choice="avoid",remove_entities_choice=mask%2==1,
		remove_trees_choice=math.floor(mask/2)%2==1,remove_rocks_choice=math.floor(mask/4)%2==1,
		fill_water_choice=math.floor(mask/8)%2==1,fill_lava_choice=math.floor(mask/16)%2==1,
		fill_oil_ocean_choice=math.floor(mask/32)%2==1,fill_other_choice=math.floor(mask/64)%2==1}
	check(terrain.blocks_entity({type="tree"},c)==not c.remove_trees_choice,"tree choice is coupled")
	check(terrain.blocks_entity({type="simple-entity"},c)==not c.remove_rocks_choice,"rock choice is coupled")
	check(terrain.blocks_entity({type="assembling-machine"},c)==not c.remove_entities_choice,"facility choice is coupled")
	for i,t in ipairs(hazards) do
		local flag=i==1 and c.fill_water_choice or false
		if i==2 then flag=c.fill_lava_choice elseif i>=3 then flag=c.fill_oil_ocean_choice end
		check(terrain.blocks_tile(t,c)==not flag,"per-terrain fill choice is coupled: "..t.name)
	end
	local snapshot=deepcopy(c)
	configuration.migrate_terrain_choices(c)
	for k,v in pairs(snapshot) do check(c[k]==v,"migration resets independent setting "..k) end
end
-- Explicit force overrides natural retention only for this plan. Facilities,
-- cliffs and terrain still follow their independent validation settings.
for _,mode in ipairs{1,2} do
 local choices={_force_build_mode=mode,remove_entities_choice=false,remove_trees_choice=false,remove_rocks_choice=false,
  cliff_mode_choice="avoid",fill_lava_choice=false}
 for _,kind in ipairs{"tree","simple-entity"} do
  check(not terrain.blocks_entity({type=kind},choices),"forced mine still avoids natural obstructions")
  check(not terrain.blocks_entity({type="entity-ghost",ghost_prototype={type=kind}},choices),"forced mine retains natural ghosts")
 end
 check(terrain.blocks_entity({type="assembling-machine"},choices),"natural override clears retained facilities")
 check(terrain.blocks_entity({type="cliff"},choices),"natural override clears retained cliffs")
 check(terrain.blocks_tile(hazards[2],choices),"natural override fills forbidden lava")
 check(not choices.remove_trees_choice and not choices.remove_rocks_choice,"force mutates saved cleanup choices")
 choices._force_build_mode=nil
 check(terrain.blocks_entity({type="simple-entity"},choices),"ordinary plan inherits forced rock clearing")
end
local legacy={cliff_mode_choice="remove",terrain_mode_choice="fill",remove_entities_choice=false}
configuration.migrate_terrain_choices(legacy)
check(legacy.fill_water_choice and legacy.fill_lava_choice and legacy.fill_oil_ocean_choice and legacy.fill_other_choice,
	"legacy fill mode was not expanded")
check(not legacy.remove_trees_choice and not legacy.remove_rocks_choice,"legacy cleanup false was not expanded")
print("Terrain OK: "..cases.." independent modes, hazard covers and demolition ownership checks")
