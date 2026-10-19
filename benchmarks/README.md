# Native workloads and gallery

Run from the repository root. Benchmarks use only Canopy and Nim's standard
library; no Rust executable, network, or terminal interaction is needed.

```sh
nim c -d:release --mm:arc --path:src --out:/tmp/canopy-bench-arc benchmarks/benchmarks.nim
/tmp/canopy-bench-arc 1
nim c -d:release --mm:orc --path:src --out:/tmp/canopy-bench-orc benchmarks/benchmarks.nim
/tmp/canopy-bench-orc 1
```

The optional positional argument (1–100, default 1) multiplies every iteration
count. Each run reports its actual memory manager, Nim version, platform, seed,
elapsed wall-clock milliseconds, microseconds per iteration, and checksum.
Deterministic data uses an explicit 32-bit LCG seeded with 302. Dataset creation
is outside the timed sections. Rendering workloads include buffer reset.

Workloads:

- Layout: the same eight mixed constraints, nonzero origin, spacing, and Start
  flex. The uncached workload disables the layout cache. The cached workload
  restores the default capacity and populates the entry before measurement.
- Paragraph: wrap 1,500 mixed ASCII/Unicode words into 100×40, varying scroll
  position over 20 offsets.
- Table: 10,000 rows × 6 columns, rendered into a 160×50 viewport; selection
  advances through the data. This measures viewport rendering and selection
  bookkeeping, not displaying all 10,000 rows simultaneously.
- Buffer diff: 240×80 cells, 5% with changed symbols/colors; each iteration
  constructs and counts the resulting update sequence.

Single local samples on 2026-09-05: Apple M4, arm64, 16 GiB RAM, macOS 27.0
(26A5421a), Nim 2.2.10 (`bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef`), release C
backend, scale 1. Builds used separate ARC/ORC outputs. These are uncontrolled
workstation measurements with no statistical or cross-library performance
claim.

| Workload | Iterations | ARC elapsed ms | ORC elapsed ms |
|---|---:|---:|---:|
| Layout uncached | 1,000 | 776.796 | 777.826 |
| Layout cached | 100,000 | 49.967 | 52.623 |
| Paragraph wrap | 100 | 404.613 | 454.254 |
| Table render | 200 | 212.639 | 230.796 |
| Buffer diff | 1,000 | 2,991.064 | 3,106.164 |

Both runs produced `checksum=90160057`. ARC validation explicitly skipped
parent/project Nim configuration files, then selected `--mm:arc`; this caught
and led to removal of an earlier configuration that forced ORC. Current project
configuration respects the memory-manager command-line option.

The noninteractive gallery renders through `Terminal[TestBackend]` and prints
the resulting 120×47 screen as plain text:

```sh
nim c -r --mm:arc --path:src examples/gallery.nim
nim c -r --mm:orc --path:src examples/gallery.nim
```

It demonstrates Block, Clear, Fill, Paragraph, List, Table, Tabs, Gauge,
LineGauge, Sparkline, Scrollbar, BarChart, Monthly, Canvas, Chart, RatatuiLogo,
and RatatuiMascot. Calendar date and all data are fixed. Colors remain in the
TestBackend buffer; plain output shows symbols only. Wide-character
continuations are omitted when printing. The ARC and ORC runs produced
identical 47-line, 10,186-byte UTF-8 output.
## Animation workloads

`nimble bench` also runs `animation_benchmarks.nim`: 1,000 active tweens and
80×24 Unicode fade/slide/wipe/dissolve regions. Separate ARC/ORC measurements,
checksums and timing boundaries are in [animation validation](../docs/validation/animation.md).
