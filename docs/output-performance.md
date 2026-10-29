# Output preview performance

Measured on 2026-10-09 with Factorio 2.1.21 on the same Apple M4 host and save.
Baseline: `c07c493`. The benchmark creates an isolated surface with a 24x24 ore patch,
then measures moving three output belts or a two-locomotive loading station.

## Results

Times are native LuaProfiler measurements in milliseconds. Total is accumulated
script work across the request, and peak tick is the longest single script update.
The existing preview pipeline still spans 32 game ticks; these numbers are not
click-to-preview wall-clock latency. Profiling wrappers are identical in both runs.

| Scenario | Before total | After total | Before peak tick | After peak tick |
| --- | ---: | ---: | ---: | ---: |
| belts-near | 264.44 | 20.51 | 98.95 | 7.61 |
| belts-moved | 241.71 | 19.66 | 79.62 | 6.96 |
| balance-3-8 | 227.97 | 72.18 | 88.22 | 27.06 |
| station-3-8 | 379.27 | 77.77 | 136.44 | 32.24 |
| station-mirrored | 440.82 | 74.82 | 173.55 | 37.58 |
| station-3-10 | 307.16 | 62.39 | 102.89 | 32.34 |
| station-far | 10685.02 | 93.86 | 9807.78 | 34.86 |
| station-over-mine | 343.20 | 64.21 | 190.80 | 24.13 |
| belts-water-wall | 1055.19 | 498.95 | 883.84 | 463.18 |
| blocked-output | 313.69 | 49.31 | 132.92 | 29.48 |

## Bottlenecks and changes

- Fast routing used the clicked station anchor instead of the actual balancer input band. The far-station case fell back to large grid searches. Corridors now use actual input coordinates.
- Terrain collection materialized every tile, including grass, repeatedly. Hazard tile prototypes are filtered by the engine, and route scans use the actual search rectangle.
- Entity collision checks traversed all retained buildings. A tile-based broad phase now limits exact box checks to nearby candidates; prototype collision geometry is cached.
- Grid search built strings for every directional node and allocated a direction array per expansion. Numeric node keys and a shared direction array reduce this work. The admissible heuristic includes a lower bound on remaining turns.

The far-station case reduced placement probes from 96185 to 3616.
The water-wall case remains relatively expensive (about half a second); general obstacle searches are still synchronous.
Mining recomputation, rendering, and apply-time validation remain enabled.

## Reproduce

Requires Python 3.12+ and a Factorio 2.1 installation. The save must contain player 1.
The supplied save is copied into the run directory before Factorio opens it.
Each run uses its own mod, configuration, save and data directories. Benchmark
instrumentation is excluded from release packages.

```sh
python3 scripts/benchmark-output.py \
  --factorio /path/to/factorio \
  --save /path/to/test-save.zip \
  --ref c07c493 \
  --output dist/performance

python3 scripts/benchmark-output.py \
  --factorio /path/to/factorio \
  --save /path/to/test-save.zip \
  --output dist/performance
```

Pass `--data /path/to/factorio/data` if the data directory cannot be inferred.
Each run produces `benchmark.log` and machine-readable `results.json`, including
digests of the tested runtime files and input save. A missing completion marker
fails the run.

## Correctness checks

- All standalone Lua tests pass, including exact collision comparisons, hazard filters, cache invalidation, negative coordinates, fractional box edges, and placement snapping.
- The offset input-band regression limits placement probes on an open corridor to prevent a return to expansive search.
- Native station workflow, blocked red diagnostics, preview/application parity, applied-mine output, and Undo pass.
- 192 native cursor placements pass across rotations, mirrors, repeat placement, and restored rail snapping.

## 2026-10-11: scan and preview overhead

Compared the working tree with `v1.9.7` on the same Factorio 2.1.21 host.
Both versions use the same updated benchmark harness. Large-mine and Apply
results are medians of three runs per version. The original ten output cases
also ran once per version to compare generated layouts and blocked states.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| 64x64 mine, ordinary outputs | 144.63 | 140.08 | 68.05 | 52.86 |
| 64x64 mine, balanced outputs | 177.04 | 172.36 | 74.29 | 56.67 |
| 64x64 mine, loading station | 223.59 | 219.60 | 77.19 | 96.25 |
| Apply a 2+4 loading station | 160.05 | 122.43 | 68.42 | 45.16 |

- Obstacle collection now excludes resource, character, unit, corpse, dropped
  item and tile-ghost types in the engine. Actual buildings, cliffs and entity
  ghosts still follow the existing exact collision and ownership checks.
  Large-mine obstacle scans fell from 16.27-22.41 ms to 2.41-3.60 ms.
- Successful Apply validation hands off to construction without redrawing
  the temporary preview or statistics. Existing overlays stay until construction
  finishes; validation and build-preparation failures still refresh diagnostics.
  The two planning/validation passes remain enabled.
- Preview sprite-path checks cache both existing and missing variants for the
  script lifetime. Placement checks and blocked colors remain live.

Large-mine previews still take 36 game ticks and Apply takes 50. These changes
reduce script work, not the number of pipeline stages. The large-station peak
did not improve in this small sample: rendering and allocation remain variable.
Water-wall routing is still synchronous and remains about half a second.
Detailed timers overlap, so their values must not be summed.

The benchmark now supports `--scenario large` and `--scenario apply`; the default
`--scenario outputs` keeps the original ten cases. For example:

```sh
python3 scripts/benchmark-output.py --factorio /path/to/factorio \
  --save /path/to/test-save.zip --scenario large --ref v1.9.7
python3 scripts/benchmark-output.py --factorio /path/to/factorio \
  --save /path/to/test-save.zip --scenario large
python3 scripts/benchmark-output.py --factorio /path/to/factorio \
  --save /path/to/test-save.zip --scenario apply --ref v1.9.7
python3 scripts/benchmark-output.py --factorio /path/to/factorio \
  --save /path/to/test-save.zip --scenario apply
```

