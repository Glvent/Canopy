## Logical terminal cells and incremental frame differences.
## Diff behavior derived from ratatui-core 0.1.2 (MIT; see licenses/ratatui.txt).
import std/[options, strutils]

import ../layout/geometry
import ../styling/style
import ../text/index as text
import ../text/unicode
import ../../internal/symbols/merge as symbol_merge
export geometry, style, text
export symbol_merge.MergeStrategy

type
  CellDiffKind* {.pure.} = enum Normal, Skip, AlwaysUpdate, ForcedWidth
  Cell* = object
    ## `symbolSet` distinguishes a never-written cell from one holding a blank; `symbol` reports
    ## `" "` for both, but border merging needs the difference.
    symbolValue: string
    symbolSet*: bool
    fg*, bg*, underlineColor*: Color
    modifiers*: Modifiers
    skip*: bool
    diffKind*: CellDiffKind
    forcedWidth*: int
  Buffer* = object
    ## `content` is row-major over `area`; index 0 is the cell at `area`'s origin, not at (0, 0).
    area*: Rect
    content*: seq[Cell]
  CellUpdate* = tuple[x, y: int, cell: Cell]

func initCell*(): Cell = Cell()
func initCell*(symbol: string): Cell = Cell(symbolValue: symbol, symbolSet: true)
func symbol*(cell: Cell): string =
  if cell.symbolSet: cell.symbolValue else: " "

proc `symbol=`*(cell: var Cell, symbol: string) =
  cell.symbolValue = symbol
  cell.symbolSet = true

func `==`*(a, b: Cell): bool =
  a.symbol == b.symbol and a.fg == b.fg and a.bg == b.bg and a.underlineColor ==
      b.underlineColor and a.modifiers == b.modifiers and a.skip == b.skip and a.diffKind ==
      b.diffKind and a.forcedWidth == b.forcedWidth

proc reset*(cell: var Cell) = cell = initCell()
proc setSymbol*(cell: var Cell, symbol: string) = cell.symbol = symbol
proc setChar*(cell: var Cell, symbol: char) = cell.symbol = $symbol
proc setFg*(cell: var Cell, color: Color) = cell.fg = color
proc setBg*(cell: var Cell, color: Color) = cell.bg = color
proc setUnderlineColor*(cell: var Cell, color: Color) = cell.underlineColor = color
proc setSkip*(cell: var Cell, skip: bool) =
  ## Marks trailing cells of wide graphemes; backends omit skipped cells from diffs.
  cell.skip = skip
  cell.diffKind = if skip: CellDiffKind.Skip else: CellDiffKind.Normal
  cell.forcedWidth = 0

proc setDiffOption*(cell: var Cell, kind: CellDiffKind, width = 1) =
  ## `width` applies only to ForcedWidth, which overrides the measured grapheme width during diff.
  cell.diffKind = kind
  cell.forcedWidth = if kind == CellDiffKind.ForcedWidth: clamp(width, 1, 65535) else: 0

proc mergeSymbol*(cell: var Cell, symbol: string, strategy: MergeStrategy) =
  cell.symbol = if cell.symbolSet: symbol_merge.mergeSymbol(cell.symbol, symbol,
      strategy) else: symbol

proc setStyle*(cell: var Cell, style: Style) =
  ## Applies `style` as a patch: absent colors keep the cell's current ones.
  if style.fg.isSome: cell.fg = style.fg.get
  if style.bg.isSome: cell.bg = style.bg.get
  if style.underlineColor.isSome: cell.underlineColor = style.underlineColor.get
  cell.modifiers = (cell.modifiers + style.addModifiers) - style.subModifiers

func style*(cell: Cell): Style = Style(fg: some(cell.fg), bg: some(cell.bg), underlineColor: some(
    cell.underlineColor), addModifiers: cell.modifiers)
proc cellWidth*(cell: Cell): int =
  if cell.diffKind == CellDiffKind.ForcedWidth: max(1, cell.forcedWidth)
  else: unicode.cellWidth(cell.symbol)

proc initBuffer*(area: Rect, cell: Cell = initCell()): Buffer =
  result.area = area
  result.content = newSeq[Cell](area.area)
  for item in result.content.mitems: item = cell

func indexOf*(buffer: Buffer, x, y: int): int =
  ## Coordinates are absolute, not area-relative; out-of-bounds access is an assertion failure.
  assert buffer.area.contains(x, y), "Cell outside buffer"
  (y-buffer.area.y)*buffer.area.width + x-buffer.area.x

