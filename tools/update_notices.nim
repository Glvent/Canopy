## Regenerate the source-distribution notices without additional tools.
import std/[os, algorithm, strutils]

var paths = @["LICENSE"]
for path in walkDirRec("licenses"):
  if fileExists(path): paths.add(path)
paths.sort()
var output = "Canopy and third-party license notices\n\n"
for path in paths:
  output.add(path & "\n" & repeat('=', path.len) & "\n" & readFile(path).strip & "\n\n")
writeFile("src/canopy/THIRD_PARTY_NOTICES.txt", output)
