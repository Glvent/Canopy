## Color parsing, conversion, and style tests.
import std/[json, os, unittest]

import canopy/core/styling/colors

let fixtures = parseFile(currentSourcePath.parentDir.parentDir / "tools/colors_fixtures.json")
suite "Pinned palette 0.7.7 color conversion":
  test "packed RGB discards high byte":
    for c in fixtures["packed"]:
      check colorFromU32(uint32(c[0].getBiggestInt)) == rgbColor(c[1].getInt, c[2].getInt, c[3].getInt)
  test "HSL/HSLuv exact bytes, wrapping, clamping and nonfinite inputs":
    var failures = 0
    for i in 0..<fixtures["cases"].len:
      let c = fixtures["cases"][i]
      let h = cast[float32](uint32(c[1].getBiggestInt))
      let s = cast[float32](uint32(c[2].getBiggestInt))
      let l = cast[float32](uint32(c[3].getBiggestInt))
      let actual = if c[0].getInt == 0: colorFromHsl(h, s, l) else: colorFromHsluv(h, s, l)
      let expected = rgbColor(c[4].getInt, c[5].getInt, c[6].getInt)
      if actual != expected:
        inc failures
        if failures <= 20: echo i, " kind=", c[0], " hsl=", h, " ", s, " ", l, " got=", actual,
            " expected=", expected
    check failures == 0
    echo fixtures["cases"].len, " color cases; manager=", (when defined(gcArc): "ARC" elif defined(
        gcOrc): "ORC" else: "other")
