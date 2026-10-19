## ANSI/VT backend with native terminal mode setup on POSIX and Windows.
import std/[os, strutils]

import ../../core/layout/geometry
import ../../core/styling/[style, colordepth]
import ../../core/rendering/buffer
import ./types
import ../../internal/terminal/platform
export types, colordepth

type AnsiBackend* = object
  ## `cursor` is the backend's belief about the terminal cursor; `cursorKnown` is false until a
  ## move or a query establishes it, because the position at startup is unknown.
  ## `synchronizedActive` records an open synchronized update that the next `flush` closes.
  output*, input*: File
  alternateScreen*, rawMode*: bool
  colorDepth*: ColorDepth
  synchronizedOutput*: bool
  initialized*, cursorVisible*: bool
  cursor*: Position
  cursorKnown: bool
  synchronizedActive: bool
  platformState: PlatformTerminalState

const
  BeginSynchronizedUpdate = "\e[?2026h"
  EndSynchronizedUpdate = "\e[?2026l"

proc writeAll(file: File, data: string) =
  if data.len == 0: return
  let written = file.writeBuffer(unsafeAddr data[0], data.len)
  if written != data.len: raise newException(IOError, "short terminal write: " & $written & "/" & $data.len)

proc detectColorDepth*(lookup: proc(name: string): string): ColorDepth =
  ## Color depth from environment conventions, read through `lookup`. A non-empty `NO_COLOR` or
  ## `TERM=dumb` disables color; `COLORTERM=truecolor|24bit` and known truecolor terminals
  ## enable RGB; a `256color` TERM selects the 256-color palette; anything else gets 16 colors.
  let term = lookup("TERM").toLowerAscii
  if lookup("NO_COLOR").len > 0 or term == "dumb": return ColorDepth.Monochrome
  if lookup("COLORTERM").toLowerAscii in ["truecolor", "24bit"]: return ColorDepth.TrueColor
  if term.endsWith("-direct") or term in ["xterm-kitty", "xterm-ghostty", "wezterm", "alacritty", "foot", "foot-extra"]:
    return ColorDepth.TrueColor
  if lookup("TERM_PROGRAM") in ["iTerm.app", "WezTerm", "ghostty", "vscode"] or lookup("WT_SESSION").len > 0:
    return ColorDepth.TrueColor
  if "256color" in term: return ColorDepth.Ansi256
  # Windows 10+ consoles render RGB through virtual-terminal processing and set no TERM.
  if term.len == 0 and defined(windows): ColorDepth.TrueColor else: ColorDepth.Ansi16

proc detectColorDepth*(): ColorDepth = detectColorDepth(proc(name: string): string = getEnv(name))

proc initAnsiBackend*(output: File = stdout, input: File = stdin, alternateScreen = true, rawMode = true,
    colorDepth = detectColorDepth(), synchronizedOutput = true): AnsiBackend =
  ## `colorDepth` downsamples colors the terminal cannot show. `synchronizedOutput` brackets each
  ## frame in DEC mode 2026 so supporting terminals paint it at once; others ignore the mode.
  AnsiBackend(output: output, input: input, alternateScreen: alternateScreen, rawMode: rawMode,
    colorDepth: colorDepth, synchronizedOutput: synchronizedOutput, cursorVisible: true)

proc init*(backend: var AnsiBackend) =
  ## Idempotent. If entering the alternate screen fails, the terminal mode is restored before the
  ## error propagates so the caller's terminal is not left raw.
  if backend.initialized: return
  backend.cursorKnown = false
  backend.synchronizedActive = false
  backend.platformState = configureTerminal(backend.input, backend.output, backend.rawMode)
  try:
    if backend.alternateScreen: writeAll(backend.output, "\e[?1049h")
    backend.output.flushFile()
    backend.initialized = true
  except CatchableError:
    try: restoreTerminal(backend.platformState)
    except CatchableError: discard
    raise

proc restore*(backend: var AnsiBackend) =
  ## Ends any open synchronized update, then resets styling and cursor visibility before leaving
  ## alternate screen and raw mode.
  if not backend.initialized and not backend.platformState.configured: return
  backend.initialized = false
  var failure: ref CatchableError
  try:
    if backend.synchronizedActive:
      writeAll(backend.output, EndSynchronizedUpdate); backend.synchronizedActive = false
    writeAll(backend.output, "\e[0m\e[?25h")
    if backend.alternateScreen: writeAll(backend.output, "\e[?1049l")
    backend.output.flushFile()
  except CatchableError as e: failure = e
  try: restoreTerminal(backend.platformState)
  except CatchableError as e:
    if failure.isNil: failure = e
  if not failure.isNil: raise failure

# Palette slot for the 16 named colors; SGR builds the final code from it.

