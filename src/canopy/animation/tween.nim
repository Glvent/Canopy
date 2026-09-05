import ./[playback, easing, interpolation]
export playback, easing, interpolation
type
  ValueBox[T] = ref object
    value: T
  Tween*[T] = object
    animation*: Animation
    box: ValueBox[T]
converter asAnimation*[T](t: Tween[T]): Animation = t.animation
func value*[T](t: Tween[T]): T = t.box.value
proc initTween*[T](first, last: T, duration: Duration, easing: Easing = linear,
    interpolate: Interpolator[T] = nil, iterations = 1, alternate = false,
    delay = DurationZero, role = MotionRole.Functional): Tween[T] =
  if easing == nil: raise newException(ValueError,"Easing cannot be nil")
  var blend = interpolate
  if blend == nil:
    when compiles(interpolation.interpolate(first,last,0.0)):
      blend = proc(a,b:T,t:float):T = interpolation.interpolate(a,b,t)
    else:
      raise newException(ValueError,"Custom type requires an interpolator")
  # Validate built-in interpolation (notably non-RGB colors) at construction.
  discard blend(first,last,0)
  let initial = when T is Position or T is Size or T is Rect: blend(first,last,0) else: first
  let final = when T is Position or T is Size or T is Rect: blend(first,last,1) else: last
  let box = ValueBox[T](value:initial)
  let length = duration.seconds
  let sampler = proc(seconds: float, reverse, finishing: bool): bool =
    let p = if length == 0: (if finishing: 1.0 else: 0.0) else: clamp(seconds/length,0.0,1.0)
    let progress = if reverse: 1-p else: p
    let next = if progress == 0: initial elif progress == 1: final
      else: blend(first,last,easing(progress))
    result = next != box.value
    box.value = next
  result.box = box
  result.animation = newClip(duration,sampler,iterations,alternate,delay,role)
