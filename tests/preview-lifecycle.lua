-- Exercise validation, build handoff and failure rendering without a game process.
local calls,player,data,build_error,reuse
local render_id=0
local function object()
	render_id=render_id+1
	local result={valid=true,id=render_id}
	result.destroy=function() assert(result.valid);result.valid=false;calls.destroyed=calls.destroyed+1 end
	return result
end
package.loaded["mpp.forced_build"]={apply=function(_,mode) calls.forced=mode;return true end}
package.loaded["mpp.preview_renderer"]={render=function(draft)
	calls.render=calls.render+1;calls.rendered_error=draft.error
	if reuse then
		local retained=draft.renderings[1]
		return {retained},{[retained.id]=true}
	end
	return {object()}
end}
package.loaded["mpp.belt_planner"]={update_blueprint=function() calls.cursor=calls.cursor+1 end}
package.loaded["layouts.common"]={
	create_belt_planner_specification=function() return {count=2} end,
	display_lane_filling=function(state) calls.statistics=calls.statistics+1;state._render_objects[1]=object() end,
}
package.loaded["mpp.preview_diagnostics"]={
	capture=function() calls.validation=calls.validation+1 end,
	resource_issues=function(_,err) return {{position={x=0,y=0},reason=err}} end,
}
package.loaded["mpp.input_mode"]={update_gui=function() end,idle=function(d) d.input_mode=nil end,
	output_specification=function(d)
		local spec=d.preview.belt_specification
		if spec then spec.output_count=d.choices.output_balance_choice and d.choices.output_belt_count_choice end
		return spec
	end}
package.loaded["mpp.output_preview"]={}
package.loaded["mpp.preview_output_cache"]={complete=function() end,resume=function() return nil end}
defines={events={on_tick=1},build_mode={forced=1,superforced=2}}
script={on_event=function() end}
task_runner_handler=function() end
List=function() return {} end
game={tick=100,get_player=function() return player end}
local function state(event)
	return {player=player,surface=player.surface,resources=event.entities,preview_only=event.preview_only,
		_force_build_mode=event.force_build_mode,
		preview_revision=event.preview_revision,_preview_specs={{name="entity-ghost",position={x=0,y=0}}},
		belts={},belt={},_collected_ghosts={}}
end
algorithm={
	on_gui_close=function() end,
	clear_selection=function() calls.clear_selection=calls.clear_selection+1 end,
	on_player_selected_area=function(event)
		if event.preview_only then calls.recheck=calls.recheck+1
		else
			calls.commit=calls.commit+1
			if build_error then return nil,build_error end
		end
		return state(event)
	end,
}
local preview=require("mpp.preview")
local function fixture()
	calls={render=0,statistics=0,cursor=0,validation=0,recheck=0,commit=0,clear_selection=0,destroyed=0}
	build_error=nil
	reuse=false
	player={index=1,surface={valid=true}}
	local prior={_collected_ghosts={}}
	local overlays={object(),object()}
	local draft={player_index=1,surface=player.surface,resources={{valid=true}},revision=1,ready=true,
		specs={},renderings=overlays,belt_target={position={x=0,y=-10},direction=0}}
	data={preview=draft,choices={belt_planner_choice=true},last_state=prior,input_mode="output",
		gui={preview_apply={valid=true},preview_cancel={valid=true},undo_button={valid=true},
			preview_force={valid=true},
			preview_status={valid=true,style={}}}}
	storage={players={[1]=data},tasks={}}
	return draft,overlays,prior
end

