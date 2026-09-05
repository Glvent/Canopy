# Text-widget compatibility matrix

`widget_text_oracle.rs` runs the locked Ratatui 0.30.2 reference library and
captures 1,428 cases: 648 Paragraph, 360 List, 420 Table. The complete buffer
starts with `.` sentinel cells around a widget at nonzero origin `(2,1)`.
Expected output includes every symbol, foreground, background, underline color,
modifier bit, and resulting row/column/offset state.

Coverage combines zero/tiny/ordinary sizes, whitespace/NBSP/ZWSP, CJK,
combining marks, emoji, wrapping modes, alignment, scrolling, style layering,
multiline selection, padding, direction, highlight spacing, column spans,
header/footer margins, incorrect selection indexes, empty data, and all flex
modes. `tests/test_reference.nim` explicitly translates each configuration into
native Canopy objects and compares all output cells and state.

Regeneration requires development-only Rust:

```sh
cargo build --locked --manifest-path reference/Cargo.toml
python3 tools/widget_text_generate.py
```

Normal Nim tests read only `tests/fixtures/widget_text_matrix.json`.

The standalone fixture schema is version 1. Each case includes a `kind`, widget
configuration fields, `width`, `height`, and row-major `cells` for a full buffer
of `(width+4, height+2)`. A cell is `[symbol, fg, bg, underlineColor, modifiers]`;
colors use Rust's named `Color` spelling and modifiers use Ratatui's flag bits.
The matrix uses no indexed/RGB colors; those have separate foundation tests.
`state` is `[offset, selected]` for List and `[offset, selected, selectedColumn]`
for Table. Null means no selection. Untouched diff metadata remains default.

An upstream behavior is preserved deliberately: wrapping `é👩‍🔬x` at width two
emits a second pending-word line of width three. Ratatui writes its final `x`
into the cell immediately outside the widget rectangle. Six matrix cases prove
the behavior for both wrapping modes and all three alignments. Canopy preserves
these writes when they remain inside the actual Buffer; writes beyond Buffer
bounds are clipped safely.
