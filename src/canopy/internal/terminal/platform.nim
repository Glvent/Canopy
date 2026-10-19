## Native terminal primitives shared by the ANSI backend and optional input.
import ../../core/layout/geometry
import ../../runtime/backends/types

when defined(windows):
  import std/winlean

  type
    Coord {.importc: "COORD", header: "<windows.h>".} = object
      x {.importc: "X".}: int16
      y {.importc: "Y".}: int16
    SmallRect {.importc: "SMALL_RECT", header: "<windows.h>".} = object
      left {.importc: "Left".}: int16
      top {.importc: "Top".}: int16
      right {.importc: "Right".}: int16
      bottom {.importc: "Bottom".}: int16
    ConsoleScreenBufferInfo {.importc: "CONSOLE_SCREEN_BUFFER_INFO",
        header: "<windows.h>".} = object
      size {.importc: "dwSize".}: Coord
      cursorPosition {.importc: "dwCursorPosition".}: Coord
      attributes {.importc: "wAttributes".}: uint16
      window {.importc: "srWindow".}: SmallRect
      maximumWindowSize {.importc: "dwMaximumWindowSize".}: Coord
    ConsoleFontInfoEx {.importc: "CONSOLE_FONT_INFOEX", header: "<windows.h>".} = object
      cbSize {.importc: "cbSize".}: uint32
      font {.importc: "nFont".}: uint32
      fontSize {.importc: "dwFontSize".}: Coord
      fontFamily {.importc: "FontFamily".}: uint32
      fontWeight {.importc: "FontWeight".}: uint32
      faceName {.importc: "FaceName".}: array[32, uint16]
    PlatformTerminalState* = object
      ## Console modes captured at configure time; `restoreTerminal` puts back only what was saved.
      inputHandle, outputHandle: Handle
      inputMode, outputMode: uint32
      inputModeSaved, outputModeSaved, configured*: bool

  const
    EnableProcessedInput = 0x0001'u32
    EnableLineInput = 0x0002'u32
    EnableEchoInput = 0x0004'u32
    EnableWindowInput = 0x0008'u32
    EnableVirtualTerminalInput = 0x0200'u32
    EnableVirtualTerminalProcessing = 0x0004'u32

  proc getOsHandle(fd: cint): Handle {.importc: "_get_osfhandle", header: "<io.h>".}
  proc getConsoleMode(h: Handle, mode: ptr uint32): WINBOOL {.stdcall, dynlib: "kernel32",
      importc: "GetConsoleMode".}
  proc setConsoleMode(h: Handle, mode: uint32): WINBOOL {.stdcall, dynlib: "kernel32",
      importc: "SetConsoleMode".}
  proc getConsoleScreenBufferInfo(h: Handle, info: ptr ConsoleScreenBufferInfo): WINBOOL {.stdcall,
      dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}
  proc getCurrentConsoleFontEx(h: Handle, maximumWindow: WINBOOL,
      info: ptr ConsoleFontInfoEx): WINBOOL {.stdcall, dynlib: "kernel32",
      importc: "GetCurrentConsoleFontEx".}

  proc configureTerminal*(input, output: File, rawMode: bool): PlatformTerminalState =
    ## Enables VT processing and, with `rawMode`, unbuffered input. A failed input change rolls the
    ## output mode back before raising, so the console is never left half-configured.
    result.inputHandle = getOsHandle(cint(input.getFileHandle)); result.outputHandle = getOsHandle(
        cint(output.getFileHandle))
    if getConsoleMode(result.outputHandle, addr result.outputMode) != 0:
      result.outputModeSaved = true
      if setConsoleMode(result.outputHandle, result.outputMode or
          EnableVirtualTerminalProcessing) == 0:
        raise newException(IOError, "SetConsoleMode(output) failed: " & $getLastError())
    if getConsoleMode(result.inputHandle, addr result.inputMode) != 0:
      result.inputModeSaved = true
      if rawMode:
        let mode = (result.inputMode and not (EnableProcessedInput or EnableLineInput or
            EnableEchoInput)) or EnableWindowInput or EnableVirtualTerminalInput
        if setConsoleMode(result.inputHandle, mode) == 0:
          if result.outputModeSaved: discard setConsoleMode(result.outputHandle, result.outputMode)
          raise newException(IOError, "SetConsoleMode(input) failed: " & $getLastError())
    result.configured = true

  proc restoreTerminal*(state: var PlatformTerminalState) =
    if not state.configured: return
    var failed = false
    if state.inputModeSaved and setConsoleMode(state.inputHandle, state.inputMode) ==
        0: failed = true
    if state.outputModeSaved and setConsoleMode(state.outputHandle, state.outputMode) ==
        0: failed = true
    state.configured = false
    if failed: raise newException(IOError, "restoring Windows console mode failed")

  proc terminalSize*(output: File): Size =
    ## Window size, not buffer size; falls back to 80x24 when the handle is not a console.
    var info: ConsoleScreenBufferInfo
    let handle = getOsHandle(cint(output.getFileHandle))
    if getConsoleScreenBufferInfo(handle, addr info) != 0:
      return initSize(int(info.window.right-info.window.left+1), int(
          info.window.bottom-info.window.top+1))
    initSize(80, 24)

  proc terminalWindowSize*(output: File): WindowSize =
    result.columnsRows = terminalSize(output)
    var font = ConsoleFontInfoEx(cbSize: uint32(sizeof(ConsoleFontInfoEx)))
    let handle = getOsHandle(cint(output.getFileHandle))
    if getCurrentConsoleFontEx(handle, 0, addr font) != 0:
      result.pixels = initSize(result.columnsRows.width*max(0, int(font.fontSize.x)),
          result.columnsRows.height*max(0, int(font.fontSize.y)))

  proc terminalCursorPosition*(input, output: File): Position =
    discard input
    var info: ConsoleScreenBufferInfo
    let handle = getOsHandle(cint(output.getFileHandle))
    if getConsoleScreenBufferInfo(handle, addr info) != 0:
      return initPosition(max(0, int(info.cursorPosition.x-info.window.left)), max(0, int(
          info.cursorPosition.y-info.window.top)))

  proc waitReadable*(input: File, timeoutMs: int): bool =
    let handle = getOsHandle(cint(input.getFileHandle))
    let timeout = if timeoutMs < 0: INFINITE else: int32(timeoutMs)
    let wait = waitForSingleObject(handle, timeout)
    if wait == WAIT_OBJECT_0: return true
    if wait == WAIT_TIMEOUT: return false
    raise newException(IOError, "WaitForSingleObject failed: " & $getLastError())

  proc readAvailable*(input: File, maxBytes = 4096): string =
    ## Blocks until at least one byte is available; an empty result means end of input.
    if maxBytes <= 0: return ""
    result = newString(maxBytes); var count: int32
    let handle = getOsHandle(cint(input.getFileHandle))
    if readFile(handle, addr result[0], int32(maxBytes), addr count, nil) == 0:
      raise newException(IOError, "ReadFile failed: " & $getLastError())
    result.setLen(int(count))

