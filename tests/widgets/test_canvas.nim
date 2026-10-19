## Canvas drawing primitive tests.
import std/[unittest, options, os]

import canopy/core/styling/style
import canopy/core/rendering/symbols
import canopy/ui/widgets/canvas
import ../support/[canvas_support, paths]

suite "Canvas":
  test "complete upstream cells":
    const fixtures = staticRead(FixturesDir / "canvas.json")
    check checkFixtures(fixtures) == 0
  test "world to grid coordinates and reversed bounds":
    var ctx = initCanvasContext(2, 2, [1.0, 2.0], [0.0, 2.0], Marker.Braille)
    let p = initPainter(ctx)
    check p.getPoint(1.0, 0.0) == some((0, 7))
    check p.getPoint(1.5, 1.0) == some((2, 4))
    check p.getPoint(2.0, 2.0) == some((3, 0))
    check p.getPoint(0.0, 0.0).isNone
    check p.bounds == ([1.0, 2.0], [0.0, 2.0])
  test "custom marker requires a single scalar":
    expect ValueError: discard initCanvas().withMarker(Marker.Custom, "ab")
