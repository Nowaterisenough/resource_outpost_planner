-- Exercise validation, build handoff and failure rendering without a game process.
local calls,player,data,build_error,reuse
local render_id=0
local function object()
	render_id=render_id+1
	local result={valid=true,id=render_id}
	result.destroy=function() assert(result.valid);result.valid=false;calls.destroyed=calls.destroyed+1 end
	return result
end
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
package.loaded["mpp.input_mode"]={update_gui=function() end,idle=function(d) d.input_mode=nil end}
package.loaded["mpp.output_preview"]={}
defines={events={on_tick=1}}
script={on_event=function() end}
task_runner_handler=function() end
List=function() return {} end
game={tick=100,get_player=function() return player end}
local function state(event)
	return {player=player,surface=player.surface,resources=event.entities,preview_only=event.preview_only,
		preview_revision=event.preview_revision,_preview_specs={{name="entity-ghost",position={x=0,y=0}}},
		belts={},belt={},_collected_ghosts={}}
end
algorithm={
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
		gui={preview_apply={valid=true},preview_cancel={valid=true},undo_button={valid=true}}}
	storage={players={[1]=data},tasks={}}
	return draft,overlays,prior
end

local draft,overlays
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

print("Preview lifecycle OK: ordinary refresh, retained sprites and cancellation")
