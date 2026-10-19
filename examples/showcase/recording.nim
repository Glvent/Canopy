## A custom backend: an adapter that wraps any backend and counts the cells each draw sends.
## Backends are plain objects with these procedures; there is no base type to inherit.
import canopy

type RecordingBackend*[B] = object
  inner*: B
  cellUpdates*: int

proc initRecordingBackend*[B](inner: sink B): RecordingBackend[B] = RecordingBackend[B](inner: inner)

proc init*[B](b: var RecordingBackend[B]) = (mixin init; init(b.inner))
proc restore*[B](b: var RecordingBackend[B]) = (mixin restore; restore(b.inner))
proc size*[B](b: var RecordingBackend[B]): Size = (mixin size; size(b.inner))
proc windowSize*[B](b: var RecordingBackend[B]): WindowSize = (mixin windowSize; windowSize(b.inner))
proc draw*[B](b: var RecordingBackend[B], updates: openArray[CellUpdate]) =
  mixin draw
  b.cellUpdates += updates.len
  draw(b.inner, updates)

proc flush*[B](b: var RecordingBackend[B]) = (mixin flush; flush(b.inner))
proc clear*[B](b: var RecordingBackend[B]) = (mixin clear; clear(b.inner))
proc clearRegion*[B](b: var RecordingBackend[B], area: Rect) = (mixin clearRegion; clearRegion(b.inner, area))
proc clearRegion*[B](b: var RecordingBackend[B], kind: ClearType) = (mixin clearRegion; clearRegion(b.inner, kind))
proc getCursorPosition*[B](b: var RecordingBackend[B]): Position =
  mixin getCursorPosition
  getCursorPosition(b.inner)

proc setCursorPosition*[B](b: var RecordingBackend[B], p: Position) =
  mixin setCursorPosition
  setCursorPosition(b.inner, p)

proc hideCursor*[B](b: var RecordingBackend[B]) = (mixin hideCursor; hideCursor(b.inner))
proc showCursor*[B](b: var RecordingBackend[B]) = (mixin showCursor; showCursor(b.inner))
proc appendLines*[B](b: var RecordingBackend[B], n: int) = (mixin appendLines; appendLines(b.inner, n))
proc scrollRegionUp*[B](b: var RecordingBackend[B], top, bottom, n: int) =
  mixin scrollRegionUp
  scrollRegionUp(b.inner, top, bottom, n)

proc scrollRegionDown*[B](b: var RecordingBackend[B], top, bottom, n: int) =
  mixin scrollRegionDown
  scrollRegionDown(b.inner, top, bottom, n)
