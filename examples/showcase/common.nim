## State and helpers shared by every showcase page.
import std/[os, strutils]

import canopy
import canopy/runtime/terminal/input
import canopy/ui/animation/index as animation

const themeNames* = ["Blue", "Magenta", "Green", "Red"]

var
  themeIndex* = 0
  animator* = initAnimator()
    ## One animator drives every page, so reduced motion applies everywhere at once.
  roundPills* = getEnv("TERM_PROGRAM").toLowerAscii in ["ghostty", "wezterm"] or
    getEnv("TERM").toLowerAscii.contains("kitty")
    ## Rounded pill ends use Powerline glyphs. These terminals draw them without a Nerd
    ## Font; `--round` and `--square` override the guess.

proc accentColor*(): Color =
  ## Bright named colors follow the terminal's palette and keep black pill text readable.
  color([ColorKind.LightBlue, ColorKind.LightMagenta, ColorKind.LightGreen,
    ColorKind.LightRed][themeIndex])

proc accent*(): Style = initStyle().withFg(accentColor())
proc muted*(): Style = initStyle().withFg(ColorKind.DarkGray)
proc highlight*(): Style = initStyle().withFg(ColorKind.Black).withBg(accentColor()).bold()

proc panel*(title: string): Block =
  ## Quiet rounded frame: gray lines, an accent title and one column of side padding.
  result = borderedBlock().withBorderType(BorderType.Rounded).withBorderStyle(muted())
    .withPadding(horizontalPadding(1))
  if title.len > 0:
    result = result.withTitle(initLine([initSpan("─", muted()),
      initSpan(" " & title & " ", accent().bold())]))

proc meter*(): Style =
  ## Gauge colors: accent fill on a black track, so the label inverts cleanly over both.
  initStyle().withFg(accentColor()).withBg(ColorKind.Black)

proc pillTitles(names: openArray[string], selected: int, numbered: bool): seq[Line] =
  # Every pill keeps one cell on each side, filled by a rounded cap or a space when selected
  # and by a plain space otherwise, so widths never change with the selection.
  for i, name in names:
    let number = if numbered: $(i + 1) & " " else: ""
    if i != selected:
      result.add(initLine([initSpan(" " & number, muted()), initSpan(name & " ")]))
    elif roundPills:
      let cap = initStyle().withFg(accentColor())
      result.add(initLine([initSpan("\uE0B6", cap), initSpan(number & name, highlight()),
        initSpan("\uE0B4", cap)]))
    else:
      result.add(initLine(initSpan(" " & number & name & " ", highlight())))

proc pillsWidth*(names: openArray[string], numbered = false): int =
  for title in pillTitles(names, -1, numbered): result += title.width
  result += max(0, names.len - 1)

proc renderPills*(frame: var Frame, area: Rect, names: openArray[string], selected: int,
    hits: var openArray[Rect], numbered = false) =
  ## Tabs drawn as pills: the selected one filled with the accent, one space between them.
  ## The titles carry their own colors, because a highlight would also paint the caps' background.
  let titles = pillTitles(names, selected, numbered)
  frame.renderWidget(initTabs(titles).withSelected(selected).withPadding("", "").withDivider(" ")
    .withHighlightStyle(initStyle()), area)
  var x = area.x
  for i, title in titles:
    hits[i] = initRect(x, area.y, title.width, 1).intersection(area)
    x += title.width + 1

proc button*(primary: bool): Block =
  ## Filled blocks make buttons read as solid controls rather than more panels.
  filledBlock(if primary: accentColor() else: color(ColorKind.DarkGray))

proc buttonLabel*(label: string, primary: bool): Line =
  initLine(initSpan(label, initStyle().withFg(if primary: ColorKind.Black else: ColorKind.White)
    .bold())).centered()

proc keyHints*(text: string): seq[Span] =
  ## Styles "key: action · key: action" help text with accent keys and gray actions.
  let hints = text.split(" · ")
  for i, hint in hints:
    if i > 0: result.add(initSpan("  ", muted()))
    let colon = hint.find(": ")
    if colon < 0: result.add(initSpan(hint, muted()))
    else:
      result.add(initSpan(hint[0..<colon], accent().bold()))
      result.add(initSpan(" " & hint[colon + 2..^1], muted()))

func isPress*(event: input.Event): bool =
  event.kind == input.EventKind.Key and event.key.kind != KeyEventKind.Release

func leftClick*(event: input.Event): Option[Position] =
  if event.kind == input.EventKind.Mouse and event.mouse.kind == MouseEventKind.Down and
      event.mouse.button == some(MouseButton.Left):
    result = some(initPosition(event.mouse.column, event.mouse.row))

func wheel*(event: input.Event, area: Rect): int =
  ## -1 or 1 when the mouse wheel turns over `area`, otherwise 0.
  if event.kind != input.EventKind.Mouse or
      not area.contains(initPosition(event.mouse.column, event.mouse.row)): return 0
  case event.mouse.kind
  of MouseEventKind.ScrollUp: -1
  of MouseEventKind.ScrollDown: 1
  else: 0

proc wakeWithin*(timeout: var int, milliseconds: int) =
  ## Shortens the event-poll timeout; a negative value means "no deadline".
  if milliseconds >= 0:
    timeout = if timeout < 0: milliseconds else: min(timeout, milliseconds)

func centeredRect*(area: Rect, width, height: int): Rect =
  let w = min(width, area.width)
  let h = min(height, area.height)
  initRect(area.x + (area.width - w) div 2, area.y + (area.height - h) div 2, w, h)

var lastFrame*: Buffer
  ## The previously drawn screen; buffer transitions animate from it.
