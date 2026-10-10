# Balancer Blueprint Sources

`balancer_matrix.lua` is an explicit 8-by-8 lookup of fixed construction
blueprints. Its primary source is the user's exported `1-128` balancer book,
received on 2026-10-10. The original export's SHA-256 (without trailing newline)
is `3132efb1470623bf30e2088a4c4a89714598acc657e29952a8a7383e30bd377f`.
The unchanged 72 blueprints with 1..8 inputs and outputs are retained in
`tests/fixtures/balancers/user-1-8.txt`. They cover 62 count pairs; the omitted
1-to-2 and 2-to-1 pairs are literal single-splitter templates in the importer.

The matrix uses only the exact input/output cell. Variants from the supplied
book are ordered by footprint, then entity count. The importer rotates the
northbound book to the planner's southbound coordinates and translates it;
it preserves every entity, underground endpoint, splitter priority and filter.
Runtime adds one output belt per channel to expose the connection interface. It does
not add balancing stages or use a blueprint with surplus inputs. For example,
2-to-8 uses `2_8_balancer` (21 source entities, including 7 splitters), and
1-to-1 and 2-to-2 retain the source lane-balancing structures.

Exact-count tier alternatives and the larger layouts in
`balancer_blueprints.lua` come from Raynquist's balancer designs, collected and
updated by Dogmai in the August 2024 balancer book.

- Collection: https://github.com/dogmaisea/factorio-balancers
- Source file: `blueprint-book-balancers-2024-august.txt`
- Source revision: `e48a9d7628b2a80306890a4b359b1cd7629e46b4`

The seven original compatibility blueprints are retained in
`tests/fixtures/balancers/tier-compatibility.txt`: `5_6_yellow`, `5_7_yellow`,
`6_6_alt_yellow`, `7_8_alt_yellow`, `8_5_alt_yellow`, `8_8`,
and `8_7_alt_yellow`. Despite its name, `8_7_alt_yellow` has a six-tile
underground span and requires red belts. The primary book always takes
precedence when the selected belt tier supports its underground spans.

Blue and red belts support all 64 pairs. Yellow supports 60: 5-to-8, 6-to-5,
7-to-5 and 8-to-7 have no verified compatible exact-count blueprint in these
sources. Those four combinations return the existing higher-tier equipment message rather
than silently using additional inputs. Belt entity names change to the chosen
tier only when its underground reach is sufficient. Factorio 1.1 source
directions are converted to Factorio 2.x values by the importer.

The legacy `5_8_yellow` is excluded after native flow testing: with five equal
inputs, its eight outputs settled at approximately 896, 896, 1152, 1152, 1152,
1151, 896 and 897 items during an 8192-tick measurement. It cannot provide equal
outputs. The user's `5_8_balancer` is retained for red/blue belts.

For larger loading stations, even output counts without a matching reference
can extend a smaller matrix with equal two-way branches. For example, 3-to-10
uses the 3-to-5 reference followed by five 1-to-2 splits. Other counts without a
direct template use a standard square reference with merging or feedback.

Regenerate the fixed matrix from the checked-in sources with:

```sh
python3 scripts/import-balancer-matrix.py
python3 tests/balancer-import.py
```

Run the native Factorio test (isolated temporary mod directory, read-only input
save; does not affect a running game or server) with:

```sh
python3 scripts/test-balancer-matrix.py --factorio /path/to/factorio --save /path/to/save.zip
```

It checks physical placement and underground connections, actual mining-output
counts, and steady output equality/flow rate while feeding all inputs together
and each input lane separately. It also round-trips splitter filters through
preview, construction ghosts, revival and rotated/mirrored station cursor
blueprints. Compact source templates retain their original throughput limits;
this test does not assert throughput-unlimited behavior. The whole-belt graph test in
`tests/output-balancer.lua` additionally checks template fidelity and larger
adapters; lane-specific circuits are covered by the native test.

Regenerate the legacy larger-layout collection with:

```sh
python3 scripts/import-balancer-blueprints.py --book /path/to/blueprint-book-balancers-2024-august.txt
```
