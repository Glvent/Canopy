## Terminal output parity against reference harness.
import std/[json, os, options, strformat, strutils, unittest]

import ../src/canopy/runtime/terminal/index as terminal
import ../src/canopy/core/styling/style
import ../src/canopy/runtime/backends/test

const Fixture = currentSourcePath.parentDir / "fixtures" / "terminal.json"

proc rectJson(area: Rect): JsonNode =
  %* {"x": area.x, "y": area.y, "width": area.width, "height": area.height}

proc colorJson(c: Color): JsonNode =
  case c.kind
  of ColorKind.Indexed: %* {"kind": "indexed", "index": int(c.index)}
  of ColorKind.Rgb: %* {"kind": "rgb", "r": int(c.r), "g": int(c.g), "b": int(c.b)}
  else:
    let name = case c.kind
      of ColorKind.Reset: "reset"
      of ColorKind.Black: "black"
      of ColorKind.Red: "red"
      of ColorKind.Green: "green"
      of ColorKind.Yellow: "yellow"
      of ColorKind.Blue: "blue"
      of ColorKind.Magenta: "magenta"
      of ColorKind.Cyan: "cyan"
      of ColorKind.Gray: "gray"
      of ColorKind.DarkGray: "darkGray"
      of ColorKind.LightRed: "lightRed"
      of ColorKind.LightGreen: "lightGreen"
      of ColorKind.LightYellow: "lightYellow"
      of ColorKind.LightBlue: "lightBlue"
      of ColorKind.LightMagenta: "lightMagenta"
      of ColorKind.LightCyan: "lightCyan"
      of ColorKind.White: "white"
      else: raise newException(ValueError, "unexpected color")
    %* {"kind": "named", "name": name}

proc modifiersJson(modifiers: Modifiers): JsonNode =
  result = newJArray()
  for item in [
    (Modifier.Bold, "bold"), (Modifier.Dim, "dim"),
    (Modifier.Italic, "italic"), (Modifier.Underlined, "underlined"),
    (Modifier.SlowBlink, "slowBlink"), (Modifier.RapidBlink, "rapidBlink"),
    (Modifier.Reversed, "reversed"), (Modifier.Hidden, "hidden"),
    (Modifier.CrossedOut, "crossedOut")]:
    if item[0] in modifiers: result.add(%item[1])

proc cellJson(cell: Cell): JsonNode =
  let diffOption = case cell.diffKind
    of CellDiffKind.Normal: %* {"kind": "none"}
    of CellDiffKind.Skip: %* {"kind": "skip"}
    of CellDiffKind.AlwaysUpdate: %* {"kind": "alwaysUpdate"}
    of CellDiffKind.ForcedWidth: %* {"kind": "forcedWidth", "width": cell.forcedWidth}
  %* {"symbol": cell.symbol, "fg": colorJson(cell.fg), "bg": colorJson(cell.bg),
      "underlineColor": colorJson(cell.underlineColor),
      "modifiers": modifiersJson(cell.modifiers), "skip": cell.skip,
      "diffOption": diffOption}

proc bufferJson(buffer: Buffer): JsonNode =
  result = %* {"area": rectJson(buffer.area), "cells": newJArray()}
  for cell in buffer.content: result["cells"].add(cellJson(cell))

proc scrollbackJson(backend: TestBackend): JsonNode =
  let width = backend.buffer.area.width
  result = %* {"area": rectJson(initRect(0, 0, width, backend.scrollback.len)),
      "cells": newJArray()}
  for row in backend.scrollback:
    for x in 0..<width:
      result["cells"].add(cellJson(if x < row.len: row[x] else: initCell()))

proc fillCell(cell: var Cell, tag, x, y: int) =
  var modifiers: Modifiers
  if (tag + x + y) mod 3 == 0: modifiers.incl Modifier.Bold
  if (tag + x + y) mod 5 == 0: modifiers.incl Modifier.Italic
  cell = initCell($(char(ord('A') + (tag + x + y * 7) mod 26)))
  cell.fg = indexedColor((tag + x + y) mod 32)
  cell.bg = indexedColor((tag * 3 + y) mod 16)
  cell.underlineColor = indexedColor((tag + x * 2) mod 16)
  cell.modifiers = modifiers

proc fill(buffer: var Buffer, tag: int) =
  let width = max(1, buffer.area.width)
  for i in 0..<buffer.content.len:
    fillCell(buffer.content[i], tag, i mod width, i div width)

proc completedJson(frame: CompletedFrame): JsonNode =
  %* {"buffer": bufferJson(frame.buffer), "area": rectJson(frame.area),
      "count": int(frame.count)}

