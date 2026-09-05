## A horizontal sequence of selectable titles.
import std/options
import ../[geometry, style, text, buffer]
import "./block"
type Tabs* = object
  titles*: seq[Line]
  blockWidget*: Option[Block]
  style*, highlightStyle*: Style
  selected*: Option[int]
  divider*: Span
  paddingLeft*, paddingRight*: Line
func initTabs*(titles: openArray[Line]): Tabs =
  Tabs(titles: @titles,selected:some(0),divider:initSpan("│"),paddingLeft:initLine(" "),paddingRight:initLine(" "),highlightStyle:initStyle().reversed())
func initTabs*(titles: openArray[string]): Tabs =
  var lines: seq[Line]
  for title in titles: lines.add(initLine(title))
  initTabs(lines)
func withTitles*(tabs: Tabs, titles: openArray[Line]): Tabs =
  result = tabs
  result.titles = @titles
func withBlock*(tabs: Tabs, b: Block): Tabs =
  result = tabs
  result.blockWidget = some(b)
func withStyle*(tabs: Tabs, style: Style): Tabs =
  result = tabs
  result.style = style
func withHighlightStyle*(tabs: Tabs, style: Style): Tabs =
  result = tabs
  result.highlightStyle = style
func withSelected*(tabs: Tabs, selected: Option[int]): Tabs =
  result = tabs
  result.selected = selected
func withSelected*(tabs: Tabs, selected:int): Tabs = tabs.withSelected(some(selected))
func withDivider*(tabs: Tabs, divider: Span): Tabs =
  result = tabs
  result.divider = divider
func withDivider*(tabs: Tabs, divider: string): Tabs = tabs.withDivider(initSpan(divider))
func withPadding*(tabs: Tabs, left,right: Line): Tabs =
  result = tabs
  result.paddingLeft = left
  result.paddingRight = right
func withPadding*(tabs: Tabs, left,right:string): Tabs = tabs.withPadding(initLine(left),initLine(right))
func withPaddingLeft*(tabs: Tabs, padding: Line): Tabs =
  result = tabs
  result.paddingLeft = padding
func withPaddingRight*(tabs: Tabs, padding: Line): Tabs =
  result = tabs
  result.paddingRight = padding
proc render*(tabs: Tabs, area: Rect, buf: var Buffer) =
  let clipped = area.intersection(buf.area)
  buf.setStyle(clipped,tabs.style)
  tabs.blockWidget.render(clipped,buf)
  let a = tabs.blockWidget.inner(clipped).intersection(buf.area)
  if a.isEmpty: return
  var x = a.x
  for i,title in tabs.titles:
    if x >= a.right: break
    x = buf.setLine(x,a.y,tabs.paddingLeft,a.right-x).x
    if x >= a.right: break
    let finish = buf.setLine(x,a.y,title,a.right-x).x
    if tabs.selected == some(i): buf.setStyle(initRect(x,a.y,finish-x,1),tabs.highlightStyle)
    x = finish
    if x >= a.right: break
    x = buf.setLine(x,a.y,tabs.paddingRight,a.right-x).x
    if x >= a.right or i == tabs.titles.high: break
    x = buf.setSpan(x,a.y,tabs.divider,a.right-x).x