func namedIndex(c: ColorKind): int =
  case c
  of ColorKind.Black: 0
  of ColorKind.Red: 1
  of ColorKind.Green: 2
  of ColorKind.Yellow: 3
  of ColorKind.Blue: 4
  of ColorKind.Magenta: 5
  of ColorKind.Cyan: 6
  of ColorKind.Gray: 7
  of ColorKind.DarkGray: 8
  of ColorKind.LightRed: 9
  of ColorKind.LightGreen: 10
  of ColorKind.LightYellow: 11
  of ColorKind.LightBlue: 12
  of ColorKind.LightMagenta: 13
  of ColorKind.LightCyan: 14
  of ColorKind.White: 15
  else: 0

proc addColor(parts: var seq[string], c: Color, foreground: bool) =
  case c.kind
  of ColorKind.Reset: parts.add(if foreground: "39" else: "49")
  of ColorKind.Indexed: parts.add((if foreground: "38;5;" else: "48;5;") & $c.index)
  of ColorKind.Rgb: parts.add((if foreground: "38;2;" else: "48;2;") & $c.r & ";" & $c.g & ";" & $c.b)
  else:
    # 30..37/40..47 hold the first eight colors, 90..97/100..107 the bright ones.
    let index = namedIndex(c.kind)
    parts.add($(if index < 8: (if foreground: 30 else: 40)+index else: (if foreground: 90 else: 100)+index-8))

proc addUnderlineColor(parts: var seq[string], c: Color) =
  case c.kind
  of ColorKind.Reset: parts.add("59")
  of ColorKind.Indexed: parts.add("58;5;" & $c.index)
  of ColorKind.Rgb: parts.add("58;2;" & $c.r & ";" & $c.g & ";" & $c.b)
  else: parts.add("58;5;" & $namedIndex(c.kind))

func downsampled(cell: Cell, depth: ColorDepth): Cell =
  result = cell
  result.fg = downsample(cell.fg, depth)
  result.bg = downsample(cell.bg, depth)
  result.underlineColor = downsample(cell.underlineColor, depth)

func fullStyle(cell: Cell): string =
  # The leading reset already restores default colors, so Reset colors add no parameters.
  var parts = @["0"]
  if cell.fg.kind != ColorKind.Reset: parts.addColor(cell.fg, true)
  if cell.bg.kind != ColorKind.Reset: parts.addColor(cell.bg, false)
  if cell.underlineColor.kind != ColorKind.Reset: parts.addUnderlineColor(cell.underlineColor)
  for (modifier, code) in [(Modifier.Bold, "1"), (Modifier.Dim, "2"), (Modifier.Italic, "3"), (Modifier.Underlined, "4"),
      (Modifier.SlowBlink, "5"), (Modifier.RapidBlink, "6"), (Modifier.Reversed, "7"), (Modifier.Hidden, "8"), (Modifier.CrossedOut, "9")]:
    if modifier in cell.modifiers: parts.add(code)
  "\e[" & parts.join(";") & "m"

func styleChange(previous, cell: Cell): string =
  # Both cells are already downsampled. Equal styles need nothing; changed colors alone are set
  # directly. Removing a modifier has no general single-attribute undo (22 clears both bold and
  # dim), so modifier changes fall back to a complete reset sequence.
  if previous.modifiers != cell.modifiers: return fullStyle(cell)
  var parts: seq[string]
  if previous.fg != cell.fg: parts.addColor(cell.fg, true)
  if previous.bg != cell.bg: parts.addColor(cell.bg, false)
  if previous.underlineColor != cell.underlineColor: parts.addUnderlineColor(cell.underlineColor)
  if parts.len > 0: "\e[" & parts.join(";") & "m" else: ""

func ansiStyle*(cell: Cell, depth: ColorDepth): string =
  ## Complete SGR sequence for a cell at `depth`. It always starts with a reset, so the result
  ## does not depend on earlier output.
  fullStyle(cell.downsampled(depth))

func ansiStyle*(cell: Cell): string = ansiStyle(cell, ColorDepth.TrueColor)

func cursorMove(position: Position): string =
  ## CUP is 1-based, unlike Canopy's 0-based positions.
  "\e[" & $(position.y+1) & ";" & $(position.x+1) & "H"

proc setCursorPosition*(backend: var AnsiBackend, position: Position) =
  let position = initPosition(max(0, position.x), max(0, position.y))
  writeAll(backend.output, cursorMove(position))
  backend.cursor = position
  backend.cursorKnown = true