Reports include detailed phase timings and a geometry hash for each preview
or applied construction plan. All 25 measured final-version snapshots match
the baseline entity names, positions, directions, underground types, priorities,
filters and blocked flags. Applied stations retain all 1201 entities.

Regression coverage includes `tests/preview-lifecycle.lua` for successful
handoff, retained overlays, cleanup, failed validation, failed build preparation
and stale results; obstacle tests retain 201 exact collision comparisons plus
type/ownership checks; renderer tests cover cached missing sprites and live
placement-color changes. Native tests pass for 12 area/obstacle-mode combinations
and the full station preview/Apply/Undo workflow, including 1150 matching
preview/applied entities and output added to an already applied mine.

## 2026-10-11: preview rendering reuse

This round compares against the first-round optimized runtime described above,
archived in `dist/performance-round2-20261011/baseline-package/`, rather than
against the published `v1.9.7` runtime. Both sides use the same updated harness.
Final runs use one fixed Factorio 2.1 test-save copy, recorded by `save_sha256`.
The large, movement and Apply scenarios each ran three times per version,
sequentially with no concurrent test jobs. Baseline samples are retained from the
paired run; the final compact representation was then measured separately.
The table shows medians; these remain accumulated script time, not UI latency.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| Large ordinary outputs | 175.71 | 140.43 | 41.02 | 28.61 |
| Large balanced outputs | 171.05 | 152.04 | 52.93 | 48.08 |
| Large loading station | 235.44 | 197.43 | 107.54 | 78.96 |
| Station initial placement | 258.53 | 230.89 | 87.52 | 77.52 |
| Station moved | 232.70 | 185.11 | 79.49 | 58.13 |
| Station rotated | 212.16 | 162.55 | 107.42 | 61.64 |
| Station mirrored | 244.65 | 160.75 | 107.91 | 44.41 |
| Apply a loading station | 77.79 | 66.67 | 18.28 | 17.12 |

Rendering medians for moving/rotating/mirroring fell from 72.26/100.23/100.03 ms
to 46.43/50.69/39.17 ms. Moving creates only 48 sprites while retaining 5680;
rotation creates none while retaining 4912. These counts demonstrate reuse,
but are not a substitute for the measured CPU times. Compact per-sprite records
avoid the larger persistent hash tables used in the intermediate implementation,
which regressed Apply in its three-run sample. Allocation and garbage-collection
timing can still move pauses between stages: final Apply samples range from
66.39 to 98.55 ms, with one 43.68 ms peak. This optimization does not promise lower
peaks for every request. The pipeline still takes 36 game ticks for these previews
and 50 for Apply.

The renderer now reuses the valid prefix of its sprite objects in draw order,
updating changed artwork, position, scale, orientation and color. An invalid
handle rebuilds the remaining suffix to preserve layer order. Obsolete sprites
and statistics are still destroyed; Cancel, Apply and Undo keep their cleanup
behavior. Terrain fallback rectangles and error annotations are refreshed.

Fluid-port shapes and sprite-layer recipes cache only prototype data. Belt/pipe
neighbors, placement checks, obstacle scans and blocked colors stay live. Shared
layer recipes avoid repeated path construction and per-sprite style tables.
Reusable handles and their metadata live on the stored preview, with style
sharing scoped to each draft so save/load does not depend on local cache state.

The new `--scenario move` starts with a 64x64 mine and places, moves, rotates and
mirrors the station without clearing it between requests. This exercises reuse
of the whole station, unlike `--scenario large`, which starts each measurement
with a mine-only preview. Run it with the same arguments shown above, replacing
`--scenario large` with `--scenario move`.

Reports additionally contain `sprites_sha256` and `sprite_order_sha256`, derived
from native render-object artwork, target positions, RGBA colors, scale and
orientation. The harness checks duplicate handles and leaked obsolete sprites.
These are checks of graphic definitions and draw sequence, not pixel screenshots.
All 74 final baseline/current snapshots from 20 runs match layout, readiness,
entity count and stage count; all 68 preview snapshots also match sprite
definitions and order. Applied plans retain all 1201 entities. These invariants
also match the earlier fixture snapshots. Full sample timings and runtime/save
digests are in `dist/performance-round2-20261011/comparison-final.json` and its
referenced run reports. The original ten output cases ran once per version:
their water-wall route still costs about half a second, and one over-mine case
has a higher peak despite lower total time. They do not establish repeatable
latency improvements on their own.

All standalone Lua suites pass, including 98 renderer cases for live topology,
asymmetric fluid-port rotation/mirroring, missing artwork, externally destroyed
handles, draw order and cache isolation. The native station workflow retains
1150 matching preview/applied entities, settings, R/H/V, blocked diagnostics,
Apply/Undo and adding output to an applied mine. An isolated native save/load
test preserves all eight sampled sprite handles and graphic properties, supports
rotation after loading and removes all of them on Cancel. Multi-client joining
was not exercised.

## 2026-10-11: obstacle search allocation

This round uses the final preview-reuse runtime as its baseline, archived in
`dist/performance-round3-20261011/baseline-package/`. The source save is copied
into each isolated run, and both runtimes use the same input-save digest.

- Search nodes use compact arrays instead of hash tables. Returned paths retain
  only coordinates, so the search metadata does not stay attached to lane paths.
- A search caches cell passability and congestion penalties independently of
  arrival direction. These caches end with that search, before the next lane or
  negotiation pass can change reservations, occupancy or congestion history.
- Out-of-bounds candidates are rejected before cost calculation, and distance
  is calculated only for candidates entering the heap. Cost, heuristic, tie
  breaking, endpoint restrictions and search budgets are unchanged.

Correctness snapshots allocate many temporary tables/strings between measured
requests. The benchmark now accepts `--timing-only` to omit those snapshots and
their leak/duplicate checks during timing runs. Use the default mode separately
for correctness verification; `capture_snapshots` records the mode in each report.
This avoids attributing snapshot-induced garbage-collection timing to normal
gameplay, but does not eliminate allocation-related variability in the planner.

