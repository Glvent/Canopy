## Deterministic wall-clock workloads, with an observable checksum.
## Run a release build; optional positional argument multiplies iteration counts.
import std/[monotimes, times, strformat, strutils, os]
import canopy

let scale = if paramCount() == 0: 1 else: parseInt(paramStr(1))
if scale < 1 or scale > 100: quit("Scale must be between 1 and 100", 1)
const manager = when defined(gcOrc): "orc" elif defined(gcArc): "arc" else: "other"
echo &"Nim {NimVersion}; {hostOS}/{hostCPU}; mm={manager}; seed=302; scale={scale}"
var checksum = 0'u64
var seed = 302'u32
proc nextInt(limit: int): int =
  seed = seed * 1664525'u32 + 1013904223'u32
  int(seed mod uint32(limit))
template measure(name: string, count: int, body: untyped) =
  block:
    let iterations = count * scale
    let started = getMonoTime()
    for iteration {.inject.} in 0..<iterations: body
    let milliseconds = float64((getMonoTime() - started).inNanoseconds) / 1_000_000.0
    echo name, ": iterations=", iterations, "; elapsed_ms=", milliseconds.formatFloat(ffDecimal, 3),
      "; us_per_iteration=", (milliseconds * 1000 / float64(iterations)).formatFloat(ffDecimal, 3)

let constraints = [length(12), percentage(20), minLength(8), maxLength(35),
                   ratio(1, 7), fill(1), fill(2), length(6)]
let layout = horizontal(constraints).withSpacing(1).withFlex(Flex.Start)
let area = initRect(3, 2, 180, 50)
setLayoutCacheSize(0)
measure("layout uncached (8 constraints)", 1000):
  for part in layout.split(area): checksum += uint64(part.x + part.width)
setLayoutCacheSize(DefaultLayoutCacheSize)
discard layout.split(area)
measure("layout cached (8 constraints)", 100_000):
  for part in layout.split(area): checksum += uint64(part.x + part.width)

var words: seq[string]
for i in 0..<1500:
  words.add(["Canopy", "native", "Unicode世界", "café", "layout", "buffer", "widgets"][nextInt(7)])
let paragraph = initParagraph(words.join(" ")).withWrap(true)
let paragraphArea = initRect(0, 0, 100, 40)
var paragraphBuffer = initBuffer(paragraphArea)
measure("paragraph wrap (1500 words, 100x40)", 100):
  paragraphBuffer.reset()
  paragraph.withScroll(iteration mod 20, 0).render(paragraphArea, paragraphBuffer)
  checksum += uint64(paragraphBuffer.content[iteration mod paragraphBuffer.content.len].symbol.len)

var rows: seq[Row]
for i in 0..<10_000:
  rows.add initRow([$i, "item " & $nextInt(100_000), "世界 " & $nextInt(1000),
                    $nextInt(100_000), ["ready", "pending", "active"][nextInt(3)], "row " & $i])
let table = initTable(rows, [length(8), fill(2), fill(2), fill(1), length(10), fill(2)])
  .withHeader(initRow(["ID", "Item", "Name", "Value", "Status", "Details"]))
let tableArea = initRect(0, 0, 160, 50)
var tableBuffer = initBuffer(tableArea)
var state = initTableState()
measure("table render (10000x6 data, 160x50 viewport)", 200):
  tableBuffer.reset()
  state.select((iteration * 47) mod rows.len)
  table.render(tableArea, tableBuffer, state)
  checksum += uint64(state.offset + tableBuffer.content[160].symbol.len)

let diffArea = initRect(0, 0, 240, 80)
var before = initBuffer(diffArea)
var after = initBuffer(diffArea)
for i in 0..<before.content.len:
  let symbol = $char(ord('a') + nextInt(26))
  before.content[i].setSymbol(symbol)
  after.content[i].setSymbol(symbol)
  if i mod 20 == 0:
    after.content[i].setSymbol("#")
    after.content[i].setFg(indexedColor(nextInt(256)))
measure("buffer diff (240x80, 5% changed)", 1000):
  checksum += uint64(diff(before, after).len)
echo "checksum=", checksum
