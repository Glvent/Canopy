## Release-only local measurements; no comparative performance claim.
import std/[strformat, strutils]

import canopy/ui/animation/index as animation

const manager = when defined(gcOrc): "orc" elif defined(gcArc): "arc" else: "other"
echo &"Nim {NimVersion}; {hostOS}/{hostCPU}; mm={manager}; seed=302"
var checksum = 0

template measure(label: string, count: int, body: untyped) =
  block:
    let started = getMonoTime()
    for iteration {.inject.} in 0..<count: body
    let elapsed = float((getMonoTime()-started).inNanoseconds)/1e6
    echo label, ": iterations=", count, "; elapsed_ms=", elapsed.formatFloat(ffDecimal, 3),
      "; us_per_iteration=", (elapsed*1000/float(count)).formatFloat(ffDecimal, 3)

let animator = initAnimator()
let origin = getMonoTime()
for i in 0..<1000:
  animator.play(initTween(0.0, 1.0, initDuration(seconds = 1), iterations = -1, alternate = true))
discard animator.advance(origin)
measure("scheduler (1000 active tweens)", 1000):
  checksum+=animator.advance(origin+initDuration(milliseconds = iteration*17)).changed.len
  checksum+=int(animator.nextWake(origin+initDuration(
      milliseconds = iteration*17)).get.inMilliseconds)

let area = initRect(0, 0, 80, 24)
var source = initBuffer(area)
var dest = initBuffer(area)
for y in 0..<24:
  source.setString(0, y, "Canopy 世界 é 👩‍💻 " & repeat("a", 55))
  dest.setString(0, y, "New canopy 🌲 界 " & repeat("b", 55))

proc palette(c: Color, channel: ColorChannel): Color =
  if channel == ColorChannel.Background: rgbColor(10, 20, 30) else: rgbColor(200, 210, 220)
for effect in TransitionEffect:
  let a = initAnimator()
  let transition = initTransition(source, area, initDuration(seconds = 1), effect,
      palette = palette)
  a.play(transition)
  discard a.advance(origin)
  discard a.advance(origin+initDuration(milliseconds = 500))
  measure($effect & " (80x24 Unicode region)", 100):
    var frame = dest
    transition.apply(frame)
    checksum+=frame.content[iteration mod frame.content.len].symbol.len
echo "checksum=", checksum
