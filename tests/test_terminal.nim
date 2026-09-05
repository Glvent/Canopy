import std/unittest
import canopy/[terminal, style]
import canopy/backends/test
import "canopy/widgets/block"

proc hello(frame: var Frame) = frame.renderWidget(initLine("hello"),frame.area)
suite "transactional terminal":
  test "frame counter wraps without disrupting the committed frame":
    withTerminal(terminal,initTestBackend(2,1)):
      terminal.frameCount = high(uint64)
      let completed = terminal.draw(proc(frame:var Frame) =
        frame.renderWidget(initLine("x"),frame.area))
      check completed.count == high(uint64)
      check terminal.frameCount == 0
      terminal.backend.resetHistory()
      discard terminal.draw(proc(frame:var Frame) =
        frame.renderWidget(initLine("x"),frame.area))
      check terminal.backend.updates.len == 0
  test "unchanged frame emits no updates; cursor and frame counters":
    var term = initTerminal(initTestBackend(8,2))
    let first = term.draw(hello)
    check first.count == 0
    term.backend.resetHistory()
    discard term.draw(hello)
    check term.backend.updates.len == 0
    check term.frameCount == 2
    check not term.backend.cursorVisible
    discard term.draw(proc(frame: var Frame) = frame.setCursorPosition(2,1))
    check term.backend.cursor == initPosition(2,1)
    check term.backend.cursorVisible
  test "failed draw and flush never commit, retries repaint":
    var term = initTerminal(initTestBackend(8,2))
    discard term.draw(hello)
    term.backend.failFlush = true
    expect IOError: discard term.draw(proc(frame: var Frame) = frame.renderWidget(initLine("new"),frame.area))
    check term.frameCount == 1
    term.backend.failFlush = false
    term.backend.resetHistory()
    discard term.draw(hello)
    check term.backend.updates.len == 16
    check term.backend.buffer[0,0].symbol == "h"
    term.backend.failDraw = true
    expect IOError: discard term.draw(hello)
    check term.frameCount == 2
  test "resize invalidates, fixed clear preserves outside cells":
    var term = initTerminal(initTestBackend(8,2))
    discard term.draw(hello)
    term.backend.resize(10,3)
    discard term.draw(hello)
    check term.viewportArea == initRect(0,0,10,3)
    var fixed = initTerminal(initTestBackend(10,3),fixedViewport(initRect(2,1,3,1)))
    fixed.backend.buffer.setString(0,0,"outside")
    fixed.clear()
    check fixed.backend.buffer[0,0].symbol == "o"
  test "custom generic widget and scoped restoration":
    var ran = false
    withTerminal(term,initTestBackend(5,3)):
      discard term.draw(proc(frame: var Frame) = frame.renderWidget(borderedBlock(),frame.area))
      check term.backend.buffer[0,0].symbol == "┌"
      ran = true
    check ran
  test "inline insertion moves viewport and preserves inserted content":
    var term = initTerminal(initTestBackend(5,6),inlineViewport(2))
    term.insertBefore(2,proc(b: var Buffer) =
      b.setString(0,0,"one")
      b.setString(0,1,"two"))
    check term.viewportArea.y == 2
    check term.backend.buffer[0,0].symbol == "o"
    check term.backend.buffer[0,1].symbol == "t"
  test "full-height inline insertion preserves display and records all log rows":
    var term = initTerminal(initTestBackend(5,2),inlineViewport(2))
    discard term.draw(proc(frame:var Frame) =
      frame.buffer[].setString(0,0,"first")
      frame.buffer[].setString(0,1,"last"))
    term.insertBefore(7,proc(b:var Buffer) =
      for y in 0..<7: b.setString(0,y,$y))
    check term.backend.scrollback.len == 7
    for y in 0..<7: check term.backend.scrollback[y][0].symbol == $y
    check term.backend.buffer[0,0].symbol == "f"
    check term.backend.buffer[0,1].symbol == "l"
    term.backend.resetHistory()
    discard term.draw(proc(frame:var Frame) =
      frame.buffer[].setString(0,0,"first")
      frame.buffer[].setString(0,1,"last"))
    check term.backend.updates.len == 0
  test "insert failure invalidates and a retry draw restores the committed viewport":
    var term = initTerminal(initTestBackend(5,4),inlineViewport(2))
    discard term.draw(hello)
    term.backend.failFlush = true
    expect IOError: term.insertBefore(1,proc(b:var Buffer) = b.setString(0,0,"log"))
    check term.frameCount == 1
    term.backend.failFlush = false
    term.backend.resetHistory()
    discard term.draw(hello)
    check term.backend.updates.len == 10
  test "cursor and callback failures never commit snapshots":
    var term = initTerminal(initTestBackend(8,2))
    let snapshot = term.draw(hello)
    term.backend.failCursor = true
    expect IOError: discard term.draw(proc(frame:var Frame) = frame.renderWidget(initLine("other"),frame.area))
    check term.frameCount == 1
    term.backend.failCursor = false
    expect ValueError:
      discard term.draw(proc(frame:var Frame) =
        frame.buffer[][0,0].symbol = "!"
        raise newException(ValueError,"callback"))
    check term.frameCount == 1
    check snapshot.buffer[0,0].symbol == "h"
    discard term.draw(hello)
    check term.backend.buffer[0,0].symbol == "h"
  test "manual frame emission requires explicit commit and backend flush":
    var term = initTerminal(initTestBackend(4,2),TerminalOptions(viewport:fullscreenViewport()))
    var frame = term.getFrame()
    frame.bufferMut().setString(0,0,"test")
    term.flush()
    check term.backend.flushCount == 0
    check term.frameCount == 0
    term.backend.flush()
    term.swapBuffers()
    check term.currentBufferMut()[0,0].symbol == " "
    term.setCursorPosition(initPosition(2,1))
    term.clear()
    check term.getCursorPosition() == initPosition(2,1)
    check term.windowSize().columnsRows == initSize(4,2)
  test "applyBuffer presents an externally rendered buffer transactionally":
    var term = initTerminal(initTestBackend(6,4),inlineViewport(2))
    term.currentBufferMut().setString(0,0,"manual")
    let frame = term.applyBufferWithCursor(some(initPosition(2,0)))
    check frame.area == initRect(0,0,6,4)
    check frame.buffer.area == initRect(0,0,6,2)
    check term.frameCount == 1
    check term.backend.cursorVisible
    check term.backend.cursor == initPosition(2,0)
    term.currentBufferMut().setString(0,0,"next")
    term.backend.failFlush = true
    expect IOError: discard term.applyBuffer()
    check term.frameCount == 1
    check term.currentBufferMut()[0,0].symbol == "n"
