## Gregorian month calendar with application-supplied date styling.
import std/[tables, hashes, times, strutils, options]

import ../../core/layout/geometry
import ../../core/styling/style
import ../../core/text/index as text
import ../../core/rendering/buffer
import ../../core/layout/index as layout
import "./block"

type
  Date* = object
    year*, month*, day*: int
  CalendarEventStore* = object
    events*: Table[Date, Style]
  DateStyler* = proc(date: Date): Style {.closure.}
  Monthly* = object
    ## Only the year and month of `displayDate` matter; the day is ignored.
    ## A `none` header style hides that header rather than styling it neutrally.
    displayDate*: Date
    events*: DateStyler
    surroundingStyle*, weekdayStyle*, monthStyle*: Option[Style]
    defaultStyle*: Style
    blockWidget*: Option[Block]

func hash*(date: Date): Hash = hash((date.year, date.month, date.day))
func daysInMonth*(year, month: int): int =
  if month notin 1..12: raise newException(ValueError, "Month must be in 1..12")
  getDaysInMonth(Month(month), year)

func initDate*(year, month, day: int): Date =
  ## Raises ValueError for a day outside the given month, leap years included.
  if day < 1 or day > daysInMonth(year, month): raise newException(ValueError, "Invalid day of month")
  Date(year: year, month: month, day: day)

func initDate*(date: DateTime): Date = initDate(date.year, ord(date.month), date.monthday)
func weekday*(date: Date): int = (ord(getDayOfWeek(date.day, Month(date.month), date.year))+1) mod 7
  ## Days since Sunday, matching the Su..Sa column order of the rendered grid.
func addDays*(date: Date, days: int): Date =
  result = date
  if days >= 0:
    for i in 0..<days:
      inc result.day
      if result.day > daysInMonth(result.year, result.month):
        result.day = 1
        inc result.month
        if result.month == 13:
          result.month = 1
          inc result.year
  else:
    for i in 0..<(-days):
      dec result.day
      if result.day == 0:
        dec result.month
        if result.month == 0:
          result.month = 12
          dec result.year
        result.day = daysInMonth(result.year, result.month)

func initCalendarEventStore*(): CalendarEventStore = CalendarEventStore()
proc add*(store: var CalendarEventStore, date: Date, style: Style) = store.events[date] = style
proc getStyle*(store: CalendarEventStore, date: Date): Style = store.events.getOrDefault(date)
proc todayEvents*(style: Style): CalendarEventStore = result.add(initDate(now()), style)
proc initMonthly*(date: Date, events: DateStyler = nil): Monthly = Monthly(displayDate: date,
    events: events)
proc initMonthly*(date: Date, events: CalendarEventStore): Monthly =
  let stored = events
  initMonthly(date, proc(date: Date): Style = stored.getStyle(date))

func withShowSurrounding*(m: Monthly, style = initStyle()): Monthly =
  result = m
  result.surroundingStyle = some(style)

func withShowWeekdaysHeader*(m: Monthly, style = initStyle()): Monthly =
  result = m
  result.weekdayStyle = some(style)

func withShowMonthHeader*(m: Monthly, style = initStyle()): Monthly =
  result = m
  result.monthStyle = some(style)

func withDefaultStyle*(m: Monthly, style: Style): Monthly =
  result = m
  result.defaultStyle = style

func withBlock*(m: Monthly, b: Block): Monthly =
  result = m
  result.blockWidget = some(b)

func width*(m: Monthly): int =
  ## Seven columns of two digits plus a separating space, before any block decoration.
  result = 21
  if m.blockWidget.isSome:
    let b = m.blockWidget.get
    let left = min(MaxCoordinate, b.padding.left+ord(Border.Left in b.borders))
    let right = min(MaxCoordinate, b.padding.right+ord(Border.Right in b.borders))
    result = min(MaxCoordinate, result+left)
    result = min(MaxCoordinate, result+right)
  result = min(MaxCoordinate, result)

func height*(m: Monthly): int =
  let first = initDate(m.displayDate.year, m.displayDate.month, 1)
  result = (first.weekday+daysInMonth(first.year, first.month)+6) div 7+ord(
      m.monthStyle.isSome)+ord(m.weekdayStyle.isSome)
  if m.blockWidget.isSome:
    let b = m.blockWidget.get
    var hasTop = Border.Top in b.borders
    var hasBottom = Border.Bottom in b.borders
    for title in b.titles:
      case title.position.get(b.titlePosition)
      of TitlePosition.Top: hasTop = true
      of TitlePosition.Bottom: hasBottom = true
    # Match Block::vertical_space directly. An inner-area probe would cap
    # overhead at the probe's height and lose large padding and title rows.
    let top = min(MaxCoordinate, b.padding.top+ord(hasTop))
    let bottom = min(MaxCoordinate, b.padding.bottom+ord(hasBottom))
    result = min(MaxCoordinate, result+top)
    result = min(MaxCoordinate, result+bottom)
  result = min(MaxCoordinate, result)

proc render*(m: Monthly, area: Rect, buf: var Buffer) =
  let clipped = area.intersection(buf.area)
  m.blockWidget.render(clipped, buf)
  let a = m.blockWidget.inner(clipped).intersection(buf.area)
  let areas = vertical([length(ord(m.monthStyle.isSome)), length(ord(m.weekdayStyle.isSome)), fill()]).split(a)
  if m.monthStyle.isSome:
    initLine($Month(m.displayDate.month) & " " & $m.displayDate.year).withStyle(
        m.monthStyle.get).withAlignment(Alignment.Center).render(areas[0], buf)
  if m.weekdayStyle.isSome: initSpan(" Su Mo Tu We Th Fr Sa", m.weekdayStyle.get).render(areas[1], buf)
  let first = initDate(m.displayDate.year, m.displayDate.month, 1)
  # Start on the Sunday of the first week, which usually falls in the previous month.
  var current = first.addDays(-first.weekday)
  let nextMonth = m.displayDate.month mod 12+1
  var y = areas[2].y
  let bg = Style(bg: m.defaultStyle.bg)
  while current.month != nextMonth:
    var spans: seq[Span]
    for i in 0..<7:
      spans.add(initSpan(" ", if i == 0: initStyle() else: bg))
      let eventStyle = if m.events == nil: initStyle() else: m.events(current)
      if current.month == m.displayDate.month:
        spans.add(initSpan(align($current.day, 2), m.defaultStyle.patch(eventStyle)))
      elif m.surroundingStyle.isSome:
        spans.add(initSpan(align($current.day, 2), m.defaultStyle.patch(
            m.surroundingStyle.get).patch(eventStyle)))
      else: spans.add(initSpan("  ", bg))
      current = current.addDays(1)
    # Pinned upstream compares absolute y against buffer height, not bottom.
    # Preserve this visible behavior for buffers with a nonzero origin.
    if y < buf.area.height: buf.setLine(a.x, y, initLine(spans), a.width)
    inc y
