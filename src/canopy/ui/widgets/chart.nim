## Axis, dataset, legend, and chart rendering matched to Ratatui 0.30.2.
import std/options

import ../../core/layout/geometry
import ../../core/styling/style
import ../../core/text/index as text
import ../../core/rendering/buffer
import ../../core/layout/index as layout
import ../../core/rendering/symbols
import "./block"
import ./canvas
export canvas.CanvasPoint, canvas.CanvasBounds

type
  Axis* = object
    title*: Option[text.Line]
    bounds*: CanvasBounds
    labels*: seq[text.Line]
    style*: Style
    labelsAlignment*: Alignment
  GraphType* {.pure.} = enum Scatter, Line, Bar, Area
  LegendPosition* {.pure.} = enum Top, TopRight, TopLeft, Left, Right, Bottom, BottomRight, BottomLeft
  Dataset* = object
    name*: Option[text.Line]
    data*: seq[CanvasPoint]
    marker*: Marker
    customSymbol*: string
    graphType*: GraphType
    style*: Style
    fillToY*: float64
  Chart* = object
    ## `hiddenLegendConstraints` bound the legend against the graph area; a legend that would
    ## exceed them is dropped rather than shrunk.
    blockWidget*: Option[Block]
    xAxis*, yAxis*: Axis
    datasets*: seq[Dataset]
    style*: Style
    hiddenLegendConstraints*: tuple[width, height: Constraint]
    legendPosition*: Option[LegendPosition]
  # Resolved positions for one render. `none` means the element does not fit and is skipped.
  ChartLayout = object
    titleX, titleY: Option[Position]
    labelX, labelY, axisX, axisY: Option[int]
    legendArea: Option[Rect]
    graphArea: Rect

func initAxis*(): Axis = Axis()
func withTitle*(axis: Axis, title: text.Line): Axis =
  result = axis; result.title = some(title)

func withTitle*(axis: Axis, title: string): Axis = axis.withTitle(initLine(title))
func withBounds*(axis: Axis, bounds: CanvasBounds): Axis =
  result = axis; result.bounds = bounds

func withLabels*(axis: Axis, labels: openArray[text.Line]): Axis =
  result = axis; result.labels = @labels

func withLabels*(axis: Axis, labels: openArray[string]): Axis =
  result = axis; result.labels = @[]
  for label in labels: result.labels.add initLine(label)

func withStyle*(axis: Axis, style: Style): Axis =
  result = axis; result.style = style

func withLabelsAlignment*(axis: Axis, alignment: Alignment): Axis =
  result = axis; result.labelsAlignment = alignment

func initDataset*(data: openArray[CanvasPoint] = []): Dataset = Dataset(data: @data,
    customSymbol: "•")
func withName*(dataset: Dataset, name: text.Line): Dataset =
  result = dataset; result.name = some(name)

func withName*(dataset: Dataset, name: string): Dataset = dataset.withName(initLine(name))
func withData*(dataset: Dataset, data: openArray[CanvasPoint]): Dataset =
  result = dataset; result.data = @data

func withMarker*(dataset: Dataset, marker: Marker, customSymbol = "•"): Dataset =
  result = dataset; result.marker = marker; result.customSymbol = customSymbol

func withGraphType*(dataset: Dataset, graphType: GraphType): Dataset =
  result = dataset; result.graphType = graphType

func withStyle*(dataset: Dataset, style: Style): Dataset =
  result = dataset; result.style = style

func withFillToY*(dataset: Dataset, y: float64): Dataset =
  result = dataset; result.fillToY = y

func initChart*(datasets: openArray[Dataset] = []): Chart =
  Chart(datasets: @datasets, hiddenLegendConstraints: (ratio(1, 4), ratio(1, 4)),
      legendPosition: some(LegendPosition.TopRight))

func withBlock*(chart: Chart, b: Block): Chart =
  result = chart; result.blockWidget = some(b)

func withStyle*(chart: Chart, style: Style): Chart =
  result = chart; result.style = style

func withXAxis*(chart: Chart, axis: Axis): Chart =
  result = chart; result.xAxis = axis

func withYAxis*(chart: Chart, axis: Axis): Chart =
  result = chart; result.yAxis = axis

func withHiddenLegendConstraints*(chart: Chart, constraints: tuple[width,
    height: Constraint]): Chart =
  result = chart; result.hiddenLegendConstraints = constraints

func withLegendPosition*(chart: Chart, position: Option[LegendPosition]): Chart =
  result = chart; result.legendPosition = position

func withLegendPosition*(chart: Chart, position: LegendPosition): Chart = chart.withLegendPosition(
    some(position))

