## Input events: keys with modifiers, mouse buttons, drags and wheel, bracketed paste, focus
## and resize. Input is a separate import and stays owned by the application.
import std/[monotimes, strutils]

import canopy
import canopy/runtime/terminal/input
import common

const
  help* = "Press keys, click, drag, scroll, paste or switch windows · c: clear log"
  maxLog = 200

var
  log: seq[string]
  pointer = none(Position)
  pointerArea: Rect
  counts: array[input.EventKind, int]

proc describe(event: input.Event): string =
  case event.kind
  of input.EventKind.Key:
    var mods: seq[string]
    for m in event.key.modifiers: mods.add($m)
    result = "Key " & $event.key.kind & " " & $event.key.code
    if event.key.text.len > 0: result.add(" " & escape(event.key.text))
    if mods.len > 0: result.add(" [" & mods.join("+") & "]")
  of input.EventKind.Mouse:
    result = "Mouse " & $event.mouse.kind & " at " & $event.mouse.column & "," & $event.mouse.row
    if event.mouse.button.isSome: result.add(" " & $event.mouse.button.get)
  of input.EventKind.Resize: result = "Resize " & $event.width & "×" & $event.height
  of input.EventKind.Paste: result = "Paste " & $event.text.len & " bytes: " & escape(event.text)
  of input.EventKind.FocusGained: result = "Focus gained"
  of input.EventKind.FocusLost: result = "Focus lost"
  of input.EventKind.Unsupported: result = "Unsupported sequence " & escape(event.raw)

proc record*(event: input.Event) =
  ## Called for every event, so the log also shows keys the app handles globally.
  inc counts[event.kind]
  log.add(describe(event))
  if log.len > maxLog: log.delete(0)
  if event.kind == input.EventKind.Mouse:
    pointer = some(initPosition(event.mouse.column, event.mouse.row))

proc render*(frame: var Frame, area: Rect) =
  let columns = horizontal([fill(), length(32)]).split(area)
  let logBlock = panel("Event log · newest first")
  let visible = logBlock.inner(columns[0]).height
  var lines: seq[Line]
  for i in countdown(log.high, max(0, log.len - visible)):
    lines.add(initLine(log[i]).patchStyle(if i == log.high: accent().bold() else: initStyle()))
  if lines.len == 0: lines.add(initLine(initSpan("Waiting for input…", initStyle().dim())))
  frame.renderWidget(initParagraph(initText(lines)).withBlock(logBlock), columns[0])

  let side = vertical([length(9), fill()]).split(columns[1])
  var rows: seq[Row]
  for kind in input.EventKind: rows.add(initRow([$kind, $counts[kind]]))
  frame.renderWidget(initTable(rows, [fill(), length(6)])
    .withBlock(panel("Event counts")), side[0])
  let trackBlock = panel("Pointer")
  pointerArea = trackBlock.inner(side[1])
  frame.renderWidget(trackBlock, side[1])
  if pointer.isSome:
    let p = pointer.get
    frame.renderWidget(initParagraph("Last pointer: " & $p.x & "," & $p.y &
      "\nMove into this box and click.").withWrap(true), pointerArea)
    if pointerArea.contains(p):
      frame.buffer[][p.x, p.y].setSymbol("◆")
      frame.buffer[][p.x, p.y].setStyle(accent().bold())

proc handle*(event: input.Event): bool =
  if event.isPress and event.key.text == "c":
    log.setLen(0)
    for kind in input.EventKind: counts[kind] = 0
    return true
  false

proc update*(now: MonoTime, active: bool): int = -1
