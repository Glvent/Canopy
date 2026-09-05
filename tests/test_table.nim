import std/[unittest,options]
import canopy/[buffer,text,geometry,style,layout]
import canopy/widgets/table

suite "Table upstream geometry and state cases":
  test "header, footer and their margins":
    let rows = [initRow(["Cell1","Cell2"]),initRow(["Cell3","Cell4"])]
    let base = initTable(rows,[length(5),length(5)])
    var buf = initBuffer(initRect(0,0,15,3))
    base.withHeader(initRow(["Head1","Head2"])).render(buf.area,buf)
    check buf == initBuffer(["Head1 Head2    ","Cell1 Cell2    ","Cell3 Cell4    "])
    buf.reset()
    base.withFooter(initRow(["Foot1","Foot2"]).withTopMargin(1)).render(buf.area,buf)
    check buf == initBuffer(["Cell1 Cell2    ","               ","Foot1 Foot2    "])
    buf.reset()
    base.withHeader(initRow(["Head1","Head2"]).withBottomMargin(1)).render(buf.area,buf)
    check buf == initBuffer(["Head1 Head2    ","               ","Cell1 Cell2    "])
  test "partial tall row renders remaining lines":
    let rows = [initRow(["Cell1","Cell2"]),initRow(["Cell3-Line1\nCell3-Line2\nCell3-Line3","Cell4-Line1\nCell4-Line2\nCell4-Line3"]).withHeight(3)]
    var buf = initBuffer(initRect(0,0,23,3))
    initTable(rows,[length(11),length(11)]).render(buf.area,buf)
    check buf == initBuffer(["Cell1       Cell2      ","Cell3-Line1 Cell4-Line1","Cell3-Line2 Cell4-Line2"])
  test "row then column then cell highlight precedence":
    let widget = initTable([initRow(["abc","def"]),initRow(["ghi","jkl"])],[length(3),length(3)]).
      withRowHighlightStyle(initStyle().withFg(ColorKind.Red)).
      withColumnHighlightStyle(initStyle().withBg(ColorKind.Blue)).
      withCellHighlightStyle(initStyle().withFg(ColorKind.Green))
    var state = initTableState().withSelectedCell((0,1))
    var buf = initBuffer(initRect(0,0,7,3))
    widget.render(buf.area,buf,state)
    check buf[0,0].fg == color(ColorKind.Red)
    check buf[4,0].fg == color(ColorKind.Green)
    check buf[4,0].bg == color(ColorKind.Blue)
    check buf[4,2].bg == color(ColorKind.Blue)
  test "column span consumes columns and spacing, zero span consumes neither":
    let widget = initTable([initRow([initTableCell("skip").withColumnSpan(0),initTableCell("abcdefg").withColumnSpan(2),initTableCell("xyz")])], [length(3),length(3),length(3)])
    var buf = initBuffer(initRect(0,0,11,1))
    widget.render(buf.area,buf)
    check buf == initBuffer(["abcdefg xyz"])
  test "empty data clears selections and clamp ignores incorrect widths":
    var state = initTableState().withSelectedCell((int.high,int.high)).withOffset(99)
    var buf = initBuffer(initRect(0,0,5,2))
    initTable([initRow(["a","b"])],[length(2)]).render(buf.area,buf,state)
    check state.selectedCell == some((0,1))
    initTable(newSeq[Row]()).render(buf.area,buf,state)
    check state.selectedCell.isNone
    check state.offset == 0
  test "percentage validation and navigation":
    expect ValueError: discard initTable(newSeq[Row](),[percentage(101)])
    var state = initTableState()
    state.selectPreviousColumn()
    state.selectLast()
    check state.selectedCell == some((int.high,int.high))
    state.selectCell(none(tuple[row,column:int]))
    state.scrollRightBy(2)
    state.scrollDownBy(3)
    check state.selectedCell == some((3,2))
