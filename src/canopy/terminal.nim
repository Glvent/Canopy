## Generic immediate-mode terminal. A frame commits only after successful output.
import std/options
import ./[geometry, buffer]
import ./backends/types
export geometry, buffer
export types

type
  ViewportKind* {.pure.} = enum Fullscreen, Fixed, Inline
  Viewport* = object
    kind*: ViewportKind
    area*: Rect
    height*: int
  TerminalOptions* = object
    viewport*: Viewport
  Frame* = object
    buffer*: ptr Buffer
    area*: Rect
    count*: uint64
    cursorPosition*: Option[Position]
  CompletedFrame* = object
    buffer*: Buffer
    area*: Rect
    count*: uint64
  Terminal*[B] = object
    backend*: B
    viewport*: Viewport
    previous: Buffer
    current: Buffer
    lastSize: Size
    lastArea: Rect
    lastCursor: Position
    viewportArea*: Rect
    frameCount*: uint64
    invalidated: bool
    initialized*: bool

func fullscreenViewport*(): Viewport = Viewport(kind:ViewportKind.Fullscreen)
func fixedViewport*(area: Rect): Viewport = Viewport(kind:ViewportKind.Fixed,area:area)
func inlineViewport*(height:int): Viewport = Viewport(kind:ViewportKind.Inline,height:clamp(height,0,MaxCoordinate))
proc renderWidget*[W](frame: var Frame, widget: W, area: Rect) =
  mixin render
  render(widget,area,frame.buffer[])
proc renderStatefulWidget*[W,S](frame: var Frame, widget: W, area: Rect, state: var S) =
  mixin render
  render(widget,area,frame.buffer[],state)
proc setCursorPosition*(frame: var Frame, position: Position) = frame.cursorPosition = some(position)
proc setCursorPosition*(frame: var Frame, x,y:int) = frame.setCursorPosition(initPosition(x,y))
proc bufferMut*(frame: var Frame): var Buffer = frame.buffer[]

proc inlineArea[B](backend: var B, height:int, dimensions:Size, offset:int): tuple[area:Rect,cursor:Position] =
  mixin getCursorPosition, appendLines
  result.cursor = getCursorPosition(backend)
  let lines = max(0,height-offset-1)
  appendLines(backend,lines)
  let available = max(0,dimensions.height-result.cursor.y-1)
  let row = max(0,max(0,result.cursor.y-max(0,lines-available))-offset)
  result.area = initRect(0,row,dimensions.width,min(height,dimensions.height))

proc initTerminal*[B](backend: sink B, viewport: Viewport = fullscreenViewport()): Terminal[B] =
  mixin init, restore, size, getCursorPosition, appendLines
  result.backend = backend
  result.viewport = viewport
  try:
    init(result.backend)
    result.lastSize = if viewport.kind == ViewportKind.Fixed: viewport.area.asSize else: size(result.backend)
    let screen = initRect(0,0,result.lastSize.width,result.lastSize.height)
    result.lastArea = if viewport.kind == ViewportKind.Fixed: viewport.area else: screen
    case viewport.kind
    of ViewportKind.Fullscreen: result.viewportArea = screen
    of ViewportKind.Fixed:
      result.viewportArea = viewport.area
      result.lastCursor = viewport.area.asPosition
    of ViewportKind.Inline:
      let computed = inlineArea(result.backend,viewport.height,result.lastSize,0)
      result.viewportArea = computed.area
      result.lastCursor = computed.cursor
    result.previous = initBuffer(result.viewportArea)
    result.current = initBuffer(result.viewportArea)
    result.invalidated = false
    result.initialized = true
  except:
    try: restore(result.backend)
    except CatchableError: discard
    raise
proc initTerminal*[B](backend: sink B, options:TerminalOptions): Terminal[B] = initTerminal(backend,options.viewport)
proc restore*[B](terminal: var Terminal[B]) =
  mixin restore
  if terminal.initialized:
    restore(terminal.backend)
    terminal.initialized = false
proc invalidate*[B](terminal: var Terminal[B]) = terminal.invalidated = true
proc setViewportArea[B](terminal: var Terminal[B], area: Rect) =
  terminal.viewportArea = area
  terminal.previous.resize(area)
  terminal.current.resize(area)
  terminal.invalidated = true
