## Stateful scrollbar. Position is the first displayed content item.
import std/options

import ../../core/layout/geometry
import ../../core/styling/style
import ../../core/rendering/buffer
import ../../core/text/unicode
import ../../core/rendering/symbols

type
  ScrollbarOrientation* {.pure.} = enum VerticalRight, VerticalLeft, HorizontalBottom, HorizontalTop
  ScrollDirection* {.pure.} = enum Forward, Backward
  ScrollbarState* = object
    ## `position` is the first displayed item, not a pixel or percentage.
    ## `viewportContentLength` of 0 means the scrollbar's own length is used as the viewport size.
    contentLength*, position*, viewportContentLength*: int
  ScrollbarSymbols* = object
    track*, thumb*, beginSymbol*, endSymbol*: string
  Scrollbar* = object
    orientation*: ScrollbarOrientation
    thumbSymbol*: string
    trackSymbol*, beginSymbol*, endSymbol*: Option[string]
    thumbStyle*, trackStyle*, beginStyle*, endStyle*: Style

func isVertical*(o: ScrollbarOrientation): bool = o in {ScrollbarOrientation.VerticalLeft,
    ScrollbarOrientation.VerticalRight}
func isHorizontal*(o: ScrollbarOrientation): bool = not o.isVertical
func initScrollbarState*(contentLength: int): ScrollbarState = ScrollbarState(contentLength: max(0,
    contentLength))
func withContentLength*(s: ScrollbarState, n: int): ScrollbarState =
  result = s
  result.contentLength = max(0, n)

func withPosition*(s: ScrollbarState, n: int): ScrollbarState =
  result = s
  result.position = max(0, n)

func withViewportContentLength*(s: ScrollbarState, n: int): ScrollbarState =
  result = s
  result.viewportContentLength = max(0, n)

proc next*(s: var ScrollbarState) = s.position = min(max(0, s.contentLength-1), s.position+1)
proc prev*(s: var ScrollbarState) = s.position = max(0, s.position-1)
proc first*(s: var ScrollbarState) = s.position = 0
proc last*(s: var ScrollbarState) = s.position = max(0, s.contentLength-1)
proc scroll*(s: var ScrollbarState, direction: ScrollDirection) =
  if direction == ScrollDirection.Forward: s.next() else: s.prev()

func initScrollbar*(orientation = ScrollbarOrientation.VerticalRight): Scrollbar =
  result.orientation = orientation
  result.thumbSymbol = "█"
  result.trackSymbol = some(if orientation.isVertical: "║" else: "═")
  result.beginSymbol = some(if orientation.isVertical: "▲" else: "◄")
  result.endSymbol = some(if orientation.isVertical: "▼" else: "►")

func withOrientation*(s: Scrollbar, orientation: ScrollbarOrientation): Scrollbar =
  result = s
  result.orientation = orientation

func withThumbSymbol*(s: Scrollbar, symbol: string): Scrollbar =
  result = s
  result.thumbSymbol = symbol

template optionalSymbol(name, field: untyped) =
  func name*(s: Scrollbar, symbol: Option[string]): Scrollbar =
    result = s
    result.field = symbol
  func name*(s: Scrollbar, symbol: string): Scrollbar = name(s, some(symbol))
optionalSymbol(withTrackSymbol, trackSymbol)
optionalSymbol(withBeginSymbol, beginSymbol)
optionalSymbol(withEndSymbol, endSymbol)

template styled(name, field: untyped) =
  func name*(s: Scrollbar, style: Style): Scrollbar =
    result = s
    result.field = style
styled(withThumbStyle, thumbStyle)
styled(withTrackStyle, trackStyle)
styled(withBeginStyle, beginStyle)
styled(withEndStyle, endStyle)

func withStyle*(s: Scrollbar, style: Style): Scrollbar =
  result = s
  result.thumbStyle = style
  result.trackStyle = style
  result.beginStyle = style
  result.endStyle = style

func withSymbols*(s: Scrollbar, symbols: ScrollbarSymbols): Scrollbar =
  result = s
  result.thumbSymbol = symbols.thumb
  result.trackSymbol = some(symbols.track)
  result.beginSymbol = some(symbols.beginSymbol)
  result.endSymbol = some(symbols.endSymbol)

func withSymbols*(s: Scrollbar, symbols: ScrollbarSet): Scrollbar =
  s.withSymbols(ScrollbarSymbols(track: symbols.track, thumb: symbols.thumb,
    beginSymbol: symbols.begin, endSymbol: symbols.`end`))

proc render*(s: Scrollbar, area: Rect, buf: var Buffer, state: var ScrollbarState) =
  let a = area.intersection(buf.area)
  if a.isEmpty or state.contentLength == 0: return
  let length = if s.orientation.isVertical: a.height else: a.width
  let arrows = (if s.beginSymbol.isSome: cellWidth(s.beginSymbol.get) else: 0)+(
      if s.endSymbol.isSome: cellWidth(s.endSymbol.get) else: 0)
  let track = max(0, length-arrows)
  if track == 0: return
  let viewport = if state.viewportContentLength != 0: state.viewportContentLength else: length
  let maximum = max(0, state.contentLength-1)
  let position = clamp(state.position, 0, maximum)
  # Arrow cells are excluded from the track, so a very short scrollbar can have no track at all.
  let denominator = min(high(int)-viewport, maximum)+viewport
  # Saturating products mirror upstream usize arithmetic.
  func satProduct(a, b: int): int =
    if b > 0 and a > high(int) div b: high(int) else: a*b
  func rounded(n, d: int): int = (min(high(int)-d div 2, n)+d div 2) div d
  # The thumb keeps a minimum of one cell so it stays visible for very long content.
  let thumb = if denominator == 0: track else: clamp(rounded(satProduct(viewport, track),
      denominator), 1, track)
  let start = if denominator == 0: 0 else: clamp(rounded(satProduct(position, track), denominator),
      0, track-thumb)
  var symbols: seq[tuple[symbol: Option[string], style: Style]]
  if s.beginSymbol.isSome: symbols.add((s.beginSymbol, s.beginStyle))
  for i in 0..<track:
    if i >= start and i < start+thumb: symbols.add((some(s.thumbSymbol), s.thumbStyle))
    else: symbols.add((s.trackSymbol, s.trackStyle))
  if s.endSymbol.isSome: symbols.add((s.endSymbol, s.endStyle))
  for i in 0..<min(length, symbols.len):
    if symbols[i].symbol.isNone: continue
    let x = case s.orientation
      of ScrollbarOrientation.VerticalRight: a.right-1
      of ScrollbarOrientation.VerticalLeft: a.x
      else: a.x+i
    let y = case s.orientation
      of ScrollbarOrientation.HorizontalBottom: a.bottom-1
      of ScrollbarOrientation.HorizontalTop: a.y
      else: a.y+i
    buf.setString(x, y, symbols[i].symbol.get, symbols[i].style)
