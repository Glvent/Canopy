## Interactive animation gallery. Applications own input, time and presentation.
## --snapshot renders a deterministic sample without terminal control.
import std/[os,strutils]
import canopy
import canopy/input
import canopy/animation

const effectNames = ["Fade", "Slide", "Wipe", "Dissolve"]
var
  animator = initAnimator()
  effect = TransitionEffect.Wipe
  direction = TransitionDirection.Left
  scene = false
  transition: Transition
  lastFrame: Buffer
  effectArea: Rect
  tabHits: array[4,Rect]
  buttonHits: array[4,Rect]
  first, second: Tween[float]
  timeline: Timeline
  spring = initSpring(0.0,1.0,role=MotionRole.Decorative)
  pulse = initTween(0,100,initDuration(seconds=2),iterations= -1,
    alternate=true,role=MotionRole.Decorative)

proc palette(c:Color,channel:ColorChannel):Color =
  ## This demo explicitly chooses its colors; the library never guesses a theme.
  if c.kind == ColorKind.Rgb: c
  elif channel == ColorChannel.Background: rgbColor(12,20,28)
  else: rgbColor(190,225,220)

proc restartDemo() =
  if transition != nil: transition.cancel()
  if timeline != nil: timeline.cancel()
  # Retire cancelled roots before starting replacements at the same supplied time.
  first = initTween(0.0,1.0,initDuration(milliseconds=700),easing=cubicInOut,role=MotionRole.Decorative)
  second = initTween(0.0,1.0,initDuration(milliseconds=700),easing=bounceOut,role=MotionRole.Decorative)
  timeline = sequence(first,delay(initDuration(milliseconds=150)),second)
  animator.play(timeline)
  if lastFrame.content.len > 0:
    scene = not scene
    transition = initTransition(lastFrame,effectArea,initDuration(milliseconds=1200),
      effect,direction,palette=palette,easing=sineInOut)
    animator.play(transition)
  animator.restart(pulse)
  animator.restart(spring)

proc togglePause() =
  let paused = pulse.state == PlaybackState.Paused
  for node in [pulse.animation,spring.animation,timeline]:
    if node != nil:
      if paused: node.resume() else: node.pause()
  if transition != nil:
    if paused: transition.resume() else: transition.pause()

proc render(frame:var Frame) =
  let areas = vertical([length(3),fill(),length(3),length(3),length(3),length(3),length(2)])
    .withMargin(1).split(frame.area)
  let blockWidget=borderedBlock().withTitle("Canopy animation gallery")
  frame.renderWidget(initTabs(effectNames).withSelected(ord(effect))
    .withHighlightStyle(initStyle().withFg(ColorKind.Cyan).bold()).withBlock(blockWidget),areas[0])
  let inner=blockWidget.inner(areas[0])
  var x=inner.x
  for i,name in effectNames:
    tabHits[i]=initRect(x,inner.y,name.len+2,1).intersection(inner)
    x+=name.len+3
  effectArea=areas[1]
  let content = if scene: "Incoming forest\n\n世界 · café · 👩‍💻\n\nLive content: " else: "Outgoing canopy\n\n🌿 · é · 界\n\nLive content: "
  frame.renderWidget(initParagraph(content & $pulse.value)
    .withStyle(initStyle().withFg(rgbColor(190,225,220)).withBg(rgbColor(12,20,28)))
    .withBlock(borderedBlock().withTitle(effectNames[ord(effect)] & " · " & $direction)),effectArea)
  if transition != nil: transition.apply(frame.buffer[],effectArea)
  frame.renderWidget(initGauge().withRatio(first.value).withLabel("Sequence 1 · cubic")
    .withBlock(borderedBlock()),areas[2])
  frame.renderWidget(initGauge().withRatio(clamp(second.value,0.0,1.0)).withLabel("Sequence 2 · bounce")
    .withBlock(borderedBlock()),areas[3])
  frame.renderWidget(initGauge().withRatio(clamp(spring.value,0.0,1.0)).withLabel("Spring · s to retarget")
    .withBlock(borderedBlock()),areas[4])
  let buttons=horizontal([fill(),fill(),fill(),fill()]).split(areas[5])
  let labels=["Play / pause", "Restart", "Direction: " & $direction,
    "Reduced motion: " & (if animator.reducedMotion:"On" else:"Off")]
  for i,area in buttons:
    buttonHits[i]=area
    frame.renderWidget(initParagraph(labels[i]).withAlignment(Alignment.Center).withBlock(borderedBlock()),area)
  frame.renderWidget(initParagraph("←/→: effect · Space: play/pause · r: restart · d: direction\n" &
    "s: spring target · m: reduced motion · click tabs/buttons · q: quit"),areas[6])

proc action(index:int) =
  case index
  of 0: togglePause()
  of 1: restartDemo()
  of 2:
    direction=TransitionDirection((ord(direction)+1) mod 4)
    restartDemo()
  else: animator.reducedMotion=not animator.reducedMotion

proc handle(event:input.Event):bool =
  result=true
  case event.kind
  of input.EventKind.Key:
    if event.key.kind==KeyEventKind.Release: return
    if event.key.text=="q" or event.key.code==KeyCode.Escape or
        (event.key.text=="c" and KeyModifier.Control in event.key.modifiers): return false
    if event.key.code in {KeyCode.Left,KeyCode.Right}:
      effect=TransitionEffect((ord(effect)+(if event.key.code==KeyCode.Right:1 else:3)) mod 4)
      restartDemo()
    else:
      case event.key.text
      of " ": action(0)
      of "r": action(1)
      of "d": action(2)
      of "m": action(3)
      of "s":
        spring.retarget(if spring.value<0.5:1.0 else:0.0)
        if not animator.isScheduled(spring): animator.play(spring)
      else: discard
  of input.EventKind.Mouse:
    if event.mouse.kind==MouseEventKind.Down and event.mouse.button==some(MouseButton.Left):
      let point=initPosition(event.mouse.column,event.mouse.row)
      for i,area in tabHits:
        if area.contains(point):
          effect=TransitionEffect(i)
          restartDemo()
          return
      for i,area in buttonHits:
        if area.contains(point): action(i)
  else: discard

let started=getMonoTime()
discard animator.advance(started)
animator.play(pulse)
animator.play(spring)
restartDemo()
if "--snapshot" in commandLineParams():
  withTerminal(terminal,initTestBackend(90,30)):
    lastFrame=terminal.draw(render).buffer
    restartDemo()
    discard animator.advance(started+initDuration(milliseconds=600))
    let frame=terminal.draw(render)
    for y in frame.area.y..<frame.area.bottom:
      var row=""
      var x=frame.area.x
      while x<frame.area.right:
        row.add(frame.buffer[x,y].symbol)
        x+=max(1,frame.buffer[x,y].cellWidth)
      echo row.strip(leading=false)
else:
  var capabilities=defaultInputCapabilities()
  capabilities.mouseCapture=true
  withTerminal(terminal,initAnsiBackend()):
    withInput(events,initInput(capabilities=capabilities,rawMode=false)):
      while true:
        discard animator.advance(getMonoTime())
        lastFrame=terminal.draw(render).buffer
        let wake=animator.nextWake(getMonoTime())
        let timeout=if wake.isSome: int((wake.get.inNanoseconds+999_999) div 1_000_000) else: -1
        let event=events.poll(timeout)
        discard animator.advance(getMonoTime())
        if events.eof or (event.isSome and not handle(event.get)): break