proc clearViewport[B](terminal: var Terminal[B]) =
  mixin clear, clearRegion, setCursorPosition, draw, size
  terminal.invalidated = true
  template clearPart(kind:ClearType, area:Rect) =
    when compiles(clearRegion(terminal.backend,kind)): clearRegion(terminal.backend,kind)
    elif compiles(clearRegion(terminal.backend,area)): clearRegion(terminal.backend,area)
    else:
      var updates:seq[CellUpdate]
      for p in area.positions: updates.add((p.x,p.y,initCell()))
      draw(terminal.backend,updates)
  if terminal.viewport.kind == ViewportKind.Fullscreen:
    when compiles(clearRegion(terminal.backend,ClearType.All)): clearRegion(terminal.backend,ClearType.All)
    else: clear(terminal.backend)
  elif terminal.viewport.kind == ViewportKind.Inline:
    setCursorPosition(terminal.backend,terminal.viewportArea.asPosition)
    clearPart(ClearType.AfterCursor,initRect(0,terminal.viewportArea.y,terminal.viewportArea.width,
      max(0,terminal.lastSize.height-terminal.viewportArea.y)))
  elif not terminal.viewportArea.isEmpty:
    let area = terminal.viewportArea
    let dimensions = size(terminal.backend)
    if area.x == 0 and area.width == dimensions.width:
      if area.bottom == dimensions.height:
        setCursorPosition(terminal.backend,area.asPosition)
        clearPart(ClearType.AfterCursor,area)
      else:
        for row in area.rows:
          setCursorPosition(terminal.backend,row.asPosition)
          clearPart(ClearType.CurrentLine,row)
    else:
      var updates:seq[CellUpdate]
      for p in area.positions: updates.add((p.x,p.y,initCell()))
      draw(terminal.backend,updates)
proc clear*[B](terminal: var Terminal[B]) =
  mixin getCursorPosition, setCursorPosition, flush
  let cursor = getCursorPosition(terminal.backend)
  terminal.clearViewport()
  setCursorPosition(terminal.backend,cursor)
  flush(terminal.backend)
proc resize*[B](terminal: var Terminal[B], area: Rect) =
  mixin clear, clearRegion, setCursorPosition
  terminal.invalidated = true
  var next = area
  var cursor = none(Position)
  if terminal.viewport.kind == ViewportKind.Inline:
    let offset = max(0,terminal.lastCursor.y-terminal.viewportArea.y)
    let computed = inlineArea(terminal.backend,terminal.viewport.height,area.asSize,offset)
    next = computed.area
    cursor = some(computed.cursor)
  if next.width < terminal.viewportArea.width:
    next.y = 0
    when compiles(clearRegion(terminal.backend,ClearType.All)): clearRegion(terminal.backend,ClearType.All)
    else: clear(terminal.backend)
  terminal.setViewportArea(next)
  terminal.lastSize = area.asSize
  terminal.lastArea = area
  terminal.clearViewport()
  if cursor.isSome: setCursorPosition(terminal.backend,cursor.get)
proc autoresize*[B](terminal: var Terminal[B]) =
  mixin size
  if terminal.viewport.kind == ViewportKind.Fixed: return
  let dimensions = size(terminal.backend)
  if dimensions != terminal.lastSize: terminal.resize(initRect(0,0,dimensions.width,dimensions.height))
proc size*[B](terminal: var Terminal[B]): Size =
  mixin size
  size(terminal.backend)
proc windowSize*[B](terminal: var Terminal[B]): WindowSize =
  mixin windowSize, size
  when compiles(windowSize(terminal.backend)): windowSize(terminal.backend)
  else: WindowSize(columnsRows:size(terminal.backend))
proc getCursorPosition*[B](terminal: var Terminal[B]): Position =
  mixin getCursorPosition
  getCursorPosition(terminal.backend)
proc setCursorPosition*[B](terminal: var Terminal[B], position:Position) =
  mixin setCursorPosition
  setCursorPosition(terminal.backend,position)
  terminal.lastCursor = position
proc hideCursor*[B](terminal: var Terminal[B]) =
  mixin hideCursor
  hideCursor(terminal.backend)
proc showCursor*[B](terminal: var Terminal[B]) =
  mixin showCursor
  showCursor(terminal.backend)
proc getFrame*[B](terminal: var Terminal[B]): Frame =
  Frame(buffer:addr terminal.current,area:terminal.viewportArea,count:terminal.frameCount)