The table is the median of three runs per version with `--timing-only`, paired
with alternating baseline/current order and no concurrent test jobs. Times are
accumulated script work, not click-to-preview latency.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| belts-near | 18.36 | 18.02 | 5.43 | 5.30 |
| belts-moved | 17.90 | 17.82 | 5.35 | 5.17 |
| balance-3-8 | 24.25 | 23.17 | 8.59 | 7.65 |
| station-3-8 | 114.83 | 113.93 | 47.45 | 50.68 |
| station-mirrored | 82.21 | 80.25 | 33.69 | 28.71 |
| station-3-10 | 66.41 | 67.45 | 29.35 | 36.20 |
| station-far | 107.33 | 112.33 | 47.01 | 50.38 |
| station-over-mine | 67.57 | 63.45 | 31.30 | 21.65 |
| belts-water-wall | 540.11 | 451.94 | 494.80 | 408.83 |
| blocked-output | 48.53 | 48.70 | 21.48 | 21.87 |

The water-wall case reduces total script time by 16.3% and peak tick time by
17.4%. Its routing phase falls from 492.53 to 408.60 ms. In the separate runs
with snapshots enabled, its medians also improve: total 555.56 to 450.96 ms and
peak 513.73 to 405.58 ms. Open routes mostly retain their existing fast corridor
path. Some station totals and peaks increase in this small sample; this is not
a general latency improvement for every station placement. Water detours remain
synchronous and can still occupy about 0.4 seconds in one script update.

Ten correctness runs cover the original outputs three times per version, plus
one movement and one Apply run per version. All 72 geometry snapshots match,
as do all 70 preview sprite-definition/order snapshots, ready states, entity
counts and pipeline ticks. The single movement/Apply pairs establish correctness,
not repeatable latency effects. Timing-only runs provide 60 additional matching
ready/entity/tick observations. Full data is in
`dist/performance-round3-20261011/comparison-final.json` and
`dist/performance-round3-20261011/comparison-timing.json`.

All standalone Lua suites pass. `tests/belt-search.lua` adds 108 cases, including
an independent Dijkstra cost/reachability oracle, weighted detours, negative and
fractional coordinates, deterministic ties, changing passability/congestion
between searches, zero/exhausted budgets and coincident endpoint restrictions.
The existing 212 route/preview cases and native station preview/Apply/Undo workflow
also pass.

```sh
python3 scripts/benchmark-output.py --factorio /path/to/factorio \
  --save /path/to/test-save.zip --scenario outputs --ref BASELINE_REF --timing-only
python3 scripts/benchmark-output.py --factorio /path/to/factorio \
  --save /path/to/test-save.zip --scenario outputs --timing-only
```

## 2026-10-11: sealed destinations and heap maintenance

The baseline is the completed obstacle-search allocation round, archived in
`dist/performance-round4-20261011/baseline-package/`. All measurements use the
same copied input save and isolated Factorio configuration/mod/data directories.

Profiling found a failed greedy water-wall search that expanded 19992 directional
states and made 441738 heap comparisons, although its destination had no legal
incoming neighbor. The search now checks up to three permitted predecessors
before expanding nodes. A sealed destination fails immediately. A free entrance
only permits the normal A* search to proceed; it does not imply that a route
exists. Source-adjacent and coincident destinations retain their existing rules,
and an exhausted budget performs no placement probes. Probe results feed the
existing per-search passability cache.

The heap also tracks its length explicitly, clears its tail directly, and
calculates each parent index once per sift-up iteration. Ordering still compares
score, turns, distance and insertion sequence in the same order. Costs,
heuristics and expansion limits are unchanged.

Three timing-only runs per version were paired with alternating run order and
no concurrent test jobs. These are medians of script work, not end-to-end UI
latency. The original ten scenarios are all included to expose mixed results.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| belts-near | 16.95 | 16.76 | 5.10 | 4.87 |
| belts-moved | 16.91 | 17.12 | 5.06 | 5.28 |
| balance-3-8 | 22.79 | 22.41 | 7.55 | 7.13 |
| station-3-8 | 112.30 | 105.46 | 47.21 | 32.87 |
| station-mirrored | 77.61 | 71.36 | 30.29 | 32.65 |
| station-3-10 | 60.31 | 65.18 | 23.94 | 27.72 |
| station-far | 103.16 | 99.18 | 43.06 | 35.30 |
| station-over-mine | 58.54 | 66.56 | 22.52 | 28.13 |
| belts-water-wall | 445.99 | 256.44 | 413.45 | 205.28 |
| blocked-output | 50.60 | 43.15 | 28.09 | 17.61 |

The water-wall case reduces total script time by 42.5% and peak script-update
time by 50.3%; the routing phase falls from 413.19 to 205.02 ms. All three current
water-wall peaks (196.62-211.61 ms) are below all three baseline peaks
(397.75-447.85 ms). With correctness capture enabled, a separate pair also
improves from 448.89/411.25 ms total/peak to 246.85/203.62 ms. Ordinary routes are
mostly unchanged; some station totals and peaks rise in this sample. Search is
still synchronous, so complex successful detours can still take about 0.2 seconds
in one script update. This is not a frame-time guarantee for arbitrary obstacles.

Six correctness runs (outputs, movement and Apply, once per version) produce
32 identical geometry snapshots and 30 identical sprite-definition/order
snapshots, with matching readiness, entity counts and pipeline ticks. The six
timing-only runs add 60 matching ready/entity/tick observations. Reports are in
`dist/performance-round4-20261011/comparison-final.json` and
`dist/performance-round4-20261011/comparison-timing.json`.

All Lua suites pass, including 119 search cases. The 11 new cases exercise
sealed destinations in every direction, an opening only on the forbidden
reverse side, exactly one legal entrance, source-adjacent outlets (including an
initial source outside the search bounds), and a coincident source/destination.
The sealed-outlet regression caps placement probes at three on a large open
grid. Native station preview/application parity, R/H/V, diagnostics, Apply/Undo
and adding output to an already applied mine also pass.

