-- Coalesce budgeted preview steps without running heavy successors or another
-- player's queued work in the same scheduling slot.
package.loaded["mpp.pole_connections"]={}
package.loaded["mpp.mpp_util"]={}
package.loaded["mpp.belt_planner"]={}
local completed=0
package.loaded["mpp.preview"]={dispose_task=function() end,complete=function() completed=completed+1 end}
local calls,result=0,true
algorithm={layouts={simple={tick=function(_,state)
 calls=calls+1
 if calls==6 and result==true then return "prepare_connections" end
 return result
end}}}
local runner=require("mpp.task_runner")
local state={layout_choice="simple",preview_only=true,_callback="layout_attempts"}
storage={tasks={state}}
runner.mining_patch_task(state)
assert(calls==4 and state._callback=="layout_attempts","small preview work still waits one tick per batch")
runner.mining_patch_task(state)
assert(calls==6 and state._callback=="prepare_connections","batch crossed into its heavy successor")
runner.mining_patch_task(state);assert(calls==7,"unbounded route step batched")
state._callback="process_grid";state._apply_after_preview=true
runner.mining_patch_task(state);assert(calls==8,"Apply validation budget changed")
state._apply_after_preview=nil;state.preview_only=false
runner.mining_patch_task(state);assert(calls==9,"actual construction budget changed")
state.preview_only=true;result=false
local other={layout_choice="simple",preview_only=true,_callback="layout_attempts"}
storage.tasks[2]=other
runner.mining_patch_task(state)
assert(calls==10 and completed==1 and storage.tasks[1]==other,"batch consumed the next player's job")
print("Preview scheduling: bounded batches, heavy-step boundaries, Apply and player isolation passed")
