## Deterministic in-memory backend with operation history and fault injection.
import ../../core/layout/geometry
import ../../core/rendering/buffer
import ./types
export types

type
  TestBackend* = object
    ## `operations` records backend calls in order so tests can assert on the sequence, and the
    ## `fail*` flags inject errors to exercise recovery paths.
    buffer*: Buffer
    cursor*: Position
    cursorVisible*: bool
    updates*: seq[CellUpdate]
    flushCount*, drawCount*: int
    operations*: seq[string]
    failDraw*, failFlush*, failCursor*: bool
    scrollback*: seq[seq[Cell]]

proc initTestBackend*(width, height: int): TestBackend =
  TestBackend(buffer: initBuffer(initRect(0, 0, width, height)), cursorVisible: true)

proc size*(backend: var TestBackend): Size = initSize(backend.buffer.area.width,
    backend.buffer.area.height)
proc windowSize*(backend: var TestBackend): WindowSize = WindowSize(columnsRows: backend.size(),
    pixels: initSize(640, 480))
proc resize*(backend: var TestBackend, width, height: int) =
  ## Reflows scrollback to the new width the way a terminal would, so tests observe realistic
  ## history after a resize.
  backend.buffer.resize(initRect(0, 0, width, height))
  var cells: seq[Cell]
  for row in backend.scrollback: cells.add(row)
  let columns = backend.buffer.area.width
  cells.setLen(columns*backend.scrollback.len)
  for y in 0..<backend.scrollback.len:
    backend.scrollback[y].setLen(columns)
    for x in 0..<columns: backend.scrollback[y][x] = cells[y*columns+x]

proc draw*(backend: var TestBackend, updates: openArray[CellUpdate]) =
  if backend.failDraw: raise newException(IOError, "Injected draw failure")
  inc backend.drawCount
  backend.operations.add("draw")
  for update in updates:
    if backend.buffer.area.contains(update.x, update.y): backend.buffer[update.x,
        update.y] = update.cell
    backend.updates.add(update)

proc flush*(backend: var TestBackend) =
  if backend.failFlush: raise newException(IOError, "Injected flush failure")
  inc backend.flushCount
  backend.operations.add("flush")

proc getCursorPosition*(backend: var TestBackend): Position = backend.cursor
proc setCursorPosition*(backend: var TestBackend, position: Position) =
  if backend.failCursor: raise newException(IOError, "Injected cursor failure")
  backend.cursor = position
  backend.operations.add("cursor")

proc hideCursor*(backend: var TestBackend) =
  if backend.failCursor: raise newException(IOError, "Injected cursor failure")
  backend.cursorVisible = false

proc showCursor*(backend: var TestBackend) =
  if backend.failCursor: raise newException(IOError, "Injected cursor failure")
  backend.cursorVisible = true

proc clear*(backend: var TestBackend) =
  backend.buffer.reset()
  backend.operations.add("clear")

proc clearRegion*(backend: var TestBackend, area: Rect) =
  for p in area.intersection(backend.buffer.area).positions: backend.buffer[p].reset()

proc clearRegion*(backend: var TestBackend, kind: ClearType) =
  let cursor = backend.cursor
  for p in backend.buffer.area.positions:
    let clear = case kind
      of ClearType.All: true
      of ClearType.AfterCursor: p.y > cursor.y or (p.y == cursor.y and p.x >= cursor.x)
      of ClearType.BeforeCursor: p.y < cursor.y or (p.y == cursor.y and p.x <= cursor.x)
      of ClearType.CurrentLine: p.y == cursor.y
      of ClearType.UntilNewLine: p.y == cursor.y and p.x >= cursor.x
    if clear: backend.buffer[p].reset()

proc scrollRegionUp*(backend: var TestBackend, top, bottom, lines: int) =
  let first = max(0, top)
  let last = min(backend.buffer.area.height, bottom)
  let n = clamp(lines, 0, max(0, last-first))
  # Only content scrolled off the top of the screen enters scrollback.
  for y in first..<first+n:
    var row: seq[Cell]
    for x in 0..<backend.buffer.area.width: row.add(backend.buffer[x, y])
    if first == 0: backend.scrollback.add(row)
  for y in first..<last:
    for x in 0..<backend.buffer.area.width:
      backend.buffer[x, y] = if y+n < last: backend.buffer[x, y+n] else: initCell()
  if first == 0:
    for unused in n..<clamp(lines, 0, MaxCoordinate):
      backend.scrollback.add(newSeq[Cell](backend.buffer.area.width))
    if backend.scrollback.len > MaxCoordinate:
      backend.scrollback = backend.scrollback[backend.scrollback.len-MaxCoordinate..^1]
  backend.operations.add("scrollUp")

proc scrollRegionDown*(backend: var TestBackend, top, bottom, lines: int) =
  let first = max(0, top)
  let last = min(backend.buffer.area.height, bottom)
  let n = clamp(lines, 0, max(0, last-first))
  for y in countdown(last-1, first):
    for x in 0..<backend.buffer.area.width:
      backend.buffer[x, y] = if y-n >= first: backend.buffer[x, y-n] else: initCell()
  backend.operations.add("scrollDown")

proc appendLines*(backend: var TestBackend, lines: int) =
  let overflow = max(0, backend.cursor.y+lines-backend.buffer.area.height+1)
  if overflow > 0: backend.scrollRegionUp(0, backend.buffer.area.height, overflow)
  backend.cursor.y = min(max(0, backend.buffer.area.height-1), backend.cursor.y+max(0, lines))
  backend.cursor.x = min(max(0, backend.buffer.area.width-1), backend.cursor.x+1)

proc init*(backend: var TestBackend) = discard
proc restore*(backend: var TestBackend) = backend.cursorVisible = true
proc resetHistory*(backend: var TestBackend) =
  backend.updates.setLen(0)
  backend.operations.setLen(0)
  backend.drawCount = 0
  backend.flushCount = 0
