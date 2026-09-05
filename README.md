# Canopy

Native Nim immediate-mode terminal UI library targeting Ratatui 0.30.2 logical-cell compatibility. **Development release: consult [parity status](docs/parity.md) before relying on stable parity.**

Requires Nim 2.2.0 or newer. Runtime and normal tests require Nim only. Rust is used solely to regenerate the pinned compatibility fixtures.

```sh
nimble install
nimble test
nimble examples
```

`import canopy` provides rendering, geometry, styles, text, buffers, widgets, terminal management and backends. Import `canopy/runtime/terminal/input` explicitly for input; applications own their event loop. Focused imports such as `canopy/core/layout/index` and `canopy/core/rendering/buffer` are supported.

Import `canopy/ui/animation/index` for the native [animation toolkit](docs/animation.md): typed tweens, easing, timelines, springs, buffer transitions and shared reduced motion. Run `nim r examples/animations.nim` for the interactive gallery.

See [the accepted plan](PLAN.md), [milestone checklist](docs/milestones.md), [shared interfaces](docs/interfaces.md), [reference generation](docs/reference.md), [upstream inventory](docs/upstream-inventory.md), and [validation record](docs/validation.md). API documentation: `nimble docs`.

Start with the [usage guide](docs/guide.md) and [Ratatui migration guide](docs/migration.md). Run `nim r examples/keyboard.nim` for an interactive screen, `nim r examples/dashboard.nim --snapshot` for a terminal-free dashboard, or `nim r examples/gallery.nim` for the widget gallery. `nimble bench` runs the recorded benchmark workloads.

Canopy is MIT licensed. Ported algorithms and data retain their upstream notices under `licenses/`; Nimble installations include `canopy/THIRD_PARTY_NOTICES.txt`.
