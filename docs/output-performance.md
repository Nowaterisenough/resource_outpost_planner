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
The save is read without overwriting it. Each run uses its own mod, configuration,
and data directories. Benchmark instrumentation is excluded from release packages.

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
a digest of the tested runtime files. A missing completion marker fails the run.

## Correctness checks

- All standalone Lua tests pass, including exact collision comparisons, hazard filters, cache invalidation, negative coordinates, fractional box edges, and placement snapping.
- The offset input-band regression limits placement probes on an open corridor to prevent a return to expansive search.
- Native station workflow, blocked red diagnostics, preview/application parity, applied-mine output, and Undo pass.
- 192 native cursor placements pass across rotations, mirrors, repeat placement, and restored rail snapping.
