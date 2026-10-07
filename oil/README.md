# Integrated Oil Planning

The planning engine in `vendor/planner.lua` and its helpers in `vendor/common.lua`
come from Oil Outpost Planner 1.7.0 by Coppermine, distributed under the MIT
license retained in `vendor/LICENSE`.

Source package: `OilOutpostPlanner_1.7.0.zip` from the installed Factorio mod library.
Upstream mod page: https://mods.factorio.com/mod/OilOutpostPlanner

The integration adds a fluid-resource layout to Resource Outpost Planner's existing
selection tool, settings window, task queue and undo control. It retains upstream
pumpjack orientation, regular/underground pipe routing, electric pole coverage,
beacon placement, heat pipes, landfill and quality support. Oil Outpost Planner
does not have to be installed or enabled separately.

Adaptations namespace helper modules and translations, isolate upstream temporary
globals, retain oil options during planner migrations, collect new
entity/tile ghosts for undo, and roll back newly created ghosts on planning failure.
Each selection must contain one fluid-resource type to avoid joining incompatible
fluids. Fluid extractors must have one output fluid box with one output connection,
as required by the upstream algorithm.
