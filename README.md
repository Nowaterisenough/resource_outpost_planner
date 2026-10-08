# Resource Outpost Planner

[English](README.md) | [Chinese](README.zh-CN.md)

Plan mining patches and oil outposts in Factorio. Select resources, inspect a robot-safe ground preview, adjust the configuration, then apply the construction plan.

## Features

- Select a mining drill or pumpjack directly from the equipment row at the top.
- Select unlocked qualities with compact icon buttons below each equipment or module picker; yellow marks the current quality. Belts, pipes, underground pipes and heat pipes have no quality control. Equipment and module columns align across the panel, without redundant equipment subtitles. The header contains only the title, and Undo sits in the footer.
- Space Age adds the big mining drill. Selecting an incompatible drill switches to a supported mining layout.
- Live previews use static entity artwork and create no construction ghosts, landfill or demolition orders.
- Mining layouts support belts, underground belts, poles, lamps, beacons, modules, fluid inputs and blueprint templates.
- Oil layouts support pumpjack orientation, pipe networks, poles, beacons, cold-surface heating and qualities.
- Share poles, pipes and qualities between both planners. Two terrain controls switch cliffs between avoid/remove and water, lava and lightning pools between avoid/fill, consistently across drills, beacons, oil layouts and belt connections.
- Both modes order equipment, transport, power/heating, beacons, layout options and terrain consistently. Oil pumpjacks and beacons also have adjacent module pickers with independent qualities and construction requests.
- Fill uses the terrain's landfill, foundation or platform; unfillable terrain remains blocked. Keeping existing facilities is independent of cliff removal and terrain filling.
- Cancel discards only the preview; Undo removes the latest applied ghosts and cancels its newly issued demolition orders where entities still exist.
- Selecting resources again clears the previous preview, statistics overlays and the latest unfinished construction plan made by this planner, including connected outputs and fill ghosts. Completed buildings and other construction plans remain. Shift-selection adds resources to the current preview.

## Requirements And Installation

Requires **Factorio 2.1**. Space Age is optional; the big drill and additional resource or cold-surface features require the corresponding game content.

Put `resource-outpost-planner_1.9.4.zip` in the Factorio mods directory, or install this repository in a folder named `resource-outpost-planner`. Enable the mod and restart Factorio.

This independent release uses the internal ID `resource-outpost-planner`. Disable the original Mining Patch Planner (or the earlier fork distributed under its ID) before enabling this mod. Existing built entities remain in the save, but original planner data and pending plans are not imported; configure this planner after switching.

## Workflow

1. Open the planner with **Ctrl+M** or its blueprint-style shortcut.
2. Click **Select**, then drag to select resources. Use **Shift + left-drag** to add another area. Click Select again or press **Q** to exit selection while keeping the preview.
3. Inspect the ground preview, using the blueprint's original artwork and green/red placement colors. Construction robots cannot build it.
4. Select equipment and adjust settings; the preview recalculates automatically.
5. Click **Apply** to revalidate the selection and place construction ghosts. Permitted terrain filling and demolition begin only after Apply.
6. Click **Cancel Preview** to discard the current draft. Selecting resources again clears the planner's latest unfinished construction plan before generating the new preview.

Solid or fluid resources automatically choose the appropriate mode. The layout dropdown controls mining layouts. A pole that does not fit a mining layout is replaced by that layout's default pole for the mining plan, with a message; oil retains the shared pole selection.

Drill modules sit beside **Extraction equipment**, and beacon modules beside **Beacon type**. Choosing a module enables it; right-click clears and disables it. Equipment without module slots hides the module control. Poles, beacons and optional oil equipment have no separate None button: click an equipment icon to enable it, click the active icon again or right-click to disable it. Yellow selection indicates enabled equipment. Required drills and belts retain a valid selection.

The footer's **Select / Output** buttons activate cursor modes; yellow marks the active mode. Opening the panel leaves tools idle, and recalculating the preview does not switch the cursor. After generating a mining preview with output belts, click **Output** to receive the native blueprint cursor, showing one belt per lane with the selected belt type and quality. Click the map to set or move the output; **R / Shift+R** rotate it. Click Output again or press **Q** to exit while keeping the target and direction. Reentering, repeated clicks and changes to lane count, belt type or quality preserve the direction. Connections appear in the ground preview, are built with the mining layout after Apply, and are included in Undo. Apply and Cancel Preview exit tool mode. Output can also connect the most recently applied mining layout. Oil and layouts without output belts disable the Output button.

**Stats** controls both placement reports and belt load displays. After Apply, chat reports drill count, internal belt rows, resource tiles and missed resources. Enable **ALT mode** to show each side's estimated production and capacity usage in previews and applied layouts, checking whether the belts can carry the drills' output. 100% is full; values above 100% are red. Big mining drills use researched belt stack capacity. Each side is capped independently for transportable throughput; totals report actual output belts and bottleneck losses. Production uses resource mining time and item yield, native module quality effects, module slots and mining productivity research. Belt merging uses the same capacity rules. Turning Stats off stops both reports and load displays. Existing settings keep Stats enabled if either former option was enabled. This option changes the display only, not the layout.