## 2026-10-11: priority-queue hot loop

This round compares against the completed sealed-destination/heap-maintenance
runtime, archived in `dist/performance-round5-20261011/baseline-package/`.
The final change keeps the binary heap and the same four-part priority order:
score, turns, distance, then insertion sequence.

- Removal first moves the heap hole down to a leaf, then sifts the former tail
  back up. This avoids comparing the tail at every downward level.
- Priority comparisons read each compared field once into local values.
- Neighbor expansion uses a numeric loop over the existing four directions.
- The heuristic returns its already calculated Manhattan distance alongside
  the estimate, avoiding a second calculation for each queued node.

Three timing-only runs per version use the same copied save, alternate run
order, and run without concurrent test jobs. Medians are accumulated script
work rather than UI latency. All ten scenarios are retained in the table.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| belts-near | 16.99 | 17.19 | 5.22 | 5.18 |
| belts-moved | 16.52 | 17.15 | 4.79 | 5.18 |
| balance-3-8 | 21.64 | 22.01 | 7.06 | 6.92 |
| station-3-8 | 108.21 | 114.49 | 46.48 | 48.56 |
| station-mirrored | 76.56 | 81.42 | 30.20 | 33.42 |
| station-3-10 | 61.69 | 64.19 | 32.00 | 32.54 |
| station-far | 98.60 | 102.33 | 46.76 | 44.94 |
| station-over-mine | 58.63 | 59.67 | 18.97 | 21.30 |
| belts-water-wall | 245.41 | 221.63 | 211.14 | 181.63 |
| blocked-output | 42.68 | 43.00 | 17.40 | 15.44 |

The water-wall case reduces total script work by 9.7% and peak script-update
time by 14.0%; its routing phase falls from 210.89 to 181.41 ms. All current
water-wall peaks (180.70-190.27 ms) are below all baseline peaks
(199.88-214.71 ms). A separate correctness-capture pair also improves, from
268.93/205.89 ms total/peak to 224.27/177.39 ms. Ordinary routes show little benefit
and several station totals/peaks increase in this sample. This change targets
the search hot loop, not every stage of station generation. Search still runs
synchronously, so it does not provide a fixed per-tick time budget.

Six correctness runs (outputs, movement and Apply once per version) match all
32 geometry and 30 sprite-definition/order snapshots, readiness, entity counts
and stage counts. Timing runs add 60 matching ready/entity/tick observations.
Per-version runtime digests and the copied input-save digest agree across both
modes. Full reports are in
`dist/performance-round5-20261011/comparison-final.json` and
`dist/performance-round5-20261011/comparison-timing.json`.

All Lua suites pass. Search coverage is now 123 cases, including four reference
detours captured before this change to protect tie selection for every output
direction, plus the independent Dijkstra oracle and existing sealed-entry and
budget cases. Native station preview/application parity, R/H/V, diagnostics,
Apply/Undo and output added to an already applied mine also pass.

## 2026-10-11: irregular mine and inward-facing station inputs

An isolated graphical test uses 4,508 iron-ore entities within a 96x76 area,
with concave edges, holes and a detached lobe. Selection must be bounded to
`{{-48,-37},{48,39}}`: newly generated chunks can add unrelated natural ore
elsewhere on the test surface. The station anchor is `(65,65)`, with two
locomotives, four wagons and double-sided loading.

The sequential routing passes could enclose later lanes when a perpendicular
station input band faces back into the mining rows. A bounded fallback now
tries nested corridors beyond the full mine/station bounds before congestion
negotiation. It checks every cell against existing occupancy, reservations and
terrain. Existing successful routes and the literal balancer templates are
unchanged; neither search budget nor per-search node limit was increased.

Native checks of four directions with and without mirroring improve from five
to seven ready previews out of eight. East-facing normal and mirrored stations
now produce 5,334 and 5,633 valid preview entities. The south-facing mirrored
station at this anchor still fails routing and correctly disables Apply; this
fallback does not solve arbitrary bundle routing.

Graphical-client checks use actual R, V and H key input. Application and Undo
are invoked through the registered GUI handlers from an isolated test command.
The west-facing result applies all 5,412 preview entities with matching names,
positions and directions, zero missing/extra entities, and Undo removes every
construction ghost. The small native station workflow also passes with 1,150
matching entities, including output added to an already applied mine.

Sixteen additional standalone cases cover 13-lane inward-facing ports in both
perpendicular directions and four world rotations, plus blocked-port rejection.
All 228 belt-planner cases, 123 search cases, balancer/rail geometry checks and
preview lifecycle/rendering tests pass. These are correctness observations,
not a new timing benchmark. Evidence is retained in
`dist/irregular-gui-test-20261011/`.

## 2026-10-11: complete the mirrored station regression

The remaining south-facing mirrored station at `(65,65)` now connects all
13 mining belts. Its constrained inputs require routes on both sides of the
mine and a cyclic input assignment. After ordinary routing fails, stations
with interchangeable inputs can try westward searches from east-facing input
ports, allowing endpoint corners. The fallback tries at most eight cyclic
offsets with one shared 65,536-node budget per routing invocation. Ordinary
fixed input assignments retain their original mapping, and retries use a copy
of the input array. The literal balancer layouts are unchanged.

All eight direction/mirror combinations now produce ready previews. The
previously failing combination contains 3,934 entities; the other seven
retain their previous entity counts. A native run applies and undoes every
combination, verifying names, positions, effective facing, quality, underground
types, splitter priorities and filters. Every case has zero missing or extra
entities and zero ghosts after Undo. The graphical client also reaches the
3,934-entity result after repeated H-key changes and successfully applies it.

Rolling-stock ghosts store their facing in `orientation`; their `direction`
can stay zero. The corrected test comparator uses orientation for locomotives
and wagons. Comparing direction alone had reported six false differences in
the graphical test even though the applied train orientations were correct.

