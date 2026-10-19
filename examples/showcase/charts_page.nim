## Data widgets fed by live data: Chart, Canvas, BarChart, Sparkline, Gauge and LineGauge.
import std/[math, monotimes, times]

import canopy
import canopy/runtime/terminal/input
import canopy/ui/widgets/[canvas, chart]
import common

const
  help* = "Space: pause/resume · ↑/↓: wave frequency · h: map detail"
  tickMs = 100
  days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var
  paused = false
  t = 0.0
  frequency = 4.0
  highResolution = true
  samples: seq[int]
  bars = [4, 7, 5, 9, 6, 3, 8]
  lastTick: MonoTime
  seed = 7'u32

proc nextRandom(limit: int): int =
  # A tiny LCG keeps the demo dependency-free and deterministic.
  seed = seed * 1103515245'u32 + 12345'u32
  int((seed shr 16) mod uint32(limit))

for i in 0..<80: samples.add(nextRandom(10))

proc step() =
  t += 0.25
  samples.delete(0)
  samples.add(max(0, min(12, samples[^1] + nextRandom(5) - 2)))
  let i = nextRandom(bars.len)
  bars[i] = max(1, min(10, bars[i] + nextRandom(3) - 1))

proc render*(frame: var Frame, area: Rect) =
  let rows = vertical([fill(), length(10)]).split(area)
  let top = horizontal([fill(), fill()]).split(rows[0])

  var sine, cosine: seq[CanvasPoint]
  for x in 0..80:
    let fx = float64(x) / 2
    sine.add((fx, sin((fx + t) / frequency)))
    cosine.add((fx, 0.6 * cos((fx + t) / (frequency * 0.7))))
  frame.renderWidget(initChart([
      initDataset(sine).withName("sin").withGraphType(GraphType.Line)
        .withMarker(Marker.Braille).withStyle(accent()),
      initDataset(cosine).withName("cos").withGraphType(GraphType.Scatter)
        .withMarker(Marker.Dot).withStyle(initStyle().withFg(ColorKind.Yellow))])
    .withXAxis(initAxis().withTitle("t").withBounds([0.0, 40.0]).withLabels(["0", "20", "40"]))
    .withYAxis(initAxis().withBounds([-1.2, 1.2]).withLabels(["-1", "0", "1"]))
    .withBlock(panel("Chart · line + scatter")), top[0])

  let lon = ((t * 12) mod 360) - 180
  frame.renderWidget(initCanvas().withXBounds([-180.0, 180.0]).withYBounds([-90.0, 90.0])
    .withBlock(panel("Canvas · map + layers"))
    .withPaint(proc(ctx: var CanvasContext) =
      ctx.draw(initMap(if highResolution: MapResolution.High else: MapResolution.Low,
        color(ColorKind.Green)))
      ctx.layer()
      ctx.draw(initCanvasLine(-180, 0, 180, 0, color(ColorKind.DarkGray)))
      ctx.draw(initCircle(lon, 20 * sin(t / 3), 12, accentColor()))
      ctx.draw(initRectangle(-125, 25, 60, 25, color(ColorKind.Yellow)))
      ctx.print(-175, -80, "Braille grid · shapes · labels")), top[1])

  let bottom = horizontal([fill(), fill(), fill()]).split(rows[1])
  var barItems: seq[Bar]
  for i, value in bars: barItems.add(initBar(days[i], uint64(value)).withStyle(accent()))
  frame.renderWidget(initBarChart(barItems).withBarWidth(3).withBarGap(2)
    .withBlock(panel("BarChart")), bottom[0])
  frame.renderWidget(initSparkline(samples).withStyle(accent())
    .withBlock(panel("Sparkline")), bottom[1])
  let gauges = vertical([length(5), length(5)]).split(bottom[2])
  let ratio = (sin(t / 6) + 1) / 2
  frame.renderWidget(initGauge().withRatio(ratio).withUseUnicode()
    .withLabel("Gauge " & $int(ratio * 100) & "%").withGaugeStyle(highlight())
    .withBlock(panel("Gauge")), gauges[0])
  frame.renderWidget(initLineGauge().withRatio(1 - ratio)
    .withLabel("LineGauge " & $int((1 - ratio) * 100) & "%").withFilledStyle(accent())
    .withBlock(panel("LineGauge")), gauges[1])

proc handle*(event: input.Event): bool =
  if not event.isPress: return false
  result = true
  case event.key.code
  of KeyCode.Up: frequency = max(1.0, frequency - 1)
  of KeyCode.Down: frequency = min(12.0, frequency + 1)
  else:
    case event.key.text
    of " ": paused = not paused
    of "h": highResolution = not highResolution
    else: result = false

proc update*(now: MonoTime, active: bool): int =
  ## Data only advances while the page is visible and not paused.
  if not active or paused:
    lastTick = now
    return -1
  let elapsed = int((now - lastTick).inMilliseconds)
  if elapsed >= tickMs:
    for _ in 0..<min(10, elapsed div tickMs): step()
    lastTick = now
    return tickMs
  tickMs - elapsed
