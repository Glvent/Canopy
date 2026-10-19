# Ratatui reference fixtures

`tests/fixtures/*.json` records behavior from Ratatui 0.30.2. Ordinary Canopy builds and tests read these files with Nim only. Rust is a development tool for regenerating or independently verifying them.

## Reproduce

From the repository root:

```sh
cargo run --manifest-path tools/reference/Cargo.toml --locked -- generate
nim c -r --path:src tests/test_reference.nim
nim c -r --mm:arc --path:src -o:/tmp/canopy-test-reference-arc tests/test_reference.nim
```

`tools/reference/Cargo.lock` pins Ratatui 0.30.2, ratatui-core 0.1.2, ratatui-widgets 0.3.2, Kasuari 0.4.12, unicode-segmentation 1.13.3, and unicode-width 0.2.2. Both Unicode crates use Unicode 17.0.0 data. Do not run Cargo from the Nim suite.

Additional checked-in matrices have dedicated generators:

- `cargo run --manifest-path tools/reference/Cargo.toml --locked -- widgets-matrix`: 1,890 Gauge/LineGauge/Tabs/BarChart/Sparkline/Scrollbar/Monthly/Logo/Mascot configurations.
- [Paragraph/List/Table](../tools/widget_text/README.md): `python3 tools/widget_text/generate.py` after the locked reference build.
- [Block, shadows, symbols](../tools/block/README.md): `python3 tools/block/generate.py` after the locked reference build; regenerating symbol catalogs also takes the tagged upstream source path.
- [Canvas/Chart](../tools/chart/README.md): `python3 tools/chart/fixture_gen.py`.
- [Palette conversions](../tools/colors/README.md): `python3 tools/colors/generate.py`.
- [Terminal actions](../tools/terminal/README.md): dedicated scrolling-regions oracle and adapter.
- Calendar dimensions: `python3 tools/calendar/generate.py` verifies 384 literal width/height cases against the locked Rust build, including titles, headers, borders and saturated padding.
- [Layout differential checks](../tools/layout/README.md) and [Unicode data](../licenses/unicode/LICENSE-UNICODE) have separate pinned source/test assets.

These development generators use Rust (and Python for the helper scripts). `nimble test` reads their saved results with Nim only. The base and extended matrices use explicit adapters; schema details for each extended corpus are in its validation document. `nim r tools/update_notices.nim` refreshes the license bundle shipped with Nimble installations.

## Schema version 1

Each fixture file is one object:

```json
{
  "schemaVersion": 1,
  "generatedBy": { "crate": "canopy-ratatui-reference", "version": "0.1.0", "command": "..." },
  "dependencies": { "ratatui": "0.30.2", "unicodeVersion": "17.0.0" },
  "cases": [
    { "name": "unique-name", "kind": "layout", "input": {}, "expected": {} }
  ]
}
```

`kind` is `geometry`, `style`, `text`, `unicode`, `buffer`, `diff`, `layout`, or `widget`. Inputs use only explicit JSON values; adapter tests reconstruct Canopy values rather than sharing runtime JSON serialization.

A rectangle is `{x,y,width,height}`. Layout output has `segments` and `spacers` arrays. Unicode output has `graphemes` and `width`. Stateful widget output adds its final state.

Every rendered buffer is:

```json
{
  "area": { "x": 2, "y": 3, "width": 8, "height": 2 },
  "cells": [
    {
      "symbol": " ",
      "fg": { "kind": "named", "name": "reset" },
      "bg": { "kind": "indexed", "index": 17 },
      "underlineColor": { "kind": "rgb", "r": 1, "g": 2, "b": 3 },
      "modifiers": ["bold", "underlined"],
      "skip": false,
      "diffOption": { "kind": "none" }
    }
  ],
  "cursor": null,
  "state": null
}
```

Cells are complete and row-major; their count is exactly `width * height`. Named colors use lower camel case. `diffOption.kind` is `none`, `skip`, `alwaysUpdate`, or `forcedWidth`; forced width adds `width`. Modifiers appear in enum order: `bold`, `dim`, `italic`, `underlined`, `slowBlink`, `rapidBlink`, `reversed`, `hidden`, `crossedOut`. Cursor is nullable. State is nullable for stateless rendering.

## Layout oracle

For differential tests, pipe a JSON array or JSON Lines requests to:

```sh
cargo run --quiet --manifest-path tools/reference/Cargo.toml --locked -- layout-oracle
```

Each request uses the same layout `input` shape and returns `{name,expected:{segments,spacers}}`. Degenerate Cassowary systems may have several equally valid solutions. Kasuari 0.4.12 stores rows in a randomly seeded hash table, so a fresh process can choose different tied pivots. Repeated fresh-process trials found multiple upstream outputs for five of seven sampled tied cases. Checked-in differential tests accept only the recorded independently observed alternatives; they do not accept arbitrary equivalent optima.

## Fixture provenance

The generator calls Ratatui public APIs and serializes the returned rectangles, text metrics, complete `Buffer::content`, `Buffer::diff`, and mutated widget state. It does not copy expected values from Canopy. Review changes to the generator and JSON together. Stable cases reproduce with a clean `--locked` run. Tied layouts are the explicit exception: preserve independently observed alternatives and provenance rather than replacing expected values with a native output.