Standalone coverage is now 241 belt-planner cases. The added cases check cyclic
assignment in four world rotations, one-to-one use of every input, obstacle and
blocked-port rejection, preservation of fixed assignments and caller arrays,
and deterministic replanning. The 123 search cases and existing balancer,
station, preview lifecycle and renderer suites also pass. Reports and the
native workflow harness are in `dist/irregular-gui-test-20261011/mirror-fix/`.

## 2026-10-11: reuse spatial data during routing retries

The baseline includes both irregular-mine routing fixes and is archived in
`dist/performance-round6-20261011/baseline-package/`. This round preserves search
order, costs, budgets, corridor selection and literal balancer geometry.

- Integer cell IDs replace repeatedly concatenated coordinate strings in
  occupancy, reservation, congestion and placement maps. Row tables assign the
  IDs without assuming a fixed coordinate range.
- Each synchronous routing call shares its immutable geometry, grid occupancy
  and placement answers between retries. Geometry receives the first contiguous
  IDs, so later attempts rebuild its occupancy from a count instead of converting
  every bounding box again. Lane occupancy and reservations remain independent
  for each attempt; A* passability and congestion caches remain per search.
- Reserved or occupied cells fail before querying the mining grid. Newly
  visited cells outside an earlier search rectangle still trigger the larger
  engine obstacle scan. The shared context expires when that routing call
  returns, including failed calls, and is never stored in a preview or save.

The benchmark adds `--scenario irregular`: exactly 4,508 generated ore entities
in the same concave 96x76 shape, four station directions and both mirror states.
The ordinary ten output scenarios also run to detect regressions. The table
shows medians of three timing-only runs per version and scenario, with alternating
baseline/current order and no concurrent test jobs. All runs use the same copied
input-save digest. Times measure script work, not end-to-end UI latency.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| Irregular north | 337.30 | 285.68 | 95.14 | 95.06 |
| Irregular east | 926.48 | 815.91 | 671.58 | 560.20 |
| Irregular south | 278.37 | 300.55 | 143.73 | 128.50 |
| Irregular west | 982.48 | 865.95 | 700.07 | 581.04 |
| Irregular north, mirrored | 368.12 | 344.68 | 157.77 | 128.97 |
| Irregular east, mirrored | 1499.38 | 1324.45 | 1223.15 | 1089.27 |
| Irregular south, mirrored | 1739.23 | 1504.02 | 1507.88 | 1306.26 |
| Irregular west, mirrored | 761.74 | 701.50 | 515.47 | 424.42 |
| belts-near | 17.62 | 16.43 | 5.07 | 4.92 |
| belts-moved | 17.24 | 15.85 | 5.43 | 4.98 |
| balance-3-8 | 21.41 | 20.74 | 6.87 | 6.00 |
| station-3-8 | 105.70 | 95.55 | 51.64 | 31.12 |
| station-mirrored | 74.15 | 71.12 | 27.50 | 37.36 |
| station-3-10 | 59.59 | 55.95 | 24.58 | 27.77 |
| station-far | 91.22 | 88.97 | 36.02 | 31.90 |
| station-over-mine | 59.07 | 57.12 | 21.71 | 24.05 |
| belts-water-wall | 215.72 | 186.73 | 172.62 | 145.37 |
| blocked-output | 41.26 | 33.61 | 15.39 | 12.76 |

The slowest irregular mirrored case reduces total work by 13.5% and peak script
time by 13.4%; its routing phase falls from 1506.07 to 1304.49 ms. The water-wall
case reduces total/peak time by 13.4%/15.8%. Several small-station peaks and the
irregular south total increase in these samples. Search remains synchronous,
and the slowest measured median peak is still about 1.3 seconds.

Eight separate correctness runs compare ordinary outputs, irregular outputs,
movement and Apply. All 24 layout pairs and 23 sprite-definition/order pairs
match, along with readiness, entity counts and pipeline ticks. Timing runs add
108 matching ready/entity/tick observations. Runtime digests match across modes
for each version. All standalone Lua suites pass, including 242 belt-planner
cases, 123 search cases and a regression that forces search-area expansion into
previously unscanned water while ensuring grid queries are not repeated.
The full native eight-orientation workflow also passes preview/application
parity, effective train facing, splitter settings and complete Undo cleanup.

Reports, individual samples and runner scripts are retained in
`dist/performance-round6-20261011/comparison-final.json` and its directory.
Use the normal benchmark arguments with `--scenario irregular --timing-only`
to repeat the large irregular-mine measurements; omit `--timing-only` for
layout and rendering snapshots.

## 2026-10-11: prioritize bounded station ingress

Baseline: published `v1.9.8`. A search-node profile of the irregular south-facing
mirrored station finds that congestion negotiation exhausts all 262,144 nodes
before a cyclic input assignment succeeds in 23,729 nodes. Including the two
ordinary attempts, that request expands 288,850 nodes. The successful bounded
assignment was already available, but ran after the more expensive fallback.

After the ordinary forward/reverse attempts, interchangeable east-facing input
ports now try the existing bounded reverse search before congestion negotiation.
It retains the shared 65,536-node budget and at most eight cyclic offsets.
Negotiation still runs when no bounded assignment succeeds. Fixed input mappings,
ordinary contour routing, the search heuristic, tie ordering, budgets, and literal
balancer blueprints are unchanged. The measured difficult request avoids the
262,144-node unsuccessful negotiation, leaving 26,706 expanded nodes.

Three timing-only runs per version and scenario were alternated, using the same
copied input save and no concurrent benchmark jobs. These are medians of script
work and peak script-update time, not end-to-end GUI latency. The full final
comparison is retained in `dist/performance-round7-20261011/final/comparison.json`.

