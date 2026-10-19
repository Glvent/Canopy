## Core widgets: stateful List, Table and Scrollbar, Calendar, Paragraph, Logo, Mascot,
## Fill, Clear, Shadow, filled blocks and a custom widget.
import std/[monotimes, times]

import canopy
import canopy/runtime/terminal/input
import common

const help* = "↑/↓ or wheel: select · click: pick a row · ←/→: month · p: popup"

type Badge = object
  ## A custom widget is any type with a render procedure; no inheritance or registration.
  text: string
  style: Style

proc render(badge: Badge, area: Rect, buffer: var Buffer) =
  # A filled block gives the badge a solid background with soft half-block corners.
  let card = filledBlock(badge.style.fg.get(color(ColorKind.White)))
  card.render(area, buffer)
  initLine(initSpan(badge.text, initStyle().withFg(ColorKind.Black).bold())).centered()
    .render(card.inner(area), buffer)

const catalog = [
  ("Block", "Borders, titles and padding around any widget.", "no"),
  ("Paragraph", "Styled text with wrapping, alignment and scrolling.", "no"),
  ("List", "Selectable items that keep the selection in view.", "yes"),
  ("Table", "Rows and columns sized by layout constraints.", "yes"),
  ("Tabs", "A row of titles with one highlighted; the bar at the top of this app.", "no"),
  ("Scrollbar", "Shows position within content longer than its viewport.", "yes"),
  ("Calendar", "A month grid with per-date styles. ←/→ changes the month.", "no"),
  ("Chart", "Line and scatter datasets with labeled axes and a legend.", "no"),
  ("BarChart", "Grouped or single bars with values and labels.", "no"),
  ("Sparkline", "A compact bar trend for a series of numbers.", "no"),
  ("Gauge", "Block progress bar with a centered label.", "no"),
  ("LineGauge", "One-line progress bar.", "no"),
  ("Canvas", "Braille, block or dot drawing with shapes, maps and layers.", "no"),
  ("Logo / Mascot", "Canopy and Ratatui artwork drawn from block glyphs.", "no"),
  ("Fill / Clear", "Fill paints a region with one symbol; Clear resets it.", "no"),
  ("Shadow", "Darkens or paints the cells a widget offset exposes. Press p.", "no"),
  ("Filled block", "Solid background with soft corners; the badges and popup use it.", "no"),
  ("Custom widget", "Any type with render(widget, area, buffer) can be drawn.", "no")]

var
  listState = initListState().withSelected(0)
  tableState = initTableState().withSelected(0)
  scroll = initScrollbarState(catalog.len)
  month = initDate(now())
  popup = false
  listHit: Rect

proc select(index: int) =
  let i = (index + catalog.len) mod catalog.len
  listState.select(i)
  tableState.select(i)
  scroll = scroll.withPosition(i)

proc shiftMonth(delta: int) =
  var m = month.month - 1 + delta
  var y = month.year
  while m < 0: (m += 12; y -= 1)
  while m > 11: (m -= 12; y += 1)
  month = initDate(y, m + 1, 1)

