## Grouped horizontal and vertical bar charts.
import std/options
import ../[geometry,style,text,buffer,symbols,unicode]
import ../internal/scaling
import "./block"
type
  Bar* = object
    value*: uint64
    label*: Option[Line]
    style*, valueStyle*: Style
    textValue*: Option[string]
  BarGroup* = object
    bars*: seq[Bar]
    label*: Option[Line]
  BarChart* = object
    data*: seq[BarGroup]
    blockWidget*: Option[Block]
    barWidth*, barGap*, groupGap*: int
    maxValue*: Option[uint64]
    barStyle*, valueStyle*, labelStyle*, style*: Style
    barSet*: BarSet
    direction*: Direction
func initBar*(value: uint64 = 0): Bar = Bar(value:value)
func initBar*(label: Line, value: uint64): Bar = Bar(value:value,label:some(label))
func initBar*(label: string, value: uint64): Bar = initBar(initLine(label),value)
func withValue*(bar: Bar, value: uint64): Bar =
  result = bar
  result.value = value
func withLabel*(bar: Bar, label: Line): Bar =
  result = bar
  result.label = some(label)
func withLabel*(bar: Bar, label: string): Bar = bar.withLabel(initLine(label))
func withStyle*(bar: Bar, style: Style): Bar =
  result = bar
  result.style = style
func withValueStyle*(bar: Bar, style: Style): Bar =
  result = bar
  result.valueStyle = style
func withTextValue*(bar: Bar, text: string): Bar =
  result = bar
  result.textValue = some(text)
func initBarGroup*(bars: openArray[Bar]): BarGroup = BarGroup(bars: @bars)
func withLabel*(group: BarGroup, label: Line): BarGroup =
  result = group
  result.label = some(label)
func withLabel*(group: BarGroup, label: string): BarGroup = group.withLabel(initLine(label))
func withBars*(group: BarGroup, bars: openArray[Bar]): BarGroup =
  result = group
  result.bars = @bars
func initBarChart*(bars: openArray[Bar] = []): BarChart =
  result = BarChart(barWidth:1,barGap:1,barSet:NineLevels,direction:Direction.Vertical)
  if bars.len > 0: result.data.add(initBarGroup(bars))
func groupedBarChart*(groups: openArray[BarGroup]): BarChart =
  result = initBarChart()
  result.data = @groups
func withData*(chart: BarChart, group: BarGroup): BarChart =
  result = chart
  if group.bars.len > 0: result.data.add(group)
func withData*(chart: BarChart, bars: openArray[Bar]): BarChart = chart.withData(initBarGroup(bars))
func withBlock*(chart: BarChart, b: Block): BarChart =
  result = chart
  result.blockWidget = some(b)
func withMax*(chart: BarChart, value: uint64): BarChart =
  result = chart
  result.maxValue = some(value)
template config(name,field: untyped, T: typedesc) =
  func name*(chart: BarChart, value: T): BarChart =
    result = chart
    result.field = value
config(withStyle,style,Style)
config(withBarStyle,barStyle,Style)
config(withValueStyle,valueStyle,Style)
config(withLabelStyle,labelStyle,Style)
config(withBarSet,barSet,BarSet)
config(withDirection,direction,Direction)
func withBarWidth*(chart: BarChart, value: int): BarChart =
  result = chart
  result.barWidth = clamp(value,0,MaxCoordinate)
func withBarGap*(chart: BarChart, value: int): BarChart =
  result = chart
  result.barGap = clamp(value,0,MaxCoordinate)
func withGroupGap*(chart: BarChart, value: int): BarChart =
  result = chart
  result.groupGap = clamp(value,0,MaxCoordinate)
