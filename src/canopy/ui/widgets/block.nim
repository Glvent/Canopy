## Border and title container shared by built-in widgets.
import std/[options, algorithm]

import ../../core/layout/geometry
import ../../core/styling/style
import ../../core/text/index as text
import ../../core/rendering/buffer
import ../../core/rendering/symbols
import ./shadow
export geometry, style, text, symbols, shadow

type
  Border* {.pure.} = enum Top, Right, Bottom, Left
  Borders* = set[Border]
  BorderType* {.pure.} = enum Plain, Rounded, Double, Thick, QuadrantInside, QuadrantOutside,
    Solid, LightDoubleDashed, HeavyDoubleDashed, LightTripleDashed, HeavyTripleDashed,
    LightQuadrupleDashed, HeavyQuadrupleDashed
  TitlePosition* {.pure.} = enum Top, Bottom
  Padding* = object
    left*, right*, top*, bottom*: int
  BlockTitle* = object
    ## `none` position and `none` line alignment inherit the block's defaults; several titles can
    ## share one edge and alignment.
    line*: Line
    position*: Option[TitlePosition]
  Block* = object
    ## `mergeBorders` decides how this block's border glyphs combine with glyphs already in the
    ## buffer, which is what makes adjacent blocks share a single line.
    borders*: Borders
    borderSet*: BorderSet
    style*, borderStyle*, titleStyle*: Style
    titles*: seq[BlockTitle]
    titleAlignment*: Alignment
    titlePosition*: TitlePosition
    padding*: Padding
    mergeBorders*: MergeStrategy
    shadow*: Option[Shadow]

const AllBorders* = {Border.Top, Border.Right, Border.Bottom, Border.Left}

func initPadding*(left, right, top, bottom: int): Padding = Padding(left: clamp(left, 0,
    MaxCoordinate), right: clamp(right, 0, MaxCoordinate), top: clamp(top, 0, MaxCoordinate),
    bottom: clamp(bottom, 0, MaxCoordinate))
func zeroPadding*(): Padding = Padding()
func uniformPadding*(value: int): Padding = initPadding(value, value, value, value)
func horizontalPadding*(value: int): Padding = initPadding(value, value, 0, 0)
func verticalPadding*(value: int): Padding = initPadding(0, 0, value, value)
func symmetricPadding*(horizontal, vertical: int): Padding = initPadding(horizontal, horizontal,
    vertical, vertical)
func proportionalPadding*(value: int): Padding =
  ## Doubles the horizontal padding, since terminal cells are about twice as tall as they are wide.
  let value = clamp(value, 0, MaxCoordinate)
  initPadding(min(MaxCoordinate, 2*value), min(MaxCoordinate, 2*value), value, value)

func leftPadding*(value: int): Padding = initPadding(value, 0, 0, 0)
func rightPadding*(value: int): Padding = initPadding(0, value, 0, 0)
func topPadding*(value: int): Padding = initPadding(0, 0, value, 0)
func bottomPadding*(value: int): Padding = initPadding(0, 0, 0, value)
func initBlock*(): Block = Block(borderSet: PlainBorder)
func borderedBlock*(): Block = Block(borders: AllBorders, borderSet: PlainBorder)
func withBorders*(b: Block, borders: Borders): Block =
  result = b
  result.borders = borders

func withStyle*(b: Block, style: Style): Block =
  result = b
  result.style = style

func withBorderStyle*(b: Block, style: Style): Block =
  result = b
  result.borderStyle = style

func withTitleStyle*(b: Block, style: Style): Block =
  result = b
  result.titleStyle = style

func withBorderSet*(b: Block, set: BorderSet): Block =
  result = b
  result.borderSet = set

