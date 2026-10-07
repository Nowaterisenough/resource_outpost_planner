# Resource Outpost Planner

[English](README.md) | [Chinese](README.zh-CN.md)

Plan mining patches and oil outposts in Factorio. Select resources, inspect a robot-safe ground preview, adjust the configuration, then apply the construction plan.

## Features

- Select a mining drill or pumpjack directly from the equipment row at the top.
- Space Age adds the big mining drill. Selecting an incompatible drill switches to a supported mining layout.
- Live previews use static entity artwork and create no construction ghosts, landfill or demolition orders.
- Mining layouts support belts, underground belts, poles, lamps, modules, fluid inputs and blueprint templates.
- Oil layouts support pumpjack orientation, pipe networks, poles, beacons, cold-surface heating and qualities.
- Share poles, pipes, qualities, obstacle avoidance, terrain filling and entity retention between both planners.
- Cancel discards only the preview; Undo removes the latest applied ghosts. Oil Undo also cancels its newly issued demolition orders where entities still exist.

## Requirements And Installation

Requires **Factorio 2.1**. Space Age is optional; the big drill and additional resource or cold-surface features require the corresponding game content.

Put `resource-outpost-planner_1.9.3.zip` in the Factorio mods directory, or install this repository in a folder named `resource-outpost-planner`. Enable the mod and restart Factorio.

This independent release uses the internal ID `resource-outpost-planner`. Disable the original Mining Patch Planner (or the earlier fork distributed under its ID) before enabling this mod. Existing built entities remain in the save, but original planner data and pending plans are not imported; configure this planner after switching.

## Workflow

1. Open the planner with **Ctrl+M** or its blueprint-style shortcut.
2. Drag to select resources. Use **Shift + left-drag** to add another area.
3. Inspect the translucent preview. Construction robots cannot build it.
4. Select equipment and adjust settings; the preview recalculates automatically.
5. Click **Apply** to revalidate the selection and place construction ghosts. Permitted terrain filling and demolition begin only after Apply.
6. Click **Cancel Preview** to discard the draft without changing the previously applied plan.

Solid or fluid resources automatically choose the appropriate mode. The layout dropdown controls mining layouts. A pole that does not fit a mining layout is replaced by that layout's default pole for the mining plan, with a message; oil retains the shared pole selection.

## Obstacle Avoidance

**Avoid** excludes lava, water, cliffs, trees, rocks and existing facilities. It overrides filling and demolition. Drills exclude blocked footprints, ordinary belts can detour, and oil routing excludes blocked locations. Unsafe auxiliary placements may be skipped. If required connections cannot be routed safely, planning stops and Apply remains disabled; try a different layout or a smaller area.

Previews use static frames of entity artwork, with an icon and footprint fallback when world graphics cannot be extracted. They are visual guides, not game entities.

## Oil Planning

Select one fluid-resource type per plan to avoid joining incompatible fluids. Extractors must have one output fluid box with one output connection. Oil settings include minimum beacon coverage, cold-surface heating and entity qualities. Optional **Module Inserter Extended** integration applies its module configuration to oil entities after Apply.

## Development And Validation

Run `python scripts/check-locales.py` to verify English/Chinese key coverage, references and placeholders. `scripts/render-settings-icons.py` rebuilds the settings atlas from installed Factorio artwork and requires Pillow.

Validated in Factorio 2.1.21: robot-safe previews, live settings, exact mining placements, big drills, oil networks, terrain filling, obstacle avoidance, cancellation, undo and applying a preview after save/reload.

## Credits And License

Based on **Mining Patch Planner** by **Rimbas**, with the planning engine from **Oil Outpost Planner 1.7.0** by **Coppermine**. The original MIT notices remain in [LICENSE](LICENSE) and [oil/vendor/LICENSE](oil/vendor/LICENSE). Integration details are in [oil/README.md](oil/README.md).

Repository: [Nowaterisenough/resource_outpost_planner](https://github.com/Nowaterisenough/resource_outpost_planner).
