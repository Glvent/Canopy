# Input

Terminal input is optional and is not re-exported by `canopy`. Import it
explicitly:

```nim
import canopy/runtime/terminal/input

var source = initInput(
  input = stdin,
  output = stdout,
  capabilities = defaultInputCapabilities(),
  rawMode = true,
)
source.init()
try:
  let event = source.read()
finally:
  source.restore()
```

`defaultInputCapabilities()` enables focus and bracketed-paste reporting.
`InputCapabilities` can also enable mouse capture and the Kitty enhanced
keyboard protocol. Capability setup and cleanup sequences are paired, and
`init`/`restore` are explicit, idempotent, partial-failure-safe operations.
Use `withInput(name, value): ...` when a small scope should always restore its
terminal modes. A handled interrupt that raises or returns through this scope
runs the same `finally` cleanup. Input and output failures propagate to the
caller.

`read` blocks until an event or raises `EOFError` after the input closes.
`poll(timeoutMs)` returns `Option[Event]`; zero is nonblocking and a negative
timeout blocks. The blocking path checks dimensions periodically, so terminal
resizes become `Resize` events without relying on an unsafe signal handler.
The decoder waits briefly to distinguish a standalone Escape key from an Alt
key or longer escape sequence.

The decoder produces:

- `Key` events for Unicode text, control keys, navigation, Insert/Delete,
  PageUp/PageDown, F1-F12, modifiers, and press/repeat/release information when
  the terminal supplies it.
- `Mouse` events for SGR and legacy X10 mouse protocols, including buttons,
  drag/move, four scroll directions, modifiers, and zero-based coordinates.
- `FocusGained`, `FocusLost`, `Paste`, and `Resize` events.
- `Unsupported` with the original `raw` bytes for complete terminal sequences
  that Canopy does not recognize.

`InputParser` is also public for deterministic sources and tests. Call `feed`
with a string or bytes, then use `nextEvent` or `drain`. It retains incomplete
UTF-8, escape, mouse, and paste sequences between calls. Invalid UTF-8 yields a
replacement-character key event instead of discarding following bytes.

POSIX polling uses `poll(2)` and raw reads. Windows polling uses the console
handle wait and `ReadFile`; resize detection uses the current console window.
Windows terminals must support virtual-terminal input for encoded enhanced
events. Basic redirected byte input remains decodable, while dimensions fall
back to 80 by 24 when the output is not attached to a console.