func withBorderType*(b: Block, kind: BorderType): Block =
  result = b
  result.borderSet = case kind
    of BorderType.Plain: PlainBorder
    of BorderType.Rounded: RoundedBorder
    of BorderType.Double: DoubleBorder
    of BorderType.Thick: ThickBorder
    of BorderType.QuadrantInside: QuadrantInsideBorder
    of BorderType.QuadrantOutside: QuadrantOutsideBorder
    of BorderType.Solid: FullBorder
    of BorderType.LightDoubleDashed, BorderType.LightTripleDashed,
        BorderType.LightQuadrupleDashed: PlainBorder
    else: ThickBorder
  if kind >= BorderType.LightDoubleDashed:
    let horizontal = case kind
      of BorderType.LightDoubleDashed: "╌"
      of BorderType.HeavyDoubleDashed: "╍"
      of BorderType.LightTripleDashed: "┄"
      of BorderType.HeavyTripleDashed: "┅"
      of BorderType.LightQuadrupleDashed: "┈"
      else: "┉"
    let vertical = case kind
      of BorderType.LightDoubleDashed: "╎"
      of BorderType.HeavyDoubleDashed: "╏"
      of BorderType.LightTripleDashed: "┆"
      of BorderType.HeavyTripleDashed: "┇"
      of BorderType.LightQuadrupleDashed: "┊"
      else: "┋"
    result.borderSet.horizontalTop = horizontal
    result.borderSet.horizontalBottom = horizontal
    result.borderSet.verticalLeft = vertical
    result.borderSet.verticalRight = vertical

func withTitle*(b: Block, line: Line): Block =
  result = b
  result.titles.add(BlockTitle(line: line))

func withTitle*(b: Block, title: string): Block = b.withTitle(initLine(title))
func withTitleTop*(b: Block, line: Line): Block =
  result = b
  result.titles.add(BlockTitle(line: line, position: some(TitlePosition.Top)))

func withTitleTop*(b: Block, title: string): Block = b.withTitleTop(initLine(title))
func withTitleBottom*(b: Block, line: Line): Block =
  result = b
  result.titles.add(BlockTitle(line: line, position: some(TitlePosition.Bottom)))

func withTitleBottom*(b: Block, title: string): Block = b.withTitleBottom(initLine(title))
func withTitleAlignment*(b: Block, alignment: Alignment): Block =
  result = b
  result.titleAlignment = alignment

func withTitlePosition*(b: Block, position: TitlePosition): Block =
  result = b
  result.titlePosition = position

func withPadding*(b: Block, padding: Padding): Block =
  result = b
  result.padding = padding

func withMergeBorders*(b: Block, strategy: MergeStrategy): Block =
  result = b; result.mergeBorders = strategy

func withShadow*(b: Block, shadow: Shadow): Block =
  result = b; result.shadow = some(shadow)

func hasTitle(b: Block, position: TitlePosition): bool =
  for title in b.titles:
    if title.position.get(b.titlePosition) == position: return true

func inner*(b: Block, area: Rect): Rect =
  ## Content rectangle after border, title, and padding shrink steps.
  ## A title reserves its edge row even when that side has no border.
  result = area
  if Border.Left in b.borders:
    result.x = min(result.x+1, result.right)
    result.width = max(0, result.width-1)
  if Border.Top in b.borders or b.hasTitle(TitlePosition.Top):
    result.y = min(result.y+1, result.bottom)
    result.height = max(0, result.height-1)
  if Border.Right in b.borders: result.width = max(0, result.width-1)
  if Border.Bottom in b.borders or b.hasTitle(TitlePosition.Bottom): result.height = max(0,
      result.height-1)
  result.x = min(MaxCoordinate, result.x+b.padding.left)
  result.y = min(MaxCoordinate, result.y+b.padding.top)
  result.width = max(0, result.width-min(MaxCoordinate, b.padding.left+b.padding.right))
  result.height = max(0, result.height-min(MaxCoordinate, b.padding.top+b.padding.bottom))

func inner*(b: Option[Block], area: Rect): Rect =
  if b.isSome: b.get.inner(area) else: area

