## Input parser and poll loop tests.
import std/[options, os, unittest]

import ../src/canopy/runtime/terminal/input

proc pop(parser: var InputParser): Event =
  let event = parser.nextEvent()
  check event.isSome
  event.get

suite "incremental terminal input":
  test "plain Unicode and control keys":
    var p = initInputParser(); p.feed("a界\x01\t\r\x7f")
    let a = p.pop; check a.key.code == KeyCode.Character and a.key.text == "a"
    let wide = p.pop; check wide.key.text == "界"
    let ctrl = p.pop; check ctrl.key.text == "a" and ctrl.key.modifiers == {KeyModifier.Control}
    check p.pop.key.code == KeyCode.Tab; check p.pop.key.code == KeyCode.Enter; check p.pop.key.code == KeyCode.Backspace

  test "fragmented UTF-8 waits and invalid bytes make replacement keys":
    var p = initInputParser(); let bytes = "👩"; p.feed(bytes[0..0]); check p.nextEvent.isNone; check p.pendingBytes == 1
    p.feed(bytes[1..2]); check p.nextEvent.isNone; p.feed(bytes[3..3]); check p.pop.key.text == "👩"
    p.feed([0xF0'u8, 0x28'u8, 0x8C'u8, 0x28'u8]); check p.pop.key.text == "�"; check p.pop.key.text == "("; check p.pop.key.text == "�"; check p.pop.key.text == "("

  test "escape ambiguity and Alt Unicode":
    var p = initInputParser(); p.feed("\e"); check p.nextEvent.isNone; p.finishEscape(); check p.pop.key.code == KeyCode.Escape
    let bytes = "\e界"; p.feed(bytes[0..1]); check p.nextEvent.isNone; p.feed(bytes[2..^1]); let alt = p.pop
    check alt.key.code == KeyCode.Character and alt.key.text == "界" and alt.key.modifiers == {KeyModifier.Alt}

  test "navigation modifiers and function keys":
    var p = initInputParser(); p.feed("\e[A\e[1;6D\e[3~\e[6~\eOP\e[24~\e[Z\e[25~\e[1;2S\e[57387u")
    check p.pop.key.code == KeyCode.Up
    let left = p.pop; check left.key.code == KeyCode.Left and left.key.modifiers == {KeyModifier.Shift, KeyModifier.Control}
    check p.pop.key.code == KeyCode.Delete; check p.pop.key.code == KeyCode.PageDown
    let f1 = p.pop; check f1.key.code == KeyCode.Function and f1.key.functionKey == 1
    let f12 = p.pop; check f12.key.functionKey == 12
    let backtab = p.pop; check backtab.key.code == KeyCode.BackTab and KeyModifier.Shift in backtab.key.modifiers
    check p.pop.key.functionKey == 13
    let shiftedF4 = p.pop; check shiftedF4.key.functionKey == 4 and shiftedF4.key.modifiers == {KeyModifier.Shift}
    check p.pop.key.functionKey == 24

  test "bracketed paste is one event across fragments":
    var p = initInputParser(); p.feed("\e[20"); check p.nextEvent.isNone; p.feed("0~hello\n\e["); check p.nextEvent.isNone
    p.feed("201~x"); let paste = p.pop; check paste.kind == EventKind.Paste and paste.text == "hello\n"; check p.pop.key.text == "x"

  test "SGR mouse supports buttons motion wheels and modifiers":
    var p = initInputParser(); p.feed("\e[<0;11;6M\e[<0;11;6m\e[<52;3;4M\e[<35;8;9M\e[<64;2;2M\e[<67;2;2M\e[<128;1;1M")
    let down = p.pop; check down.mouse.kind == MouseEventKind.Down and down.mouse.button == some(MouseButton.Left) and down.mouse.column == 10 and down.mouse.row == 5
    check p.pop.mouse.kind == MouseEventKind.Up
    let drag = p.pop; check drag.mouse.kind == MouseEventKind.Drag and drag.mouse.button == some(MouseButton.Left) and drag.mouse.modifiers == {KeyModifier.Shift, KeyModifier.Control}
    let moved = p.pop; check moved.mouse.kind == MouseEventKind.Moved and moved.mouse.button.isNone
    check p.pop.mouse.kind == MouseEventKind.ScrollUp; check p.pop.mouse.kind == MouseEventKind.ScrollRight
    check p.pop.mouse.button == some(MouseButton.Other)

  test "legacy mouse protocol":
    var p = initInputParser(); p.feed("\e[M" & $char(32) & $char(38) & $char(36))
    let event = p.pop; check event.kind == EventKind.Mouse and event.mouse.kind == MouseEventKind.Down
    check event.mouse.button == some(MouseButton.Left) and event.mouse.column == 5 and event.mouse.row == 3

  test "focus enhanced keyboard and modifyOtherKeys":
    var p = initInputParser(); p.feed("\e[I\e[O\e[97;5:2u\e[57352;1:3u\e[27;3;120~")
    check p.pop.kind == EventKind.FocusGained; check p.pop.kind == EventKind.FocusLost
    let repeated = p.pop; check repeated.key.text == "a" and repeated.key.kind == KeyEventKind.Repeat and repeated.key.modifiers == {KeyModifier.Control}
    let released = p.pop; check released.key.code == KeyCode.Up and released.key.kind == KeyEventKind.Release
    let modified = p.pop; check modified.key.text == "x" and modified.key.modifiers == {KeyModifier.Alt}

  test "resize injection and unsupported sequences remain distinguishable":
    var p = initInputParser(); p.pushResize(120, 40); let resize = p.pop
    check resize.kind == EventKind.Resize and resize.width == 120 and resize.height == 40
    p.feed("\e[?9999h"); let unknown = p.pop; check unknown.kind == EventKind.Unsupported and unknown.raw == "\e[?9999h"

  test "EOF resolves incomplete sequences without losing their bytes":
    var p = initInputParser(); p.feed("\e[12"); p.finish()
    let sequence = p.pop; check sequence.kind == EventKind.Unsupported and sequence.raw == "\e[12"
    p.feed([0xF0'u8, 0x9F'u8]); p.finish(); check p.pop.key.text == "�"

