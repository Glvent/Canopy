## Canvas shapes and layered pseudo-pixel rendering, ported from Ratatui 0.30.2.
import std/[math, options, unicode]
import ../[geometry, style, text, buffer, symbols]
import ../internal/canvas_tables
import "./block"
export symbols.Marker

type
  CanvasPoint* = tuple[x, y: float64]
  CanvasBounds* = array[2, float64]
  CanvasLine* = object
    x1*, y1*, x2*, y2*: float64
    color*: Color
  FilledLine* = object
    x1*, y1*, x2*, y2*, fillToY*: float64
    color*: Color
  Points* = object
    coords*: seq[CanvasPoint]
    color*: Color
  Rectangle* = object
    x*, y*, width*, height*: float64
    color*: Color
  Circle* = object
    x*, y*, radius*: float64
    color*: Color
  MapResolution* {.pure.} = enum Low, High
  Map* = object
    resolution*: MapResolution
    color*: Color
  CanvasLabel* = object
    x*, y*: float64
    line*: text.Line
  LayerCell = object
    symbol: string
    fg, bg: Option[Color]
  PatternCell = object
    pattern: uint8
    color: Option[Color]
  CanvasContext* = object
    width, height: int
    xBounds, yBounds: CanvasBounds
    markerKind: Marker
    customSymbol: string
    cells: seq[PatternCell]
    pixels: seq[Option[Color]]
    dirty: bool
    layers: seq[seq[LayerCell]]
    labels: seq[CanvasLabel]
  Painter* = object
    context: ptr CanvasContext
    resolution: CanvasPoint
  CanvasPaint* = proc(context: var CanvasContext) {.closure.}
  Canvas* = object
    blockWidget*: Option[Block]
    xBounds*, yBounds*: CanvasBounds
    paintFunc*: CanvasPaint
    backgroundColor*: Color
    marker*: Marker
    customSymbol*: string

func initCanvasLine*(x1, y1, x2, y2: float64, color: Color): CanvasLine =
  CanvasLine(x1: x1, y1: y1, x2: x2, y2: y2, color: color)
func initFilledLine*(x1, y1, x2, y2, fillToY: float64, color: Color): FilledLine =
  FilledLine(x1: x1, y1: y1, x2: x2, y2: y2, fillToY: fillToY, color: color)
func initPoints*(coords: openArray[CanvasPoint], color: Color): Points = Points(coords: @coords, color: color)
func initRectangle*(x, y, width, height: float64, color: Color): Rectangle =
  Rectangle(x: x, y: y, width: width, height: height, color: color)
func initCircle*(x, y, radius: float64, color: Color): Circle = Circle(x: x, y: y, radius: radius, color: color)
func initMap*(resolution = MapResolution.Low, color = color(ColorKind.Reset)): Map = Map(resolution: resolution, color: color)
func initCanvas*(): Canvas = Canvas(marker: Marker.Braille, backgroundColor: color(ColorKind.Reset), customSymbol: "•")
func withBlock*(canvas: Canvas, b: Block): Canvas =
  result = canvas; result.blockWidget = some(b)
func withXBounds*(canvas: Canvas, bounds: CanvasBounds): Canvas =
  result = canvas; result.xBounds = bounds
func withYBounds*(canvas: Canvas, bounds: CanvasBounds): Canvas =
  result = canvas; result.yBounds = bounds
func withPaint*(canvas: Canvas, callback: CanvasPaint): Canvas =
  result = canvas; result.paintFunc = callback
func withBackgroundColor*(canvas: Canvas, color: Color): Canvas =
  result = canvas; result.backgroundColor = color
proc markerSymbol(symbol: string): string =
  if symbol.runeLen != 1: raise newException(ValueError, "Custom canvas marker requires one Unicode scalar")
  symbol
proc withMarker*(canvas: Canvas, marker: Marker, customSymbol = "•"): Canvas =
  result = canvas; result.marker = marker
  result.customSymbol = if marker == Marker.Custom: markerSymbol(customSymbol) else: customSymbol

func dimensions(marker: Marker): tuple[w, h: int] =
  case marker
  of Marker.Braille, Marker.Octant: (2, 4)
  of Marker.Sextant: (2, 3)
  of Marker.Quadrant: (2, 2)
  of Marker.HalfBlock: (1, 2)
  else: (1, 1)
