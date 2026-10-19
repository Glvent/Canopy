## Portable Nim-only test/example runner; Rust fixture generation is separate.
import std/[os, osproc, strutils, algorithm]

let examples = paramCount() > 0 and paramStr(1) == "examples"
let folder = if examples: "examples" else: "tests"
var files: seq[string]
if examples:
  for file in walkFiles(folder / "*.nim"): files.add(file)
else:
  for file in walkDirRec(folder):
    let name = extractFilename(file)
    if name.startsWith("test_") and name.endsWith(".nim"): files.add(file)
files.sort()
var names: seq[string]
for file in files:
  let name = splitFile(file).name
  if name in names: quit("Duplicate test name: " & name, 1)
  names.add(name)
let manager = if defined(gcArc): "arc" else: "orc"
let outputDir = "build" / (NimVersion & "-" & manager)
createDir(outputDir)
echo "Nim ", NimVersion, " / ", manager
for file in files:
  let output = outputDir / splitFile(file).name
  let command = "nim c " & (if examples: "" else: "-r ") &
    "--path:src --hints:off --mm:" & manager &
    " --nimcache:" & quoteShell(outputDir / "nimcache" / splitFile(file).name) &
    " --out:" & quoteShell(output) & " " & quoteShell(file)
  echo command
  if execCmd(command) != 0: quit(1)
if files.len == 0: quit("No " & folder & " found", 1)