| Scenario | Before total ms | After total ms | Before peak tick ms | After peak tick ms |
| --- | ---: | ---: | ---: | ---: |
| irregular-0 | 325.34 | 349.98 | 136.00 | 156.33 |
| irregular-4 | 854.63 | 877.30 | 605.65 | 568.51 |
| irregular-8 | 312.91 | 271.04 | 136.91 | 79.12 |
| irregular-12 | 916.50 | 915.30 | 617.60 | 636.39 |
| irregular-0-mirrored | 375.55 | 369.96 | 151.85 | 123.80 |
| irregular-4-mirrored | 1409.10 | 1373.22 | 1126.45 | 1086.56 |
| irregular-8-mirrored | 1560.19 | 356.66 | 1359.51 | 137.83 |
| irregular-12-mirrored | 692.10 | 744.95 | 457.79 | 448.41 |
| belts-near | 16.73 | 17.52 | 5.22 | 5.41 |
| belts-moved | 16.63 | 17.29 | 5.01 | 5.36 |
| balance-3-8 | 17.21 | 17.79 | 5.44 | 5.25 |
| station-3-8 | 78.74 | 83.56 | 21.03 | 22.09 |
| station-mirrored | 75.16 | 75.72 | 35.49 | 33.38 |
| station-3-10 | 59.22 | 61.29 | 17.81 | 23.77 |
| station-far | 92.94 | 96.17 | 35.46 | 37.12 |
| station-over-mine | 59.68 | 61.76 | 30.86 | 27.07 |
| belts-water-wall | 189.30 | 190.82 | 146.10 | 145.27 |
| blocked-output | 31.86 | 31.70 | 12.97 | 12.99 |

The irregular south-facing mirrored case improves from 1560.19 to 356.66 ms
in total script work (77.1%), and from 1359.51 to 137.83 ms in peak tick time
(89.9%). Its routing phase falls from 1357.73 to 136.15 ms (90.0%). Other cases
do not show a uniform improvement: the branch does not affect most ordinary
routes, and rendering/allocation timing varies between runs. The other heavy
mirrored direction still takes about 1.09 seconds in a synchronous routing tick;
this change does not eliminate that remaining bottleneck.

A candidate also prechecked pending station inlets after each completed lane.
Profiling showed no reduction in expanded nodes for these cases, while extracting
its shared passability helper added overhead to ordinary searches. That candidate
was discarded; the final runtime change only reorders the station fallback.

Ten separate correctness runs cover ordinary outputs, all eight irregular station
poses, three beacon-contour outlets, repeated movement/rotation/mirroring, and
Apply. All 27 geometry pairs and 26 sprite-definition/order pairs match `v1.9.8`,
including readiness, entity counts and pipeline ticks. The new `--scenario contour`
uses the 4,508-tile irregular patch, big drills, full beacon rows and top/middle/
bottom same-facing outlets. It preserves the footprint and pole-pruning behavior.
All timing runs also retain the same readiness, entity counts and ticks, and all
runs share one input-save digest and one runtime digest per version.

All standalone Lua suites pass, including 274 belt-planner cases and 123 search
cases. New checks cover endpoint-corner fallback in four rotations when no
alternate port exists and ensure a usable bounded assignment avoids weighted
negotiation. A native eight-pose station workflow verifies construction against
the preview (including train orientation, quality and splitter settings), with
zero missing/extra entities and no ghosts left after Undo.

Reproduce the timing runs with the normal benchmark arguments and
`--scenario irregular --timing-only`, using `--ref v1.9.8` for the baseline.
Use `--scenario contour` without `--timing-only` to capture beacon-contour layouts.

## 2026-10-13: reuse mining geometry when moving outputs

Baseline: published `v1.10.0`. The new `load` scenario uses the same 4,508-tile
irregular mine, legendary big drills, beacon rows, production modules, a load
range of 0.8–1.1 and eight balanced outputs. Profiling now covers every mining
layout, including internal capacity rows. Each output click previously repeated
three grid builds, 41 layout-attempt callbacks and 30 convolution callbacks.
These unchanged mining steps accounted for most of the 137-tick wait.

Output-only requests now retain the mining entities, collection ports and a
sparse routing occupancy map. They check the mining inputs and world state,
then recompute the output route and render on successive ticks. Cached data is
plain persistent data, so it survives save/load and multiplayer joins. It never
stores the transient routing-grid function or a completed output route.

The cache is discarded for mining settings or output-count changes, resource
removal/movement/amount changes, mining productivity, belt-stack research, surface
effects, force changes, nearby entities or hazard tiles. Changing the ordinary
output direction also checks whether it changes trimmed collection-belt tails.
Blueprint layouts, non-row beacon planning and full layouts containing landfill
retain the full planning path. Output obstacles and landfill are checked afresh
on every route; Apply still performs its existing complete validation.

The table contains medians of three native timing-only runs per version. The
baseline samples came from the alternating before/after series; the final
conservative landfill guard was then measured in three separate runs. All runs
used the same save digest with no concurrent benchmark jobs. Total and peak
measure script CPU work; game ticks measure scheduling, not observed wall-clock
latency. At 60 UPS, 137 ticks span 2.28 seconds and 9 ticks span 0.15 seconds,
before accounting for slow frames.

| Output action | Before total ms | After total ms | Before peak tick ms | After peak tick ms | Ticks before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| load-initial | 460.58 | 56.60 | 135.24 | 33.89 | 137 → 9 |
| load-moved | 407.71 | 164.59 | 46.99 | 102.68 | 137 → 9 |
| load-rotated | 498.36 | 142.96 | 85.53 | 109.06 | 137 → 9 |
| load-moved-again | 371.45 | 59.19 | 41.76 | 35.62 | 137 → 9 |

Total script work falls by 59.6–87.7%, and the pipeline uses 93.4% fewer ticks.
The change does not uniformly improve the longest frame: the measured second
move and rotation still reach about 103–109 ms. Rendering, allocation and routing
remain synchronous within their respective steps.

Correctness comparisons cover 21 output states: the four new load cases, ten
ordinary/balanced/station/blocked cases, four station movements and three compact
beacon-contour outputs. Entity geometry, sprite definitions/order, readiness and
entity counts match the baseline. The existing 28 native capacity cases pass.
A separate two-process localhost test saves and reloads a real cached preview,
checks five mining-input invalidations against forced full replans, and verifies
preview/Apply parity plus complete Undo. Standalone tests cover cache ownership,
failure diagnostics, depleted/moved resources, research, terrain and tail trimming.

