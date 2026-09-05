## Native layout solver benchmark; release build recommended.
import std/[monotimes, times, strformat]

import canopy/core/layout/geometry
import canopy/core/layout/index as layout

let arrangement = horizontal([length(8), minLength(3), percentage(20), ratio(1, 7),
                         maxLength(15), fill(2), fill(1), length(4)]).withSpacing(1)
# The checksum only keeps the solver's results live so the loop is not optimized away.
var checksum = 0
# Measure the solver itself first, then the cache hit path with a warmed entry.
setLayoutCacheSize(0)
let start = getMonoTime()
for i in 0..<1000:
  let segments = arrangement.split(initRect(0, 0, 100 + i mod 20, 24))
  checksum += segments[0].width
let uncached = (getMonoTime() - start).inNanoseconds.float64 / 1e6
setLayoutCacheSize(500)
discard arrangement.split(initRect(0, 0, 120, 24))
let cachedStart = getMonoTime()
for i in 0..<100_000:
  let segments = arrangement.split(initRect(0, 0, 120, 24))
  checksum += segments[0].width
let cached = (getMonoTime() - cachedStart).inNanoseconds.float64 / 1e6
echo &"8 constraints: 1000 uncached splits {uncached:.2f} ms; 100000 cached splits {cached:.2f} ms; checksum={checksum}"
