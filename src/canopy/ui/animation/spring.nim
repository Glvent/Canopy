## Closed-form damped oscillators; no numerical integration or frame-sized steps.
import std/math

import ./[playback, interpolation]
export playback, interpolation

type
  SpringConfig* = object
    ## `frequency` is in hertz and `damping` is a ratio: below 1 oscillates, 1 is critical, above 1
    ## is overdamped. The thresholds decide when motion counts as settled, and `maxDuration` caps
    ## the settling search.
    frequency*, damping*: float
    positionThreshold*, velocityThreshold*: float
    maxDuration*: Duration
  SpringData[T] = ref object
    initial, target, initialVelocity, value, velocity: T
    config: SpringConfig
    settle: float
  Spring*[T] = object
    animation*: Animation
    data: SpringData[T]

func defaultSpringConfig*(): SpringConfig =
  SpringConfig(frequency: 4, damping: 1, positionThreshold: 0.001,
    velocityThreshold: 0.001, maxDuration: initDuration(seconds = 10))
converter asAnimation*[T](s: Spring[T]): Animation = s.animation
func value*[T](s: Spring[T]): T = s.data.value
func velocity*[T](s: Spring[T]): T = s.data.velocity

# Closed-form solution of the damped oscillator on one axis, with `x` relative to the target and
# `w` the angular frequency. Each damping regime needs its own form.
func axis(x, v, t, w, damping: float): tuple[x, v: float] =
  if damping < 1:
    let alpha = damping*w
    let beta = w*sqrt(1-damping*damping)
    let b = (v+alpha*x)/beta
    let c = cos(beta*t)
    let s = sin(beta*t)
    let e = exp(-alpha*t)
    result = (e*(x*c+b*s), e*((b*beta-alpha*x)*c+(-x*beta-alpha*b)*s))
  elif damping == 1:
    let b = v+w*x
    let e = exp(-w*t)
    result = ((x+b*t)*e, (v-w*b*t)*e)
  else:
    # Reciprocal form avoids cancellation for strongly overdamped springs.
    let r2 = -w*(damping+sqrt(damping*damping-1))
    let r1 = w*w/r2
    let b = (v-r1*x)/(r2-r1)
    let a = x-b
    result = (a*exp(r1*t)+b*exp(r2*t), a*r1*exp(r1*t)+b*r2*exp(r2*t))

# Upper bound on displacement and velocity at time `t`, used to find the settling time without
# sampling the oscillation itself.

func envelope(x, v, t, w, d: float): tuple[x, v: float] =
  if d < 1:
    let alpha = d*w
    let beta = w*sqrt(1-d*d)
    let b = (v+alpha*x)/beta
    let amplitude = hypot(x, b)
    (amplitude*exp(-alpha*t), w*amplitude*exp(-alpha*t))
  elif d == 1:
    let b = abs(v+w*x)
    ((abs(x)+b*t)*exp(-w*t), (abs(v)+w*b*t)*exp(-w*t))
  else:
    let r2 = -w*(d+sqrt(d*d-1))
    let r1 = w*w/r2
    let b = (v-r1*x)/(r2-r1)
    let a = x-b
    (abs(a)*exp(r1*t)+abs(b)*exp(r2*t), abs(a*r1)*exp(r1*t)+abs(b*r2)*exp(r2*t))

# Earliest time at which the envelope stays under both thresholds, found by bisection because the
# envelope is monotonically decreasing after its peak.

func settleAxis(x, v: float, c: SpringConfig): float =
  if x == 0 and v == 0: return 0
  let w = 2*PI*c.frequency
  var lo = if c.damping == 1: min(1/w, c.maxDuration.seconds) else: 0.0
  var hi = c.maxDuration.seconds
  # Bounds decrease after the critical envelope's peak (at most 1/w).
  for i in 0..<60:
    let mid = (lo+hi)/2
    let bound = envelope(x, v, mid, w, c.damping)
    if bound.x <= c.positionThreshold and bound.v <= c.velocityThreshold: hi = mid
    else: lo = mid
  hi

proc settlingTime[T](d: SpringData[T]): float =
  when T is float:
    settleAxis(d.initial-d.target, d.initialVelocity, d.config)
  else:
    max(settleAxis(d.initial.x-d.target.x, d.initialVelocity.x, d.config),
      settleAxis(d.initial.y-d.target.y, d.initialVelocity.y, d.config))

proc initSpring*[T: float|Vec2](first, target: T, config: SpringConfig,
    initialVelocity: T, role = MotionRole.Functional): Spring[T] =
  ## Raises ValueError for non-finite, negative, or zero parameters that would make settling
  ## undefined. The clip runs for the computed settling time, not `maxDuration`.
  for v in [config.frequency, config.damping, config.positionThreshold, config.velocityThreshold]:
    if v.classify in {fcNan, fcInf, fcNegInf} or v < 0:
      raise newException(ValueError, "Spring parameters must be finite and nonnegative")
  if config.frequency == 0 or config.positionThreshold == 0 or config.velocityThreshold == 0 or
      config.maxDuration <= DurationZero:
    raise newException(ValueError, "Spring frequency, thresholds and maximum duration must be positive")
  let d = SpringData[T](initial: first, target: target, initialVelocity: initialVelocity,
    value: first, velocity: initialVelocity, config: config)
  d.settle = settlingTime(d)
  let sampler = proc(t: float, reverse, finishing: bool): bool =
    let old = d.value
    if finishing or t >= d.settle:
      d.value = d.target
      d.velocity = default(T)
    else:
      when T is float:
        let sampled = axis(d.initial-d.target, d.initialVelocity, t, 2*PI*config.frequency,
            config.damping)
        d.value = d.target+sampled.x
        d.velocity = sampled.v
      else:
        let x = axis(d.initial.x-d.target.x, d.initialVelocity.x, t, 2*PI*config.frequency,
            config.damping)
        let y = axis(d.initial.y-d.target.y, d.initialVelocity.y, t, 2*PI*config.frequency,
            config.damping)
        d.value = Vec2(x: d.target.x+x.x, y: d.target.y+y.x)
        d.velocity = Vec2(x: x.v, y: y.v)
    d.value != old
  result.data = d
  result.animation = newClip(config.maxDuration, sampler, role = role)
  result.animation.setClipDuration(d.settle)

proc initSpring*[T: float|Vec2](first, target: T, config = defaultSpringConfig(),
    role = MotionRole.Functional): Spring[T] =
  initSpring(first, target, config, default(T), role)

proc retarget*[T](s: Spring[T], target: T) =
  ## Call advance(now) first. Velocity is preserved at that sampled instant.
  s.data.initial = s.data.value
  s.data.initialVelocity = s.data.velocity
  s.data.target = target
  s.data.settle = settlingTime(s.data)
  s.animation.setClipDuration(s.data.settle)
