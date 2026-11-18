-- Run the configuration event as if a mod supplying a belt and a drill was removed.
local changed
script={active_mods={},on_configuration_changed=function(f) changed=f end}
local player={index=1,valid=true,force={},gui={left={},screen={}}}
local surface={valid=true}
game={players={player}}
local function noop() end
package.loaded.configuration={default_config={choices={belt_choice="transport-belt",miner_choice="electric-mining-drill"}},
	migrate_statistics_choice=noop,migrate_terrain_choices=noop,update_player_quality_data=noop}
package.loaded['mpp.belt_load']={migrate_choices=noop}
package.loaded['mpp.belt_planner']={clear_belt_planner_stack=function(data) data.belt_planner_stack={} end}
package.loaded['mpp.preview']={cancel=noop,dispose_task=function(s) s.disposed=true end}
prototypes={entity={["transport-belt"]={},["electric-mining-drill"]={}},quality={normal={}},item={}}
require('migration')
local old={valid=true,type="entity-ghost",destroy=function() error("destroyed an earlier mine") end}
local prior={surface=surface,player=player,belt_choice="missing-belt",resources={{}},belts={{}},_collected_ghosts={old}}
local new={valid=true,type="entity-ghost"}
new.destroy=function() new.valid=false end
local order={valid=true,cancel_deconstruction=function(force) assert(force==player.force);new.order_cancelled=true end}
local partial={type="layout",surface=surface,player=player,_from_preview=true,_undo_state=prior,
	builder_belts={{name="missing-belt"}},_collected_ghosts={new},_deconstruction_orders={order}}
local still_valid={type="layout",surface=surface,player=player,belt_choice="transport-belt"}
local extension={type="belt_planner",surface=surface,player=player,belt_choice="missing-belt",_collected_ghosts={old}}
local data={choices={belt_choice="missing-belt",miner_choice="missing-drill"},belt_planner_stack={prior}}
storage={version=require('mpp.version'),players={data},tasks={partial,still_valid},immediate_tasks={extension}}
changed{mod_changes={equipment={old_version="1.0"}}}
assert(#storage.tasks==1 and storage.tasks[1]==still_valid and not still_valid.disposed)
assert(#storage.immediate_tasks==0 and extension.disposed and partial.disposed and new.order_cancelled and not new.valid)
assert(data.last_state==prior and prior._collected_ghosts[1]==old and not prior.belts and #data.belt_planner_stack==0)
assert(data.choices.belt_choice=="transport-belt" and data.choices.miner_choice=="electric-mining-drill")

local function ore(kind,category)
	return {resource_category=category,mineable_properties={products=kind and {{type=kind}} or nil}}
end
local resources={gas=ore("fluid","mixed"),ore=ore("item","mixed"),empty=ore(nil,"mixed"),oil=ore("fluid","liquid")}
local drills={multi={resource_categories={mixed=true,liquid=true},fluidbox_prototypes={}},
	fluid_only={resource_categories={liquid=true},fluidbox_prototypes={}}}
prototypes.get_entity_filtered=function(filter) return filter[1].type=="resource" and resources or drills end
local enums=require('mpp.enums')
local miners,categories=enums.get_available_miners()
assert(miners.multi and not miners.fluid_only and categories.mixed and not categories.liquid)
assert(enums.is_solid_resource("ore") and not enums.is_solid_resource("empty") and not enums.is_solid_resource("gas"))
print("Configuration removal: stale equipment, partial build rollback, Undo ownership and mixed resource categories passed")
