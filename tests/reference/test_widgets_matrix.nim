## Matrix of widget combinations and regressions.
import std/[json, os, options]

import canopy
import ../support/[reference_support, paths]

let fixtures = parseFile(FixturesDir / "widgets_matrix.json")
var failures = 0
for fixture in fixtures["cases"]:
  let input = fixture["input"]
  let a = referenceRect(input["area"])
  let expected = fixture["expected"]
  let config = input["config"].getInt
  var buf = initBuffer(referenceRect(expected["area"]), initCell("."))
  let base = initStyle().withFg(ColorKind.Yellow).withBg(ColorKind.Blue).italic()
  const ratios = [0.0, 0.01, 0.375, 0.5, 0.99, 1.0]
  case input["widget"].getStr
  of "gauge":
    var w = initGauge().withRatio(ratios[config]).withStyle(base).withGaugeStyle(initStyle().withFg(
        ColorKind.Green).withBg(ColorKind.Red))
    if config mod 2 == 1: w = w.withUseUnicode()
    if config >= 3: w = w.withLabel(initSpan("界é", initStyle().withFg(ColorKind.Cyan)))
    w.render(a, buf)
  of "lineGauge":
    var w = initLineGauge().withRatio(ratios[config]).withStyle(base).withFilledStyle(initStyle().withFg(
        ColorKind.Green)).withUnfilledStyle(initStyle().withFg(ColorKind.Red))
    if config >= 3: w = w.withLabel("界").withFilledSymbol("=").withUnfilledSymbol("-")
    w.render(a, buf)
  of "tabs":
    var w = initTabs(["one", "界é", "three"]).withStyle(base).withSelected(if config == 5: none(
        int) else: some(config)).withHighlightStyle(initStyle().withBg(ColorKind.Red).bold())
    if config mod 2 == 1: w = w.withPadding("[", "]").withDivider(" • ")
    w.render(a, buf)
  of "barChart":
    let group = initBarGroup([initBar("zero", 0), initBar("界", 3).withStyle(initStyle().withFg(
        ColorKind.Green)).withTextValue("hi"), initBar("max", high(uint64)-1)]).withLabel(initLine(
        "group").withAlignment(Alignment.Center))
    var w = initBarChart().withData(group).withBarWidth(1+config mod 3).withBarGap(
        config mod 2).withGroupGap(1).withStyle(base).withBarStyle(initStyle().withFg(
        ColorKind.Red)).withLabelStyle(initStyle().withFg(ColorKind.Cyan)).withValueStyle(initStyle().withFg(
        ColorKind.White))
    if config mod 2 == 1: w = w.withDirection(Direction.Horizontal)
    if config >= 3: w = w.withMax(5)
    w.render(a, buf)
  of "sparkline":
    let data = [initSparklineBar(0), initSparklineBar(none(uint64)), initSparklineBar(3).withStyle(
        initStyle().withFg(ColorKind.Green)), initSparklineBar(high(uint64)), initSparklineBar(high(uint64)-1)]
    var w = initSparkline(data).withStyle(base).withAbsentValueSymbol("?").withAbsentValueStyle(
        initStyle().withFg(ColorKind.Magenta))
    if config mod 2 == 1: w = w.withDirection(RenderDirection.RightToLeft)
    if config >= 3: w = w.withMax(if config == 5: 0'u64 else: 6'u64)
    w.render(a, buf)
  of "scrollbar":
    var w = initScrollbar(ScrollbarOrientation(config mod 4)).withStyle(base).withThumbStyle(
        initStyle().withFg(ColorKind.Red))
    if config == 4: w = w.withBeginSymbol(none(string)).withEndSymbol(none(string))
    if config == 5: w = w.withTrackSymbol(none(string))
    var state = initScrollbarState(if config == 0: 0 else: 9).withPosition(
        config*2).withViewportContentLength(if config mod 2 == 0: 0 else: 12)
    w.render(a, buf, state)
  of "calendar":
    const months = [2, 1, 12, 8, 9, 6]
    let date = initDate(2024, months[config], 1)
    var events = initCalendarEventStore()
    events.add(date, initStyle().withBg(ColorKind.Red))
    var w = initMonthly(date, events).withDefaultStyle(base)
    if config mod 2 == 1: w = w.withShowSurrounding(initStyle().withFg(ColorKind.DarkGray))
    if config >= 2: w = w.withShowMonthHeader(initStyle().withFg(ColorKind.Cyan))
    if config >= 4: w = w.withShowWeekdaysHeader(initStyle().withFg(ColorKind.Magenta))
    w.render(a, buf)
  of "logo": initRatatuiLogo(RatatuiLogoSize(config mod 2)).render(a, buf)
  of "mascot": initRatatuiMascot().withEye(MascotEyeColor(config mod 2)).render(a, buf)
  else: quit("No matrix adapter", 1)
  for i, cell in buf.content:
    let want = referenceCell(expected["cells"][i])
    if cell != want:
      inc failures
      echo fixture["name"].getStr, " at ", buf.posOf(i), " got=", cell, " expected=", want
      break
echo fixtures["cases"].len, " widget matrix cases; ", failures, " failures"
if failures > 0: quit(1)
