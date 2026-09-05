## Native-only fixture comparator; accepts a schema root or an array of cases.
import std/[json, os, strutils, sequtils]
import canopy/[geometry, layout]

proc rectangle(node: JsonNode): Rect =
  initRect(node["x"].getInt, node["y"].getInt, node["width"].getInt, node["height"].getInt)
proc decode(node: JsonNode): Layout =
  result = initLayout(if node["direction"].getStr == "horizontal": Direction.Horizontal else: Direction.Vertical)
  result.flex = parseEnum[Flex](node["flex"].getStr)
  result.spacing = node["spacing"].getInt
  result.margin = initMargin(node["margin"]["horizontal"].getInt, node["margin"]["vertical"].getInt)
  for c in node["constraints"]:
    case c["kind"].getStr
    of "length": result.constraints.add length(c["value"].getInt)
    of "min": result.constraints.add minLength(c["value"].getInt)
    of "max": result.constraints.add maxLength(c["value"].getInt)
    of "percentage": result.constraints.add percentage(c["value"].getInt)
    of "fill": result.constraints.add fill(c["value"].getInt)
    of "ratio": result.constraints.add ratio(c["numerator"].getInt, c["denominator"].getInt)
    else: raise newException(ValueError, "Unknown constraint: " & $c)

let root = parseFile(if paramCount() == 0: "tests/fixtures/layout.json" else: paramStr(1))
let cases = if root.kind == JArray: root else: root["cases"]
var failed = 0
var nativeResults = newJArray()
for item in cases:
  let layout = decode(item["input"])
  let actual = layout.splitWithSpacers(rectangle(item["input"]["area"]))
  nativeResults.add %*{"name": item["name"], "expected": {"segments": actual.segments, "spacers": actual.spacers}}
  var expected: LayoutResult
  for r in item["expected"]["segments"]: expected.segments.add rectangle(r)
  for r in item["expected"]["spacers"]: expected.spacers.add rectangle(r)
  var matches = actual == expected
  if item.hasKey("expectedAlternatives"):
    let encoded = %*{"segments": actual.segments, "spacers": actual.spacers}
    for alternative in item["expectedAlternatives"]:
      if encoded == alternative: matches = true
  if not matches:
    inc failed
    if failed <= 20:
      echo item["name"], " input=", item["input"]
      echo " expected segments=", expected.segments.mapIt((it.x, it.y, it.width, it.height))
      echo " actual segments=", actual.segments.mapIt((it.x, it.y, it.width, it.height))
echo cases.len, " layout cases; ", failed, " mismatches"
if paramCount() > 1: writeFile(paramStr(2), $nativeResults)
quit(if failed == 0: 0 else: 1)
