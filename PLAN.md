# Canopy: a native Nim TUI library with Ratatui parity

## Summary

Build Canopy as a reusable Nim library targeting the stable features of [Ratatui 0.30.2](https://github.com/ratatui/ratatui/releases/tag/ratatui-v0.30.2). Preserve its immediate-mode rendering model and match rendered cells, layout results, styles, and widget state through compatibility tests.

Deliver the complete library in working milestones, with macOS, Linux, and Windows support and a separate optional input module.

## Architecture and public API

- Ship one Nimble package. `import canopy` exposes the standard rendering API; individual modules allow focused imports. Input requires an explicit import.
- Separate geometry/layout, Unicode/text, styling, buffers, widgets, terminal management, backends, and input.
- Expose recognizable types: `Rect`, `Layout`, `Constraint`, `Color`, `Style`, `Span`, `Line`, `Text`, `Cell`, `Buffer`, `Frame`, and `Terminal[B]`.
- Use Nim value objects, camelCase procedures, `initType` constructors, and chainable `withX` configuration. Qualify conflicting names such as canvas lines and table cells.
- Support custom widgets through generic `render(widget, area, buffer)` procedures. Stateful widgets accept an additional mutable state argument; applications own that state.
- Make backends replaceable through a documented generic contract covering drawing, flushing, dimensions, clearing, cursor operations, and scrolling.
- Provide `draw`, `renderWidget`, `renderStatefulWidget`, explicit terminal initialization/restoration, and a scoped `withTerminal` helper. Keep event loops under application control.

## Implementation milestones

### 1. Compatibility foundation

- Create package scaffolding, documentation, CI, and `docs/parity.md`. Inventory every stable upstream feature and public operation, mapping it to a Nim equivalent and acceptance test.
- Add a development-only Rust reference program pinned to Ratatui 0.30.2 and its dependency lockfile. Generate fixtures containing layout rectangles, complete cell contents/styles, cursor state, and resulting widget state.
- Implement geometry, style composition/reset, styled text, buffers, clipping, and buffer differences.
- Implement native Unicode segmentation and display width matching the pinned `unicode-segmentation` and `unicode-width` behavior. Port the relevant algorithms and tables into internal Nim modules, retaining upstream notices. Unicode versions follow the reference lockfile.
- Preserve grapheme boundaries and wide-character overwrite behavior throughout measurement, clipping, wrapping, and rendering.

### 2. Layout and working terminals

- Port Ratatui’s constraint construction and required Kasuari solver functionality to internal Nim modules. Preserve priorities, rounding, overflow behavior, and ordering; validate against upstream fixtures. Include `Length`, `Min`, `Max`, `Percentage`, `Ratio`, `Fill`, all flex modes, margins, spacing/overlap, spacer rectangles, and configurable layout caching. [Upstream layout implementation](https://github.com/ratatui/ratatui/blob/ratatui-v0.30.2/ratatui-core/src/layout/layout.rs)
- Implement double-buffered drawing that emits changed cells, with cursor management, resizing, invalidation, and clear operations.
- Provide an ANSI/VT backend using POSIX terminal APIs on macOS/Linux and native console APIs on Windows. Provide a deterministic in-memory `TestBackend`.
- Support fullscreen, fixed, and inline viewports, including insertion above inline content and scrolling-region operations.
- Restore changed terminal modes after normal exit, exceptions, handled interrupts, and partial initialization failure. Propagate drawing/output errors.
- Deliver a runnable cross-platform example using blocks, paragraphs, and keyboard input.

### 3. Complete widgets and supporting features

- Implement every stable built-in widget: Block, Paragraph, List, Table, Tabs, Gauge, LineGauge, BarChart, Sparkline, Chart, Canvas, Scrollbar, Clear, Fill, Monthly calendar, RatatuiLogo, and Mascot. Include their supporting types, configuration options, state behavior, canvas shapes, markers, and symbol sets. [Upstream widget modules](https://github.com/ratatui/ratatui/blob/ratatui-v0.30.2/ratatui-widgets/src/lib.rs)
- Match wrapping, alignment, scrolling, selection, highlights, borders, titles, legends, axes, and calendar styling through reference fixtures.
- Include named/indexed/RGB colors, underline color, modifiers, styling shortcuts, theme serialization, and Nim equivalents of text/layout construction helpers.
- Add explicit JSON encode/decode helpers for colors and styles using Nim’s standard library; document their format independently of Rust serialization.

### 4. Input, documentation, and release completion

- Finish the optional input module with blocking reads and timed polling for keyboard, mouse, resize, focus, and bracketed-paste events.
- Handle fragmented UTF-8 and escape sequences incrementally. Expose terminal capabilities for enhanced events; keep unsupported event kinds distinguishable from supported ones.
- Publish API documentation, a Ratatui-to-Canopy migration guide, widget gallery, dashboard, inline-output example, and custom-widget/backend examples.
- Complete the parity matrix before declaring stable parity. Intermediate milestones remain explicitly incomplete releases.

## Validation and acceptance

- Compare exact cells, styles, geometry, and state against the pinned reference for every supported widget and layout behavior.
- Cover empty/tiny areas, nonzero origins, conflicting constraints, rounding, overlapping layouts, resizing, and empty/out-of-range selections.
- Test CJK, combining marks, emoji sequences, flags, grapheme clipping, and replacing wide characters with narrow ones.
- Verify unchanged frames emit no cell updates and output failures do not silently advance the committed frame.
- Exercise terminal lifecycle and input through POSIX pseudo-terminals and Windows console integration tests, including exception cleanup and partial input.
- Run package tests and compile examples on all three platforms. Benchmark layout, wrapping, large tables, and frame differences; record results without imposing an arbitrary performance claim.
- Ordinary installation and tests use Nim only. Rust is required solely to regenerate or independently verify reference fixtures.

## Defaults and boundaries

- Package name: `canopy`. Minimum Nim: 2.2.0; CI also covers the locally installed 2.2.10. Validate ARC and ORC.
- MIT license for Canopy, preserving applicable upstream attribution and licenses.
- Native implementation with no external C or Rust library dependency. Standard OS APIs remain available; pure Nim dependencies are permitted.
- Target desktop terminals, including Windows 10/11 with VT support.
- Parity covers stable official functionality. Rust backend adapters and Rust-specific integrations map to native capabilities; Rust ABI compatibility, experimental APIs, embedded `no_std`, and third-party widgets are excluded.
- Exact compatibility means logical terminal cells and behavior; terminal fonts and glyph appearance remain terminal-dependent.
