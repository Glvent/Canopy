## Optional terminal input. Import `canopy/runtime/terminal/input` explicitly.
import std/[options, monotimes, times]

import ../../core/layout/geometry
import ./parser
import ../../internal/terminal/platform
export parser

type
  InputCapabilities* = object
    focusEvents*, bracketedPaste*, mouseCapture*, enhancedKeyboard*: bool
  Input* = object
    ## `escapeStarted`/`escapeWaiting` time the ambiguity window for a lone ESC byte, which could
    ## still become a longer sequence.
    inputFile*, outputFile*: File
    parser*: InputParser
    capabilities*: InputCapabilities
    rawMode*: bool
    initialized*, eof*: bool
    lastSize: Size
    escapeStarted: MonoTime
    escapeWaiting: bool
    platformState: PlatformTerminalState

func defaultInputCapabilities*(): InputCapabilities = InputCapabilities(focusEvents: true, bracketedPaste: true)
func initInput*(input: File = stdin, output: File = stdout, capabilities = defaultInputCapabilities(), rawMode = true): Input =
  Input(inputFile: input, outputFile: output, parser: initInputParser(), capabilities: capabilities, rawMode: rawMode)

proc writeAll(file: File, data: string) =
  if data.len == 0: return
  let written = file.writeBuffer(unsafeAddr data[0], data.len)
  if written != data.len: raise newException(IOError, "short terminal write: " & $written & "/" & $data.len)

func enableSequence(c: InputCapabilities): string =
  if c.focusEvents: result.add("\e[?1004h")
  if c.bracketedPaste: result.add("\e[?2004h")
  if c.mouseCapture: result.add("\e[?1003h\e[?1006h")
  if c.enhancedKeyboard: result.add("\e[>1u")

# Disabled in the reverse order of `enableSequence` so nested terminal modes unwind cleanly.

func disableSequence(c: InputCapabilities): string =
  if c.enhancedKeyboard: result.add("\e[<u")
  if c.mouseCapture: result.add("\e[?1006l\e[?1003l")
  if c.bracketedPaste: result.add("\e[?2004l")
  if c.focusEvents: result.add("\e[?1004l")

proc init*(source: var Input) =
  ## Idempotent. Terminal attributes are restored before any failure to enable input modes
  ## propagates.
  if source.initialized: return
  source.eof = false
  source.platformState = configureTerminal(source.inputFile, source.outputFile, source.rawMode)
  try:
    source.outputFile.writeAll(enableSequence(source.capabilities)); source.outputFile.flushFile()
    source.lastSize = terminalSize(source.outputFile); source.initialized = true
  except CatchableError:
    try: restoreTerminal(source.platformState)
    except CatchableError: discard
    raise

proc restore*(source: var Input) =
  ## Disables input modes before restoring terminal attributes; surfaces the first failure.
  if not source.initialized and not source.platformState.configured: return
  source.initialized = false
  var failure: ref CatchableError
  try: source.outputFile.writeAll(disableSequence(source.capabilities)); source.outputFile.flushFile()
  except CatchableError as e: failure = e
  try: restoreTerminal(source.platformState)
  except CatchableError as e:
    if failure.isNil: failure = e
  if not failure.isNil: raise failure

proc feed*(source: var Input, data: string) = source.parser.feed(data)
proc feed*(source: var Input, data: openArray[byte]) = source.parser.feed(data)
proc drain*(source: var Input): seq[Event] = source.parser.drain()

# Resize is polled rather than signal-driven, so it is detected only between waits.
proc changedSize(source: var Input): Option[Event] =
  let current = terminalSize(source.outputFile)
  if current != source.lastSize:
    source.lastSize = current
    return some(resizeEvent(current.width, current.height))

proc poll*(source: var Input, timeoutMs: int): Option[Event] =
  ## Waits up to `timeoutMs` for one event; a negative timeout waits indefinitely. It always
  ## performs at least one wait, so a zero timeout still reports input that is already available.
  let started = getMonoTime()
  var firstWait = true
  while true:
    result = source.parser.nextEvent()
    if result.isSome: return
    result = source.changedSize()
    if result.isSome: return
    # Bare Escape must not block longer than a partial CSI sequence would.
    if source.parser.pending == "\e":
      if not source.escapeWaiting:
        source.escapeWaiting = true; source.escapeStarted = getMonoTime()
      if (getMonoTime()-source.escapeStarted).inMilliseconds >= 25:
        source.parser.finishEscape(); source.escapeWaiting = false
        return source.parser.nextEvent()
    else: source.escapeWaiting = false
    let elapsed = int((getMonoTime()-started).inMilliseconds)
    if timeoutMs >= 0 and not firstWait and elapsed >= timeoutMs: return none(Event)
    var wait = if timeoutMs < 0: 50 else: max(0, timeoutMs-elapsed)
    if source.escapeWaiting:
      wait = min(wait, max(0, 25-int((getMonoTime()-source.escapeStarted).inMilliseconds)))
    firstWait = false
    if not waitReadable(source.inputFile, wait):
      if source.escapeWaiting and (getMonoTime()-source.escapeStarted).inMilliseconds >= 25:
        source.parser.finishEscape(); source.escapeWaiting = false
        return source.parser.nextEvent()
      if timeoutMs < 0: continue
      return none(Event)
    let data = readAvailable(source.inputFile)
    if data.len == 0:
      source.eof = true; source.parser.finish()
      return source.parser.nextEvent()
    source.parser.feed(data)

proc read*(source: var Input): Event =
  ## Blocks until an event arrives; raises EOFError once input is closed and drained.
  while true:
    let event = source.poll(-1)
    if event.isSome: return event.get
    if source.eof: raise newException(EOFError, "terminal input closed")

template withInput*(name: untyped, sourceValue: untyped, body: untyped) =
  block:
    var name {.inject.} = sourceValue
    name.init()
    try: body
    finally: name.restore()
