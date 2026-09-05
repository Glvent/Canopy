## Chart and sparkline rendering tests.
import std/unittest

import ./canvas_test_support

suite "Chart":
  test "complete upstream cells":
    const fixtures = staticRead("chart_fixtures.json")
    check checkFixtures(fixtures) == 0