proc resetGrid(ctx: var CanvasContext) =
  ctx.cells = newSeq[PatternCell](ctx.width * ctx.height)
  ctx.pixels = if ctx.markerKind == Marker.HalfBlock: newSeq[Option[Color]](ctx.width * ctx.height * 2) else: @[]
proc initCanvasContext*(width, height: int, xBounds, yBounds: CanvasBounds,
                        marker = Marker.Braille, customSymbol = "•"): CanvasContext =
  result = CanvasContext(width: clamp(width, 0, 65535), height: clamp(height, 0, 65535),
    xBounds: xBounds, yBounds: yBounds, markerKind: marker,
    customSymbol: (if marker == Marker.Custom: markerSymbol(customSymbol) else: customSymbol))
  result.resetGrid()
proc initPainter*(ctx: var CanvasContext): Painter =
  ## Borrowed painter: do not retain it beyond the lifetime of ctx.
  let d = dimensions(ctx.markerKind)
  Painter(context: addr ctx, resolution: (float64(ctx.width * d.w), float64(ctx.height * d.h)))
func bounds*(painter: Painter): tuple[x, y: CanvasBounds] =
  (painter.context.xBounds, painter.context.yBounds)
func saturatingInt(value: float64): int =
  if value != value or value <= 0.0: 0
  elif value >= float64(int.high): int.high
  else: int(value)
func getPoint*(painter: Painter, x, y: float64): Option[tuple[x, y: int]] =
  let ctx = painter.context
  if x < ctx.xBounds[0] or x > ctx.xBounds[1] or y < ctx.yBounds[0] or y > ctx.yBounds[1]: return
  let width = ctx.xBounds[1] - ctx.xBounds[0]
  let height = ctx.yBounds[1] - ctx.yBounds[0]
  if width <= 0.0 or height <= 0.0: return
  some((saturatingInt(round((x-ctx.xBounds[0]) * (painter.resolution.x-1.0) / width)),
        saturatingInt(round((ctx.yBounds[1]-y) * (painter.resolution.y-1.0) / height))))
proc paint*(painter: var Painter, x, y: int, color: Color) =
  let ctx = painter.context
  if x < 0 or y < 0: return
  if ctx.markerKind == Marker.HalfBlock:
    if x < ctx.width and y < ctx.height * 2: ctx.pixels[y*ctx.width+x] = some(color)
  else:
    let d = dimensions(ctx.markerKind)
    if y div d.h > int.high div max(1, ctx.width): return
    let rowStart = (y div d.h) * ctx.width
    if x div d.w > int.high - rowStart: return
    let index = rowStart + x div d.w
    if index < ctx.cells.len:
      ctx.cells[index].pattern = ctx.cells[index].pattern or uint8(1 shl ((x mod d.w) + d.w*(y mod d.h)))
      ctx.cells[index].color = some(color)
proc layer*(ctx: var CanvasContext) =
  var layer = newSeq[LayerCell](ctx.width*ctx.height)
  for i in 0..<layer.len:
    if ctx.markerKind == Marker.HalfBlock:
      let top = ctx.pixels[(i div ctx.width)*ctx.width*2 + i mod ctx.width]
      let bottom = ctx.pixels[(i div ctx.width)*ctx.width*2 + ctx.width + i mod ctx.width]
      if top.isSome:
        layer[i] = LayerCell(symbol: (if top == bottom: "█" else: "▀"), fg: top, bg: bottom)
      elif bottom.isSome: layer[i] = LayerCell(symbol: "▄", fg: bottom)
    elif ctx.cells[i].pattern != 0:
      let cell = ctx.cells[i]
      let symbol = case ctx.markerKind
        of Marker.Braille: symbols.Braille[cell.pattern]
        of Marker.Quadrant: symbols.Quadrants[cell.pattern]
        of Marker.Sextant: symbols.Sextants[cell.pattern]
        of Marker.Octant: symbols.Octants[cell.pattern]
        of Marker.Block: "█"
        of Marker.Bar: "▄"
        of Marker.Custom: ctx.customSymbol
        else: "•"
      layer[i] = LayerCell(symbol: symbol, fg: cell.color,
        bg: (if ctx.markerKind == Marker.Block: cell.color else: none(Color)))
  ctx.layers.add layer
  ctx.resetGrid()
  ctx.dirty = false