Reproduce the timing and snapshot checks using `scripts/benchmark-output.py`
with `--scenario load`, `--ref v1.10.0` for the baseline, and optionally
`--timing-only`. The native persistence test is:

```sh
python3 scripts/test-preview-output-cache.py --factorio /path/to/factorio \
  --data /path/to/factorio/data --save /path/to/fixture.zip \
  --output dist/output-cache-checks
```

The persistence test copies each input save into a separate directory and starts
only private localhost test servers on allocated ports. Reports and paired
measurements are in `dist/performance-output-cache-20261013/`.

## 2026-10-13: reduce allocation during repeated previews

This round starts from the unpublished output-cache optimization above, not
from released `v1.10.0`. Its runtime is archived in
`dist/performance-preview-round2-20261013/baseline-package/`; `baseline.json`
records the original package and runtime-file digests.

- Store the ore snapshot in parallel arrays instead of allocating a record for
  each resource. Read each native ore position once per validation. Compare
  current options directly against the saved options instead of copying them
  again. Older cache records safely trigger a full replan.
- Skip output-cache setup for layouts without belt outputs, including logistics
  beacon rows.
- Index preview connectivity by numeric rows and columns. Share immutable
  direction/type records within the ephemeral topology, retaining live world
  connections and avoiding per-neighbor coordinate-string construction.
- Calculate each displayed entity collision box once per render and reuse it
  for the obstacle check. Reuse normalized positions for native placement probes
  and sprite targets. Known blocked diagnostics retain their red tint without
  redundant native placement probes. Live checks remain enabled for other entities.

The new `load-repeat` scenario performs 24 successive output placements on the
same 4,508-tile mine, with every sixth placement rotated. Three timing-only runs
per version alternate order, share one save digest, and run without concurrent
benchmark jobs. The following values compare this round with the preceding
cache implementation. Cumulative values and peaks are medians across the three
runs; per-move values are medians across all 72 measured requests per version.

| Measurement | Previous cache | This round | Reduction |
| --- | ---: | ---: | ---: |
| Total script work, 24 moves | 2222.78 ms | 1885.46 ms | 15.2% |
| Rendering work, 24 moves | 1021.17 ms | 660.50 ms | 35.3% |
| Largest script-update pause per run | 149.46 ms | 116.87 ms | 21.8% |
| Typical output request | 84.43 ms | 65.32 ms | 22.6% |
| Typical render | 33.38 ms | 25.27 ms | 24.3% |

The scheduling delay remains 9 game ticks. These measurements describe script
CPU work, not wall-clock click latency. Some individual moves are slower, and
allocation/collection and synchronous routing still cause occasional pauses
around 0.1 seconds. The aggregate improvement holds across the three runs.

All standalone tests pass, including 122 renderer checks and 60 output-cache
checks. Native comparisons cover 41 previews: ordinary and blocked outputs,
station movement/rotation/mirroring, compact beacon contours, and all 24 repeated
load-controlled placements. Geometry, sprite definitions, draw order, readiness
and entity counts match the previous cache implementation. The separate native
save/reload test also passes invalidation, forced-full-plan parity, Apply and Undo.

To compare an unpublished baseline, first keep its installable archive and pass
`--package /path/to/baseline.zip` to `scripts/benchmark-output.py`. Use
`--scenario load-repeat --timing-only` for repeated-placement timing; omit
`--timing-only` to record geometry and sprite-order snapshots. `--package` and
`--ref` are mutually exclusive. Detailed samples are retained under
`dist/performance-preview-round2-20261013/repeat-timing/`, with native comparisons
in `correctness/` and persistence results in `native/`.


## 2026-10-28: output-click latency and perpendicular routing

Baseline: the working-tree package installed after the compact capacity-row and
power-coverage checks, including all earlier uncommitted GUI/terrain changes.
SHA-256: `fd6ab57629cca44d0f07c7be3288def1002f46ab21fff1a3e00479c86145443d`.
This comparison isolates the subsequent output-click optimizations.

The fixture has 4508 ore tiles, legendary big mining drills, beacons, an eight-belt
output budget and 24 output moves/rotations. `load-repeat` keeps the mine in preview;
`load-output-only` first applies the mine, then moves its independent output preview.
All cases report ready. Measurements use the same harness and source save in isolated
Factorio processes; the original save is not changed.

| Scenario | Before request-to-ready ticks | After ticks | Before script time | After script time |
| --- | ---: | ---: | ---: | ---: |
| Mine preview, all 24 placements | 9 | 2 | 71.42 ms | 59.37 ms |
| Mine preview, perpendicular middle-band cases | 9 | 2 | 125.86 ms | 68.09 ms |
| Applied mine, all 24 independent output previews | 8 | 1 | 56.05 ms | 36.90 ms |
| Applied mine, perpendicular middle-band cases | 8 | 1 | 121.29 ms | 38.72 ms |

Mine-preview timings are medians of the per-run means over three alternating
before/after rounds. Applied-mine timings are from one before/after pair. The primary
24-case run means were before 69.47, 73.84, 71.42
ms and after 63.28, 59.37, 58.50 ms.
Script time is accumulated LuaProfiler work, not wall-clock click latency.
At 60 UPS, removing seven idle scheduling ticks removes about 117 ms of fixed wait;
slow frames or reduced UPS still add latency. The next-tick route and subsequent
render are kept on separate ticks for the cached mine preview.

Changes:

- Discrete output clicks refresh next tick. Rapid configuration edits retain their
  eight-tick debounce, and duplicate held clicks still do not cancel/restart work.
- Perpendicular output bands use verified direct bends or nested U corridors,
  including bands cutting through the source rows. Each proposed cell is checked
  against planned entities, earlier lanes, selected obstacles and balancer geometry.
  A blocked candidate falls back to the existing search.
