## Basic widget rendering tests.
import std/[unittest, json, os]

import canopy
import ../support/[reference_support, paths]

suite "remaining widget reference fixtures":
  let cases = parseFile(FixturesDir / "widgets.json")["cases"]
  for fixture in cases:
    let name = fixture["name"].getStr
    if fixture["input"]["widget"].getStr in ["paragraph", "list", "table", "chart",
        "canvas"]: continue
    test name:
      let expected = fixture["expected"]
      let area = referenceRect(expected["area"])
      var buf = initBuffer(area)
      case fixture["input"]["widget"].getStr
      of "block":
        borderedBlock().withTitle(initLine(" Canopy ").withAlignment(
            Alignment.Center)).withTitleBottom(initLine(" bottom ").withAlignment(
            Alignment.Right)).withBorderType(BorderType.Double).withStyle(initStyle().withBg(
            ColorKind.Blue)).withBorderStyle(initStyle().withFg(ColorKind.Yellow)).render(area, buf)
      of "tabs":
        initTabs(["One", "界 Two", "Three"]).withBlock(borderedBlock()).withSelected(
            1).withDivider(" • ").withHighlightStyle(initStyle().withFg(ColorKind.Yellow).bold()).withPadding(
            "[", "]").render(area, buf)
      of "gauge":
        initGauge().withBlock(borderedBlock()).withRatio(0.42).withLabel("42%").withUseUnicode().withGaugeStyle(
            initStyle().withFg(ColorKind.Green).withBg(ColorKind.DarkGray).bold()).render(area, buf)
      of "lineGauge":
        initLineGauge().withBlock(borderedBlock()).withRatio(0.375).withLabel(
            "load").withFilledStyle(initStyle().withFg(ColorKind.LightGreen)).withUnfilledStyle(
            initStyle().withFg(ColorKind.DarkGray)).render(area, buf)
      of "barChart":
        let group = initBarGroup([initBar("A", 3).withStyle(initStyle().withFg(ColorKind.Red)),
            initBar("B界", 7).withStyle(initStyle().withFg(ColorKind.Green)), initBar("C",
            5).withStyle(initStyle().withFg(ColorKind.Blue))]).withLabel("Q1")
        initBarChart().withBlock(borderedBlock()).withBarWidth(3).withBarGap(1).withGroupGap(
            2).withMax(8).withData(group).withValueStyle(initStyle().withFg(
            ColorKind.Yellow)).render(area, buf)
      of "sparkline": initSparkline([0, 1, 4, 2, 8, 3, 7, 5, 9, 0]).withBlock(borderedBlock()).withMax(
          10).withStyle(initStyle().withFg(ColorKind.Magenta)).render(area, buf)
      of "scrollbar":
        var state = initScrollbarState(40).withPosition(13).withViewportContentLength(8)
        initScrollbar().withBeginSymbol("↑").withEndSymbol("↓").withTrackSymbol("│").render(
            area, buf, state)
        check state.position == expected["state"]["position"].getInt
      of "fill": initFill("界").withStyle(initStyle().withFg(rgbColor(9, 8, 7)).withBg(
          ColorKind.Black)).render(area, buf)
      of "clear":
        buf.setString(area.x, area.y, "erase me", initStyle().withFg(ColorKind.Red))
        initClear().render(area, buf)
      of "ratatuiLogo": initRatatuiLogo().render(area, buf)
      of "ratatuiMascot": initRatatuiMascot().render(area, buf)
      of "monthlyCalendar":
        var events = initCalendarEventStore()
        events.add(initDate(2024, 2, 14), initStyle().withFg(ColorKind.Red).bold())
        events.add(initDate(2024, 2, 29), initStyle().withBg(ColorKind.Blue))
        initMonthly(initDate(2024, 2, 1), events).withShowMonthHeader(initStyle().withFg(
            ColorKind.Yellow).bold()).withShowWeekdaysHeader(initStyle().withFg(
            ColorKind.Cyan)).withShowSurrounding(initStyle().withFg(
            ColorKind.DarkGray)).withDefaultStyle(initStyle().withFg(ColorKind.White)).withBlock(
            borderedBlock()).render(area, buf)
      else: raise newException(ValueError, "Missing widget adapter")
      checkReferenceBuffer(buf, expected, name)