proc finish(ctx: var CanvasContext) =
  if ctx.dirty: ctx.layer()
proc setMarker*(ctx: var CanvasContext, marker: Marker, customSymbol = "•") =
  ctx.finish()
  ctx.markerKind = marker
  ctx.customSymbol = if marker == Marker.Custom: markerSymbol(customSymbol) else: customSymbol
  ctx.resetGrid()
proc print*(ctx: var CanvasContext, x, y: float64, line: text.Line) = ctx.labels.add CanvasLabel(x: x, y: y, line: line)
proc print*(ctx: var CanvasContext, x, y: float64, line: string) = ctx.print(x, y, initLine(line))

func region(point: CanvasPoint, xb, yb: CanvasBounds): int =
  if point.x < xb[0]: result = result or 1
  elif point.x > xb[1]: result = result or 2
  if point.y < yb[0]: result = result or 4
  elif point.y > yb[1]: result = result or 8
func intersection(a, b: CanvasPoint, region: int, xb, yb: CanvasBounds): CanvasPoint =
  let dx = b.x-a.x
  let dy = b.y-a.y
  if (region and 1) != 0: (xb[0], a.y + (xb[0]-a.x)*dy/dx)
  elif (region and 2) != 0: (xb[1], a.y + (xb[1]-a.x)*dy/dx)
  elif (region and 4) != 0: (a.x + (yb[0]-a.y)*dx/dy, yb[0])
  else: (a.x + (yb[1]-a.y)*dx/dy, yb[1])
func clipLine*(xb, yb: CanvasBounds, x1, y1, x2, y2: float64): Option[tuple[a, b: CanvasPoint]] =
  var a: CanvasPoint = (x1, y1)
  var b: CanvasPoint = (x2, y2)
  var ra = region(a, xb, yb)
  var rb = region(b, xb, yb)
  while true:
    if (ra and rb) != 0: return
    if ra != 0:
      a = intersection(a, b, ra, xb, yb)
      ra = region(a, xb, yb)
    elif rb != 0:
      b = intersection(b, a, rb, xb, yb)
      rb = region(b, xb, yb)
    else: return some((a, b))
iterator linePoints*(x1, y1, x2, y2: int): tuple[x, y: int] =
  let dx = abs(x2-x1)
  let dy = abs(y2-y1)
  if dx == 0:
    for y in min(y1,y2)..max(y1,y2): yield (x1,y)
  elif dy == 0:
    for x in min(x1,x2)..max(x1,x2): yield (x,y1)
  elif dy < dx:
    let xa = min(x1,x2)
    let xb = max(x1,x2)
    let ya = if x1 > x2: y2 else: y1
    let yb = if x1 > x2: y1 else: y2
    var y = ya
    var d = 2*dy-dx
    for x in xa..xb:
      yield (x,y)
      if d > 0:
        y += (if ya > yb: -1 else: 1)
        d -= 2*dx
      d += 2*dy
  else:
    let ya = min(y1,y2)
    let yb = max(y1,y2)
    let xa = if y1 > y2: x2 else: x1
    let xb = if y1 > y2: x1 else: x2
    var x = xa
    var d = 2*dx-dy
    for y in ya..yb:
      yield (x,y)
      if d > 0:
        x += (if xa > xb: -1 else: 1)
        d -= 2*dy
      d += 2*dx
proc draw*(shape: CanvasLine, painter: var Painter) =
  let (xb,yb) = painter.bounds()
  let clipped = clipLine(xb,yb,shape.x1,shape.y1,shape.x2,shape.y2)
  if clipped.isNone: return
  let a = painter.getPoint(clipped.get.a.x,clipped.get.a.y)
  let b = painter.getPoint(clipped.get.b.x,clipped.get.b.y)
  if a.isNone or b.isNone: return
  for p in linePoints(a.get.x,a.get.y,b.get.x,b.get.y): painter.paint(p.x,p.y,shape.color)
