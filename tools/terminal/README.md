# Terminal reference validation

`tools/terminal/reference` is a development-only oracle built against
`ratatui-core = 0.1.2`, the core crate published with Ratatui 0.30.2. Its
checked-in `Cargo.lock` and exact dependency constraints make regeneration
reproducible. The `scrolling-regions` and `underline-color` features are
enabled. Canopy tests load only the generated JSON; Rust is never required by
the library or its test runtime.

Regenerate and verify the fixture from the repository root:

```sh
cargo run --locked --manifest-path tools/terminal/reference/Cargo.toml -- /tmp/terminal.json
cmp /tmp/terminal.json tests/fixtures/terminal.json
```

The fixture contains 204 deterministic cases. Every snapshot serializes the
viewport area, frame count, current frame, complete visible backend buffer,
complete scrollback buffer, cursor position, and cursor visibility. Every cell
includes its symbol, foreground, background, underline color, modifiers, skip
flag, and diff option. Successful draws also serialize the complete
`CompletedFrame`, including its buffer, area, and count.

The matrix covers fullscreen and nonzero-origin fixed viewports, plus inline
viewports with zero, one-row, partial, full-screen, and larger-than-screen
requested heights. Initial cursors appear at the top, middle, and bottom.
Actions cover normal draw, manual flush and buffer swap, `insertBefore` with
zero, one, small, full-screen, and larger-than-screen heights, resize with
existing content and nonzero cursors, clear, explicit frame cursors, and
repeated actions. Input explicitly sets initial cursor visibility to false so
the comparison does not depend on the differing constructors of the two test
backends. An additional 24 cases begin with partial or no-op draws over sentinel
backend cells, checking first-frame invalidation and zero-height insertion.

`tests/reference/test_terminal_reference.nim` reconstructs each input through Canopy's
public terminal and TestBackend APIs and compares each complete snapshot. Run:

```sh
nim c -r --mm:arc --nimcache:/tmp/canopy-terminal-arc tests/reference/test_terminal_reference.nim
nim c -r --mm:orc --nimcache:/tmp/canopy-terminal-orc tests/reference/test_terminal_reference.nim
```

The comparison exposed three parity gaps during development, all corrected in
the checked-in Canopy implementation:

- Fixed viewport resize did not reproduce Ratatui's cursor side effect from
  clearing the resized viewport.
- TestBackend resize did not resize existing scrollback rows to the new width.
- The first partial or no-op draw repainted untouched sentinel backend cells,
  while Ratatui compares the two initially blank terminal buffers and emits
  only actual differences.

All 204 cases now match every serialized field under both ARC and ORC.

The Ratatui TestBackend panics when `clear` follows construction of a
zero-height inline viewport whose computed origin is exactly the screen bottom.
The matrix still exercises zero-height inline draw, insertion, and resize, but
does not ask the Rust oracle to perform that panicking clear sequence.
