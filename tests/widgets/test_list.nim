## List widget selection and highlight tests.
import std/[unittest, options]

import canopy/core/rendering/buffer
import canopy/core/text/index as text
import canopy/core/layout/geometry
import canopy/core/styling/style
import canopy/ui/widgets/list

proc items(values: openArray[string]): seq[ListItem] =
  for value in values: result.add initListItem(value)

suite "List upstream selection and viewport cases":
  test "bottom-to-top keeps item zero at bottom":
    var buf = initBuffer(initRect(0, 0, 10, 4))
    initList(items(["Item 0", "Item 1", "Item 2"])).withDirection(ListDirection.BottomToTop).render(
        buf.area, buf)
    check buf == initBuffer(["          ", "Item 2    ", "Item 1    ", "Item 0    "])
  test "selection before and after offset scrolls into view":
    let widget = initList(items(["Item 0", "Item 1", "Item 2", "Item 3", "Item 4", "Item 5",
        "Item 6"])).withHighlightSymbol(">>")
    var state = initListState().withSelected(1).withOffset(3)
    var buf = initBuffer(initRect(0, 0, 10, 3))
    widget.render(buf.area, buf, state)
    check state.offset == 1
    check buf == initBuffer([">>Item 1  ", "  Item 2  ", "  Item 3  "])
    state = initListState().withSelected(6).withOffset(3)
    buf.reset()
    widget.render(buf.area, buf, state)
    check state.offset == 4
    check buf == initBuffer(["  Item 4  ", "  Item 5  ", ">>Item 6  "])
  test "inconsistent heights reduce scroll padding":
    let widget = initList(items(["Item 0", "Item 1", "Item 2", "Item 3", "Item 4\nTest\nTest",
        "Item 5"])).withScrollPadding(1).withHighlightSymbol(">> ")
    var state = initListState().withSelected(3)
    var buf = initBuffer(initRect(0, 0, 10, 3))
    widget.render(buf.area, buf, state)
    check buf == initBuffer(["   Item 1 ", "   Item 2 ", ">> Item 3 "])
  test "symbol style overrides selection and repeats on multiline items":
    let symbol = initLine(">>").withFg(ColorKind.Red).bold()
    let widget = initList(items(["Item 0\nLine 2", "Item 1", "Item 2"])).withHighlightSymbol(
        symbol).withRepeatHighlightSymbol(true).withHighlightStyle(initStyle().withFg(
        ColorKind.Yellow))
    var state = initListState().withSelected(0)
    var buf = initBuffer(initRect(0, 0, 10, 5))
    widget.render(buf.area, buf, state)
    check buf[0, 0].fg == color(ColorKind.Red)
    check buf[0, 1].fg == color(ColorKind.Red)
    check Modifier.Bold in buf[0, 1].modifiers
    check buf[2, 1].fg == color(ColorKind.Yellow)
    check buf[2, 2].fg == color(ColorKind.Reset)
  test "empty and out-of-range selection and state navigation":
    var state = initListState().withSelected(int.high).withOffset(100)
    var buf = initBuffer(initRect(0, 0, 4, 2))
    initList(items(["a", "b"])).render(buf.area, buf, state)
    check state.selected == some(1)
    initList(newSeq[ListItem]()).render(buf.area, buf, state)
    check state.selected.isNone
    check state.offset == 0
    state.selectPrevious()
    check state.selected == some(int.high)
    state.select(none(int))
    state.selectNext()
    check state.selected == some(0)
