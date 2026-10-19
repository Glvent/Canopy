## Animation toolkit: buffer transitions, tweens with easing, timelines, springs and looping
## tweens. The application owns time: it advances the animator and sleeps until nextWake.
import std/monotimes

import canopy
import canopy/runtime/terminal/input
import canopy/ui/animation/index as animation
import common

const
  help* = "←/→: effect · Space: pause · r: restart · d: direction · s: spring · click buttons"
  effectNames = ["Fade", "Slide", "Wipe", "Dissolve"]

var
  effect = TransitionEffect.Wipe
  direction = TransitionDirection.Left
  scene = false
  transition: Transition
  effectArea: Rect
  tabHits: array[4, Rect]
  buttonHits: array[3, Rect]
  first, second: Tween[float]
  timeline: Timeline
  spring = initSpring(0.0, 1.0, role = MotionRole.Decorative)
  pulse = initTween(0, 100, initDuration(seconds = 2), iterations = -1,
    alternate = true, role = MotionRole.Decorative)
  started = false
  wasActive = false

proc palette(c: Color, channel: ColorChannel): Color =
  ## Transitions blend RGB only; this page chooses explicit colors instead of guessing a theme.
  if c.kind == ColorKind.Rgb: c
  elif channel == ColorChannel.Background: rgbColor(12, 20, 28)
  else: rgbColor(190, 225, 220)

proc restartDemo(withTransition = true) =
  if transition != nil: transition.cancel()
  if timeline != nil: timeline.cancel()
  first = initTween(0.0, 1.0, initDuration(milliseconds = 700), easing = cubicInOut,
    role = MotionRole.Decorative)
  second = initTween(0.0, 1.0, initDuration(milliseconds = 700), easing = bounceOut,
    role = MotionRole.Decorative)
  timeline = sequence(first, delay(initDuration(milliseconds = 150)), second)
  animator.play(timeline)
  if withTransition and lastFrame.content.len > 0 and effectArea.width > 0:
    scene = not scene
    transition = initTransition(lastFrame, effectArea, initDuration(milliseconds = 1200),
      effect, direction, palette = palette, easing = sineInOut)
    animator.play(transition)
  animator.restart(pulse)
  animator.restart(spring)

proc setPaused(paused: bool) =
  for node in [pulse.animation, spring.animation, timeline]:
    if node != nil:
      if paused: node.pause() else: node.resume()
  if transition != nil:
    if paused: transition.pause() else: transition.resume()

proc render*(frame: var Frame, area: Rect) =
  let areas = vertical([length(1), length(1), fill(), length(7), length(3)]).split(area)
  let picker = horizontal([length(9), fill()]).split(areas[0])
  frame.renderWidget(initLine(initSpan(" Effect", muted())), picker[0])
  frame.renderPills(picker[1], effectNames, ord(effect), tabHits)

  # The transition covers only the panel body, so the frame stays put while content changes.
  let stage = panel(effectNames[ord(effect)] & " · " & $direction)
  frame.renderWidget(stage, areas[2])
  effectArea = stage.inner(areas[2])
  let content = if scene: "Incoming forest\n\n世界 · café · 👩‍💻\n\nLive content: "
                else: "Outgoing canopy\n\n🌿 · é · 界\n\nLive content: "
  let body = vertical([fill(), length(5), fill()]).split(effectArea)
  frame.buffer[].setStyle(effectArea, initStyle().withFg(rgbColor(190, 225, 220))
    .withBg(rgbColor(12, 20, 28)))
  frame.renderWidget(initParagraph(content & $pulse.value).centered(), body[1])
  if transition != nil: transition.apply(frame.buffer[], effectArea)

  let curves = panel("Timeline · spring")
  frame.renderWidget(curves, areas[3])
  let meters = vertical([length(1), length(1), length(1), length(1), length(1)])
    .split(curves.inner(areas[3]))
  let values = [first.value, second.value, spring.value]
  let names = ["Step 1 · cubicInOut", "Step 2 · bounceOut", "Spring · s retargets mid-flight"]
  for i in 0..2:
    frame.renderWidget(initGauge().withRatio(clamp(values[i], 0.0, 1.0)).withUseUnicode()
      .withLabel(names[i]).withGaugeStyle(meter()), meters[i * 2])

  let buttons = horizontal([fill(), fill(), fill()]).withSpacing(2).split(areas[4])
  let paused = pulse.state == PlaybackState.Paused
  let labels = [if paused: "Resume" else: "Pause", "Restart", "Direction: " & $direction]
  for i, area in buttons:
    buttonHits[i] = area
    let primary = i == 1
    frame.renderWidget(initParagraph(initText([buttonLabel(labels[i], primary)]))
      .withBlock(button(primary)), area)

proc action(index: int) =
  case index
  of 0: setPaused(pulse.state != PlaybackState.Paused)
  of 1: restartDemo()
  else:
    direction = TransitionDirection((ord(direction) + 1) mod 4)
    restartDemo()

proc selectEffect(index: int) =
  effect = TransitionEffect((index + 4) mod 4)
  restartDemo()

proc handle*(event: input.Event): bool =
  result = true
  let click = event.leftClick
  if click.isSome:
    for i, hit in tabHits:
      if hit.contains(click.get): selectEffect(i); return
    for i, hit in buttonHits:
      if hit.contains(click.get): action(i); return
    return false
  if not event.isPress: return false
  case event.key.code
  of KeyCode.Left: selectEffect(ord(effect) - 1)
  of KeyCode.Right: selectEffect(ord(effect) + 1)
  else:
    case event.key.text
    of " ": action(0)
    of "r": action(1)
    of "d": action(2)
    of "s":
      spring.retarget(if spring.value < 0.5: 1.0 else: 0.0)
      if not animator.isScheduled(spring): animator.play(spring)
    else: result = false

proc update*(now: MonoTime, active: bool): int =
  ## Animations run only while visible, so hidden pages never keep the app awake.
  if active and not wasActive:
    if not started:
      animator.play(pulse)
      animator.play(spring)
      started = true
    setPaused(false)
    # The app already wipes between pages, so arriving here skips this page's own transition.
    restartDemo(withTransition = false)
  elif wasActive and not active:
    setPaused(true)
  wasActive = active
  -1