proc draw*(shape: FilledLine, painter: var Painter) =
  let (xb,yb) = painter.bounds()
  let clipped = clipLine(xb,yb,shape.x1,shape.y1,shape.x2,shape.y2)
  if clipped.isNone: return
  let a = painter.getPoint(clipped.get.a.x,clipped.get.a.y)
  let b = painter.getPoint(clipped.get.b.x,clipped.get.b.y)
  let baseline = painter.getPoint(clipped.get.a.x,clamp(shape.fillToY,yb[0],yb[1]))
  if a.isNone or b.isNone or baseline.isNone: return
  for p in linePoints(a.get.x,a.get.y,b.get.x,b.get.y):
    for y in min(p.y,baseline.get.y)..max(p.y,baseline.get.y): painter.paint(p.x,y,shape.color)
proc draw*(shape: Points, painter: var Painter) =
  for point in shape.coords:
    let p = painter.getPoint(point.x,point.y)
    if p.isSome: painter.paint(p.get.x,p.get.y,shape.color)
proc draw*(shape: Rectangle, painter: var Painter) =
  for line in [initCanvasLine(shape.x,shape.y,shape.x,shape.y+shape.height,shape.color),
               initCanvasLine(shape.x,shape.y+shape.height,shape.x+shape.width,shape.y+shape.height,shape.color),
               initCanvasLine(shape.x+shape.width,shape.y,shape.x+shape.width,shape.y+shape.height,shape.color),
               initCanvasLine(shape.x,shape.y,shape.x+shape.width,shape.y,shape.color)]:
    line.draw(painter)
proc fusedMultiplyAdd(x,y,z: float64): float64 {.importc: "fma", header: "<math.h>".}
proc draw*(shape: Circle, painter: var Painter) =
  for angle in 0..<360:
    let radians = float64(angle) * (PI / 180.0)
    let p = painter.getPoint(fusedMultiplyAdd(shape.radius,cos(radians),shape.x),
                             fusedMultiplyAdd(shape.radius,sin(radians),shape.y))
    if p.isSome: painter.paint(p.get.x,p.get.y,shape.color)
proc draw*(shape: Map, painter: var Painter) =
  template paintMap(data: untyped) =
    for point in data:
      let p = painter.getPoint(point[0],point[1])
      if p.isSome: painter.paint(p.get.x,p.get.y,shape.color)
  if shape.resolution == MapResolution.Low: paintMap(WORLD_LOW_RESOLUTION)
  else: paintMap(WORLD_HIGH_RESOLUTION)
proc draw*[S](ctx: var CanvasContext, shape: S) =
  mixin draw
  ctx.dirty = true
  var painter = initPainter(ctx)
  shape.draw(painter)

proc render*(canvas: Canvas, area: Rect, buf: var Buffer) =
  let area = area.intersection(buf.area)
  canvas.blockWidget.render(area,buf)
  let inner = canvas.blockWidget.inner(area)
  if inner.isEmpty: return
  buf.setStyle(inner,initStyle().withBg(canvas.backgroundColor))
  if canvas.paintFunc.isNil: return
  var ctx = initCanvasContext(inner.width,inner.height,canvas.xBounds,canvas.yBounds,canvas.marker,canvas.customSymbol)
  canvas.paintFunc(ctx)
  ctx.finish()
  for layer in ctx.layers:
    for index, pixel in layer:
      let x = inner.x + index mod inner.width
      let y = inner.y + index div inner.width
      if pixel.symbol.len > 0: buf[x,y].setSymbol(pixel.symbol)
      if pixel.fg.isSome: buf[x,y].fg = pixel.fg.get
      if pixel.bg.isSome: buf[x,y].bg = pixel.bg.get
  let width = abs(canvas.xBounds[1]-canvas.xBounds[0])
  let height = abs(canvas.yBounds[1]-canvas.yBounds[0])
  for label in ctx.labels:
    if label.x >= canvas.xBounds[0] and label.x <= canvas.xBounds[1] and
       label.y >= canvas.yBounds[0] and label.y <= canvas.yBounds[1]:
      let x = inner.x + saturatingInt((label.x-canvas.xBounds[0])*float64(inner.width-1)/width)
      let y = inner.y + saturatingInt((canvas.yBounds[1]-label.y)*float64(inner.height-1)/height)
      discard buf.setLine(x,y,label.line,inner.right-x)