suite "input lifecycle":
  test "capability setup and cleanup are paired and idempotent":
    let path = getTempDir()/"canopy-input-test.tmp"; var file: File
    check open(file, path, fmReadWrite)
    defer: close(file)
    defer: removeFile(path)
    let caps = InputCapabilities(focusEvents: true, bracketedPaste: true, mouseCapture: true, enhancedKeyboard: true)
    var source = initInput(file, file, caps, false)
    source.init(); source.init(); source.restore(); source.restore()
    file.setFilePos(0)
    check file.readAll() == "\e[?1004h\e[?2004h\e[?1003h\e[?1006h\e[>1u\e[<u\e[?1006l\e[?1003l\e[?2004l\e[?1004l"

  test "failed initialization is safe to restore":
    let path = getTempDir()/"canopy-input-read-only.tmp"; var file: File
    writeFile(path, "")
    check open(file, path, fmRead)
    defer: close(file)
    defer: removeFile(path)
    var source = initInput(file, file, defaultInputCapabilities(), false)
    expect IOError: source.init()
    check not source.initialized
    source.restore()

  test "withInput restores capabilities after an exception":
    let path = getTempDir()/"canopy-input-scope.tmp"; var file: File
    check open(file, path, fmReadWrite)
    defer: close(file)
    defer: removeFile(path)
    expect ValueError:
      withInput(source, initInput(file, file, defaultInputCapabilities(), false)):
        raise newException(ValueError, "test")
    file.setFilePos(0)
    check file.readAll() == "\e[?1004h\e[?2004h\e[?2004l\e[?1004l"