**More Drills** places drills more readily along patch edges and sparse areas, allowing more overlap between mining ranges. It can increase the number of drills mining at once, at the cost of more equipment and belts.

Choose a **Beacon Type** in mining settings to place beacons automatically; beacons start disabled. Enabling beacons uses **full rows on both sides**: reserve continuous beacon rows first, then arrange drill columns between them, sharing the middle row between adjacent columns. Beacon rows span the entire drill column. Underground belts cross the rows; poles and lamps use transport and power lanes. Fluid inputs reserve pipe channels between drills and beacon rows. Legacy density selections use the full-row arrangement.

**Beacon Modules** is separate from drill modules, with independent beacon and module qualities. Selected water, cliff and obstacle avoidance is respected. A blocked row keeps its red entity preview so the selection or obstacle settings can be adjusted. Electric drills cannot reach the centre ore tile underneath a 3x3 beacon; each unreachable ore tile appears red. Big drills have a mining area suitable for continuous rows. Supply power yourself when no pole is selected. The preview reports beacon count, drill coverage and the range of towers affecting each drill; belt load uses actual coverage, qualities and profile attenuation. Apply creates construction ghosts with module requests, and Undo includes beacons and supply poles. Blueprint templates retain their own beacons.

## Obstacle Avoidance

**Avoid** excludes lava, water, cliffs, trees, rocks and existing facilities. It overrides filling and demolition. Drills exclude blocked footprints, ordinary belts can detour, and oil routing excludes blocked locations. Unsafe auxiliary placements may be skipped. If required connections cannot be routed safely, Apply remains disabled and the ground preview stays visible: usable entities and completed connections are green, while blocked entities and unconnected belts are red with adjustment hints at problem locations. Red connections explain the failure and cannot be built. If no drill can be placed, selected resource positions are highlighted red. Moving or rotating the output or changing settings recalculates the preview.

Belt output connections prefer long straight runs, fewer turns and aligned parallel corridors. Opposite-facing outputs reverse row order to avoid crossing. Outputs behind the mine use nested parallel return corridors; if a greedy lane closes another lane's route, the planner tries the opposite order. Connections follow the individual water, cliff and obstacle avoidance settings, avoid planned equipment, and keep lanes separate. Move a blocked or unreachable output or adjust the settings. Apply validates the full route again before construction starts.

Previews use the blueprint's original artwork, dimensions, offsets and placement colors, including belt bends, underground entrances/exits and connected pipes. They have no footprint grid overlay. Entities whose artwork cannot be extracted use an icon. These previews are visual guides, not game entities.

## Oil Planning

Select one fluid-resource type per plan to avoid joining incompatible fluids. Extractors must have one output fluid box with one output connection. Oil settings include minimum beacon coverage, cold-surface heating and entity qualities. Optional **Module Inserter Extended** integration applies its module configuration to oil entities after Apply.

## Development And Validation

Run `python scripts/check-locales.py` to verify English/Chinese key coverage, references and placeholders. `scripts/render-settings-icons.py` rebuilds the settings atlas from installed Factorio artwork and requires Pillow.

Run `lua tests/belt-planner.lua` with Lua 5.2 to check rotated and multiple outputs, turn counts, parallel and return corridors, stable routing, obstacle routing, preview targeting, cursor direction persistence, failed previews and marker cleanup, preflight validation, landfill and undo collection. Belt previews, red/green failure diagnostics, recovery cleanup, targeting, blocked cliffs, rotation, applied placement parity and Undo have also been checked in Factorio 2.1.21.

Run `lua tests/preview-renderer.lua` to check blueprint artwork, original dimensions, placement colors, belt curves, underground entrances/exits and pipe connections. All eight belt curves have also been compared with actual placed belts in Factorio 2.1.21.

Run `lua tests/throughput.lua` to check production, module quality, resource yields, stack capacity, belt merging in four layouts, per-side saturation and actual output belt counts.

Run `lua tests/beacons.lua` to check beacon selection, permitted modules, qualities, profile attenuation, module requests, per-drill coverage differences and merged belt loads. `lua tests/beacon-rows.lua` checks both flanking rows, shared rows, continuity, rotated collision footprints, pipe channels, ore coverage, legacy density migration and blocked-row diagnostics.

Validated in Factorio 2.1.21: robot-safe previews, live settings, exact mining placements, big drills, oil networks, terrain filling, obstacle avoidance, cancellation, undo and applying a preview after save/reload.

## Credits And License

Based on **Mining Patch Planner** by **Rimbas**, with the planning engine from **Oil Outpost Planner 1.7.0** by **Coppermine**. The original MIT notices remain in [LICENSE](LICENSE) and [oil/vendor/LICENSE](oil/vendor/LICENSE). Integration details are in [oil/README.md](oil/README.md).

Repository: [Nowaterisenough/resource_outpost_planner](https://github.com/Nowaterisenough/resource_outpost_planner).
