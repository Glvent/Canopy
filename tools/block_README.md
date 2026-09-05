# Block, shadow and symbols compatibility

Native implementation follows Ratatui 0.30.2 (`ratatui-core` 0.1.2,
`ratatui-widgets` 0.3.2). Attribution: `licenses/ratatui.txt`.

`block_generate_symbols.py` ports every public string/character constant and
symbol set from the upstream symbol modules, all 592 marker-array entries, and
125 box-drawing decompositions. It also generates independent adapters that
evaluate the corresponding constants in the pinned Rust library. Native names
prefix the module (`BorderPlain`, `BarNineLevels`, `ScrollbarVertical`);
`Braille`, `Quadrants`, `Sextants`, and `Octants` preserve upstream array names.
Existing shorter aliases remain available. `BorderType.Solid` is a native
convenience for the upstream `border::FULL` custom set.

Regenerate after building `reference/Cargo.toml` with its lockfile:

```sh
python3 tools/block_generate_symbols.py /path/to/ratatui-ratatui-v0.30.2
python3 tools/block_generate.py
nim c -r --path:src --mm:arc tests/test_symbols.nim
nim c -r --path:src --mm:arc tests/test_block.nim
```

Repeat native checks with `--mm:orc`. Fixture tests require no Rust toolchain.
`tests/fixtures/block_matrix.json` covers 53,067 merge combinations (all box
characters plus unknown, empty and multiple-character input, three strategies),
991 independently evaluated symbol values, 3,744 border configurations,
864 title configurations, and 336 shadow configurations. Borders vary every
type/mask/strategy, tiny dimensions, and unset/explicit-space/text/border cells.
Titles vary collision priority, positions, alignment and Unicode truncation.
Shadows vary all effects, offsets, clipped areas, named/RGB backgrounds and
style precedence. Padding constructors have native saturation checks.

`mergeSymbol(previous, next, strategy)` is exported through `canopy/core/rendering/symbols`.
Cell merging separately preserves upstream unset-symbol behavior through
`Cell.symbolSet`. Block renders titles left, center, then right: later groups
overwrite earlier groups when their areas collide.

`Shadow` offers `overlayShadow`, `blockShadow`, three shade constructors,
`symbolShadow`, `customShadow`, `withStyle`, and `withOffset`. A `CellEffect`
closure receives the clipped shadow area, base area and mutable buffer.
Custom objects can implement `apply(effect, shadowArea, baseArea, buffer)`;
`customShadow(dimmed())` sets Dim and halves RGB background channels (other
backgrounds become Black), matching upstream. Custom callbacks define their
own effects; the built-in Dimmed implementation is covered by the oracle.
