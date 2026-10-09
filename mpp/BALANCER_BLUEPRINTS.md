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

The 1-to-8 input/output matrix prefers matching counts and then the smallest
compatible reference footprint. The trivial one/two-way splits and 1-to-4
binary tree complete its small entries. In particular, 3-to-8 retains the
3-to-8 reference rather than leaving an input of a 4-to-8 reference unused.

For larger loading stations, even output counts without a matching reference
can extend a smaller matrix with equal two-way branches. For example, 3-to-10
uses the 3-to-5 reference followed by five 1-to-2 splits. Other counts without a
direct template use a standard square reference with merging or feedback.

Regenerate the normalized data with:

```sh
python3 scripts/import-balancer-blueprints.py --book /path/to/blueprint-book-balancers-2024-august.txt
```