proc draw*(backend: var AnsiBackend, updates: openArray[CellUpdate]) =
  ## Writes changed cells in one write. A cursor move is emitted only when a cell does not follow
  ## the previous single-width cell on the same row, and SGR only when the style changes. Both
  ## start unknown on every call, so output written between draws cannot desynchronize them.
  ## With `synchronizedOutput`, the first cell opens a synchronized update that `flush` closes.
  var output = ""
  var previous: Cell
  var written, opened, anchored = false
  var next, last: Position
  for update in updates:
    if update.cell.diffKind == CellDiffKind.Skip or (update.cell.skip and update.cell.diffKind == CellDiffKind.Normal): continue
    if not written and backend.synchronizedOutput and not backend.synchronizedActive:
      output.add(BeginSynchronizedUpdate); opened = true
    let position = initPosition(max(0, update.x), max(0, update.y))
    if not anchored or position != next: output.add(cursorMove(position))
    let cell = update.cell.downsampled(backend.colorDepth)
    output.add(if written: styleChange(previous, cell) else: fullStyle(cell))
    output.add(update.cell.symbol)
    # Re-anchor after wide or width-forced cells: the terminal's idea of their width may differ.
    let width = update.cell.cellWidth
    anchored = width == 1 and update.cell.diffKind != CellDiffKind.ForcedWidth
    next = initPosition(position.x+1, position.y)
    last = initPosition(position.x+width, position.y)
    previous = cell; written = true
  if not written: return
  # Marked open before writing: if the write fails part way, `flush` or `restore` still closes
  # it, and closing an update that never opened is harmless.
  if opened: backend.synchronizedActive = true
  writeAll(backend.output, output)
  backend.cursor = last
  backend.cursorKnown = true

proc flush*(backend: var AnsiBackend) =
  ## Closes a synchronized update opened by `draw`, then flushes the output file.
  if backend.synchronizedActive:
    writeAll(backend.output, EndSynchronizedUpdate); backend.synchronizedActive = false
  backend.output.flushFile()

proc size*(backend: var AnsiBackend): Size = terminalSize(backend.output)
proc windowSize*(backend: var AnsiBackend): WindowSize = terminalWindowSize(backend.output)
proc getCursorPosition*(backend: var AnsiBackend): Position =
  if not backend.cursorKnown:
    backend.cursor = terminalCursorPosition(backend.input, backend.output)
    backend.cursorKnown = true
  backend.cursor

proc hideCursor*(backend: var AnsiBackend) =
  writeAll(backend.output, "\e[?25l"); backend.cursorVisible = false

proc showCursor*(backend: var AnsiBackend) =
  writeAll(backend.output, "\e[?25h"); backend.cursorVisible = true

proc clear*(backend: var AnsiBackend) =
  writeAll(backend.output, "\e[2J\e[H"); backend.cursor = initPosition(0, 0); backend.cursorKnown = true

proc clearRegion*(backend: var AnsiBackend, kind: ClearType) =
  writeAll(backend.output, case kind
    of ClearType.All: "\e[2J"
    of ClearType.AfterCursor: "\e[0J"
    of ClearType.BeforeCursor: "\e[1J"
    of ClearType.CurrentLine: "\e[2K"
    of ClearType.UntilNewLine: "\e[0K")

proc clearRegion*(backend: var AnsiBackend, area: Rect) =
  if area.isEmpty: return
  let spaces = repeat(' ', area.width)
  for y in area.y..<area.bottom:
    backend.setCursorPosition(initPosition(area.x, y)); writeAll(backend.output, "\e[0m" & spaces)
  backend.setCursorPosition(initPosition(area.x, area.y))

proc scrollRegionUp*(backend: var AnsiBackend, top, bottom, lines: int) =
  ## Scrolls rows `top`..`bottom` and resets the scroll region afterwards, leaving the rest of the
  ## screen unaffected.
  let top = max(0, top); let bottom = max(top, bottom); let lines = clamp(lines, 0, bottom-top)
  if lines == 0: return
  writeAll(backend.output, "\e[" & $(top+1) & ";" & $bottom & "r\e[" & $lines & "S\e[r")
  backend.output.flushFile()

proc scrollRegionDown*(backend: var AnsiBackend, top, bottom, lines: int) =
  let top = max(0, top); let bottom = max(top, bottom); let lines = clamp(lines, 0, bottom-top)
  if lines == 0: return
  writeAll(backend.output, "\e[" & $(top+1) & ";" & $bottom & "r\e[" & $lines & "T\e[r")
  backend.output.flushFile()

proc appendLines*(backend: var AnsiBackend, lines: int) =
  ## Writes newlines to scroll the viewport, then re-derives the cursor from the terminal size
  ## because the terminal, not the backend, decides how far the content moved.
  if lines <= 0: return
  writeAll(backend.output, repeat('\n', lines))
  backend.output.flushFile()
  let dimensions = backend.size
  backend.cursor = initPosition(min(max(0, dimensions.width-1), backend.cursor.x+1), min(max(0, dimensions.height-1), backend.cursor.y+lines))
