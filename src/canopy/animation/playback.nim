## Application-owned playback. Controls take effect at the last advance time.
## Composition consumes children permanently; animator ownership lasts until removal.
import std/[monotimes, times, options, math, algorithm]
export monotimes, times, options
type
  PlaybackState* {.pure.} = enum Idle, Playing, Paused, Completed, Cancelled
  EventKind* {.pure.} = enum Completed, Cancelled
  MotionRole* {.pure.} = enum Functional, Decorative, Transition
  NodeKind = enum Clip, Sequential, Parallel
  Animation* = ref object
    stateValue: PlaybackState
    kind: NodeKind
    children: seq[Animation]
    owner: int
    composed: bool
    durationValue: float
    elapsed, delayValue, waited: float
    iterations: int
    alternate: bool
    role: MotionRole
    sampler: proc(seconds: float, reverse, finishing: bool): bool {.closure.}
    pending: seq[AnimationEvent]
    dirty: bool
    index: int
    controlTime: float
  AnimationEvent* = object
    animation*: Animation
    kind*: EventKind
    time: float
    order: int
  Update* = object
    changed*: seq[Animation]
    events*: seq[AnimationEvent]
  Animator* = ref object
    roots: seq[Animation]
    id: int
    last: Option[MonoTime]
    frame: Duration
    reduced: bool
    clock: float
  Timeline* = Animation

var nextOwner = 0
proc identity(): int =
  inc nextOwner
  nextOwner
func seconds*(d: Duration): float = float(d.inNanoseconds)/1e9
func state*(a: Animation): PlaybackState = a.stateValue
func completed*(a: Animation): bool = a.state == PlaybackState.Completed
func stopped(a: Animation): bool = a.state in {PlaybackState.Completed, PlaybackState.Cancelled}
func durationSeconds*(a: Animation): float = a.durationValue
func elapsedSeconds*(a: Animation): float = a.elapsed
proc sample(a: Animation, time: float, reverse = false, finishing = false) =
  if a.sampler != nil: a.dirty = a.sampler(time,reverse,finishing) or a.dirty
proc queue(a: Animation, kind: EventKind, time: float) =
  # Store no self references: pending event identity is filled during collection.
  a.pending.add(AnimationEvent(kind:kind,time:time))
proc reset(a: Animation) =
  a.elapsed = 0
  a.waited = 0
  a.index = 0
  a.stateValue = PlaybackState.Playing
  a.sample(0)
  for child in a.children: child.reset()

proc newClip*(duration: Duration, sampler: proc(seconds: float, reverse, finishing: bool): bool {.closure.},
    iterations = 1, alternate = false, delay = DurationZero,
    role = MotionRole.Functional): Animation =
  ## iterations = -1 repeats forever. One iteration is one traversal.
  if duration < DurationZero or delay < DurationZero or iterations == 0 or iterations < -1:
    raise newException(ValueError,"Invalid animation duration, delay or iteration count")
  if duration == DurationZero and iterations == -1:
    raise newException(ValueError,"Infinite zero-duration animation")
  Animation(durationValue:duration.seconds,delayValue:delay.seconds,
    sampler:sampler,iterations:iterations,alternate:alternate,role:role)

proc setClipDuration*(a: Animation, seconds: float) =
  ## Internal spring hook. Retargeting starts a new traversal at the current tick.
  if a.kind != Clip or seconds < 0 or seconds.classify in {fcNan,fcInf,fcNegInf} or
      (seconds == 0 and a.iterations == -1):
    raise newException(ValueError,"Invalid clip duration")
  a.durationValue = seconds
  a.elapsed = 0
  a.waited = a.delayValue
  if a.state notin {PlaybackState.Idle,PlaybackState.Paused}: a.stateValue = PlaybackState.Playing

proc finishAt(a: Animation, time: float) =
  if a.stopped: return
  for child in a.children: child.finishAt(time)
  let reverse = a.alternate and a.iterations > 0 and a.iterations mod 2 == 0
  a.sample(a.durationValue,reverse,true)
  a.stateValue = PlaybackState.Completed
  a.queue(EventKind.Completed,time)
