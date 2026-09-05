## Terminal cell geometry. Coordinates saturate at the u16 terminal boundary.
type
  Direction* {.pure.} = enum Horizontal, Vertical
  Alignment* {.pure.} = enum Left, Center, Right
  HorizontalAlignment* = Alignment
  VerticalAlignment* {.pure.} = enum Top, Center, Bottom
  Position* = object
    x*, y*: int
  Size* = object
    width*, height*: int
  Margin* = object
    horizontal*, vertical*: int
  Offset* = object
    x*, y*: int
  Rect* = object
    x*, y*, width*, height*: int

const MaxCoordinate* = 65535
func bounded(n: int): int = clamp(n, 0, MaxCoordinate)
func initPosition*(x, y: int): Position = Position(x: bounded(x), y: bounded(y))
func initSize*(width, height: int): Size = Size(width: bounded(width), height: bounded(height))
func initMargin*(horizontal, vertical: int): Margin = Margin(horizontal: bounded(horizontal), vertical: bounded(vertical))
func initRect*(x, y, width, height: int): Rect =
  Rect(x: bounded(x), y: bounded(y), width: min(bounded(width), MaxCoordinate-bounded(x)), height: min(bounded(height), MaxCoordinate-bounded(y)))
func initOffset*(x, y: int): Offset = Offset(x:x, y:y)
func left*(r: Rect): int = r.x
func top*(r: Rect): int = r.y
func asPosition*(r: Rect): Position = Position(x:r.x,y:r.y)
func asSize*(r: Rect): Size = Size(width:r.width,height:r.height)
func right*(r: Rect): int = min(MaxCoordinate, r.x + r.width)
func bottom*(r: Rect): int = min(MaxCoordinate, r.y + r.height)
func area*(r: Rect): int = r.width * r.height
func isEmpty*(r: Rect): bool = r.width == 0 or r.height == 0
func contains*(r: Rect, p: Position): bool = p.x >= r.x and p.x < r.right and p.y >= r.y and p.y < r.bottom
func contains*(r: Rect, x, y: int): bool = r.contains(Position(x: x, y: y))
func intersection*(a, b: Rect): Rect =
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  initRect(x, y, max(0, min(a.right, b.right) - x), max(0, min(a.bottom, b.bottom) - y))
func union*(a, b: Rect): Rect =
  let x = min(a.x, b.x)
  let y = min(a.y, b.y)
  initRect(x, y, max(a.right, b.right) - x, max(a.bottom, b.bottom) - y)
func inner*(r: Rect, m: Margin): Rect =
  let horizontal = min(MaxCoordinate, 2*m.horizontal)
  let vertical = min(MaxCoordinate, 2*m.vertical)
  if r.width < horizontal or r.height < vertical:
    return initRect(0, 0, 0, 0)
  initRect(r.x+m.horizontal, r.y+m.vertical, r.width-horizontal, r.height-vertical)
func intersects*(a, b: Rect): bool = a.x < b.right and a.right > b.x and a.y < b.bottom and a.bottom > b.y
func outer*(r: Rect, m: Margin): Rect =
  let x = max(0,r.x-m.horizontal)
  let y = max(0,r.y-m.vertical)
  initRect(x,y,min(MaxCoordinate,r.right+m.horizontal)-x,min(MaxCoordinate,r.bottom+m.vertical)-y)
func offset*(r: Rect, o: Offset): Rect =
  initRect(clamp(r.x+clamp(o.x,-MaxCoordinate,MaxCoordinate),0,MaxCoordinate-r.width),
    clamp(r.y+clamp(o.y,-MaxCoordinate,MaxCoordinate),0,MaxCoordinate-r.height),r.width,r.height)
func `+`*(r: Rect, o: Offset): Rect = r.offset(o)
func `+`*(o: Offset, r: Rect): Rect = r.offset(o)
func `-`*(r: Rect, o: Offset): Rect = r.offset(initOffset(-clamp(o.x,-MaxCoordinate,MaxCoordinate), -clamp(o.y,-MaxCoordinate,MaxCoordinate)))
proc `+=`*(r: var Rect, o: Offset) = r = r + o
proc `-=`*(r: var Rect, o: Offset) = r = r - o
func resize*(r: Rect, s: Size): Rect = initRect(r.x,r.y,s.width,s.height)
func clamp*(r: Rect, bounds: Rect): Rect =
  let w = min(r.width, bounds.width)
  let h = min(r.height, bounds.height)
  initRect(system.clamp(r.x, bounds.x, bounds.right-w), system.clamp(r.y, bounds.y, bounds.bottom-h),w,h)
iterator rows*(r: Rect): Rect =
  for y in r.y..<r.bottom: yield initRect(r.x, y, r.width, 1)
iterator columns*(r: Rect): Rect =
  for x in r.x..<r.right: yield initRect(x, r.y, 1, r.height)
iterator positions*(r: Rect): Position =
  for y in r.y..<r.bottom:
    for x in r.x..<r.right: yield Position(x:x, y:y)