# Places the legend box, nudging it by one row where an axis title would otherwise overlap it.
func legendLayout(position: LegendPosition, area: Rect, width, height, xTitleWidth,
    yTitleWidth: int): Option[Rect] =
  if area.height-height-ord(xTitleWidth != 0)-ord(yTitleWidth != 0) < 0: return
  var x, y: int
  case position
  of LegendPosition.TopRight:
    x = area.right-width
    y = area.y+ord(width+yTitleWidth > area.width)
  of LegendPosition.TopLeft:
    x = area.x; y = area.y+ord(yTitleWidth != 0)
  of LegendPosition.Top:
    let offset = (area.width-width) div 2
    x = area.x+offset
    y = area.y+ord(area.x+yTitleWidth > offset)
  of LegendPosition.Left, LegendPosition.Right:
    let offset = max(0, (area.height-height) div 2+ord(yTitleWidth != 0)-ord(xTitleWidth != 0))
    x = if position == LegendPosition.Left: area.x else: area.right-width
    y = area.y+offset
  of LegendPosition.BottomLeft:
    x = area.x; y = area.bottom-height-ord(xTitleWidth+width > area.width)
  of LegendPosition.BottomRight:
    x = area.right-width; y = area.bottom-height-ord(xTitleWidth != 0)
  of LegendPosition.Bottom:
    x = area.x+(area.width-width) div 2
    y = area.bottom-height-ord(x+width > area.right-xTitleWidth)
  some(initRect(x, y, width, height))

# Columns reserved for y labels, including the part of the first x label that reaches left of the
# graph. Capped at a third of the area so labels cannot squeeze out the plot.

proc labelWidth(chart: Chart, area: Rect, hasYAxis: bool): int =
  for label in chart.yAxis.labels: result = max(result, label.width)
  # Upstream stores widths as u16; masking reproduces its wrapping for pathological inputs.
  result = result and 65535
  if chart.xAxis.labels.len > 0:
    let width = chart.xAxis.labels[0].width and 65535
    let left = case chart.xAxis.labelsAlignment
      of Alignment.Left: max(0, width-ord(hasYAxis))
      of Alignment.Center: width div 2
      of Alignment.Right: 0
    result = max(result, left)
  result = min(result, area.width div 3)

# Claims space from the outside in: x labels, y labels, then the axes, leaving the rest as the
# graph area. Elements that no longer fit are left unset.

proc computeLayout(chart: Chart, area: Rect): Option[ChartLayout] =
  if area.isEmpty: return
  var c: ChartLayout
  var x = area.x
  var y = area.bottom-1
  if chart.xAxis.labels.len > 0 and y > area.y:
    c.labelX = some(y); dec y
  if chart.yAxis.labels.len > 0: c.labelY = some(x)
  x += chart.labelWidth(area, chart.yAxis.labels.len > 0)
  if chart.xAxis.labels.len > 0 and y > area.y:
    c.axisX = some(y); dec y
  if chart.yAxis.labels.len > 0 and x+1 < area.right:
    c.axisY = some(x); inc x
  c.graphArea = initRect(x, area.y, max(0, area.right-x), max(0, y-area.y)+1)
  let graph = c.graphArea
  if chart.xAxis.title.isSome:
    let width = chart.xAxis.title.get.width and 65535
    if width < graph.width and graph.height > 2:
      c.titleX = some(initPosition(x+graph.width-width, y))
  if chart.yAxis.title.isSome:
    let width = chart.yAxis.title.get.width and 65535
    if width+1 < graph.width and graph.height > 2:
      c.titleY = some(initPosition(x, area.y))
  if chart.legendPosition.isSome:
    var innerWidth, names: int
    for dataset in chart.datasets:
      if dataset.name.isSome:
        inc names; innerWidth = max(innerWidth, dataset.name.get.width and 65535)
    if names > 0:
      let width = innerWidth+2
      let height = names+2
      let maxWidth = horizontal([chart.hiddenLegendConstraints.width]).split(graph)[0].width
      let maxHeight = vertical([chart.hiddenLegendConstraints.height]).split(graph)[0].height
      if innerWidth > 0 and width <= maxWidth and height <= maxHeight:
        c.legendArea = legendLayout(chart.legendPosition.get, graph, width, height,
          (if c.titleX.isSome: chart.xAxis.title.get.width and 65535 else: 0),
          (if c.titleY.isSome: chart.yAxis.title.get.width and 65535 else: 0))
  some(c)

proc renderLabel(buf: var Buffer, label: text.Line, area: Rect, alignment: Alignment) =
  label.withAlignment(alignment).render(area, buf)

proc renderXLabels(chart: Chart, buf: var Buffer, c: ChartLayout, area, graph: Rect) =
  if c.labelX.isNone or chart.xAxis.labels.len < 2: return
  let labels = chart.xAxis.labels
  let y = c.labelX.get
  let ticks = graph.width div labels.len
  let labelWidth = labels[0].width and 65535
  let limits = case chart.xAxis.labelsAlignment
    of Alignment.Left: (area.x, graph.x)
    of Alignment.Center: (area.x, graph.x+min(ticks, labelWidth))
    of Alignment.Right: (max(0, graph.x-1), graph.x+ticks)
  let alignment = case chart.xAxis.labelsAlignment
    of Alignment.Left: Alignment.Right
    of Alignment.Center: Alignment.Center
    of Alignment.Right: Alignment.Left
  buf.renderLabel(labels[0], initRect(limits[0], y, limits[1]-limits[0], 1), alignment)
  for i in 1..<labels.len-1:
    buf.renderLabel(labels[i], initRect(graph.x+i*ticks+1, y, max(0, ticks-1), 1), Alignment.Center)
  buf.renderLabel(labels[^1], initRect(graph.right-ticks, y, ticks, 1), Alignment.Right)

