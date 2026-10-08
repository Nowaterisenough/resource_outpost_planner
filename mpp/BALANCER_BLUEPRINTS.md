# Balancer Blueprint Sources

The normalized construction layouts in `balancer_blueprints.lua` come from
Raynquist's balancer designs, collected and updated by Dogmai in the August 2024
balancer book.

- Collection: https://github.com/dogmaisea/factorio-balancers
- Source file: `blueprint-book-balancers-2024-august.txt`
- Source revision: `e48a9d7628b2a80306890a4b359b1cd7629e46b4`

The data retains entity positions, underground entrance/exit types, directions
and splitter priorities. Positions are normalized around the output interface;
Factorio 1.1 direction values are converted to Factorio 2.1 values. Belt names
are substituted at planning time to match the chosen belt tier.

Directly matching layouts are preferred. Compatible larger input layouts may
leave unused inputs disconnected. Counts without a direct template use a
standard square reference layout with additional merging or feedback connections.

Regenerate the normalized data with:

```sh
python3 scripts/import-balancer-blueprints.py --book /path/to/blueprint-book-balancers-2024-august.txt
```
