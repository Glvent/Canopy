## Stateful multiline list, matching Ratatui's viewport and selection behavior.
import std/[options, strutils]
import ../[geometry, style, text, buffer]
import "./block"
import ./state
export state

type
  ListDirection* {.pure.} = enum TopToBottom, BottomToTop
  ListItem* = object
    content*: Text
    style*: Style
  ListState* = object
    offset*: int
    selected*: Option[int]
  List* = object
    items*: seq[ListItem]
    blockWidget*: Option[Block]
    style*, highlightStyle*: Style
    highlightSymbol*: Line
    repeatHighlightSymbol*: bool
    highlightSpacing*: HighlightSpacing
    direction*: ListDirection
    scrollPadding*: int

func initListItem*(content: Text): ListItem = ListItem(content: content)
func initListItem*(content: string): ListItem = initListItem(initText(content))
func initListItem*(content: Line): ListItem = initListItem(initText([content]))
func withStyle*(item: ListItem, style: Style): ListItem =
  result = item; result.style = style
func height*(item: ListItem): int = item.content.height
proc width*(item: ListItem): int = item.content.width
func initListState*(): ListState = ListState()
func withOffset*(s: ListState, offset: int): ListState =
  result = s; result.offset = max(0,offset)
func withSelected*(s: ListState, selected: Option[int]): ListState =
  result = s; result.selected = selected
func withSelected*(s: ListState, selected: int): ListState = s.withSelected(some(max(0,selected)))
proc select*(s: var ListState, index: Option[int]) =
  s.selected = index
  if index.isNone: s.offset = 0
proc select*(s: var ListState, index: int) = s.select(some(max(0,index)))
proc selectNext*(s: var ListState) = s.select(if s.selected.isSome: min(s.selected.get,int.high-1)+1 else: 0)
proc selectPrevious*(s: var ListState) = s.select(if s.selected.isSome: max(0,s.selected.get-1) else: int.high)
proc selectFirst*(s: var ListState) = s.select(0)
proc selectLast*(s: var ListState) = s.select(int.high)
proc scrollDownBy*(s: var ListState, amount: int) = s.select(min(s.selected.get(0),int.high-max(0,amount))+max(0,amount))
proc scrollUpBy*(s: var ListState, amount: int) = s.select(max(0,s.selected.get(0)-max(0,amount)))
func initList*(items: openArray[ListItem]): List = List(items: @items)
func withItems*(list: List, items: openArray[ListItem]): List =
  result = list; result.items = @items
func withBlock*(list: List, b: Block): List =
  result = list; result.blockWidget = some(b)
func withStyle*(list: List, s: Style): List =
  result = list; result.style = s
func withHighlightStyle*(list: List, s: Style): List =
  result = list; result.highlightStyle = s
func withHighlightSymbol*(list: List, symbol: Line): List =
  result = list; result.highlightSymbol = symbol
func withHighlightSymbol*(list: List, symbol: string): List = list.withHighlightSymbol(initLine(symbol))
func withRepeatHighlightSymbol*(list: List, repeat: bool): List =
  result = list; result.repeatHighlightSymbol = repeat
func withHighlightSpacing*(list: List, spacing: HighlightSpacing): List =
  result = list; result.highlightSpacing = spacing
func withDirection*(list: List, direction: ListDirection): List =
  result = list; result.direction = direction
func withScrollPadding*(list: List, padding: int): List =
  result = list; result.scrollPadding = max(0,padding)
func len*(list: List): int = list.items.len
func isEmpty*(list: List): bool = list.items.len == 0

proc itemBounds(list: List, selected: Option[int], offset, maxHeight: int): tuple[first,last:int] =
  let offset = clamp(offset,0,list.items.high)
  result = (offset,offset)
  var height = 0
  for i in offset..<list.items.len:
    if height + list.items[i].height > maxHeight: break
    height += list.items[i].height
    inc result.last
  var display = offset
  if selected.isSome:
    let selected = clamp(selected.get,0,list.items.high)
    var padding = min(list.scrollPadding,list.items.len)
    while padding > 0:
      var surrounding = 0
      for i in max(0,selected-padding)..min(list.items.high,selected+padding):
        surrounding += list.items[i].height
      if surrounding <= maxHeight: break
      dec padding
    display = if min(selected+padding,list.items.high) >= result.last: min(selected+padding,list.items.high)
              elif max(0,selected-padding) < result.first: max(0,selected-padding)
              else: selected
  while display >= result.last:
    height += list.items[result.last].height
    inc result.last
    while height > maxHeight:
      height -= list.items[result.first].height
      inc result.first
  while display < result.first:
    dec result.first
    height += list.items[result.first].height
    while height > maxHeight:
      dec result.last
      height -= list.items[result.last].height

proc render*(list: List, area: Rect, buf: var Buffer, state: var ListState) =
  let area = area.intersection(buf.area)
  buf.setStyle(area,list.style)
  list.blockWidget.render(area,buf)
  let inner = list.blockWidget.inner(area)
  if inner.isEmpty: return
  if list.items.len == 0:
    state.select(none(int)); return
  if state.selected.isSome: state.select(clamp(state.selected.get,0,list.items.high))
  let bounds = list.itemBounds(state.selected,state.offset,inner.height)
  state.offset = bounds.first
  let symbolWidth = min(MaxCoordinate,list.highlightSymbol.width)
  let emptySymbol = initLine(repeat(' ',symbolWidth))
  let spacing = list.highlightSpacing.shouldAdd(state.selected.isSome)
  var consumed = 0
  for i in bounds.first..<bounds.last:
    let item = list.items[i]
    let itemHeight = min(MaxCoordinate,item.height)
    let y = if list.direction == ListDirection.BottomToTop: inner.bottom-consumed-itemHeight
            else: inner.y+consumed
    consumed += itemHeight
    let row = initRect(inner.x,y,inner.width,itemHeight)
    buf.setStyle(row,list.style.patch(item.style))
    let selected = state.selected == some(i)
    let contentArea = if spacing: initRect(row.x+symbolWidth,row.y,max(0,row.width-symbolWidth),row.height) else: row
    item.content.render(contentArea,buf)
    if selected: buf.setStyle(row,list.highlightStyle)
    if spacing:
      for j in 0..<item.height:
        let line = if selected and (j == 0 or list.repeatHighlightSymbol): list.highlightSymbol else: emptySymbol
        line.render(initRect(inner.x,y+j,symbolWidth,1),buf)

proc render*(list: List, area: Rect, buf: var Buffer) =
  var state = initListState()
  list.render(area,buf,state)
