# Stable API audit

Audit baseline is Ratatui 0.30.2, core 0.1.2 and widgets 0.3.2. This document
covers foundation, layout, symbols and built-in widgets. Terminal, input and
platform acceptance remain in `docs/parity.md`. Implementation status and
specific fixture evidence are separated in [upstream-inventory.md](upstream-inventory.md).

## Findings resolved during integration

- `Line::raw` / string conversion split Rust `str::lines()` into concatenated
  spans. Native `initLine(string)` now does the same, including CRLF, a lone
  trailing CR and empty input. The initial single-span constructor differed in
  structural content, width and string conversion for embedded newlines.
- `Scrollbar.withSymbols` now accepts the public `symbols.ScrollbarSet`
  catalog, alongside the original `ScrollbarSymbols` convenience type.
  `orientation_and_symbol` maps to `withOrientation(...).withSymbols(...)`.
- Stable packed RGB and optional palette color conversions are implemented as
  `colorFromU32`, `colorFromHsl`, and `colorFromHsluv` in `canopy/core/styling/colors`, with
  native algorithms and a pinned palette-enabled oracle. They were absent from
  the original inventory and are included in the stable target.

`test_public_api` checks newline construction and symbol-set integration.
`test_colors` compares five packed colors and 31,347 independent palette
conversions. Terminal `applyBuffer`/`applyBufferWithCursor` and calendar metrics
were also corrected during final audit; terminal transaction/oracle tests and
384 independent upstream metric cases cover them. No known implementation
finding remains open; Windows execution remains a release acceptance gate.

## Native equivalents, not missing operations

- Rust borrowed/owned conversions and iterator constructors map to Nim value
  constructors, sequences, and `items`/`mitems`. Public `content`, `spans`,
  `lines`, configuration and state fields provide getter/setter access.
  `ListState.selected` and `TableState.selected/selectedColumn/offset` map to
  Rust accessor and mutable-accessor pairs; selection methods preserve the
  upstream offset-reset behavior.
- `Span::styled`, `Line::styled`, and `Text::styled` map to constructors plus
  `withStyle`. `ToSpan`/`ToLine`/`ToText` map to the corresponding constructors;
  `initText([line])` explicitly converts a Line. Repeated append and public
  sequence mutation cover Rust `Extend`/`AddAssign` traits.
- `Cell::EMPTY` / default map to `initCell()`. `CellDiffOption::None` is
  `CellDiffKind.Normal`. `setSymbol` accepts a Unicode scalar string as well
  as a grapheme; Nim `char` is a byte, so Rust `set_char` with non-ASCII input
  maps to `setSymbol`. Mutable indexing after `area.contains` provides the
  safe native equivalent of Rust's optional mutable cell reference.
- `Buffer::filled` is `initBuffer(area, cell)`. `diff` returns native updates;
  iteration over those updates covers `diff_iter` without borrowing lifetimes.
- `Spacing::Space/Overlap` maps to positive/negative `Layout.spacing`.
  Fixed arrays use `areas[N]` / `layout[N]`; optional length validation uses
  `tryAreas[N]` / `tryLayout[N]`. Required internal solver operations are
  implemented; edit variables/removal are not public Ratatui Layout APIs.
- Symbol names prefix their module, for example `BorderPlain` and
  `ScrollbarVertical`. Marker enum payloads become `Marker.Custom` plus a
  separately validated scalar `customSymbol`. `BorderType.Solid` is a native
  convenience for the upstream `border::FULL` set.
- `BlockExt.inner_if_some` maps to `Option[Block].inner`. `CellEffect` is a
  closure or custom object implementing `apply`. `Shape` is a generic
  `draw(shape, var Painter)` overload; `Context` is `CanvasContext`, and its
  paint callback is an owned Nim closure. `CanvasLine` avoids collision with
  styled text `Line`.
- `CalendarEventStore.today` maps to `todayEvents` using the local date.
  `DateStyler` is a date-to-style callback; `CalendarEventStore` supplies one
  through the `initMonthly` overload. Calendar uses native dates rather than
  exposing Rust's `time` crate types.
- Absent styles or selections are `Option` fields and can be cleared by
  assigning `none(...)`. This includes `SparklineBar.style`; a separate
  fluent clearing overload is not required for the operation to exist.

## Deliberate upstream exclusions

`Paragraph.line_count` and `line_width` are marked
`instability::unstable(feature = "rendered-line-info")` upstream, despite
having public Rust signatures. `WidgetRef` and `StatefulWidgetRef` are likewise
unstable. They are not missing stable APIs. Deprecated aliases, Rust ABI/trait
formatting conventions, `no_std`, alternate backend crates and third-party
widgets remain outside the agreed target. Optional stable palette conversion
is included, as is the optional stable calendar widget.

## Evidence limits

The checked-in suites compare finite reference cases. Public field access is
an API mapping, not proof that every value is independently tested. The symbol
catalog and finite merge truth table are exhaustive for their enumerated
inputs; geometry, Unicode sequences, floating-point drawing, text, styles and
widget combinations are not exhaustively enumerable. `todayEvents` depends
on wall-clock local date and does not have a deterministic Rust fixture.

Layout fixtures admit only alternatives actually observed in fresh pinned
upstream processes for tied systems; they do not accept arbitrary equivalent
optima. See `tools/layout/README.md`. Canvas/Chart finite-float coverage
and non-finite JSON limitations are in `tools/chart/README.md`.
## Canopy filled-block extension

`Block.fill`, `withFill` and `filledBlock` paint a block's body and color its border glyphs so
half-block borders form a solid panel with soft corners. They are not Ratatui compatibility
claims; blocks without a fill render exactly as upstream, which the block matrix covers.

## Canopy animation extension

`canopy/ui/animation/index` adds native tweens, easing, timelines, analytical springs,
scheduling, buffer transitions and reduced motion. These are Canopy extensions,
not Ratatui compatibility claims. See [animation contracts](../animation.md) and
[validation](../validation/animation.md); Windows runtime acceptance remains open.
