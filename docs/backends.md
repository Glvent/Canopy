# Backends

Canopy renders through a structural backend contract. A backend supplies
`draw`, `flush`, `size`, cursor visibility and positioning, clearing,
scroll-region operations, and `appendLines`. Methods raise their underlying
I/O error. The terminal commits its previous buffer only after the complete
backend operation succeeds.

## ANSI backend

Import `canopy/backends/ansi` and construct it with:

```nim
var backend = initAnsiBackend(
  output = stdout,
  input = stdin,
  alternateScreen = true,
  rawMode = true,
)
backend.init()
try:
  # use backend through Terminal or call the backend contract directly
  discard
finally:
  backend.restore()
```

`init` and `restore` are explicit and idempotent. Initialization first saves
the native terminal state and then enters the alternate screen when requested.
If initialization fails, it restores any saved native state before re-raising.
Restoration attempts both ANSI cleanup and native mode restoration; it reports
the first error after both cleanup paths have run. Scoped terminal helpers use
this lifecycle for normal returns, exceptions, and handled interrupts.

The backend emits ANSI/VT sequences for named, indexed, and RGB foreground and
background colors, underline color, and every Canopy text modifier. It handles
Unicode cell width, explicit skipped cells, cursor visibility and position,
complete and rectangular clears, bottom-exclusive scrolling regions, and line
insertion for inline viewports. `getCursorPosition` returns the position tracked
from backend operations. Its first call queries an attached terminal and then
tracks later backend operations; applications that write independently to the
same stream must reposition the backend before the next frame. `windowSize`
returns both character-cell and pixel dimensions. `ClearType` exposes whole
screen, before/after cursor, current-line, and until-end-of-line clears.

Set `alternateScreen = false` for fixed and inline views. Set `rawMode = false`
when another component owns input mode. Output may be redirected to any Nim
`File`; writes and flushes remain observable and failures are never discarded.

## Platform behavior

On POSIX systems Canopy uses `termios`, `poll`, `read`, and terminal-size
`ioctl` calls. Raw mode disables canonical input, echo, signal-generating input
characters, input translations, and output post-processing. Restore applies
the saved state immediately so cleanup cannot block on an undrained terminal
output queue.

Cursor-position replies share the input descriptor with `canopy/input`. Bytes
read beside the terminal's reply are retained by the platform layer and are
returned by the next input poll.

On Windows Canopy uses native console handles. It enables virtual-terminal
output and, when raw input is requested, virtual-terminal and window input
while disabling line, echo, and processed input. It saves and restores each
console mode independently. Redirected standard handles remain valid ANSI byte
streams and use an 80 by 24 size fallback when no console window is available.

Custom backends may be value types. They should implement the signatures in
`docs/interfaces.md`, treat `bottom` as exclusive in scrolling methods, and
raise on failed operations.
