## Progress gauges with cell-exact labels and fractional block rendering.
import std/[math, strutils, options]
import ../[geometry, style, text, buffer, symbols]
import "./block"
type
  Gauge* = object
    blockWidget*: Option[Block]
    style*, gaugeStyle*: Style
    ratio*: float64
    label*: Option[Span]
    useUnicode*: bool
  LineGauge* = object
    blockWidget*: Option[Block]
    style*, filledStyle*, unfilledStyle*: Style
    ratio*: float64
    label*: Option[Line]
    filledSymbol*, unfilledSymbol*: string
func initGauge*(): Gauge = Gauge()
func initLineGauge*(): LineGauge = LineGauge(filledSymbol:"─",unfilledSymbol:"─")
template common(T: typedesc) =
  func withBlock*(g: T, b: Block): T =
    result = g
    result.blockWidget = some(b)
  func withStyle*(g: T, style: Style): T =
    result = g
    result.style = style
  func withRatio*(g: T, ratio: float64): T =
    if not (ratio >= 0.0 and ratio <= 1.0): raise newException(ValueError,"Gauge ratio must be in 0..1")
    result = g
    result.ratio = ratio
common(Gauge)
common(LineGauge)
func withPercent*(g: Gauge, percent: int): Gauge =
  if percent notin 0..100: raise newException(ValueError,"Gauge percent must be in 0..100")
  g.withRatio(float64(percent)/100.0)
func withLabel*(g: Gauge, label: Span): Gauge =
  result = g
  result.label = some(label)
func withLabel*(g: Gauge, label: string): Gauge = g.withLabel(initSpan(label))
func withGaugeStyle*(g: Gauge, style: Style): Gauge =
  result = g
  result.gaugeStyle = style
func withUseUnicode*(g: Gauge, value = true): Gauge =
  result = g
  result.useUnicode = value
func withLabel*(g: LineGauge, label: Line): LineGauge =
  result = g
  result.label = some(label)
func withLabel*(g: LineGauge, label: string): LineGauge = g.withLabel(initLine(label))
func withFilledStyle*(g: LineGauge, style: Style): LineGauge =
  result = g
  result.filledStyle = style
func withUnfilledStyle*(g: LineGauge, style: Style): LineGauge =
  result = g
  result.unfilledStyle = style
func withGaugeStyle*(g: LineGauge, style: Style): LineGauge =
  result = g
  result.filledStyle = style
  result.filledStyle.bg = none(Color)
  result.unfilledStyle = style
  result.unfilledStyle.fg = style.bg
  result.unfilledStyle.bg = none(Color)
func withLineSet*(g: LineGauge, set: LineSet): LineGauge =
  result = g
  result.filledSymbol = set.horizontal
  result.unfilledSymbol = set.horizontal
func withFilledSymbol*(g: LineGauge, symbol: string): LineGauge =
  result = g
  result.filledSymbol = symbol
func withUnfilledSymbol*(g: LineGauge, symbol: string): LineGauge =
  result = g
  result.unfilledSymbol = symbol
proc render*(g: Gauge, area: Rect, buf: var Buffer) =
  let clipped = area.intersection(buf.area)
  buf.setStyle(clipped,g.style)
  g.blockWidget.render(clipped,buf)
  let a = g.blockWidget.inner(clipped).intersection(buf.area)
  if a.isEmpty: return
  buf.setStyle(a,g.gaugeStyle)
  let label = g.label.get(initSpan($int(round(g.ratio*100)) & "%"))
  let width = min(a.width,label.width)
  let col = a.x+(a.width-width) div 2
  let row = a.y+a.height div 2
  let filled = float64(a.width)*g.ratio
  let finish = a.x+int(if g.useUnicode: floor(filled) else: round(filled))
  for y in a.y..<a.bottom:
    for x in a.x..<finish:
      if x < col or x > col+width or y != row:
        buf[x,y].symbol = "█"
        buf[x,y].fg = g.gaugeStyle.fg.get(color(ColorKind.Reset))
        buf[x,y].bg = g.gaugeStyle.bg.get(color(ColorKind.Reset))
      else:
        buf[x,y].symbol = " "
        buf[x,y].fg = g.gaugeStyle.bg.get(color(ColorKind.Reset))
        buf[x,y].bg = g.gaugeStyle.fg.get(color(ColorKind.Reset))
    if g.useUnicode and g.ratio < 1.0:
      const fractions = [" ","▏","▎","▍","▌","▋","▊","▉","█"]
      buf[finish,y].symbol = fractions[int(round((filled-floor(filled))*8))]
  buf.setSpan(col,row,label,width)
proc render*(g: LineGauge, area: Rect, buf: var Buffer) =
  let clipped = area.intersection(buf.area)
  buf.setStyle(clipped,g.style)
  g.blockWidget.render(clipped,buf)
  let a = g.blockWidget.inner(clipped).intersection(buf.area)
  if a.isEmpty: return
  let label = g.label.get(initLine(align($int(round(g.ratio*100)),3) & "%"))
  let p = buf.setLine(a.x,a.y,label,a.width)
  let first = p.x+1
  if first >= a.right: return
  let finish = first+int(floor(float64(a.right-first)*g.ratio))
  for x in first..<a.right:
    buf[x,a.y].symbol = if x < finish: g.filledSymbol else: g.unfilledSymbol
    buf[x,a.y].setStyle(if x < finish: g.filledStyle else: g.unfilledStyle)