func groupTicks(chart: BarChart, available,maxLength:int): seq[seq[int]] =
  var maximum = 1'u64
  for group in chart.data:
    for bar in group.bars: maximum = max(maximum,bar.value)
  maximum = max(1'u64,chart.maxValue.get(maximum))
  var space = available
  for group in chart.data:
    if space == 0: break
    let width = group.bars.len*chart.barWidth+max(0,group.bars.len-1)*chart.barGap
    var n = group.bars.len
    if space > width: space = max(0,space-width-chart.groupGap-chart.barGap)
    else:
      n = (space+chart.barGap) div (chart.barWidth+chart.barGap)
      if n == 0: break
      space = 0
    var ticks: seq[int]
    for i in 0..<min(n,group.bars.len): ticks.add(scaleFraction(group.bars[i].value,maximum,maxLength*8))
    result.add(ticks)
proc groupLabel(group: BarGroup, area: Rect, buf: var Buffer, style: Style) =
  if group.label.isNone: return
  let line = group.label.get
  let width = min(MaxCoordinate,line.width)
  let offset = case line.alignment.get(Alignment.Left)
    of Alignment.Left: 0
    of Alignment.Center: max(0,area.width-width) div 2
    of Alignment.Right: max(0,area.width-width)
  let a = initRect(area.x+offset,area.y,width,area.height).intersection(buf.area)
  buf.setStyle(a,style)
  line.render(a,buf)
proc barLabel(bar: Bar, width,x,y:int, buf: var Buffer, style: Style) =
  if bar.label.isNone: return
  let line = bar.label.get
  let w = min(width,line.width)
  let a = initRect(x+(width-w) div 2,y,w,1)
  buf.setStyle(a,style)
  line.render(a,buf)
proc render*(chart: BarChart, area: Rect, buf: var Buffer) =
  let clipped = area.intersection(buf.area)
  buf.setStyle(clipped,chart.style)
  chart.blockWidget.render(clipped,buf)
  let a = chart.blockWidget.inner(clipped).intersection(buf.area)
  if a.isEmpty or chart.data.len == 0 or chart.barWidth == 0: return
  if chart.direction == Direction.Vertical:
    var barLabels, groupLabels = false
    if a.height > 1:
      for group in chart.data:
        groupLabels = groupLabels or group.label.isSome
        for bar in group.bars: barLabels = barLabels or bar.label.isSome
      if a.height == 2 and barLabels: groupLabels = false
    let labels = ord(barLabels)+ord(groupLabels)
    let h = a.height-labels
    let ticks = chart.groupTicks(a.width,h)
    var x = a.x
    for gi,groupTicks in ticks:
      let group = chart.data[gi]
      if groupLabels:
        group.groupLabel(initRect(x,a.bottom-1,max(0,groupTicks.len*(chart.barWidth+chart.barGap)-chart.barGap),1),buf,chart.labelStyle)
      for bi,barTicks in groupTicks:
        let bar = group.bars[bi]
        var t = barTicks
        let style = chart.barStyle.patch(bar.style)
        for y in countdown(a.y+h-1,a.y):
          for dx in 0..<chart.barWidth:
            if buf.area.contains(x+dx,y):
              buf[x+dx,y].symbol = chart.barSet.level(min(8,t))
              buf[x+dx,y].setStyle(style)
          t = max(0,t-8)
        if barLabels: bar.barLabel(chart.barWidth,x,a.y+h,buf,chart.labelStyle)
        if bar.value != 0:
          let value = bar.textValue.get($bar.value)
          let width = displayWidth(value)
          if width < chart.barWidth or (width == chart.barWidth and barTicks >= 8):
            buf.setString(x+max(0,chart.barWidth-value.len) div 2,a.y+h-1,value,chart.valueStyle.patch(bar.valueStyle))
        x += chart.barGap+chart.barWidth
      x += chart.groupGap
  else:
    var labelWidth = 0
    for group in chart.data:
      for bar in group.bars:
        if bar.label.isSome: labelWidth = max(labelWidth,bar.label.get.width)
    let x = a.x+labelWidth+ord(labelWidth != 0)
    let w = max(0,a.right-x)
    let ticks = chart.groupTicks(a.height,w)
    var y = a.y
    for gi,groupTicks in ticks:
      let group = chart.data[gi]
      for bi,barTicks in groupTicks:
        let bar = group.bars[bi]
        let length = barTicks div 8
        let style = chart.barStyle.patch(bar.style)
        for dy in 0..<chart.barWidth:
          for dx in 0..<w:
            if buf.area.contains(x+dx,y+dy):
              buf[x+dx,y+dy].symbol = if dx < length: chart.barSet.full else: chart.barSet.empty
              buf[x+dx,y+dy].setStyle(style)
        let row = y+chart.barWidth div 2
        if bar.label.isSome: buf.setLine(a.x,row,bar.label.get,labelWidth)
        let value = bar.textValue.get($bar.value)
        if value.len > 0:
          buf.setStringn(x,row,value,length,chart.valueStyle.patch(bar.valueStyle))
          if value.len > length:
            var boundary = min(length,value.len)
            while boundary < value.len and (ord(value[boundary]) and 0xC0) == 0x80: inc boundary
            if boundary <= w: buf.setStringn(x+boundary,row,value[boundary..^1],w-boundary,style)
        y += chart.barGap+chart.barWidth
      let labelY = y-chart.barGap
      if chart.groupGap > 0 and labelY < a.bottom:
        group.groupLabel(initRect(x,labelY,w,a.height),buf,chart.labelStyle)
        y += chart.groupGap