proc currentBufferMut*[B](terminal: var Terminal[B]): var Buffer = terminal.current
proc flush*[B](terminal: var Terminal[B]) =
  ## Applies cell differences only. Manual users must flush the backend before swapping.
  mixin draw
  var updates:seq[CellUpdate]
  if terminal.invalidated:
    var empty = initBuffer(terminal.current.area)
    for cell in empty.content.mitems: cell.symbol = ""
    updates = diff(empty,terminal.current)
  else: updates = diff(terminal.previous,terminal.current)
  try:
    draw(terminal.backend,updates)
    if updates.len > 0: terminal.lastCursor = initPosition(updates[^1].x,updates[^1].y)
  except:
    terminal.invalidated = true
    raise
proc swapBuffers*[B](terminal: var Terminal[B]) =
  terminal.previous = terminal.current
  terminal.current.reset()
  terminal.invalidated = false
proc applyBufferWithCursor*[B](terminal: var Terminal[B], cursor:Option[Position]): CompletedFrame =
  mixin flush, hideCursor, showCursor, setCursorPosition
  if not terminal.initialized: raise newException(IOError,"Terminal is not initialized")
  try:
    terminal.flush()
    if cursor.isSome:
      showCursor(terminal.backend)
      setCursorPosition(terminal.backend,cursor.get)
      terminal.lastCursor = cursor.get
    else: hideCursor(terminal.backend)
    flush(terminal.backend)
    result = CompletedFrame(buffer:terminal.current,area:terminal.lastArea,count:terminal.frameCount)
    terminal.swapBuffers()
    inc terminal.frameCount
  except:
    terminal.invalidated = true
    raise
proc applyBuffer*[B](terminal: var Terminal[B]): CompletedFrame = terminal.applyBufferWithCursor(none(Position))
proc draw*[B](terminal: var Terminal[B], callback: proc(frame: var Frame) {.closure.}): CompletedFrame =
  if not terminal.initialized: raise newException(IOError,"Terminal is not initialized")
  try:
    terminal.autoresize()
    terminal.current.reset()
    var frame = terminal.getFrame()
    callback(frame)
    result = terminal.applyBufferWithCursor(frame.cursorPosition)
  except:
    terminal.invalidated = true
    raise
proc insertBefore*[B](terminal: var Terminal[B], height:int, callback: proc(buffer: var Buffer) {.closure.}) =
  ## Inserts lines above an inline viewport using scrolling regions, preserving its cells.
  mixin draw, flush, scrollRegionUp, scrollRegionDown
  if terminal.viewport.kind != ViewportKind.Inline: return
  var content = initBuffer(initRect(0,0,terminal.viewportArea.width,clamp(height,0,MaxCoordinate)))
  callback(content)
  let screenHeight = terminal.lastSize.height
  if screenHeight == 0 or content.area.isEmpty: return
  let wasInvalidated = terminal.invalidated
  var written = 0
  template drawLines(source: Buffer, sourceRow, targetRow, count:int, cleared:bool) =
    block:
      let area = initRect(0,targetRow,content.area.width,count)
      var next = initBuffer(area)
      for y in 0..<count:
        for x in 0..<area.width: next[x,targetRow+y] = source[x,sourceRow+y]
      var old = initBuffer(area)
      if not cleared:
        for cell in old.content.mitems: cell.symbol = ""
      draw(terminal.backend,diff(old,next))
      flush(terminal.backend)
  try:
    if terminal.viewportArea.height == screenHeight:
      for row in 0..<content.area.height:
        drawLines(content,row,0,1,row > 0)
        scrollRegionUp(terminal.backend,0,1,1)
      drawLines(terminal.previous,terminal.previous.area.y,0,1,true)
    else:
      let room = max(0,screenHeight-terminal.viewportArea.bottom)
      if room > 0:
        let n = min(room,content.area.height)
        let origin = terminal.viewportArea.y
        scrollRegionDown(terminal.backend,origin,terminal.viewportArea.bottom+n,n)
        drawLines(content,0,origin,n,true)
        terminal.setViewportArea(initRect(0,origin+n,content.area.width,terminal.viewportArea.height))
        written = n
      let origin = terminal.viewportArea.y
      while written < content.area.height:
        let n = min(origin,content.area.height-written)
        scrollRegionUp(terminal.backend,0,origin,n)
        drawLines(content,written,origin-n,n,true)
        written += n
    terminal.invalidated = wasInvalidated
  except:
    terminal.invalidated = true
    raise

template withTerminal*(name: untyped, backend: untyped, body: untyped) =
  block:
    var name {.inject.} = initTerminal(backend)
    try: body
    finally: name.restore()
template withTerminal*(name: untyped, backend: untyped, viewport: untyped, body: untyped) =
  block:
    var name {.inject.} = initTerminal(backend,viewport)
    try: body
    finally: name.restore()