proc renderYLabels(chart: Chart, buf: var Buffer, c: ChartLayout, area, graph: Rect) =
  if c.labelY.isNone or chart.yAxis.labels.len < 2: return
  for i, label in chart.yAxis.labels:
    let dy = i*(graph.height-1) div (chart.yAxis.labels.len-1)
    if dy < graph.bottom:
      buf.renderLabel(label, initRect(c.labelY.get, max(0, graph.bottom-1)-dy,
        max(0, graph.x-area.x-1), 1), chart.yAxis.labelsAlignment)

proc render*(chart: Chart, area: Rect, buf: var Buffer) =
  let area = area.intersection(buf.area)
  buf.setStyle(area, chart.style)
  chart.blockWidget.render(area, buf)
  let inner = chart.blockWidget.inner(area)
  let computed = chart.computeLayout(inner)
  if computed.isNone: return
  let c = computed.get
  let graph = c.graphArea
  # Titles and the legend sit on the chart background, so the pre-plot style is captured before
  # the datasets paint over it.
  let originalStyle = buf[area.x, area.y].style()
  chart.renderXLabels(buf, c, inner, graph)
  chart.renderYLabels(buf, c, inner, graph)
  if c.axisX.isSome:
    for x in graph.x..<graph.right:
      buf[x, c.axisX.get].setSymbol(NormalLine.horizontal)
      buf[x, c.axisX.get].setStyle(chart.xAxis.style)
  if c.axisY.isSome:
    for y in graph.y..<graph.bottom:
      buf[c.axisY.get, y].setSymbol(NormalLine.vertical)
      buf[c.axisY.get, y].setStyle(chart.yAxis.style)
  if c.axisX.isSome and c.axisY.isSome:
    buf[c.axisY.get, c.axisX.get].setSymbol(NormalLine.bottomLeft)
    buf[c.axisY.get, c.axisX.get].setStyle(chart.xAxis.style)
  let datasets = chart.datasets
  let drawing = initCanvas().withBackgroundColor(chart.style.bg.get(color(ColorKind.Reset)))
    .withXBounds(chart.xAxis.bounds).withYBounds(chart.yAxis.bounds)
    .withPaint(proc(ctx: var CanvasContext) =
      for dataset in datasets:
        ctx.setMarker(dataset.marker, dataset.customSymbol)
        let color = dataset.style.fg.get(color(ColorKind.Reset))
        ctx.draw(initPoints(dataset.data, color))
        case dataset.graphType
        of GraphType.Line:
          for i in 0..<dataset.data.len-1:
            let a = dataset.data[i]; let b = dataset.data[i+1]
            ctx.draw(initCanvasLine(a.x, a.y, b.x, b.y, color))
        of GraphType.Area:
          for i in 0..<dataset.data.len-1:
            let a = dataset.data[i]; let b = dataset.data[i+1]
            ctx.draw(initFilledLine(a.x, a.y, b.x, b.y, dataset.fillToY, color))
        of GraphType.Bar:
          for p in dataset.data: ctx.draw(initCanvasLine(p.x, 0.0, p.x, p.y, color))
        of GraphType.Scatter: discard)
  drawing.render(graph, buf)
  for pair in [(c.titleX, chart.xAxis.title), (c.titleY, chart.yAxis.title)]:
    if pair[0].isSome:
      let position = pair[0].get
      let title = pair[1].get
      let width = min(max(0, graph.right-position.x), title.width and 65535)
      buf.setStyle(initRect(position.x, position.y, width, 1), originalStyle)
      discard buf.setLine(position.x, position.y, title, width)
  if c.legendArea.isSome:
    let legend = c.legendArea.get
    buf.setStyle(legend, originalStyle)
    borderedBlock().render(legend, buf)
    var i = 0
    for dataset in chart.datasets:
      if dataset.name.isSome:
        dataset.name.get.patchStyle(dataset.style).render(initRect(legend.x+1, legend.y+1+i,
            legend.width-2, 1), buf)
        inc i

template styling(T: typedesc) =
  func patchStyle*(value: T, style: Style): T = value.withStyle(value.style.patch(style))
  func withFg*(value: T, color: Color): T = value.patchStyle(initStyle().withFg(color))
  func withBg*(value: T, color: Color): T = value.patchStyle(initStyle().withBg(color))
  func bold*(value: T): T = value.patchStyle(initStyle().bold())
  func italic*(value: T): T = value.patchStyle(initStyle().italic())
  func underlined*(value: T): T = value.patchStyle(initStyle().underlined())
styling(Axis)
styling(Dataset)
styling(Chart)