proc render*(frame: var Frame, area: Rect) =
  # The bottom row gives up height first so the calendar keeps its six week rows.
  let rows = vertical([fill(), length(clamp(area.height - 10, 0, 11))]).split(area)
  let top = horizontal([length(26), fill(), length(25)]).split(rows[0])
  let selected = listState.selected.get(0)

  var items: seq[ListItem]
  for entry in catalog: items.add(initListItem(entry[0]))
  let listBlock = panel("List + Scrollbar")
  frame.renderStatefulWidget(initList(items).withBlock(listBlock)
    .withHighlightSymbol("› ").withHighlightStyle(highlight()), top[0], listState)
  listHit = listBlock.inner(top[0])
  scroll = scroll.withViewportContentLength(listHit.height)
  # The scrollbar replaces the panel's right border: a gray track with an accent thumb.
  let rail = initRect(top[0].x, top[0].y + 1, top[0].width, max(0, top[0].height - 2))
  frame.renderStatefulWidget(initScrollbar().withBeginSymbol(none(string))
    .withEndSymbol(none(string)).withTrackSymbol("│").withTrackStyle(muted())
    .withThumbSymbol("┃").withThumbStyle(accent()), rail, scroll)

  var tableRows: seq[Row]
  for i, entry in catalog: tableRows.add(initRow([$(i + 1), entry[0], entry[2]]))
  frame.renderStatefulWidget(initTable(tableRows, [length(3), fill(), length(8)])
    .withHeader(initRow(["#", "Widget", "Stateful"]).withStyle(accent().bold()))
    .withRowHighlightStyle(highlight()).withHighlightSymbol("› ")
    .withBlock(panel("Table")), top[1], tableState)

  var dates = todayEvents(highlight())
  frame.renderWidget(initMonthly(month, dates).withShowMonthHeader(accent().bold())
    .withShowWeekdaysHeader(accent()).withShowSurrounding(initStyle().dim())
    .withBlock(panel("Calendar")), top[2])

  let bottom = horizontal([fill(), length(30), length(32)]).split(rows[1])
  frame.renderWidget(initParagraph(initText([
      initLine(initSpan(catalog[selected][0], accent().bold())),
      initLine(""),
      initLine(catalog[selected][1]),
      initLine(""),
      initLine([initSpan("Wide text clips cleanly: "), initSpan("世界 · café · 👩‍💻", accent())])]))
    .withWrap(true).withBlock(panel("Paragraph").withPadding(horizontalPadding(1))), bottom[0])

  frame.renderWidget(panel("Logo + Mascot"), bottom[1])
  let art = panel("").inner(bottom[1])
  frame.renderWidget(tinyLogo(), initRect(art.x, art.y, art.width, 2))
  frame.renderWidget(initMascot(), initRect(art.x, art.y + 2, min(28, art.width), 7).intersection(art))

  frame.renderWidget(panel("Custom widget + Fill/Clear"), bottom[2])
  let side = panel("").inner(bottom[2])
  let badges = horizontal([fill(), fill()]).split(initRect(side.x, side.y, side.width, 3))
  frame.renderWidget(Badge(text: "Badge", style: accent()), badges[0])
  frame.renderWidget(Badge(text: "Custom", style: initStyle().withFg(ColorKind.Yellow)), badges[1])
  let tile = initRect(side.x, side.y + 3, side.width, max(0, side.height - 3))
  frame.renderWidget(initFill("░").withStyle(accent().dim()), tile)
  let inset = tile.inner(initMargin(4, 1))
  frame.renderWidget(initClear(), inset)
  frame.renderWidget(initParagraph("Fill + Clear").centered(), inset)

  if popup:
    let box = centeredRect(area, 44, 7)
    frame.renderWidget(initShadow(dimmed()), box)
    frame.renderWidget(initClear(), box)
    frame.renderWidget(initParagraph("Clear erased the cells under this box.\n" &
      "The shadow dims the cells it exposes.\n\nPress p again to close.").centered()
      .withBlock(filledBlock(color(ColorKind.DarkGray)).withTitle(" Popup · Clear + Shadow ")
        .withTitleStyle(accent().bold())), box)

proc handle*(event: input.Event): bool =
  result = true
  let delta = event.wheel(listHit)
  if delta != 0: select(listState.selected.get(0) + delta); return
  let click = event.leftClick
  if click.isSome and listHit.contains(click.get):
    let index = listState.offset + click.get.y - listHit.y
    if index < catalog.len: select(index)
    return
  if not event.isPress: return false
  case event.key.code
  of KeyCode.Up: select(listState.selected.get(0) - 1)
  of KeyCode.Down: select(listState.selected.get(0) + 1)
  of KeyCode.Left: shiftMonth(-1)
  of KeyCode.Right: shiftMonth(1)
  else:
    if event.key.text == "p": popup = not popup
    else: result = false

proc update*(now: MonoTime, active: bool): int = -1