local draft,overlays,prior=fixture()
assert(preview.apply(data) and draft.applying,"Apply did not start validation")
assert(calls.recheck==1 and calls.commit==0 and #storage.tasks==1,"Apply bypassed its safety check")
local validation=storage.tasks[1]
assert(validation.preview_only and validation._apply_after_preview)
preview.complete(validation)
assert(calls.validation==1 and calls.commit==1 and #storage.tasks==2,"validated plan was not queued for construction")
local build=storage.tasks[2]
assert(build._from_preview and build._undo_state==prior,"build handoff lost Undo state")
assert(draft.applying and not data.gui.preview_apply.enabled,"Apply became available during construction")
assert(calls.render==0 and calls.statistics==0 and calls.cursor==0,"successful Apply redrew its temporary preview")
assert(draft.renderings==overlays and overlays[1].valid and overlays[2].valid,"existing preview disappeared before construction")
table.remove(storage.tasks,1)
preview.applied(build)
assert(not data.preview and calls.destroyed==2,"completed construction left stale preview objects")

draft,overlays=fixture()
preview.complete(state{entities=draft.resources,preview_only=true,preview_revision=1})
assert(calls.render==1 and calls.statistics==1 and calls.cursor==1,"ordinary preview refresh was skipped")
assert(calls.destroyed==2 and not overlays[1].valid and data.gui.preview_apply.enabled,"ordinary preview did not replace its overlays")

draft,overlays=fixture();reuse=true
preview.complete(state{entities=draft.resources,preview_only=true,preview_revision=1})
assert(calls.destroyed==1 and overlays[1].valid and not overlays[2].valid,"refresh destroyed a retained sprite or kept obsolete statistics")
assert(draft.renderings[1]==overlays[1] and #draft.renderings==2)
preview.cancel(data)
assert(calls.destroyed==3 and not overlays[1].valid and not data.preview,"Cancel leaked a reused sprite")

draft,overlays=fixture()
assert(preview.apply(data))
validation=storage.tasks[1];validation.preview_error={"mpp.output_balance_blocked"}
preview.complete(validation)
assert(not draft.applying and not draft.ready and not data.gui.preview_apply.enabled,"failed validation can still Apply")
assert(calls.commit==0 and calls.render==1 and calls.rendered_error==validation.preview_error,"failed validation lost its diagnostic preview")
assert(data.gui.preview_status.visible and data.gui.preview_status.caption==validation.preview_error,"failure is hidden behind the Apply tooltip")
assert(not overlays[1].valid and #storage.tasks==1,"failed validation queued construction or kept stale overlays")

draft=fixture()
assert(preview.apply(data))
build_error={"mpp.msg_miner_err_0"}
preview.complete(storage.tasks[1])
assert(calls.commit==1 and #storage.tasks==0,"failed build preparation left a task queued")
assert(not draft.applying and not draft.ready and calls.render>0,"build preparation failure was hidden by the fast path")
assert(calls.rendered_error==build_error and not data.gui.preview_apply.enabled)

draft,overlays=fixture()
preview.complete(state{entities=draft.resources,preview_only=true,preview_revision=0})
assert(calls.render==0 and calls.validation==0 and calls.commit==0 and overlays[1].valid,"stale result changed the active preview")
draft=fixture()
preview.request(data)
assert(data.gui.preview_status.visible and data.gui.preview_status.caption[1]=="mpp.preview_updating","output recalculation has no visible feedback")
assert(draft.refresh_at==game.tick+8,"rapid settings edits lost their debounce")
preview.complete(state{entities=draft.resources,preview_only=true,preview_revision=draft.revision})
assert(not data.gui.preview_status.visible,"successful preview retained a stale error/progress label")
draft=fixture()
draft.belt_specification={count=26,minimum_output_count=23}
data.choices.output_balance_choice=true;data.choices.output_belt_count_choice=8
preview.request(data,true)
assert(not draft.error and draft.refresh_at and data.gui.preview_status.visible,"fixed output count blocks layout replanning")
assert(draft.refresh_at==game.tick+1,"output click retains the settings debounce delay")
local capped=state{entities=draft.resources,preview_revision=draft.revision}
capped.preview_warning={"mpp.belt_capacity_outputs",8,"63.6"}
preview.complete(capped)
assert(draft.ready and data.gui.preview_apply.enabled and data.gui.preview_status.caption==capped.preview_warning,"bottleneck warning blocks Apply or is hidden")
data.choices.output_belt_count_choice=24
preview.request(data,true)
assert(not draft.error and draft.refresh_at,"valid output count did not recover")
local revision,deadline=draft.revision,draft.refresh_at
for i=1,60 do
	game.tick=100+i
	assert(preview.set_belt_target(data,{position={x=0,y=-10},direction=0,mirror=false}))
end
assert(draft.revision==revision and draft.refresh_at==deadline,"held clicks keep postponing or canceling the plan")
preview.set_belt_target(data,{position={x=1,y=-10},direction=0})
assert(draft.revision==revision+1,"moving the output is ignored")
data.choices.output_belt_count_choice=8
preview.request(data)
assert(not draft.warning and not draft.error and draft.refresh_at,"equipment changes use stale capacity estimates")
draft=fixture();draft.output_basis={cached=true}
preview.request(data,true)
assert(draft.output_basis and draft.output_change,"output request discarded reusable mining basis")
preview.request(data)
assert(not draft.output_basis and not draft.output_change,"equipment request kept an obsolete mining basis")

draft=fixture();draft.ready=false;draft.error={"mpp.output_balance_blocked"}
draft.specs={{name="entity-ghost",position={x=0,y=0},preview_blocked=true}}
preview.update_gui(data)
assert(data.gui.preview_force.enabled and not data.gui.preview_apply.enabled,"blocked plan has no force action")
assert(not preview.apply(data),"ordinary Apply bypasses blocked plan")
assert(preview.apply(data,defines.build_mode.superforced),"forced Apply cannot replan an obstructed output")
validation=storage.tasks[1]
assert(validation.preview_only and validation._force_build_mode==defines.build_mode.superforced)
preview.complete(validation)
assert(calls.forced==defines.build_mode.superforced and storage.tasks[2]._forced_applied,"native build mode lost")
assert(calls.commit==0,"forced plan fell back to ordinary ghost placement")

draft=fixture();assert(preview.apply(data,defines.build_mode.forced))
validation=storage.tasks[1];validation.preview_error={"mpp.msg_obstacle_route_failed"}
preview.complete(validation)
assert(not calls.forced and storage.tasks[2]._force_build_mode,"changed obstacles did not trigger a coherent fallback")
validation=storage.tasks[2];validation.preview_error={"mpp.msg_obstacle_route_failed"}
preview.complete(validation)
assert(not calls.forced and not draft.ready and not draft.applying,"invalid diagnostic guides reached native building")
draft=fixture();preview.request(data)
assert(not data.gui.preview_force.enabled and not preview.apply(data,defines.build_mode.forced),"force builds an unfinished preview")

draft=fixture();assert(preview.apply(data,defines.build_mode.forced))
validation=storage.tasks[1]
assert(not validation._force_build_mode,"force discards a valid displayed route")
preview.complete(validation)
assert(calls.forced==defines.build_mode.forced and storage.tasks[2]._forced_applied)

draft=fixture();assert(preview.apply(data,defines.build_mode.forced))
validation=storage.tasks[1];validation._preview_specs={};validation.preview_error={"mpp.preview_failed"}
preview.complete(validation)
assert(not draft.applying and not data.gui.preview_apply.enabled and data.gui.preview_status.caption==draft.error,
	"empty failed preflight leaves UI stuck applying")

-- Automatic facility removal is a native superforced build, but must never
-- retry a failed terrain check with the manual force-routing override.
draft=fixture();data.choices.remove_entities_choice=true
assert(preview.apply(data));validation=storage.tasks[1]
assert(validation._native_build_mode==defines.build_mode.superforced and validation._facility_removal)
preview.complete(validation)
assert(calls.forced==defines.build_mode.superforced and storage.tasks[2]._forced_applied)
draft=fixture();data.choices.remove_entities_choice=true
assert(preview.apply(data));validation=storage.tasks[1];validation.preview_error={"blocked-terrain"}
preview.complete(validation)
assert(not calls.forced and #storage.tasks==1 and not draft.applying and draft.error,
 "automatic facility removal bypasses terrain validation")

-- Explicit Shift/Force Apply must not turn off a checked Clear control.
for _,mode in ipairs{defines.build_mode.forced,defines.build_mode.superforced} do
 draft=fixture();data.choices.remove_entities_choice=true
 assert(preview.apply(data,mode));validation=storage.tasks[1]
 assert(validation._native_build_mode==defines.build_mode.superforced, "forced Apply ignores checked cleanup")
 assert(not validation._facility_removal, "explicit force lost its routing override")
 preview.complete(validation)
 assert(calls.forced==defines.build_mode.superforced, "checked cleanup did not reach native building removal")
end
-- Independent forced plans own only their new ghosts/orders. Otherwise Undo
-- on the second mine also removes the first, even when their areas differ.
for _,mode in ipairs{defines.build_mode.forced,defines.build_mode.superforced} do
 draft,overlays,prior=fixture()
 local old_ghost,old_order={},{}
 prior._collected_ghosts={old_ghost};prior._deconstruction_orders={old_order}
 assert(preview.apply(data,mode));validation=storage.tasks[1]
 preview.complete(validation)
 local built=storage.tasks[2]
 assert(built and #built._collected_ghosts==0 and #(built._deconstruction_orders or {})==0,
  "new forced mine inherited the previous plan's Undo ownership")
 assert(prior._collected_ghosts[1]==old_ghost and prior._deconstruction_orders[1]==old_order,
  "second force apply mutated first plan ownership")
end
-- Large jobs must keep both Apply modes disabled and clean up only their own
-- newly allocated handles when retargeted, including output construction jobs.
local renderer=package.loaded["mpp.preview_renderer"]
local partial
renderer.begin=function(d)
 partial=object()
 return {objects={d.renderings[1],partial},retained={[d.renderings[1].id]=true},remaining=2}
end
renderer.step=function(d,job)
 job.remaining=job.remaining-1
 if job.remaining>0 then return end
 return job.objects,job.retained
end
draft,overlays=fixture()
local large=state{entities=draft.resources,preview_only=true,preview_revision=1}
for i=1,3000 do large._preview_specs[i]={name="entity-ghost",position={x=i,y=0}} end
preview.complete(large)
assert(preview.has_pending() and draft.render_job and not draft.ready and not data.gui.preview_force.enabled)
assert(not preview.apply(data) and not preview.apply(data,defines.build_mode.superforced),"Apply accepts partial rendering")
preview.tick();assert(draft.render_job,"render job finished before its last batch")
preview.tick();assert(draft.ready and not preview.has_pending() and data.gui.preview_apply.enabled)
assert(overlays[1].valid and not overlays[2].valid and partial.valid,"completed render cleanup changed retained objects")
large.preview_revision=draft.revision;preview.complete(large)
local abandoned=partial
preview.request(data,true)
assert(not draft.render_job and not abandoned.valid and overlays[1].valid,"retarget leaked or deleted the wrong layers")
draft.output_job={unfinished=true}
preview.request(data,true)
assert(not draft.output_job,"retarget did not cancel construction")
preview.cancel(data)
assert(not data.preview and not overlays[1].valid,"cancel leaked retained sprites")
print("Preview lifecycle OK: validation, build handoff, cleanup click modes, overlay cleanup and failure paths")
