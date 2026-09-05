## Terminal cell geometry. Coordinates saturate at the u16 terminal boundary.
type
  Direction* {.pure.} = enum Horizontal, Vertical
  Alignment* {.pure.} = enum Left, Center, Right
  HorizontalAlignment* = Alignment
  VerticalAlignment* {.pure.} = enum Top, Center, Bottom
  Position* = object
    ## Cell coordinate; the origin is the top-left cell of the terminal.
    x*, y*: int
  Size* = object
    width*, height*: int
  Margin* = object
    ## Per-side inset; `inner`/`outer` apply each component to both opposing sides.
    horizontal*, vertical*: int
  Offset* = object
    ## Signed translation, unlike the unsigned coordinate types.
    x*, y*: int
  Rect* = object
    ## Half-open cell region: it covers x..<right and y..<bottom.
    x*, y*, width*, height*: int

const MaxCoordinate* = 65535 ## Largest addressable coordinate; matches the u16 terminal limit.

func bounded(n: int): int = clamp(n, 0, MaxCoordinate)
func initPosition*(x, y: int): Position = Position(x: bounded(x), y: bounded(y))
func initSize*(width, height: int): Size = Size(width: bounded(width), height: bounded(height))
func initMargin*(horizontal, vertical: int): Margin = Margin(horizontal: bounded(horizontal),
    vertical: bounded(vertical))
func initRect*(x, y, width, height: int): Rect =
  ## Width and height clamp so x+width and y+height never exceed MaxCoordinate.
  Rect(x: bounded(x), y: bounded(y), width: min(bounded(width), MaxCoordinate-bounded(x)),
      height: min(bounded(height), MaxCoordinate-bounded(y)))

func initOffset*(x, y: int): Offset = Offset(x: x, y: y)
func left*(r: Rect): int = r.x
func top*(r: Rect): int = r.y
func asPosition*(r: Rect): Position = Position(x: r.x, y: r.y)
func asSize*(r: Rect): Size = Size(width: r.width, height: r.height)
func right*(r: Rect): int = min(MaxCoordinate, r.x + r.width)
  ## Exclusive right edge, saturated at MaxCoordinate.

func bottom*(r: Rect): int = min(MaxCoordinate, r.y + r.height)
  ## Exclusive bottom edge, saturated at MaxCoordinate.
func area*(r: Rect): int = r.width * r.height
func isEmpty*(r: Rect): bool = r.width == 0 or r.height == 0
func contains*(r: Rect, p: Position): bool = p.x >= r.x and p.x < r.right and p.y >= r.y and p.y < r.bottom
func contains*(r: Rect, x, y: int): bool = r.contains(Position(x: x, y: y))
func intersection*(a, b: Rect): Rect =
  ## Overlapping region, or an empty Rect positioned at the overlap origin when they are disjoint.
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  initRect(x, y, max(0, min(a.right, b.right) - x), max(0, min(a.bottom, b.bottom) - y))

func union*(a, b: Rect): Rect =
  ## Smallest Rect covering both operands, including any gap between disjoint inputs.
  let x = min(a.x, b.x)
  let y = min(a.y, b.y)
  initRect(x, y, max(a.right, b.right) - x, max(a.bottom, b.bottom) - y)

func inner*(r: Rect, m: Margin): Rect =
  ## Shrinks by `m` on every side, collapsing to Rect(0, 0, 0, 0) when the margins do not fit.
  let horizontal = min(MaxCoordinate, 2*m.horizontal)
  let vertical = min(MaxCoordinate, 2*m.vertical)
  if r.width < horizontal or r.height < vertical:
    return initRect(0, 0, 0, 0)
  initRect(r.x+m.horizontal, r.y+m.vertical, r.width-horizontal, r.height-vertical)

func intersects*(a, b: Rect): bool = a.x < b.right and a.right > b.x and a.y < b.bottom and
    a.bottom > b.y
func outer*(r: Rect, m: Margin): Rect =
  ## Grows by `m` on every side, clipped to the coordinate range rather than wrapping.
  let x = max(0, r.x-m.horizontal)
  let y = max(0, r.y-m.vertical)
  initRect(x, y, min(MaxCoordinate, r.right+m.horizontal)-x, min(MaxCoordinate,
      r.bottom+m.vertical)-y)

func offset*(r: Rect, o: Offset): Rect =
  ## Translates while preserving size; the result stops at the coordinate limits.
  initRect(clamp(r.x+clamp(o.x, -MaxCoordinate, MaxCoordinate), 0, MaxCoordinate-r.width),
    clamp(r.y+clamp(o.y, -MaxCoordinate, MaxCoordinate), 0, MaxCoordinate-r.height), r.width, r.height)

func `+`*(r: Rect, o: Offset): Rect = r.offset(o)
func `+`*(o: Offset, r: Rect): Rect = r.offset(o)
func `-`*(r: Rect, o: Offset): Rect = r.offset(initOffset(-clamp(o.x, -MaxCoordinate,
    MaxCoordinate), -clamp(o.y, -MaxCoordinate, MaxCoordinate)))
proc `+=`*(r: var Rect, o: Offset) = r = r + o
proc `-=`*(r: var Rect, o: Offset) = r = r - o
func resize*(r: Rect, s: Size): Rect = initRect(r.x, r.y, s.width, s.height)
func clamp*(r: Rect, bounds: Rect): Rect =
  ## Moves and shrinks `r` until it fits inside `bounds`, preferring size over position.
  let w = min(r.width, bounds.width)
  let h = min(r.height, bounds.height)
  initRect(system.clamp(r.x, bounds.x, bounds.right-w), system.clamp(r.y, bounds.y,
      bounds.bottom-h), w, h)

iterator rows*(r: Rect): Rect =
  ## Yields each row of `r` top to bottom as a one-cell-high Rect.
  for y in r.y..<r.bottom: yield initRect(r.x, y, r.width, 1)

iterator columns*(r: Rect): Rect =
  ## Yields each column of `r` left to right as a one-cell-wide Rect.
  for x in r.x..<r.right: yield initRect(x, r.y, 1, r.height)

iterator positions*(r: Rect): Position =
  ## Yields every contained cell in row-major order, matching buffer index order.
  for y in r.y..<r.bottom:
    for x in r.x..<r.right: yield Position(x: x, y: y)