proc render*(b: Block, area: Rect, buf: var Buffer) =
  let a = area.intersection(buf.area)
  if a.isEmpty: return
  buf.setStyle(a, b.style)
  template put(x, y: int, symbol: string) =
    buf[x, y].mergeSymbol(symbol, b.mergeBorders)
    buf[x, y].setStyle(b.borderStyle)
  # When merging, edges stop one cell short of each corner so the corner glyph decides the
  # junction instead of an edge glyph overwriting it.
  let merging = b.mergeBorders != MergeStrategy.Replace
  let left = a.x+ord(merging and Border.Left in b.borders)
  let top = a.y+ord(merging and Border.Top in b.borders)
  let right = max(0, a.right-1-ord(merging and Border.Right in b.borders))
  let bottom = max(0, a.bottom-1-ord(merging and Border.Bottom in b.borders))
  if Border.Left in b.borders:
    for y in top..bottom: put(a.x, y, b.borderSet.verticalLeft)
  if Border.Top in b.borders:
    for x in left..right: put(x, a.y, b.borderSet.horizontalTop)
  if Border.Right in b.borders:
    for y in top..bottom: put(a.right-1, y, b.borderSet.verticalRight)
  if Border.Bottom in b.borders:
    for x in left..right: put(x, a.bottom-1, b.borderSet.horizontalBottom)
  if {Border.Right, Border.Bottom} <= b.borders: put(a.right-1, a.bottom-1, b.borderSet.bottomRight)
  if {Border.Right, Border.Top} <= b.borders: put(a.right-1, a.y, b.borderSet.topRight)
  if {Border.Left, Border.Bottom} <= b.borders: put(a.x, a.bottom-1, b.borderSet.bottomLeft)
  if {Border.Left, Border.Top} <= b.borders: put(a.x, a.y, b.borderSet.topLeft)
  for position in TitlePosition:
    let tx = a.x+ord(Border.Left in b.borders)
    let tw = max(0, a.width-ord(Border.Left in b.borders)-ord(Border.Right in b.borders))
    let ty = if position == TitlePosition.Top: a.y else: a.bottom-1
    for alignment in [Alignment.Left, Alignment.Center, Alignment.Right]:
      var titles: seq[Line]
      var total = 0
      for title in b.titles:
        if title.position.get(b.titlePosition) == position and title.line.alignment.get(
            b.titleAlignment) == alignment:
          titles.add(title.line)
          total = min(MaxCoordinate, total+min(MaxCoordinate, title.line.width+1))
      total = max(0, total-1)
      # Right-aligned titles are laid out from the right edge inward, so their order reverses.
      if alignment == Alignment.Right: titles.reverse()
      var x = tx
      var available = tw
      var offset = if alignment == Alignment.Center: max(0, total-tw) div 2 else: 0
      if alignment == Alignment.Center and total <= tw: x += (tw-total) div 2
      for title in titles:
        if available == 0: break
        let width = min(MaxCoordinate, title.width)
        var w = min(available, width)
        var at = x
        var line = title
        if alignment == Alignment.Right: at = tx+max(0, available-width)
        # Overlong centered titles are clipped symmetrically: the leading part is cut from the
        # left and the trailing part from the right.
        if alignment == Alignment.Center and total > tw:
          w = max(0, w-offset)
          line.alignment = some(if offset > 0: Alignment.Right else: Alignment.Left)
          offset = max(0, offset-w-1)
        let titleArea = initRect(at, ty, w, 1)
        buf.setStyle(titleArea, b.titleStyle)
        line.render(titleArea, buf)
        let advance = if alignment == Alignment.Center and total > tw: w+1 else: width+1
        x = min(MaxCoordinate, x+advance)
        available = max(0, available-advance)
  if b.shadow.isSome: b.shadow.get.render(a, buf)

proc render*(b: Option[Block], area: Rect, buf: var Buffer) =
  if b.isSome: b.get.render(area, buf)