- Empty-ground route probes use the obstacle index before asking the engine for
  an existing reusable belt. Overlapping belts still require direction/quality matching.

For the first rotated case, placement probes decreased from 4830 to 1632, and
shared-entity checks from 5646 to 816. Its entity count stayed at 2091 for the full
preview and 816 for the independent output preview. The 20 unrotated cases in each
workflow retain identical entity geometry, sprite content and sprite order.
The four rotated cases use the new corridors and retain the same entity count.

Validation:

- 328 belt routing/preview cases, including 28 new four-direction corridor,
  search-size and obstruction-fallback regressions.
- 123 search oracle/budget checks; 205 obstacle checks, including empty-ground
  query avoidance and native existing-belt direction/quality reuse.
- 14054 balancer flow/pairing checks; preview lifecycle/cache/renderer, terrain,
  ore filtering, locales and whitespace checks pass.
- Native save/reload, five cache invalidations, cached/full-plan parity, Apply and Undo pass.
- Native placement, existing facilities, robot demolition, copper wiring,
  output-only workflow and station/rail checks pass.

Evidence: `dist/output-latency-20261028/final-results.json`, `summary.json`,
`final/`, `native-cache/` and `native-placement/`.

Reproduce with `scripts/benchmark-output.py --scenario load-repeat` and
`--scenario load-output-only`, supplying the Factorio binary, data and save paths
as above. Add `--package /path/to/baseline.zip` for the baseline.

## 2026-10-29: dense mine output terrain and duplicate validation

Baseline: the locally installed, unpublished dual-sided big-drill runtime,
archived at `dist/performance-dense-20261029/baseline.zip` (archive SHA-256
`45e6b8d2fe407f7c8550077d0638b9527af7e21066461f484b04a68b6ccfdcd7`).
Comparing with HEAD would also include earlier GUI, density and throughput work,
so this round compares the packaged runtimes directly.

The new `dense-repeat` fixture uses 17,965 irregularly distributed ore tiles,
527 normal big drills in the first output snapshot, normal speed-module-3 modules,
blue belts, four-item stacks, productivity bonus 4, poles and lamps, no beacons,
and 24 final outputs. It measures 24 moves, rotating every sixth output, with
roughly 18,000 entities and 30,000 sprite layers per preview. Natural entities and decoratives are disabled, and the fixture is covered with
grass before adding ore. All runs use an
isolated copy of the same source save.

Changes:

- Find hazardous tiles through one engine-filtered query over the route bounds.
  Dry corridors stop there instead of reading every ground tile through Lua.
  Mixed terrain is looked up by numeric tile coordinates while retaining the
  original per-spec footprint order, cover selection and deduplication. Space
  scaffolds and modded coverable tiles use the same terrain rules. Gaps between
  routes are not filled. Tile data is queried afresh for each call.
- When a successful output plan is immediately converted into preview specs,
  reuse its selected-obstacle validation in that synchronous tick. The builder
  still identifies shared belts/rails and honors explicit native placement
  probes. Failed diagnostics, later ticks and actual construction validate as
  before; the renderer retains its live placement checks. Both cached mine
  previews and independent outputs use this path.

Three sequential baseline/optimized pairs use `--timing-only`, with no other
benchmark running concurrently. Each table entry is the median of three per-run
measurements. Phase means overlap and must not be added together.

| Measurement | Baseline | Optimized | Reduction |
| --- | ---: | ---: | ---: |
| Mean script work per output request | 777.25 ms | 626.33 ms | 19.4% |
| Mean output-cache refresh work | 498.58 ms | 329.70 ms | 33.9% |
| Mean output landfill scan | 140.96 ms | 44.84 ms | 68.2% |
| Largest script-update pause per run | 763.19 ms | 603.39 ms | 20.9% |
| Selected-obstacle probes across 24 requests | 719,968 | 359,984 | 50.0% |

Per-run mean request times were 827.12 / 767.68 / 777.25 ms before and
623.41 / 626.33 / 668.63 ms after. Scheduling remains two game ticks. These are
instrumented LuaProfiler work measurements, not stopwatch click-to-screen
latency. Rendering remains about 255 ms per request in this fixture. Routing,
rendering and garbage collection can still cause visible stalls, particularly
when rotating such a large output; this change does not make every placement
instantaneous.

Reproduce with `scripts/benchmark-output.py --scenario dense-repeat --timing-only`,
passing `--package dist/performance-dense-20261029/baseline.zip` for the baseline.
Omit `--timing-only` for entity, sprite and drawing-order comparisons. The `fill`
scenario additionally exercises water, lava and oil-ocean output construction.
Raw timings, snapshot comparisons and native tests are retained under
`dist/performance-dense-20261029/`; `summary.json` records each run and digest.

Validation completed on the final packaged runtime:

- 63 native snapshot states match the baseline: 24 dense mine moves, 10 ordinary /
  balanced / station / blocked outputs, three hazardous-terrain fills, 24
  independent outputs on an applied mine, and the station preview/Apply pair.
  Entity geometry, readiness and counts match; sprite content and order also
  match wherever a preview is present. Fill cases retain native tile ghosts.
- Native save/reload, five cache invalidations, cached/full-plan parity, Apply
  and Undo pass. The placement suite also passes force modes, robot demolition,
  existing belts/rails, copper wiring and station/output-only workflows.
- Standalone routing/preview tests pass 342 cases, including 14 added regressions
  for dry scanning, mixed/rotated footprints, dynamic terrain, diagnostics,
  shared belts, next-tick changes, native checks and real construction. Search,
  balancer flow, obstacle, cache, renderer, lifecycle, terrain, train, rail,
  capacity and throughput suites pass; 81 Lua files pass syntax compilation.
- The installed test archive's 143 runtime files match the working tree and the
  runtime digest measured in all three optimized timing runs. The previous
  archive is backed up under `before-optimization/`. The source save digest is
  unchanged. Installation details are in `installation.json`.
