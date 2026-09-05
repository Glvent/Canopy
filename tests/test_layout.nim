## Layout solver and flex distribution tests.
import std/[unittest, json, strutils, options]

import canopy/core/layout/geometry
import canopy/core/layout/index as layout

suite "Cassowary layout":
  test "fixed arrays and constraint helper semantics":
    let l = horizontal(fromLengths([2, 3]))
    let area = initRect(0, 0, 10, 1)
    check areas[2](l, area) == [initRect(0, 0, 2, 1), initRect(2, 0, 3, 1)]
    check tryAreas[1](l, area).isNone
    check spacerAreas[3](l, area)[2] == initRect(5, 0, 5, 1)
    expect ValueError: discard areas[1](l, area)
    check percentage(33).apply(10) == 3
    check ratio(1, 0).apply(10) == 10
    check minLength(20).apply(10) == 20
    check fill(2).apply(10) == 2
  test "weighted fill and boundary rounding":
    check initLayout(Direction.Horizontal, [fill(1), fill(2)]).split(initRect(3, 7, 10, 2)) ==
      @[initRect(3, 7, 3, 2), initRect(6, 7, 7, 2)]
    check initLayout(Direction.Horizontal, [percentage(50), percentage(50)]).split(initRect(0, 0, 5, 1)) ==
      @[initRect(0, 0, 3, 1), initRect(3, 0, 2, 1)]
  test "start end center":
    let l = initLayout(Direction.Horizontal, [length(2), length(2)])
    check l.split(initRect(0, 0, 10, 1)) == @[initRect(0, 0, 2, 1), initRect(2, 0, 2, 1)]
    check l.withFlex(Flex.End).split(initRect(0, 0, 10, 1)) == @[initRect(6, 0, 2, 1), initRect(8,
        0, 2, 1)]
    check l.withFlex(Flex.Center).split(initRect(0, 0, 10, 1)) == @[initRect(3, 0, 2, 1), initRect(
        5, 0, 2, 1)]
  test "spacing and overlap have clipped spacer extents":
    let l = initLayout(Direction.Horizontal, [length(4), length(4)]).withSpacing(-2)
    let r = l.splitWithSpacers(initRect(0, 0, 10, 1))
    check r.segments == @[initRect(0, 0, 4, 1), initRect(2, 0, 4, 1)]
    check r.spacers == @[initRect(0, 0, 0, 1), initRect(4, 0, 0, 1), initRect(6, 0, 4, 1)]
  test "fill zero, ratio zero denominator, and empty":
    let area = initRect(0, 0, 10, 1)
    check initLayout(Direction.Horizontal, [fill(0), fill(1)]).split(area) ==
      @[initRect(0, 0, 0, 1), area]
    check initLayout(Direction.Horizontal, [ratio(1, 0)]).split(area) == @[area]
    check initLayout(Direction.Horizontal).splitWithSpacers(area) == (newSeq[Rect](), @[area])
  test "cache eviction, disabling, and value isolation":
    setLayoutCacheSize(1)
    let l = initLayout(Direction.Horizontal, [fill()])
    var first = l.split(initRect(0, 0, 5, 1))
    first[0].width = 99
    check l.split(initRect(0, 0, 5, 1))[0].width == 5
    discard l.split(initRect(0, 0, 6, 1))
    check layoutCacheSize() == 1
    clearLayoutCache()
    check layoutCacheSize() == 0
    setLayoutCacheSize(0)
    discard l.split(initRect(0, 0, 6, 1))
    check layoutCacheSize() == 0
    setLayoutCacheSize(DefaultLayoutCacheSize)
  test "upstream literal letter cases":
    const upstreamCases = staticRead("../tools/layout_upstream_cases.json")
    let cases = parseJson(upstreamCases)
    var failures = 0
    for item in cases:
      var constraints: seq[Constraint]
      for c in item["constraints"]:
        case c[0].getStr
        of "Length": constraints.add length(c[1].getInt)
        of "Min": constraints.add minLength(c[1].getInt)
        of "Max": constraints.add maxLength(c[1].getInt)
        of "Percentage": constraints.add percentage(c[1].getInt)
        of "Ratio": constraints.add ratio(c[1].getInt, c[2].getInt)
        of "Fill": constraints.add fill(c[1].getInt)
        else: raise newException(ValueError, "Unknown upstream constraint")
      let width = item["width"].getInt
      let l = initLayout(Direction.Horizontal, constraints).withFlex(parseEnum[Flex](item[
          "flex"].getStr))
      var actual = repeat(' ', width)
      for i, rect in l.split(initRect(0, 0, width, 1)):
        for x in rect.x..<rect.right: actual[x] = char(ord('a') + i)
      if actual != item["expected"].getStr:
        inc failures
        if failures <= 10: echo item, " actual=", actual
    check failures == 0
  test "2000 pinned mixed layouts including observed upstream alternatives":
    const mixedCases = staticRead("../tools/layout_differential_cases.json")
    let document = parseJson(mixedCases)
    let cases = if document.kind == JArray: document else: document["cases"]
    var failures = 0
    for item in cases:
      let input = item["input"]
      var constraints: seq[Constraint]
      for c in input["constraints"]:
        case c["kind"].getStr
        of "length": constraints.add length(c["value"].getInt)
        of "min": constraints.add minLength(c["value"].getInt)
        of "max": constraints.add maxLength(c["value"].getInt)
        of "percentage": constraints.add percentage(c["value"].getInt)
        of "ratio": constraints.add ratio(c["numerator"].getInt, c["denominator"].getInt)
        of "fill": constraints.add fill(c["value"].getInt)
        else: raise newException(ValueError, "Unknown constraint")
      let direction = if input["direction"].getStr ==
          "horizontal": Direction.Horizontal else: Direction.Vertical
      let l = initLayout(direction, constraints).withFlex(parseEnum[Flex](input["flex"].getStr))
        .withSpacing(input["spacing"].getInt)
        .withMargin(initMargin(input["margin"]["horizontal"].getInt, input["margin"][
            "vertical"].getInt))
      let a = input["area"]
      let actual = l.splitWithSpacers(initRect(a["x"].getInt, a["y"].getInt, a["width"].getInt, a[
          "height"].getInt))
      let encoded = %*{"segments": actual.segments, "spacers": actual.spacers}
      var matches = encoded == item["expected"]
      if item.hasKey("expectedAlternatives"):
        for candidate in item["expectedAlternatives"]:
          if encoded == candidate: matches = true
      if not matches:
        inc failures
        if failures <= 10: echo item["name"], " unexpected geometry: ", encoded
    check failures == 0