proc snapshot(terminal: var Terminal[TestBackend], completed = none(JsonNode)): JsonNode =
  let frame = terminal.getFrame()
  result = %* {"viewportArea": rectJson(frame.area), "frameCount": int(frame.count),
      "current": bufferJson(frame.buffer[]),
      "backend": {"buffer": bufferJson(terminal.backend.buffer),
        "scrollback": scrollbackJson(terminal.backend),
        "cursor": {"x": terminal.backend.cursor.x, "y": terminal.backend.cursor.y},
        "cursorVisible": terminal.backend.cursorVisible}}
  if completed.isSome: result["completedFrame"] = completed.get

proc viewportOf(node: JsonNode): Viewport =
  case node["kind"].getStr
  of "fullscreen": fullscreenViewport()
  of "fixed": fixedViewport(initRect(node["x"].getInt, node["y"].getInt,
      node["width"].getInt, node["height"].getInt))
  of "inline": inlineViewport(node["height"].getInt)
  else: raise newException(ValueError, "unknown viewport")

proc applyAction(terminal: var Terminal[TestBackend], action: JsonNode): Option[JsonNode] =
  case action["kind"].getStr
  of "draw":
    let tag = action["tag"].getInt
    let completed = terminal.draw(proc(frame: var Frame) =
      fill(frame.buffer[], tag)
      if action.hasKey("cursor"):
        frame.setCursorPosition(initPosition(action["cursor"]["x"].getInt,
            action["cursor"]["y"].getInt)))
    some(completedJson(completed))
  of "partialDraw":
    let tag = action["tag"].getInt
    let completed = terminal.draw(proc(frame: var Frame) =
      if not frame.area.isEmpty:
        fillCell(frame.buffer[][frame.area.x, frame.area.y], tag, 0, 0))
    some(completedJson(completed))
  of "noopDraw":
    let completed = terminal.draw(proc(frame: var Frame) = discard)
    some(completedJson(completed))
  of "manual":
    fill(terminal.currentBufferMut(), action["tag"].getInt)
    terminal.flush()
    terminal.backend.flush()
    terminal.swapBuffers()
    none(JsonNode)
  of "insertBefore":
    let tag = action["tag"].getInt
    terminal.insertBefore(action["height"].getInt,
      proc(buffer: var Buffer) = fill(buffer, tag))
    none(JsonNode)
  of "resize":
    let width = action["width"].getInt
    let height = action["height"].getInt
    terminal.backend.resize(width, height)
    terminal.resize(initRect(0, 0, width, height))
    none(JsonNode)
  of "clear":
    terminal.clear()
    none(JsonNode)
  else: raise newException(ValueError, "unknown action")

proc firstDifference(actual, expected: JsonNode, path = "$"): string =
  if actual.kind != expected.kind: return &"{path}: kind {actual.kind} != {expected.kind}"
  case actual.kind
  of JObject:
    for key, value in expected:
      if not actual.hasKey(key): return &"{path}: missing {key}"
      let difference = firstDifference(actual[key], value, path & "." & key)
      if difference.len > 0: return difference
    for key, unused in actual:
      if not expected.hasKey(key): return &"{path}: unexpected {key}"
  of JArray:
    if actual.len != expected.len: return &"{path}: length {actual.len} != {expected.len}"
    for i in 0..<actual.len:
      let difference = firstDifference(actual[i], expected[i], &"{path}[{i}]")
      if difference.len > 0: return difference
  else:
    if actual != expected: return &"{path}: {actual} != {expected}"

proc runCase(testCase: JsonNode): seq[string] =
  let input = testCase["input"]
  var backend = initTestBackend(input["screen"]["width"].getInt,
      input["screen"]["height"].getInt)
  fill(backend.buffer, input["initialTag"].getInt)
  backend.cursor = initPosition(input["cursor"]["x"].getInt,
      input["cursor"]["y"].getInt)
  backend.cursorVisible = input["cursorVisible"].getBool
  var terminal = initTerminal(backend, viewportOf(input["viewport"]))
  var actual = snapshot(terminal)
  var difference = firstDifference(actual, testCase["expected"][0])
  if difference.len > 0:
    result.add(testCase["name"].getStr & " init " & difference)
  for i in 0..<input["actions"].len:
    let action = input["actions"][i]
    let completed = applyAction(terminal, action)
    actual = snapshot(terminal, completed)
    difference = firstDifference(actual, testCase["expected"][i + 1])
    if difference.len > 0:
      result.add(
        testCase["name"].getStr & " action " & $i & " " & action["kind"].getStr & " " & difference)

suite "pinned Ratatui terminal reference":
  test "all terminal state transitions match complete snapshots":
    let fixture = parseFile(Fixture)
    check fixture["schemaVersion"].getInt == 1
    check fixture["oracle"]["version"].getStr == "0.1.2"
    check fixture["cases"].len >= 100
    var errors: seq[string]
    for testCase in fixture["cases"]:
      errors.add(runCase(testCase))
    if errors.len > 0: checkpoint errors.join("\n")
    check errors.len == 0
