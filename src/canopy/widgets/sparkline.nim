## Compact time series with optional values and per-bar styles.
import std/options
import ../[geometry, style, buffer, symbols]
import ../internal/scaling
import "./block"
type
  RenderDirection* {.pure.} = enum LeftToRight, RightToLeft
  SparklineBar* = object
    value*: Option[uint64]
    style*: Option[Style]
  Sparkline* = object
    data*: seq[SparklineBar]
    blockWidget*: Option[Block]
    style*, absentValueStyle*: Style
    absentValueSymbol*: string
    barSet*: BarSet
    maxValue*: Option[uint64]
    direction*: RenderDirection
func initSparklineBar*(value: Option[uint64]): SparklineBar = SparklineBar(value:value)
func initSparklineBar*(value: uint64): SparklineBar = initSparklineBar(some(value))
func withStyle*(bar: SparklineBar, style: Style): SparklineBar =
  result = bar
  result.style = some(style)
func initSparkline*(data: openArray[SparklineBar] = []): Sparkline =
  Sparkline(data: @data,barSet:NineLevels,absentValueSymbol:" ")
func initSparkline*(data: openArray[uint64]): Sparkline =
  result = initSparkline()
  for value in data: result.data.add(initSparklineBar(value))
func initSparkline*(data: openArray[int]): Sparkline =
  result = initSparkline()
  for value in data: result.data.add(initSparklineBar(uint64(max(0,value))))
func withData*(s: Sparkline, data: openArray[SparklineBar]): Sparkline =
  result = s
  result.data = @data
func withBlock*(s: Sparkline, b: Block): Sparkline =
  result = s
  result.blockWidget = some(b)
func withStyle*(s: Sparkline, style: Style): Sparkline =
  result = s
  result.style = style
func withAbsentValueStyle*(s: Sparkline, style: Style): Sparkline =
  result = s
  result.absentValueStyle = style
func withAbsentValueSymbol*(s: Sparkline, symbol: string): Sparkline =
  result = s
  result.absentValueSymbol = symbol
func withBarSet*(s: Sparkline, set: BarSet): Sparkline =
  result = s
  result.barSet = set
func withMax*(s: Sparkline, value: uint64): Sparkline =
  result = s
  result.maxValue = some(value)
func withDirection*(s: Sparkline, direction: RenderDirection): Sparkline =
  result = s
  result.direction = direction
proc render*(s: Sparkline, area: Rect, buf: var Buffer) =
  let clipped = area.intersection(buf.area)
  s.blockWidget.render(clipped,buf)
  let a = s.blockWidget.inner(clipped).intersection(buf.area)
  if a.isEmpty: return
  var maximum = 1'u64
  var found = false
  for bar in s.data:
    if bar.value.isSome:
      if not found: maximum = bar.value.get
      else: maximum = max(maximum,bar.value.get)
      found = true
  maximum = s.maxValue.get(maximum)
  for i in 0..<min(a.width,s.data.len):
    let item = s.data[i]
    let x = if s.direction == RenderDirection.LeftToRight: a.x+i else: a.right-i-1
    var height = if item.value.isSome: scaleFraction(item.value.get,maximum,a.height*8) else: a.height*8
    let style = s.style.patch(if item.value.isSome: item.style.get(initStyle()) else: s.absentValueStyle)
    for y in countdown(a.bottom-1,a.y):
      buf[x,y].symbol = if item.value.isNone: s.absentValueSymbol else: s.barSet.level(min(8,height))
      buf[x,y].setStyle(style)
      height = max(0,height-8)