proc finish*(a: Animation) = a.finishAt(a.controlTime)
proc cancel*(a: Animation) =
  if a.stopped: return
  for child in a.children: child.cancel()
  a.stateValue = PlaybackState.Cancelled
  a.queue(EventKind.Cancelled,a.controlTime)
proc pause*(a: Animation) =
  if a.state == PlaybackState.Playing: a.stateValue = PlaybackState.Paused
proc resume*(a: Animation) =
  if a.state == PlaybackState.Paused: a.stateValue = PlaybackState.Playing
proc restart*(a: Animation) =
  if a.composed: raise newException(ValueError,"Restart the owning timeline")
  a.reset()

proc compose(children: openArray[Animation], kind: NodeKind): Animation =
  # Validate every child before taking any ownership.
  for i, child in children:
    if child == nil or child.owner != 0 or child.state != PlaybackState.Idle:
      raise newException(ValueError,"Animation already owned or started")
    for j in 0..<i:
      if children[j] == child: raise newException(ValueError,"Duplicate animation child")
  result = Animation(kind:kind,iterations:1)
  let id = identity()
  for child in children:
    child.owner = id
    child.composed = true
    result.children.add(child)
func animationNode*[T](child: T): Animation =
  when T is Animation: child
  else: child.animation
proc sequence*(children: varargs[Animation, animationNode]): Timeline = compose(children,Sequential)
proc parallel*(children: varargs[Animation, animationNode]): Timeline = compose(children,Parallel)
proc delay*(duration: Duration): Animation = newClip(duration,nil)
proc stagger*(spacing: Duration, children: varargs[Animation, animationNode]): Timeline =
  if spacing < DurationZero: raise newException(ValueError,"Negative stagger")
  # Validate before constructing wrappers so an error cannot consume inputs.
  for i, child in children:
    if child == nil or child.owner != 0 or child.state != PlaybackState.Idle:
      raise newException(ValueError,"Animation already owned or started")
    for j in 0..<i:
      if child == children[j]: raise newException(ValueError,"Duplicate animation child")
  var branches: seq[Animation]
  for i, child in children: branches.add(sequence(delay(spacing*i),child))
  parallel(branches)

proc tick(a: Animation, dt: float, start: float): float =
  ## Return unused time so a sequence can cross several boundaries in one update.
  if a.stopped: return dt
  if a.state != PlaybackState.Playing: return 0
  var remaining = dt
  var time = start
  if a.waited < a.delayValue:
    let used = min(remaining,a.delayValue-a.waited)
    a.waited += used
    remaining -= used
    time += used
    if a.waited < a.delayValue: return 0
  case a.kind
  of Clip:
    let total = if a.iterations < 0: Inf else: a.durationValue*float(a.iterations)
    let used = min(remaining,max(0.0,total-a.elapsed))
    a.elapsed += used
    if a.elapsed >= total:
      a.finishAt(time+used)
      return max(0.0,remaining-used)
    let traversal = floor(a.elapsed/a.durationValue)
    let reverse = a.alternate and floor(traversal/2)*2 != traversal
    a.sample(a.elapsed-traversal*a.durationValue,reverse)
  of Sequential:
    while a.index < a.children.len:
      let unused = a.children[a.index].tick(remaining,time)
      time += remaining-unused
      remaining = unused
      if not a.children[a.index].stopped: return 0
      inc a.index
    a.finishAt(time)
    return remaining
  of Parallel:
    var unused = remaining
    var allDone = true
    for child in a.children:
      unused = min(unused,child.tick(remaining,time))
      allDone = allDone and child.stopped
    if allDone:
      a.finishAt(time+remaining-unused)
      return unused

proc collect(a: Animation, update: var Update, time: float) =
  a.controlTime = time
  for child in a.children: child.collect(update,time)
  if a.dirty:
    update.changed.add(a)
    a.dirty = false
  for event in a.pending:
    update.events.add(AnimationEvent(animation:a,kind:event.kind,time:event.time,order:update.events.len))
  a.pending.setLen(0)
