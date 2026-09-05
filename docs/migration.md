# Ratatui 0.30.2 → Canopy

Canopy preserves immediate-mode rendering and logical cell behavior. Its APIs use Nim value objects, camelCase and chainable `withX` configuration.

| Ratatui | Canopy |
|---|---|
| `use ratatui::prelude::*` | `import canopy` |
| `Rect::new(x,y,w,h)` | `initRect(x,y,w,h)` |
| `Style::new().fg(Color::Cyan).bold()` | `initStyle().cyan().bold()` |
| `Color::Rgb(r,g,b)` / `Indexed(n)` | `rgbColor(r,g,b)` / `indexedColor(n)` |
| `Span::raw(s)` / `Span::styled(s, style)` | `initSpan(s)` / `initSpan(s, style)` |
| `Line::from(...)`, `Text::from(...)` | `initLine(...)`, `initText(...)` |
| `Layout::horizontal([...]).spacing(1)` | `horizontal([...]).withSpacing(1)` |
| `Constraint::{Length,Min,Max,Percentage,Ratio,Fill}` | `length`, `minLength`, `maxLength`, `percentage`, `ratio`, `fill` |
| `Block::bordered().title(s)` | `borderedBlock().withTitle(s)` |
| `Paragraph::new(s).block(b)` | `initParagraph(s).withBlock(b)` |
| `Widget::render` | `render(widget, area, buffer)` |
| `StatefulWidget::render` | `render(widget, area, buffer, state)` |
| `frame.render_widget(widget, area)` | `frame.renderWidget(widget, area)` |
| `frame.render_stateful_widget(widget, area, &mut state)` | `frame.renderStatefulWidget(widget, area, state)` |
| `Terminal::with_options(backend, options)` | `initTerminal(backend, options)` or `initTerminal(backend, viewport)` |
| `terminal.draw` / `try_draw` | `terminal.draw`; Nim exceptions propagate |
| `Some(index)` / `None` | `some(index)` / `none(int)` from `std/options` |
| `table::Cell` / `canvas::Line` | `TableCell` / `CanvasLine` |
| `Marker::Custom(ch)` | `Marker.Custom` plus `withMarker(symbol)` or `customSymbol` |
| Rust text/layout macros | `initSpan`, `initLine`, `initText`, constraint arrays, `areas[N]` |
| Backend adapters and crossterm events | native `AnsiBackend` and optional `canopy/input` |

Public fields replace Rust accessors and ownership-conversion traits where appropriate. For example, use `state.selected`, `buffer.content`, `frame.area`, `terminal.backend`, and `widget.style`. `Frame.buffer` is a scoped pointer; `bufferMut` returns its mutable target. Nim sequences and strings own their values; there are no Rust borrow/lifetime parameters.

Cell `symbol` distinguishes an unset value internally for border merging while exposing a blank string value (`" "`) by default. Use `setSymbol`, `setStyle`, `setDiffOption` and `mergeSymbol`, or public fields for direct editing. All comparisons and fixtures concern logical terminal cells, not a terminal font's glyph shapes.

The pinned upstream solver has randomized pivot ordering. A few degenerate layouts have multiple valid upstream outputs; [layout validation](../tools/layout-validation.md) records the observed alternatives. Unicode segmentation and width use the lockfile's Unicode 17 tables. Fixture cases preserve documented upstream quirks, including some widget writes beyond their requested rectangle but within the containing buffer; see [parity](parity.md).

Rust-specific ABI, runtime/backend integrations, third-party widgets, embedded `no_std`, deprecated aliases, and unstable APIs are outside the accepted target. Canopy's input event model and theme JSON are native interfaces, not Rust serialization formats. See the [operation inventory](upstream-inventory.md) for explicit mappings and acceptance evidence.