func posOf*(buffer: Buffer, index: int): Position =
  assert index >= 0 and index < buffer.content.len, "Index outside buffer"
  Position(x: buffer.area.x+index mod buffer.area.width,
      y: buffer.area.y+index div buffer.area.width)

proc `[]`*(buffer: var Buffer, x, y: int): var Cell = buffer.content[buffer.indexOf(x, y)]
func `[]`*(buffer: Buffer, x, y: int): Cell = buffer.content[buffer.indexOf(x, y)]
proc `[]=`*(buffer: var Buffer, x, y: int, cell: Cell) = buffer.content[buffer.indexOf(x, y)] = cell
proc `[]`*(buffer: var Buffer, p: Position): var Cell = buffer[p.x, p.y]
func `[]`*(buffer: Buffer, p: Position): Cell = buffer[p.x, p.y]
proc `[]=`*(buffer: var Buffer, p: Position, cell: Cell) = buffer[p.x, p.y] = cell
func cell*(buffer: Buffer, p: Position): Option[Cell] =
  ## Bounds-checked alternative to `[]`, which asserts instead.
  if buffer.area.contains(p): some(buffer[p]) else: none(Cell)

proc setStringn*(buffer: var Buffer, x, y: int, content: string, maxWidth: int,
    style: Style = initStyle()): Position {.discardable.} =
  ## Writes graphemes until `maxWidth` cells are used, skipping control and zero-width clusters,
  ## and returns the position just past the last written cell. A grapheme that does not fit whole
  ## is dropped rather than truncated.
  result = Position(x: x, y: y)
  if y < buffer.area.y or y >= buffer.area.bottom: return
  let limit = min(buffer.area.right, x+max(0, maxWidth))
  for symbol in graphemes(content):
    if hasControl(symbol): continue
    let width = unicode.cellWidth(symbol)
    if width == 0: continue
    if width > limit-result.x: break
    if result.x >= buffer.area.x:
      buffer[result.x, y].setSymbol(symbol)
      buffer[result.x, y].setStyle(style)
      # Wide graphemes occupy trailing cells that must stay blank for terminal width math.
      for trailing in 1..<width: buffer[result.x+trailing, y].reset()
    result.x += width

proc setString*(buffer: var Buffer, x, y: int, content: string, style: Style = initStyle()): Position {.discardable.} =
  buffer.setStringn(x, y, content, MaxCoordinate, style)

proc setLine*(buffer: var Buffer, x, y: int, line: Line, maxWidth: int): Position {.discardable.} =
  result = Position(x: x, y: y)
  var remaining = max(0, maxWidth)
  for span in line.spans:
    if remaining == 0: break
    let next = buffer.setStringn(result.x, y, span.content, remaining, line.style.patch(span.style))
    remaining -= max(0, next.x-result.x)
    result = next

proc setSpan*(buffer: var Buffer, x, y: int, span: Span,
    maxWidth: int): Position {.discardable.} = buffer.setStringn(x, y, span.content, maxWidth, span.style)

proc setStyle*(buffer: var Buffer, area: Rect, style: Style) =
  for p in buffer.area.intersection(area).positions: buffer[p].setStyle(style)

proc reset*(buffer: var Buffer) =
  for cell in buffer.content.mitems: cell.reset()

proc resize*(buffer: var Buffer, area: Rect) =
  ## Keeps existing cells by index, so content shifts when the width changes.
  let oldLen = buffer.content.len
  buffer.content.setLen(area.area)
  for i in oldLen..<buffer.content.len: buffer.content[i] = initCell()
  buffer.area = area

proc merge*(buffer: var Buffer, other: Buffer) =
  ## Expands to the union area; `other` wins on overlapping cells.
  var merged = initBuffer(buffer.area.union(other.area))
  for p in buffer.area.positions: merged[p] = buffer[p]
  for p in other.area.positions: merged[p] = other[p]
  buffer = move(merged)

proc initBuffer*(lines: openArray[string]): Buffer =
  var w = 0
  for line in lines: w = max(w, displayWidth(line))
  result = initBuffer(initRect(0, 0, w, lines.len))
  for y, line in lines: result.setString(0, y, line)

# Skip can come from the explicit diff kind or from the legacy `skip` flag left at Normal.

func isSkipped(cell: Cell): bool = cell.diffKind == CellDiffKind.Skip or (cell.skip and
    cell.diffKind == CellDiffKind.Normal)