proc reduce(a: Animation) =
  if a.stopped: return
  if a.role == MotionRole.Transition or (a.role == MotionRole.Decorative and a.iterations > 0):
    a.finish()
  elif a.role == MotionRole.Decorative and a.iterations < 0:
    a.sample(0)
    a.cancel()
  else:
    for child in a.children: child.reduce()

proc initAnimator*(fps = 60.0, reducedMotion = false): Animator =
  if fps <= 1e9/float(high(int64)) or fps.classify in {fcNan,fcInf,fcNegInf}:
    raise newException(ValueError,"FPS must be finite with a representable positive frame interval")
  Animator(id:identity(),frame:initDuration(nanoseconds = max(1'i64,int64(1e9/fps))),reduced:reducedMotion)
func reducedMotion*(a: Animator): bool = a.reduced
proc `reducedMotion=`*(a: Animator, enabled: bool) =
  a.reduced = enabled
  if enabled:
    for root in a.roots: root.reduce()

proc advance*(a: Animator, now: MonoTime): Update =
  if a.last.isSome and now < a.last.get:
    raise newException(ValueError,"Animation time must be monotonic")
  let dt = if a.last.isSome: (now-a.last.get).seconds else: 0.0
  a.last = some(now)
  var active: seq[Animation]
  for root in a.roots:
    if a.reduced: root.reduce()
    discard root.tick(dt,a.clock)
    root.collect(result,a.clock+dt)
    if root.stopped: root.owner = 0
    else: active.add(root)
  a.roots = move(active)
  a.clock += dt
  result.events.sort(proc(x,y:AnimationEvent):int =
    let byTime = cmp(x.time,y.time)
    if byTime != 0: byTime else: cmp(x.order,y.order))

proc setControlTime(a: Animation, time: float) =
  a.controlTime = time
  for child in a.children: child.setControlTime(time)

proc play*(a: Animator, animation: Animation) =
  ## Start at the animator's last supplied time; the first advance establishes time.
  if animation == nil or animation.owner != 0:
    raise newException(ValueError,"Animation already belongs to a playback tree")
  animation.owner = a.id
  animation.reset()
  animation.setControlTime(a.clock)
  a.roots.add(animation)
  if a.reduced: animation.reduce()
  discard animation.tick(0,a.clock)

func isScheduled*(a: Animator, animation: Animation): bool = animation.owner == a.id
proc restart*(a: Animator, animation: Animation) =
  ## Restart an attached root, or register a previously completed/cancelled root.
  if a.isScheduled(animation):
    animation.restart()
    if a.reduced: animation.reduce()
    discard animation.tick(0,a.clock)
  else: a.play(animation)

proc wake(a: Animation, frame: float): float =
  if a.state != PlaybackState.Playing: return Inf
  if a.waited < a.delayValue: return a.delayValue-a.waited
  case a.kind
  of Clip:
    let remaining = if a.iterations < 0: Inf else: max(0.0,a.durationValue*float(a.iterations)-a.elapsed)
    if a.sampler == nil: remaining else: min(frame,remaining)
  of Sequential:
    if a.index >= a.children.len: 0.0
    elif a.children[a.index].stopped: 0.0
    else: a.children[a.index].wake(frame)
  of Parallel:
    var nearest = Inf
    var allDone = true
    for child in a.children:
      nearest = min(nearest,child.wake(frame))
      allDone = allDone and child.stopped
    if allDone: 0.0 else: nearest

proc nextWake*(a: Animator, now: MonoTime): Option[Duration] =
  var nearest = Inf
  for root in a.roots:
    let w = root.wake(a.frame.seconds)
    nearest = min(nearest,if w == 0: a.frame.seconds else: w)
  if nearest == Inf: return none(Duration)
  let elapsed = if a.last.isSome: max(0.0,(now-a.last.get).seconds) else: 0.0
  some(initDuration(nanoseconds = int64(ceil(max(0.0,nearest-elapsed)*1e9))))
