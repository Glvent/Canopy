# Windows console validation

`tests/runtime/test_windows.nim` exercises Canopy against a native Windows console. It
opens `CONIN$` and `CONOUT$` from the inherited console, or calls
`AllocConsole` when the test process has no console. It does not rely on the
runner's redirected standard handles.

The test records both console modes with `GetConsoleMode` and checks:

- ANSI initialization enables virtual-terminal output and the requested raw
  input flags, then restores both modes exactly.
- `withInput` restores both modes when its body raises an exception.
- ANSI and input initialization restore modes when writing their enable
  sequences fails after native mode configuration.
- fragmented VT and UTF-8 input remains incremental.
- a `KEY_EVENT_RECORD` injected with `WriteConsoleInputW` reaches `Input.poll`
  within a bounded one-second polling budget.

The native input declarations deliberately bind C field names, including
`INPUT_RECORD.Event.KeyEvent` and
`KEY_EVENT_RECORD.uChar.UnicodeChar`. The Windows C compiler validates those
aliases against `<windows.h>` instead of trusting a duplicated Nim layout.

Run the complete suite on Windows from a Developer Command Prompt or another
shell with a working C compiler:

```console
nim r --mm:arc tools/tester.nim
nim r --mm:orc tools/tester.nim
```

GitHub Actions is configured to run that suite on `windows-latest` with Nim 2.2.0 and 2.2.10,
under ARC and ORC. A green Windows matrix is the runtime evidence for these
checks.

From another host, semantic analysis and C generation can catch Nim errors and
expose the emitted imported field accesses for inspection without making a
Windows compile or runtime claim:

```console
nim c --compileOnly --os:windows --cpu:amd64 --mm:arc \
  --nimcache:build/windows-c-arc tests/runtime/test_windows.nim
nim c --compileOnly --os:windows --cpu:amd64 --mm:orc \
  --nimcache:build/windows-c-orc tests/runtime/test_windows.nim
```

These cross-host commands do not run the executable, link the generated C, or
prove console behavior. Windows console validation remains scoped to the ANSI
and input backend paths covered above; it does not establish global platform
parity or cover optional upstream/Rust backend integrations.

Final local C generation passed for this test and all six examples under Nim
2.2.0 and 2.2.10, both ARC and ORC. No Windows runtime result is claimed.
