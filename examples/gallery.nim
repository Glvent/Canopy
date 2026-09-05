## Noninteractive widget gallery. Run: nim c -r --path:src examples/gallery.nim
import std/math
import canopy
import canopy/widgets/[canvas, chart]

let accent = initStyle().withFg(ColorKind.Cyan)
let selected = initStyle().withFg(ColorKind.Black).withBg(ColorKind.Cyan)
proc panel(title: string): Block = borderedBlock().withTitle(title).withBorderStyle(accent)

var terminal = initTerminal(initTestBackend(120, 47))
var selection = initListState().withSelected(2)
var tableSelection = initTableState().withSelected(1)
var scroll = initScrollbarState(12).withPosition(2).withViewportContentLength(7)
var events = initCalendarEventStore()
events.add(initDate(2026, 9, 5), selected)
var wave: seq[CanvasPoint]
for x in 0..40: wave.add((float64(x), sin(float64(x) / 4.0)))

discard terminal.draw(proc(frame: var Frame) =
  let rows = vertical([length(3), length(11), length(12), length(13), length(8)]).split(frame.area)
  frame.renderWidget(initTabs(["Canopy", "Widgets", "Native Nim", "Ratatui 0.30.2"])
    .withSelected(1).withBlock(panel("CANOPY  /  deterministic TestBackend gallery")), rows[0])

  let top = horizontal([length(29), length(25), fill(1)]).split(rows[1])
  var items: seq[ListItem]
  for title in ["Layout and constraints", "Styled Unicode text", "Stateful selection", "Wide characters: 世界",
                "Wrapped paragraphs", "Layered Canvas", "Charts and legends", "Buffered terminal"]:
    items.add initListItem(title)
  frame.renderStatefulWidget(initList(items).withBlock(panel("List + Scrollbar"))
    .withHighlightSymbol("› ").withHighlightStyle(selected), top[0], selection)
  frame.renderStatefulWidget(initScrollbar(), panel("").inner(top[0]), scroll)
  frame.renderWidget(initMonthly(initDate(2026, 9, 5), events).withShowMonthHeader(accent)
    .withShowWeekdaysHeader(accent).withShowSurrounding(initStyle().dim())
    .withBlock(panel("Calendar")), top[1])
  frame.renderWidget(initParagraph("Compose widgets inside constraint layouts. This screen is rendered through a real " &
    "Terminal[TestBackend] frame, then printed as plain text.\n\n" &
    "Unicode: 世界 • café • 👩‍💻\n" &
    "Selection, clipping, wrapping, chart axes, canvas layers, and buffer diffs use the same native runtime.")
    .withWrap(true).withBlock(panel("Paragraph")), top[2])

  let middle = horizontal([length(66), fill(1)]).split(rows[2])
  frame.renderWidget(initChart([
    initDataset(wave).withName("sin(x / 4)").withGraphType(GraphType.Line)
      .withMarker(Marker.Braille).withStyle(accent),
    initDataset([(0.0, 0.0), (40.0, 0.0)]).withName("zero").withGraphType(GraphType.Line)
      .withMarker(Marker.Dot).withStyle(initStyle().withFg(ColorKind.Yellow))])
    .withXAxis(initAxis().withBounds([0.0, 40.0]).withLabels(["0", "20", "40"]))
    .withYAxis(initAxis().withBounds([-1.2, 1.2]).withLabels(["-1", "0", "1"]))
    .withHiddenLegendConstraints((percentage(45), percentage(50)))
    .withBlock(panel("Chart")), middle[0])
  frame.renderWidget(initCanvas().withXBounds([-180.0, 180.0]).withYBounds([-90.0, 90.0])
    .withBlock(panel("Canvas / world map"))
    .withPaint(proc(ctx: var CanvasContext) =
      ctx.draw(initMap(MapResolution.High, color(ColorKind.Green)))
      ctx.layer()
      ctx.draw(initRectangle(-125, 25, 60, 25, color(ColorKind.Yellow)))
      ctx.print(-170, -70, "Braille grid + layered shapes")), middle[1])

  let lower = horizontal([length(29), length(43), fill(1)]).split(rows[3])
  frame.renderWidget(initBarChart([initBar("Mon", 4), initBar("Tue", 7), initBar("Wed", 5),
    initBar("Thu", 9), initBar("Fri", 6)]).withBarWidth(3).withBarGap(2)
    .withBlock(panel("BarChart")), lower[0])
  let tableRows = [initRow(["Canvas", "277", "ARC / ORC"]), initRow(["Chart", "230", "ARC / ORC"]),
    initRow(["Layout", "native", "Cassowary"]), initRow(["Text", "Unicode", "graphemes"]),
    initRow(["Backend", "Test", "deterministic"])]
  frame.renderStatefulWidget(initTable(tableRows, [length(10), length(7), fill(1)])
    .withHeader(initRow(["Module", "Cases", "Details"]).withStyle(accent))
    .withRowHighlightStyle(selected).withHighlightSymbol("› ").withBlock(panel("Table")), lower[1], tableSelection)
  frame.renderWidget(panel("Logo / Mascot / Fill + Clear"), lower[2])
  let art = panel("").inner(lower[2])
  frame.renderWidget(tinyLogo(), initRect(art.x, art.y, art.width, 2))
  frame.renderWidget(initMascot(), initRect(art.x, art.y + 3, 28, 7))
  let tile = initRect(art.x + 30, art.y + 3, 14, 7)
  frame.renderWidget(initFill("░"), tile)
  let inset = tile.inner(initMargin(1, 1))
  frame.renderWidget(initClear(), inset)
  frame.renderWidget(initParagraph("Fill\n +\nClear").centered(), inset)

  let bottom = horizontal([length(40), length(40), fill(1)]).split(rows[4])
  frame.renderWidget(initGauge().withPercent(73).withLabel("Gauge 73%")
    .withUseUnicode().withGaugeStyle(selected).withBlock(panel("Gauge")), bottom[0])
  frame.renderWidget(initLineGauge().withRatio(0.62).withLabel("LineGauge 62%")
    .withFilledStyle(accent).withBlock(panel("LineGauge")), bottom[1])
  frame.renderWidget(initSparkline([1, 3, 2, 7, 4, 9, 6, 3, 5, 8, 7, 4, 2, 1, 6, 9, 5, 7, 3, 4])
    .withStyle(accent).withBlock(panel("Sparkline")), bottom[2]))

let screen = terminal.backend.buffer
for y in screen.area.top..<screen.area.bottom:
  var line = ""
  var x = screen.area.left
  while x < screen.area.right:
    let cell = screen[x, y]
    line.add cell.symbol
    x += max(1, cell.cellWidth)
  echo line
terminal.restore()
