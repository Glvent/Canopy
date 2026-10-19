## ANSI backend draw and terminal mode tests.
import std/[os, tables, unittest]

import ../src/canopy/core/layout/geometry
import ../src/canopy/core/styling/style
import ../src/canopy/core/rendering/buffer
import ../src/canopy/runtime/backends/ansi

proc tempFile(): tuple[path: string, file: File] =
  result.path = getTempDir()/"canopy-ansi-test.tmp"
  check open(result.file, result.path, fmReadWrite)

proc readOnlyTemp(): tuple[path: string, file: File] =
  result.path = getTempDir()/"canopy-ansi-read-only.tmp"
  writeFile(result.path, "")
  check open(result.file, result.path, fmRead)

proc contents(file: File): string =
  file.flushFile(); file.setFilePos(0); file.readAll()

proc styled(symbol: string, fg = color(ColorKind.Reset), bg = color(ColorKind.Reset), modifiers: Modifiers = {}): Cell =
  result = initCell(symbol); result.fg = fg; result.bg = bg; result.modifiers = modifiers

proc environment(pairs: openArray[(string, string)]): proc(name: string): string =
  let table = pairs.toTable
  result = proc(name: string): string = table.getOrDefault(name)

suite "ANSI backend":
  test "encodes complete styles and cell updates":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, alternateScreen = false, rawMode = false,
      colorDepth = ColorDepth.TrueColor, synchronizedOutput = false)
    var c = initCell("界"); c.fg = rgbColor(1, 2, 3); c.bg = indexedColor(17); c.underlineColor = color(ColorKind.LightCyan)
    c.modifiers = {Modifier.Bold, Modifier.Italic, Modifier.Underlined, Modifier.CrossedOut}
    backend.draw([(x: 2, y: 3, cell: c)])
    check tmp.file.contents == "\e[4;3H\e[0;38;2;1;2;3;48;5;17;58;5;14;1;3;4;9m界"
    check backend.getCursorPosition == initPosition(4, 3)

  test "consecutive cells share cursor moves and styles":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false, ColorDepth.TrueColor, false)
    let red = color(ColorKind.Red); let blue = color(ColorKind.Blue)
    backend.draw([(x: 0, y: 0, cell: styled("a", red)), (x: 1, y: 0, cell: styled("b", red)),
      (x: 2, y: 0, cell: styled("c", blue)), (x: 5, y: 0, cell: styled("d", blue)),
      (x: 0, y: 1, cell: styled("e", blue, modifiers = {Modifier.Bold}))])
    check tmp.file.contents == "\e[1;1H\e[0;31mab\e[34mc\e[1;6Hd\e[2;1H\e[0;34;1me"
    check backend.getCursorPosition == initPosition(1, 1)

  test "wide cells re-anchor the cursor and colors return to defaults":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false, ColorDepth.TrueColor, false)
    backend.draw([(x: 0, y: 0, cell: styled("界", color(ColorKind.Red), color(ColorKind.Blue))),
      (x: 2, y: 0, cell: styled("x"))])
    check tmp.file.contents == "\e[1;1H\e[0;31;44m界\e[1;3H\e[39;49mx"
    check backend.getCursorPosition == initPosition(3, 0)
    check ansiStyle(initCell("x")) == "\e[0m"

  test "synchronized output brackets draw through flush and restore":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false, ColorDepth.TrueColor)
    backend.init()
    backend.draw([(x: 0, y: 0, cell: initCell("a"))]); backend.hideCursor(); backend.flush(); backend.flush()
    backend.draw([]); backend.draw([(x: 1, y: 0, cell: initCell("b"))]); backend.restore()
    check tmp.file.contents == "\e[?2026h\e[1;1H\e[0ma\e[?25l\e[?2026l" &
      "\e[?2026h\e[1;2H\e[0mb\e[?2026l\e[0m\e[?25h"

  test "colors are downsampled to the configured depth":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false, ColorDepth.Ansi256, false)
    # Both reds map to palette entry 196, so the second cell needs no SGR.
    backend.draw([(x: 0, y: 0, cell: styled("a", rgbColor(255, 0, 0))), (x: 1, y: 0, cell: styled("b", rgbColor(250, 5, 5)))])
    check tmp.file.contents == "\e[1;1H\e[0;38;5;196mab"
    let cell = styled("x", rgbColor(1, 2, 3), indexedColor(17), {Modifier.Bold})
    check ansiStyle(cell, ColorDepth.Ansi16) == "\e[0;30;40;1m"
    check ansiStyle(cell, ColorDepth.Monochrome) == "\e[0;1m"

  test "nearest palette colors":
    check nearestAnsi256(255, 0, 0) == 196 and nearestAnsi256(95, 135, 175) == 67
    check nearestAnsi256(0, 0, 0) == 16 and nearestAnsi256(255, 255, 255) == 231
    check nearestAnsi256(128, 128, 128) == 244 and nearestAnsi256(238, 238, 238) == 255
    check nearestAnsi256(10, 10, 10) == 232
    check nearestAnsi16(250, 10, 10) == color(ColorKind.LightRed) and nearestAnsi16(200, 0, 0) == color(ColorKind.Red)
    check nearestAnsi16(128, 128, 128) == color(ColorKind.DarkGray)
    check nearestAnsi16(0, 0, 0) == color(ColorKind.Black) and nearestAnsi16(255, 255, 255) == color(ColorKind.White)
    check paletteRgb(67) == [95'u8, 135, 175] and paletteRgb(244) == [128'u8, 128, 128] and paletteRgb(9) == [255'u8, 0, 0]
    check downsample(indexedColor(9), ColorDepth.Ansi16) == color(ColorKind.LightRed)
    check downsample(indexedColor(196), ColorDepth.Ansi16) == color(ColorKind.LightRed)
    check downsample(indexedColor(17), ColorDepth.Ansi256) == indexedColor(17)
    check downsample(rgbColor(255, 0, 0), ColorDepth.Ansi256) == indexedColor(196)
    check downsample(rgbColor(1, 2, 3), ColorDepth.TrueColor) == rgbColor(1, 2, 3)
    check downsample(color(ColorKind.Red), ColorDepth.Ansi16) == color(ColorKind.Red)
    check downsample(color(ColorKind.Red), ColorDepth.Monochrome) == color(ColorKind.Reset)

  test "color depth follows environment conventions":
    check detectColorDepth(environment({"NO_COLOR": "1", "COLORTERM": "truecolor"})) == ColorDepth.Monochrome
    check detectColorDepth(environment({"NO_COLOR": "", "COLORTERM": "truecolor"})) == ColorDepth.TrueColor
    check detectColorDepth(environment({"TERM": "dumb", "COLORTERM": "truecolor"})) == ColorDepth.Monochrome
    check detectColorDepth(environment({"TERM": "xterm", "COLORTERM": "24bit"})) == ColorDepth.TrueColor
    check detectColorDepth(environment({"TERM": "xterm-kitty"})) == ColorDepth.TrueColor
    check detectColorDepth(environment({"TERM": "xterm-direct"})) == ColorDepth.TrueColor
    check detectColorDepth(environment({"TERM": "xterm-256color", "TERM_PROGRAM": "iTerm.app"})) == ColorDepth.TrueColor
    check detectColorDepth(environment({"TERM": "xterm-256color", "WT_SESSION": "1"})) == ColorDepth.TrueColor
    check detectColorDepth(environment({"TERM": "screen-256color"})) == ColorDepth.Ansi256
    check detectColorDepth(environment({"TERM": "xterm"})) == ColorDepth.Ansi16
    check detectColorDepth(environment([])) == (when defined(windows): ColorDepth.TrueColor else: ColorDepth.Ansi16)

  test "skip cells produce no bytes":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false); var c = initCell("x"); c.diffKind = CellDiffKind.Skip
    backend.draw([(x: 0, y: 0, cell: c)]); check tmp.file.contents == ""

  test "init and restore are idempotent and honor alternate screen":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, true, false)
    backend.init(); backend.init(); backend.hideCursor(); backend.restore(); backend.restore()
    check tmp.file.contents == "\e[?1049h\e[?25l\e[0m\e[?25h\e[?1049l"

  test "clear, region scrolling, and append emit VT commands":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false)
    backend.clear(); backend.clearRegion(initRect(2, 1, 3, 2)); backend.scrollRegionUp(1, 5, 2); backend.scrollRegionDown(0, 4, 1); backend.appendLines(2)
    check tmp.file.contents == "\e[2J\e[H\e[2;3H\e[0m   \e[3;3H\e[0m   \e[2;3H\e[2;5r\e[2S\e[r\e[1;4r\e[1T\e[r\n\n"
    check backend.cursor == initPosition(3, 3)

  test "backend clear types and window dimensions are available":
    let tmp = tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false)
    backend.clearRegion(ClearType.All); backend.clearRegion(ClearType.AfterCursor)
    backend.clearRegion(ClearType.BeforeCursor); backend.clearRegion(ClearType.CurrentLine)
    backend.clearRegion(ClearType.UntilNewLine)
    check tmp.file.contents == "\e[2J\e[0J\e[1J\e[2K\e[0K"
    check backend.windowSize.columnsRows == initSize(80, 24)

  test "read-only output errors propagate":
    let tmp = readOnlyTemp()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, false, false)
    expect IOError: backend.showCursor()

  test "failed initialization rolls native state back":
    let tmp = readOnlyTemp()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend = initAnsiBackend(tmp.file, tmp.file, true, false)
    expect IOError: backend.init()
    check not backend.initialized
    backend.restore()
