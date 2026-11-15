-- Removed LuaPlayers expose only valid. Exercise the real event handler and
-- teardown with handles that throw on all other access after invalidation.
local handlers={}
defines={events={on_player_created=1,on_player_removed=2}}
script={on_event=function(event,handler) handlers[event]=handler end}
package.loaded["util"]={}
package.loaded["layouts.common"]={}
for _,name in ipairs{"preview_renderer","belt_planner","preview_diagnostics",
	"output_preview","preview_output_cache","forced_build","terrain","belt_load",
	"output_balancer","train_station"} do
	package.loaded["mpp."..name]={}
end
game={get_player=function() error("player removal must not access a player") end}
require("configuration")
local remove=assert(handlers[defines.events.on_player_removed])
local next_id=0
local function handle(kind,properties,on_destroy)
	local valid=true
	local values=properties or {}
	next_id=next_id+1
	values.id=next_id
	values.destroy=function()
		assert(valid,kind.." destroyed twice")
		valid=false
		if on_destroy then on_destroy() end
	end
	local result=setmetatable({}, {__index=function(_,key)
		if key=="valid" then return valid end
		assert(valid,kind.." API call when invalid: "..tostring(key))
		return values[key]
	end})
	return result,values.destroy
end
local function task(player,preview_only)
	local stack={valid_for_read=true}
	stack.clear=function() stack.valid_for_read=false end
	local blueprint,invalidate=handle("LuaItemStack",stack)
	-- Destroying an inventory also invalidates its item stacks.
	local inventory=handle("LuaInventory",nil,invalidate)
	local state={player=player,preview_only=preview_only,blueprint=blueprint,
		blueprint_inventory=inventory,_preview_rectangle=handle("LuaRenderObject"),
		_render_objects={(handle("LuaRenderObject"))}}
	return state
end

-- A deleted player with only a completed plan reproduces the screenshot:
-- ordinary cancellation used last_state.player and accessed its index.
local removed,invalidate_player=handle("LuaPlayer",{index=1})
local historical=task(removed,false)
local saved_ghost=handle("LuaEntity")
local saved_order=handle("LuaEntity")
historical._collected_ghosts={saved_ghost}
historical._deconstruction_orders={saved_order}
local selection=handle("LuaRenderObject")
local inventory=handle("LuaInventory")
local data={last_state=historical,selection_render={selection},blueprint_items=inventory,gui={}}
storage={players={[1]=data},tasks={},immediate_tasks={}}
invalidate_player()
remove{player_index=1}
assert(not storage.players[1] and not selection.valid and not inventory.valid)
assert(not historical._preview_rectangle.valid and not historical._render_objects[1].valid)
assert(not historical.blueprint.valid and not historical.blueprint_inventory.valid)
assert(saved_ghost.valid and saved_order.valid,"removal changed an applied plan")
remove{player_index=1} -- Missing player data is harmless.

-- Cancel every kind of pending work, including builds and immediate belt
-- tasks. Leave another player's tasks, resources and preview untouched.
for _,applying in ipairs{false,true} do
	removed,invalidate_player=handle("LuaPlayer",{index=1})
	local other=handle("LuaPlayer",{index=2})
	local stale,invalidate_stale=handle("LuaPlayer",{index=3})
	invalidate_stale()
	local planned=task(removed,true)
	local build=task(removed,false)
	local immediate=task(removed,false)
	local orphan=task(stale,true)
	local other_task=task(other,true)
	local other_build=task(other,false)
	local other_immediate=task(other,false)
	local overlay=handle("LuaRenderObject")
	local partial=handle("LuaRenderObject")
	local draft={player_index=1,applying=applying,renderings={overlay},
		render_job={objects={overlay,partial},retained={[overlay.id]=true}},output_job={}}
	local other_overlay=handle("LuaRenderObject")
	local other_data={preview={renderings={other_overlay}}}
	data={preview=draft,last_state=build,selection_render={(handle("LuaRenderObject"))},
		blueprint_items=handle("LuaInventory")}
	storage={players={[1]=data,[2]=other_data},
		tasks={other_task,planned,build,orphan,other_build},immediate_tasks={other_immediate,immediate}}
	invalidate_player()
	remove{player_index=1}
	assert(not storage.players[1] and storage.players[2]==other_data)
	assert(#storage.tasks==2 and storage.tasks[1]==other_task and storage.tasks[2]==other_build)
	assert(#storage.immediate_tasks==1 and storage.immediate_tasks[1]==other_immediate)
	assert(not overlay.valid and not partial.valid and not draft.render_job and not draft.output_job)
	for _,state in ipairs{planned,build,immediate,orphan} do
		assert(not state.blueprint.valid and not state.blueprint_inventory.valid)
		assert(not state._preview_rectangle.valid and not state._render_objects[1].valid)
	end
	for _,state in ipairs{other_task,other_build,other_immediate} do
		assert(state.blueprint.valid and state.blueprint_inventory.valid)
		assert(state._preview_rectangle.valid and state._render_objects[1].valid)
	end
	assert(other_overlay.valid,"removal affected another player's preview")
end

-- Cleanup can run without PlayerData, and inventories may already be invalid.
local orphan=task(removed,false)
storage={players={},tasks={orphan},immediate_tasks={}}
remove{player_index=1}
assert(#storage.tasks==0 and not orphan.blueprint_inventory.valid)
local invalid_inventory,invalidate_inventory=handle("LuaInventory")
invalidate_inventory()
storage.players[1]={blueprint_items=invalid_inventory}
remove{player_index=1}
assert(not storage.players[1])
print("Player removal OK: invalid handles, preview/build/belt cleanup, partial renders and player isolation")
