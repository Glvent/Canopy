import std/[os, unittest]
import ../src/canopy/[geometry, style, buffer]
import ../src/canopy/backends/ansi

proc tempFile():tuple[path:string,file:File] =
  result.path=getTempDir()/"canopy-ansi-test.tmp"
  check open(result.file,result.path,fmReadWrite)

proc readOnlyTemp():tuple[path:string,file:File] =
  result.path=getTempDir()/"canopy-ansi-read-only.tmp"
  writeFile(result.path,"")
  check open(result.file,result.path,fmRead)

proc contents(file:File):string =
  file.flushFile(); file.setFilePos(0); file.readAll()

suite "ANSI backend":
  test "encodes complete styles and cell updates":
    let tmp=tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,alternateScreen=false,rawMode=false)
    var c=initCell("界"); c.fg=rgbColor(1,2,3); c.bg=indexedColor(17); c.underlineColor=color(ColorKind.LightCyan)
    c.modifiers={Modifier.Bold,Modifier.Italic,Modifier.Underlined,Modifier.CrossedOut}
    backend.draw([(x:2,y:3,cell:c)])
    check tmp.file.contents=="\e[4;3H\e[0;38;2;1;2;3;48;5;17;58;5;14;1;3;4;9m界"
    check backend.getCursorPosition==initPosition(4,3)

  test "skip cells produce no bytes":
    let tmp=tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,false,false); var c=initCell("x"); c.diffKind=CellDiffKind.Skip
    backend.draw([(x:0,y:0,cell:c)]); check tmp.file.contents==""

  test "init and restore are idempotent and honor alternate screen":
    let tmp=tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,true,false)
    backend.init(); backend.init(); backend.hideCursor(); backend.restore(); backend.restore()
    check tmp.file.contents=="\e[?1049h\e[?25l\e[0m\e[?25h\e[?1049l"

  test "clear, region scrolling, and append emit VT commands":
    let tmp=tempFile()
    defer: close(tmp.file)
    defer: removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,false,false)
    backend.clear(); backend.clearRegion(initRect(2,1,3,2)); backend.scrollRegionUp(1,5,2); backend.scrollRegionDown(0,4,1); backend.appendLines(2)
    check tmp.file.contents=="\e[2J\e[H\e[2;3H\e[0m   \e[3;3H\e[0m   \e[2;3H\e[2;5r\e[2S\e[r\e[1;4r\e[1T\e[r\n\n"
    check backend.cursor==initPosition(3,3)

  test "backend clear types and window dimensions are available":
    let tmp=tempFile()
    defer:close(tmp.file)
    defer:removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,false,false)
    backend.clearRegion(ClearType.All);backend.clearRegion(ClearType.AfterCursor)
    backend.clearRegion(ClearType.BeforeCursor);backend.clearRegion(ClearType.CurrentLine)
    backend.clearRegion(ClearType.UntilNewLine)
    check tmp.file.contents=="\e[2J\e[0J\e[1J\e[2K\e[0K"
    check backend.windowSize.columnsRows==initSize(80,24)

  test "read-only output errors propagate":
    let tmp=readOnlyTemp()
    defer:close(tmp.file)
    defer: removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,false,false)
    expect IOError: backend.showCursor()

  test "failed initialization rolls native state back":
    let tmp=readOnlyTemp()
    defer:close(tmp.file)
    defer: removeFile(tmp.path)
    var backend=initAnsiBackend(tmp.file,tmp.file,true,false)
    expect IOError:backend.init()
    check not backend.initialized
    backend.restore()
