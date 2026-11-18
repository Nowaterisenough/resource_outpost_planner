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
