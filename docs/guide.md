# Using Canopy

Install a local checkout with `nimble install`. Nim 2.2.0 or newer and a C compiler are sufficient; no Rust or external runtime library is needed. `import canopy` includes the standard widgets and ANSI/Test backends. Import `canopy/runtime/terminal/input` separately when you want its event decoder.

```nim
import canopy
import canopy/runtime/terminal/input

withTerminal(terminal, initAnsiBackend()):
  withInput(events, initInput(rawMode=false)):
    while true:
      discard terminal.draw(proc(frame: var Frame) =
        frame.renderWidget(initParagraph("Hello, 世界 🌿")
          .withBlock(borderedBlock().withTitle("Canopy")), frame.area))
      let event = events.read()
      if event.kind == EventKind.Key and event.key.text == "q": break
```

`withTerminal` initializes the backend and restores its modes in `finally`. `withInput` does the same for event capabilities. Here the terminal owns raw mode, so input uses `rawMode=false`. Ctrl-C is a key event in raw mode; applications decide how to handle it. Examples explicitly handle exit keys. No library-owned event loop or process-global signal handler is installed. Interrupt handlers that unwind through the scoped helpers get the same cleanup as exceptions.

Each `draw` starts with a clean current buffer. Render the complete UI every time. Canopy sends cell differences to the backend, then applies the frame cursor and flushes output. It commits the frame only after those operations succeed. Failed output invalidates the display for a full repaint on retry; the frame count does not advance. A `CompletedFrame` owns a snapshot. A `Frame` contains a pointer into the terminal and must stay inside its render scope; do not retain it across draws or move the terminal while it is borrowed.

## Layout and styles

```nim
let columns = horizontal([length(24), fill()]).withSpacing(1).split(area)
let popup = area.centered(percentage(60), length(8))
let selected = initStyle().cyan().onBlue().bold()
let heading = "Jobs".green().bold()
```

Constraints include length, minimum, maximum, percentage, ratio and weighted fill. `Flex` controls unused space; negative spacing creates overlap. `splitWithSpacers` also returns the gaps. `setLayoutCacheSize(0)` disables the per-thread cache; the default is 500 entries. Coordinates and dimensions use `int` with constructors saturating at the upstream 16-bit boundary.

Styles are patches: an absent color inherits, `ColorKind.Reset` restores the terminal default, and modifier removal overrides earlier additions. `withStyle` replaces a widget's style; color/modifier shortcuts patch it. Span style overrides Line style, which overrides Text/widget style. `initLine(string)` concatenates newline-separated spans; use `initText` or `initParagraph` for multiple rows.

## State and custom rendering

Store `ListState`, `TableState` and `ScrollbarState` in application state. Call `renderStatefulWidget` with a mutable state; rendering may clamp selection or adjust scrolling. `none(int)` clears a selection. Widgets and configuration are value objects with public data and chainable `withX` builders.

A custom widget implements `render(widget, area: Rect, buffer: var Buffer)`. A stateful widget adds `state: var YourState`. Generic dispatch finds these procedures without registration or inheritance. The renderer owns clipping to the buffer. Use `buffer.area.intersection(area)` for direct cell writes and `setStringn` for grapheme-safe text. A canvas shape implements `draw(shape, painter: var Painter)`; see the Canvas API and the showcase's Widgets page.

Backends implement the structural contract in [interfaces](interfaces.md). `TestBackend` records updates, screen cells, cursor and scrollback for deterministic tests. `AnsiBackend` uses native OS terminal modes and ANSI/VT output; see [backend behavior](backends.md).

## Viewports and lower-level rendering

The default viewport fills the screen. `fixedViewport(rect)` renders inside a fixed region. `inlineViewport(height)` reserves rows at the current cursor and supports `insertBefore(height, callback)` for log output above the UI. Construct ANSI with `alternateScreen=false` for fixed or inline views. Scrolling regions preserve the inline display; one-row scrolling-region support follows the upstream VT backend and depends on terminal emulation.

Use `clear` after external output changes, or `invalidate` when the next draw should repaint without clearing immediately. `autoresize` follows backend size for fullscreen/inline viewports; fixed regions change only through explicit `resize`.

Advanced integrations can use `getFrame`/`currentBufferMut`, `flush`, `backend.flush`, then `swapBuffers`. Manual `flush` only emits the cell diff; it does not flush output, move/show the requested frame cursor, count frames, or commit. These lower-level operations put presentation and error recovery under the caller's control. Prefer `draw` for the transactional path.

`applyBuffer` or `applyBufferWithCursor` presents an already-rendered current buffer through the same transactional path as `draw`, without resetting it or automatically resizing. `CompletedFrame.area` describes the last known terminal area (the fixed area for fixed viewports); `CompletedFrame.buffer.area` is the rendered viewport, which can be smaller for inline output.

## JSON themes

Colors encode as named strings (`"Red"`, `"Reset"`), `{"indexed":240}`, or `{"rgb":[12,34,56]}`. Styles are objects with optional `fg`, `bg`, `underlineColor`, `addModifiers` and `subModifiers`. Modifier arrays contain exact names such as `"Bold"` and `"Underlined"`. Omitted colors inherit; a reset color is explicit. Unknown keys, names and out-of-range components raise `ValueError`.

`colorFromU32` extracts packed RGB. `colorFromHsl` takes degree hue and saturation/lightness in 0..1; `colorFromHsluv` takes degree hue and saturation/lightness in 0..100. Both use float32 inputs to match the pinned palette conversion.

A `Theme` is a string-to-Style table. `theme.toJson`, `themeFromJson`, `loadTheme` and `saveTheme` use this format. It is Canopy's documented JSON format, independent of Rust serde.

## Examples and documentation

`nimble examples` compiles the examples. The showcase is one interactive app that covers every
feature; run it from the repository root in a terminal of at least 80×24:

```sh
nim r examples/showcase/showcase.nim
nim r examples/showcase/showcase.nim --inline
```

Switch pages with Tab, Shift-Tab, `1`-`6` or a click on a tab. `t` cycles the accent color,
`m` toggles reduced motion and `q`, Escape or Ctrl-C exits. The bottom line lists each page's own
keys. Each page is a module in `examples/showcase/` with `render`, `handle` and `update`
procedures:

- Widgets (`widgets_page.nim`): List, Table and Scrollbar with shared selection, Calendar,
  Paragraph, Logo, Mascot, Fill, Clear, a Shadow popup and a custom `Badge` widget.
- Charts (`charts_page.nim`): live Chart, Canvas with a map and layers, BarChart, Sparkline,
  Gauge and LineGauge.
- Text & color (`text_page.nim`): modifiers, alignment, spans, named, indexed, HSL and HSLuv
  colors, the detected color depth and Unicode display widths.
- Motion (`motion_page.nim`): transition effects and directions, timelines, easing and a spring.
- Jobs (`jobs_page.nim`): simulated jobs with tweened progress and session settings.
- Input (`input_page.nim`): a log of every key, mouse, paste, focus and resize event.

The status line shows the cells sent for the last frame. They are counted by
`recording.nim`, a custom backend that wraps the ANSI backend. `--inline` runs
`inline_demo.nim`, which draws a progress viewport in normal scrollback and inserts log lines
above it.

`nimble docs` builds browsable API documentation under `build/docs`. [Migration](migration.md), [input](input.md), [parity](parity.md), and [reference regeneration](reference.md) provide additional details.
## Optional animation

Import `canopy/ui/animation/index` explicitly for tweens, timelines, springs and buffer
transitions. Applications supply monotonic timestamps and combine animation
deadlines with input polling. See [animation contracts and examples](animation.md).
