## Chart and sparkline rendering tests.
import std/[unittest, os]

import ../support/[canvas_support, paths]

suite "Chart":
  test "complete upstream cells":
    const fixtures = staticRead(FixturesDir / "chart.json")
    check checkFixtures(fixtures) == 0
