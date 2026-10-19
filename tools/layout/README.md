# Layout compatibility evidence

Target: Ratatui 0.30.2, ratatui-core 0.1.2, Kasuari 0.4.12.

`tests/test_layout.nim` runs without Rust or Python. It includes 391 literal
upstream layout cases and 2,000 seeded mixed layouts from the pinned reference.
Mixed cases cover all seven flex modes, all six constraint kinds, empty inputs,
u16 extremes, conflicting priorities, negative spacing, margins, zero/tiny areas,
nonzero origins, and two-stage rounding. Segment and spacer rectangles are exact.
Focused checks cover cache eviction/disabling/value isolation and fixed arrays.

Regeneration (development only):

```
python3 tools/layout/extract_tests.py PATH/ratatui-core-0.1.2/src/layout/layout.rs
python3 tools/layout/differential.py 2000
```

The differential generator uses seed 302, saves the dependency-lock SHA-256,
and retains the initial upstream output for every case. When native geometry
differs, it executes 50 additional fresh upstream processes and records every
distinct exact output and its sample count. Acceptance requires native geometry
to equal an observed upstream output. It does not replace mismatches with native
results, loosen rectangle comparison, or assume all feasible layouts equivalent.

Kasuari's hashbrown tables use `foldhash::fast::RandomState`; pivot tie order can
change between executions. Therefore, some conflicting constraints admit multiple
upstream geometries for identical input. `expectedAlternatives` records those
observed outputs. A single live Rust output is not a deterministic specification
for these cases. Canopy's insertion-ordered tableau chooses a deterministic
solution. No claim is made that every possible randomized upstream output has
been enumerated, or that every untested layout has a unique solution.

The checked-in run has 1,995 matches to the first upstream sample and five cases
with observed alternatives. Their 51-sample frequencies are: `mixed-361` 27/24,
`mixed-1008` 24/27, `mixed-1224` 16/16/19, `mixed-1451` 41/10, and `mixed-1791`
15/36. Native geometry matches one observed result in every case. Both ARC and
ORC passed all 2,000 mixed cases, all 391 literal cases, and focused checks;
the separate 18-case reference layout fixture also has zero mismatches.

Verification commands:

```
nim c -r --path:src --mm:arc tests/test_layout.nim
nim c -r --path:src --mm:orc tests/test_layout.nim
nim c -r --path:src tools/layout/compare.nim tests/fixtures/layout.json
nim c -r -d:release --path:src benchmarks/layout_benchmark.nim
```

Local Nim 2.2.10 release ORC benchmark: eight mixed constraints, 1,000 uncached
splits in 969.03 ms; 100,000 cached splits in 50.58 ms. These are observations,
not performance guarantees. Cache defaults to 500 thread-local entries; size zero
disables caching. LRU eviction scans current entries only on an uncached split.

The native solver implements required/weighted equalities and inequalities,
artificial-variable feasibility, and primal simplex optimization. Edit variables,
constraint removal, and dual optimization are omitted because Ratatui layout
never uses those operations. Upstream notices are under `licenses/kasuari*`.
