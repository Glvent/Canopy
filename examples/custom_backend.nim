## An adapter can intercept output while delegating storage to another backend.
import canopy

type RecordingBackend = object
  storage: TestBackend
  changedCells: int

proc init(b: var RecordingBackend) = b.storage.init()
proc restore(b: var RecordingBackend) = b.storage.restore()
proc size(b: var RecordingBackend): Size = b.storage.size()
proc draw(b: var RecordingBackend, updates: openArray[CellUpdate]) =
  b.changedCells += updates.len
  b.storage.draw(updates)

proc flush(b: var RecordingBackend) = b.storage.flush()
proc clear(b: var RecordingBackend) = b.storage.clear()
proc clearRegion(b: var RecordingBackend, area: Rect) = b.storage.clearRegion(area)
proc getCursorPosition(b: var RecordingBackend): Position = b.storage.getCursorPosition()
proc setCursorPosition(b: var RecordingBackend, p: Position) = b.storage.setCursorPosition(p)
proc hideCursor(b: var RecordingBackend) = b.storage.hideCursor()
proc showCursor(b: var RecordingBackend) = b.storage.showCursor()
proc appendLines(b: var RecordingBackend, n: int) = b.storage.appendLines(n)
proc scrollRegionUp(b: var RecordingBackend, top, bottom, n: int) = b.storage.scrollRegionUp(top, bottom, n)
proc scrollRegionDown(b: var RecordingBackend, top, bottom, n: int) = b.storage.scrollRegionDown(
    top, bottom, n)

withTerminal(terminal, RecordingBackend(storage: initTestBackend(20, 2))):
  for i in 0..<2:
    discard terminal.draw(proc(frame: var Frame) = frame.renderWidget(initLine("Hello backend"), frame.area))
  echo terminal.backend.changedCells, " cell updates across two identical frames"