iterator diffIter*(previous, next: Buffer): CellUpdate =
  ## Yields cell updates for backends; areas must share origin and width so indices align.
  assert previous.area.x == next.area.x and previous.area.y == next.area.y and
      previous.area.width == next.area.width, "Buffer areas must have same x, y and width"
  let length = min(previous.content.len, next.content.len)
  var i = 0
  while i < length:
    let current = next.content[i]
    let old = previous.content[i]
    if current.isSkipped:
      inc i
      continue
    let width = current.cellWidth
    if current.diffKind == CellDiffKind.ForcedWidth:
      if current != old:
        let p = next.posOf(i)
        yield (p.x, p.y, current)
      i += max(1, width)
      continue
    if current == old and current.diffKind != CellDiffKind.AlwaysUpdate:
      i += max(1, width)
      continue
    let p = next.posOf(i)
    yield (p.x, p.y, current)
    let oldWidth = old.cellWidth
    # A wide grapheme's trailing cells were never emitted, so a shrink or a VS16 sequence can
    # leave the terminal showing stale glyphs; re-emit the covered cells in those two cases.
    let vs16 = width > 1 and current.symbol.contains("\xEF\xB8\x8F")
    const visibleOnBlank = {Modifier.Reversed, Modifier.Underlined, Modifier.SlowBlink,
        Modifier.RapidBlink, Modifier.CrossedOut}
    let force = width <= 1 and oldWidth > width and (old.bg.kind != ColorKind.Reset or (
        old.modifiers * visibleOnBlank) != {})
    if vs16 or force:
      var j = i+1
      var finish = min(length, i+(if force: oldWidth else: width))
      while j < finish:
        let at = j
        j += max(1, next.content[at].cellWidth)
        finish = min(length, max(finish, j))
        if not next.content[at].isSkipped and (force or previous.content[at].symbol != next.content[at].symbol):
          let pos = next.posOf(at)
          yield (pos.x, pos.y, next.content[at])
      i = finish
    else: i += max(1, width)

proc diff*(previous, next: Buffer): seq[CellUpdate] =
  for update in previous.diffIter(next): result.add(update)

proc render*(span: Span, area: Rect, buffer: var Buffer) =
  let clipped = area.intersection(buffer.area)
  if not clipped.isEmpty: buffer.setSpan(clipped.x, clipped.y, span, clipped.width)

proc render*(line: Line, area: Rect, buffer: var Buffer) =
  ## Renders one row: content wider than the area is trimmed from the side the alignment scrolls
  ## away from, so centered and right-aligned lines keep their trailing text visible.
  var clipped = area.intersection(buffer.area)
  if clipped.isEmpty: return
  clipped.height = 1
  let width = line.width
  if width == 0: return
  buffer.setStyle(clipped, line.style)
  let remaining = max(0, clipped.width-width)
  let alignment = line.alignment.get(Alignment.Left)
  var x = clipped.x + (case alignment
    of Alignment.Left: 0
    of Alignment.Center: remaining div 2
    of Alignment.Right: remaining)
  var skip = case alignment
    of Alignment.Left: 0
    of Alignment.Center: max(0, width-clipped.width) div 2
    of Alignment.Right: max(0, width-clipped.width)
  for span in line.spans:
    let spanWidth = span.width
    if skip >= spanWidth:
      skip -= spanWidth
      continue
    var content = span.content
    var actualWidth = spanWidth
    if skip > 0:
      # Rebuild the span from its end so a partially skipped wide grapheme is dropped whole.
      let available = spanWidth-skip
      let clusters = graphemes(content)
      content = ""
      actualWidth = 0
      for i in countdown(clusters.high, 0):
        let w = displayWidth(clusters[i])
        if actualWidth+w > available: break
        content = clusters[i] & content
        actualWidth += w
      x += available-actualWidth
      skip = 0
    if x >= clipped.right: break
    buffer.setStringn(x, clipped.y, content, clipped.right-x, span.style)
    x += actualWidth

proc render*(text: Text, area: Rect, buffer: var Buffer) =
  let clipped = area.intersection(buffer.area)
  buffer.setStyle(clipped, text.style)
  for i, line in text.lines:
    if i >= clipped.height: break
    var styled = line
    if styled.alignment.isNone: styled.alignment = text.alignment
    styled.render(initRect(clipped.x, clipped.y+i, clipped.width, 1), buffer)
