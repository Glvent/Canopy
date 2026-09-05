## Interpolation samples fractional geometry only at the cell boundary.
import std/math
import ../[geometry, style]
export geometry, style
type
  Interpolator*[T] = proc(a, b: T, t: float): T {.closure.}
  Vec2* = object
    x*, y*: float

func interpolate*(a, b, t: float): float = a*(1-t)+b*t
func interpolate*(a, b: float32, t: float): float32 = float32(interpolate(float(a),float(b),t))
func rounded(a, b: int, t: float, limit: int): int =
  let v = round(interpolate(float(a),float(b),t))
  if v >= float(limit): limit
  elif v <= float(low(int)): low(int)
  else: int(v)
func interpolate*(a, b: int, t: float): int = rounded(a,b,t,high(int))
func interpolate*[T: SomeInteger](a, b: T, t: float): T =
  let value = round(interpolate(float(a),float(b),t))
  if value >= float(high(T)): high(T)
  elif value <= float(low(T)): low(T)
  else: T(value)
func interpolate*(a, b: Position, t: float): Position =
  initPosition(rounded(a.x,b.x,t,MaxCoordinate),rounded(a.y,b.y,t,MaxCoordinate))
func interpolate*(a, b: Size, t: float): Size =
  initSize(rounded(a.width,b.width,t,MaxCoordinate),rounded(a.height,b.height,t,MaxCoordinate))
func interpolate*(a, b: Rect, t: float): Rect =
  initRect(rounded(a.x,b.x,t,MaxCoordinate),rounded(a.y,b.y,t,MaxCoordinate),
    rounded(a.width,b.width,t,MaxCoordinate),rounded(a.height,b.height,t,MaxCoordinate))
func interpolate*(a, b: Vec2, t: float): Vec2 =
  Vec2(x:interpolate(a.x,b.x,t),y:interpolate(a.y,b.y,t))
proc interpolate*(a, b: Color, t: float): Color =
  if a.kind != ColorKind.Rgb or b.kind != ColorKind.Rgb:
    raise newException(ValueError,"Color interpolation requires RGB colors")
  rgbColor(rounded(int(a.r),int(b.r),t,255),rounded(int(a.g),int(b.g),t,255),
    rounded(int(a.b),int(b.b),t,255))
