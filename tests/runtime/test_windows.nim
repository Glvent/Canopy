## Windows-specific terminal behavior tests.
import std/unittest

when defined(windows):
  import std/[options, winlean]
  import canopy/runtime/backends/ansi
  import canopy/runtime/terminal/input

  type
    NativeKeyEvent {.importc: "KEY_EVENT_RECORD", header: "<windows.h>".} = object
      keyDown {.importc: "bKeyDown".}: WINBOOL
      repeatCount {.importc: "wRepeatCount".}: uint16
      virtualKeyCode {.importc: "wVirtualKeyCode".}: uint16
      virtualScanCode {.importc: "wVirtualScanCode".}: uint16
      unicodeChar {.importc: "uChar.UnicodeChar".}: uint16
      controlKeyState {.importc: "dwControlKeyState".}: uint32
    NativeInputRecord {.importc: "INPUT_RECORD", header: "<windows.h>".} = object
      eventType {.importc: "EventType".}: uint16
      keyEvent {.importc: "Event.KeyEvent".}: NativeKeyEvent
    ConsoleFixture = object
      input, output: File
      allocated: bool

  const
    EnableProcessedInput = 0x0001'u32
    EnableLineInput = 0x0002'u32
    EnableEchoInput = 0x0004'u32
    EnableWindowInput = 0x0008'u32
    EnableVirtualTerminalInput = 0x0200'u32
    EnableVirtualTerminalProcessing = 0x0004'u32
    KeyEventRecord = 0x0001'u16

  proc allocConsole(): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "AllocConsole".}
  proc freeConsole(): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "FreeConsole".}
  proc getOsHandle(fd: cint): Handle
    {.importc: "_get_osfhandle", header: "<io.h>".}
  proc getConsoleMode(handle: Handle, mode: ptr uint32): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}
  proc writeConsoleInput(handle: Handle, records: ptr NativeInputRecord,
                         count: uint32, written: ptr uint32): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "WriteConsoleInputW".}

  proc osHandle(file: File): Handle =
    getOsHandle(cint(file.getFileHandle))

  proc mode(file: File): uint32 =
    if getConsoleMode(file.osHandle, addr result) == 0:
      raise newException(IOError, "GetConsoleMode failed: " & $getLastError())

  proc openConsole(): ConsoleFixture =
    if not open(result.input, "CONIN$", fmReadWriteExisting) or
        not open(result.output, "CONOUT$", fmReadWriteExisting):
      if result.input != nil: close(result.input)
      if result.output != nil: close(result.output)
      if allocConsole() == 0:
        raise newException(IOError, "AllocConsole failed: " & $getLastError())
      result.allocated = true
      if not open(result.input, "CONIN$", fmReadWriteExisting) or
          not open(result.output, "CONOUT$", fmReadWriteExisting):
        if result.input != nil: close(result.input)
        if result.output != nil: close(result.output)
        discard freeConsole()
        raise newException(IOError, "opening CONIN$/CONOUT$ failed")
    discard result.input.mode
    discard result.output.mode

  proc close(console: var ConsoleFixture) =
    if console.input != nil: close(console.input)
    if console.output != nil: close(console.output)
    if console.allocated: discard freeConsole()

  template withConsole(body: untyped) =
    block:
      var console {.inject.} = openConsole()
      try:
        body
      finally:
        console.close()

  func expectedRawInput(original: uint32): uint32 =
    (original and not (EnableProcessedInput or EnableLineInput or
      EnableEchoInput)) or EnableWindowInput or EnableVirtualTerminalInput

  suite "Windows console integration":
    test "ANSI raw mode changes native modes and restores them exactly":
      withConsole:
        let originalInput = console.input.mode
        let originalOutput = console.output.mode
        var backend = initAnsiBackend(console.output, console.input,
          alternateScreen = false, rawMode = true)
        backend.init()
        try:
          check backend.initialized
          check console.input.mode == expectedRawInput(originalInput)
          check console.output.mode ==
            (originalOutput or EnableVirtualTerminalProcessing)
          let size = backend.size
          let window = backend.windowSize
          let cursor = backend.getCursorPosition
          check size.width > 0 and size.height > 0
          check window.columnsRows == size
          check window.pixels.width >= 0 and window.pixels.height >= 0
          check cursor.x >= 0 and cursor.y >= 0
        finally:
          backend.restore()
        check not backend.initialized
        check console.input.mode == originalInput
        check console.output.mode == originalOutput

    test "withInput restores native modes after an exception":
      withConsole:
        let originalInput = console.input.mode
        let originalOutput = console.output.mode
        expect ValueError:
          withInput(source, initInput(console.input, console.output,
              InputCapabilities(), rawMode = true)):
            check console.input.mode == expectedRawInput(originalInput)
            check console.output.mode ==
              (originalOutput or EnableVirtualTerminalProcessing)
            raise newException(ValueError, "test")
        check console.input.mode == originalInput
        check console.output.mode == originalOutput

    test "ANSI partial initialization rolls native modes back":
      withConsole:
        let originalInput = console.input.mode
        let originalOutput = console.output.mode
        var readOnlyOutput: File
        require open(readOnlyOutput, "CONOUT$", fmRead)
        try:
          var backend = initAnsiBackend(readOnlyOutput, console.input,
            alternateScreen = true, rawMode = true)
          expect IOError:
            backend.init()
          check not backend.initialized
          backend.restore()
        finally:
          close(readOnlyOutput)
        check console.input.mode == originalInput
        check console.output.mode == originalOutput

    test "input partial initialization rolls native modes back":
      withConsole:
        let originalInput = console.input.mode
        let originalOutput = console.output.mode
        var readOnlyOutput: File
        require open(readOnlyOutput, "CONOUT$", fmRead)
        try:
          var source = initInput(console.input, readOnlyOutput,
            InputCapabilities(focusEvents: true), rawMode = true)
          expect IOError:
            source.init()
          check not source.initialized
          source.restore()
        finally:
          close(readOnlyOutput)
        check console.input.mode == originalInput
        check console.output.mode == originalOutput

    test "fragmented input and an injected console key stay bounded":
      withConsole:
        let originalInput = console.input.mode
        let originalOutput = console.output.mode
        var source = initInput(console.input, console.output,
          InputCapabilities(), rawMode = true)
        source.init()
        try:
          let bytes = "\e[A界"
          source.feed(bytes[0 .. 1])
          check source.parser.nextEvent.isNone
          source.feed(bytes[2 .. 3])
          let up = source.parser.nextEvent
          check up.isSome and up.get.key.code == KeyCode.Up
          check source.parser.nextEvent.isNone
          source.feed(bytes[4 .. ^1])
          let wide = source.parser.nextEvent
          check wide.isSome and wide.get.key.text == "界"

          var record: NativeInputRecord
          record.eventType = KeyEventRecord
          record.keyEvent.keyDown = 1
          record.keyEvent.repeatCount = 1
          record.keyEvent.virtualKeyCode = uint16(ord('Q'))
          record.keyEvent.unicodeChar = uint16(ord('q'))
          var written: uint32
          require writeConsoleInput(console.input.osHandle, addr record, 1,
            addr written) != 0
          require written == 1
          var found = false
          for _ in 0 ..< 10:
            let event = source.poll(100)
            if event.isSome and event.get.kind == EventKind.Key and
                event.get.key.text == "q":
              found = true
              break
          check found
        finally:
          source.restore()
        check console.input.mode == originalInput
        check console.output.mode == originalOutput
else:
  suite "Windows console integration":
    test "not applicable":
      check true