else:
  import std/[os, posix, strutils, tables]
  import posix/termios

  # Bytes read while polling for a cursor-position report but belonging to the application.
  # They are replayed by `readAvailable` so no keystroke is lost to the query.
  var pendingInput {.threadvar.}: Table[cint, string]

  type PlatformTerminalState* = object
    inputFd*: cint
    original*: Termios
    modeSaved*, configured*: bool

  proc configureTerminal*(input, output: File, rawMode: bool): PlatformTerminalState =
    ## Switches the input terminal to raw mode, saving the original attributes for restoration.
    ## A non-tty input is left untouched, which keeps piped and test input working.
    discard output
    result.inputFd = cint(input.getFileHandle)
    if rawMode and isatty(result.inputFd) != 0:
      if tcGetAttr(result.inputFd, addr result.original) != 0: raiseOSError(osLastError())
      result.modeSaved = true
      var raw = result.original
      raw.c_iflag = raw.c_iflag and not (IGNBRK or BRKINT or PARMRK or ISTRIP or INLCR or IGNCR or
          ICRNL or IXON)
      raw.c_oflag = raw.c_oflag and not OPOST
      raw.c_cflag = (raw.c_cflag and not (CSIZE or PARENB)) or CS8
      raw.c_lflag = raw.c_lflag and not (ECHO or ECHONL or ICANON or IEXTEN or ISIG)
      raw.c_cc[VMIN] = char(1); raw.c_cc[VTIME] = char(0)
      if tcSetAttr(result.inputFd, TCSAFLUSH, addr raw) != 0: raiseOSError(osLastError())
    result.configured = true

  proc restoreTerminal*(state: var PlatformTerminalState) =
    if not state.configured: return
    state.configured = false
    # Restoration must not wait for a terminal's output queue. In particular,
    # a pseudo-terminal can have pending output while its controller is being
    # unwound after an exception.
    if state.modeSaved and tcSetAttr(state.inputFd, TCSANOW, addr state.original) !=
        0: raiseOSError(osLastError())

  proc terminalSize*(output: File): Size =
    var ws: IOctl_WinSize
    if ioctl(cint(output.getFileHandle), TIOCGWINSZ, addr ws) == 0 and ws.ws_col > 0 and ws.ws_row > 0:
      return initSize(int(ws.ws_col), int(ws.ws_row))
    initSize(80, 24)

  proc terminalWindowSize*(output: File): WindowSize =
    var ws: IOctl_WinSize
    if ioctl(cint(output.getFileHandle), TIOCGWINSZ, addr ws) == 0:
      result.columnsRows = initSize(int(ws.ws_col), int(ws.ws_row))
      result.pixels = initSize(int(ws.ws_xpixel), int(ws.ws_ypixel))
    else: result.columnsRows = initSize(80, 24)

  proc waitReadable*(input: File, timeoutMs: int): bool
  proc readAvailable*(input: File, maxBytes = 4096): string

  proc terminalCursorPosition*(input, output: File): Position =
    ## Queries the terminal with DSR and waits briefly for the reply; returns (0, 0) when input or
    ## output is not a tty or no report arrives. Bytes read that are not the report are buffered
    ## for the next `readAvailable`.
    let inputFd = cint(input.getFileHandle); let outputFd = cint(output.getFileHandle)
    if isatty(inputFd) == 0 or isatty(outputFd) == 0: return
    var query = "\e[6n"
    if output.writeBuffer(unsafeAddr query[0], query.len) != query.len:
      raise newException(IOError, "short terminal cursor query write")
    output.flushFile()
    var response = ""
    for attempt in 0..<4:
      if not waitReadable(input, 25): break
      response.add(readAvailable(input, 64-response.len))
      let start = response.find("\e["); let finish = response.find('R', max(0, start+2))
      if start >= 0 and finish > start:
        let fields = response[start+2..<finish].split(';')
        if fields.len == 2:
          try:
            let position = initPosition(max(0, parseInt(fields[1])-1), max(0, parseInt(fields[0])-1))
            let unrelated = response[0..<start] & response[finish+1..^1]
            if unrelated.len > 0: pendingInput.mgetOrPut(inputFd, "").add(unrelated)
            return position
          except ValueError: break
    if response.len > 0: pendingInput.mgetOrPut(inputFd, "").add(response)

  proc waitReadable*(input: File, timeoutMs: int): bool =
    ## Negative `timeoutMs` waits indefinitely. Interrupted polls are retried, so a signal does not
    ## surface as a spurious timeout.
    let fd = cint(input.getFileHandle)
    if pendingInput.hasKey(fd) and pendingInput[fd].len > 0: return true
    var descriptor = TPollfd(fd: fd, events: POLLIN)
    while true:
      let rc = poll(addr descriptor, Tnfds(1), cint(timeoutMs))
      if rc > 0:
        if (descriptor.revents and POLLNVAL) != 0: raise newException(IOError, "poll reported an invalid terminal descriptor")
        return (descriptor.revents and (POLLIN or POLLHUP or POLLERR)) != 0
      if rc == 0: return false
      if errno != EINTR: raiseOSError(osLastError())

  proc readAvailable*(input: File, maxBytes: int): string =
    if maxBytes <= 0: return ""
    let fd = cint(input.getFileHandle)
    if pendingInput.hasKey(fd) and pendingInput[fd].len > 0:
      let count = min(maxBytes, pendingInput[fd].len)
      result = pendingInput[fd][0..<count]
      pendingInput[fd].delete(0..count-1)
      if pendingInput[fd].len == 0: pendingInput.del(fd)
      return
    result = newString(maxBytes)
    while true:
      let count = posix.read(fd, addr result[0], maxBytes)
      if count >= 0: result.setLen(count); return
      if errno != EINTR: raiseOSError(osLastError())
