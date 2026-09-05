## Pure easing curves. Custom closures use the same Easing signature.
import std/math

type Easing* = proc(t: float): float {.closure.}
  ## Maps progress 0..1 to eased progress. Back and elastic curves overshoot that range on purpose.

func linear*(t: float): float = t
func quadraticIn*(t: float): float = t*t
func cubicIn*(t: float): float = t*t*t
func sineIn*(t: float): float = 1-cos(t*PI/2)
func exponentialIn*(t: float): float =
  if t == 0: 0 else: pow(2, 10*t-10)

func circularIn*(t: float): float = 1-sqrt(max(0.0, 1-t*t))
func backIn*(t: float): float = 2.70158*t*t*t-1.70158*t*t
func elasticIn*(t: float): float =
  if t == 0 or t == 1: t
  else: -pow(2, 10*t-10)*sin((t*10-10.75)*2*PI/3)

func bounceOut*(t: float): float =
  if t < 1/2.75: 7.5625*t*t
  elif t < 2/2.75: 7.5625*(t-1.5/2.75)^2+0.75
  elif t < 2.5/2.75: 7.5625*(t-2.25/2.75)^2+0.9375
  else: 7.5625*(t-2.625/2.75)^2+0.984375

func bounceIn*(t: float): float = 1-bounceOut(1-t)

# Derives the Out and InOut curves from an In curve by the standard reflections.
template variants(inside, outside, both: untyped) =
  func outside*(t: float): float = 1-inside(1-t)
  func both*(t: float): float =
    if t < 0.5: inside(2*t)/2 else: 1-inside(2-2*t)/2
variants(quadraticIn, quadraticOut, quadraticInOut)
variants(cubicIn, cubicOut, cubicInOut)
variants(sineIn, sineOut, sineInOut)
variants(exponentialIn, exponentialOut, exponentialInOut)
variants(circularIn, circularOut, circularInOut)
variants(backIn, backOut, backInOut)
variants(elasticIn, elasticOut, elasticInOut)

func bounceInOut*(t: float): float =
  if t < 0.5: bounceIn(2*t)/2 else: 1-bounceIn(2-2*t)/2
