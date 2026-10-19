# Animation (Canopy extension)

Use `import canopy/ui/animation/index` explicitly. The toolkit has no threads, sleeps,
terminal ownership, input handling, or dependency on a renderer. Existing
rendering and Ratatui compatibility contracts are unchanged.

## Application-owned loop

Advance once using a monotonic timestamp before handling controls or retargeting.
Render sampled values, then combine `nextWake` with your application's next
functional deadline. Round a duration **up** to input's integer milliseconds.
`none(Duration)` means no animation timer is needed; input can block until an
event. A draw failure does not change animation time: terminal recovery repaints
the latest sample on the next draw.

```nim
import canopy
import canopy/runtime/terminal/input
import canopy/ui/animation/index as animation

let animator = initAnimator() # 60 FPS; fps is configurable
let progress = initTween(0.0, 1.0, initDuration(seconds=2), easing=cubicInOut)
discard animator.advance(getMonoTime())
animator.play(progress)
withTerminal(terminal, initAnsiBackend()):
  withInput(events, initInput(rawMode=false)):
    while true:
      let update = animator.advance(getMonoTime())
      # All state is updated before changed handles and lifecycle events return.
      for event in update.events:
        discard event # application-owned completion/cancellation handling
      discard terminal.draw(proc(frame: var Frame) =
        frame.renderWidget(initGauge().withRatio(progress.value), frame.area))
      let wake = animator.nextWake(getMonoTime())
      let timeout = if wake.isSome:
        int((wake.get.inNanoseconds + 999_999) div 1_000_000)
        else: -1
      let event = events.poll(timeout)
      if events.eof or (event.isSome and event.get.kind == input.EventKind.Key and
          event.get.key.text == "q"): break
```

Calling `advance` always consumes actual elapsed time; missed presentation frames
are skipped. Backward timestamps raise `ValueError`. Start clips after supplying
the current time, or let the first `advance` establish the epoch. Controls take
effect at the last supplied timestamp, not at a hidden wall-clock reading.

## Values and lifecycle

`Tween[T]` and `Spring[T]` are typed handles with `.value`, `.state`, `.completed`
and `.animation` (the untyped identity used in update reports). Copies share
owned heap state. No handle retains an application stack-variable pointer.
Typed handles convert to `Animation` for scheduling, composition and controls.

`animator.play(handle)` starts from the initial sample. `pause`, `resume`,
`cancel`, `finish`, and `restart` work on roots and timelines. Child pause/resume,
cancel and finish are allowed; restarting a composed child is rejected: restart
its owning timeline. `animator.restart(handle)` restarts an attached root or
reattaches a retired one. `handle.restart()` alone resets state; detached roots
still need `play`. `isScheduled` reports whether a root belongs to that animator.

States are `Idle`, `Playing`, `Paused`, `Completed`, and `Cancelled`. Cancellation
retains the current sample. Finish samples the defined final endpoint. Both emit
one event per run, collected by the next `advance`, after all updates. Repeated
finish/cancel on a stopped clip does nothing. No callbacks execute during tree
mutation. Rounded or otherwise equal values do not appear in `Update.changed`.
Retain the animator through collection to receive its pending events. Finished
and cancelled roots are removed and release animator ownership during collection.

Tween options include `iterations` (positive, or `-1` forever), `alternate`,
`delay`, `easing`, and `role`. One iteration is one traversal; alternating clips
reverse odd-numbered traversals (counting from zero). An even finite count ends
at the initial value, an odd count at the destination. Finish on an infinite
clip selects the forward destination. Zero-duration finite clips complete when
started (after any delay). Negative durations, invalid counts and infinite
zero-duration clips raise `ValueError`.

Interpolation supports floats, integers, `Position`, `Size`, `Rect`, RGB `Color`,
and `Vec2`. Calculations remain fractional until sampling. Integer/geometry
samples round halfway away from zero; geometry uses existing coordinate limits.
Back/elastic curves may overshoot; geometry and RGB channels saturate. Built-in
color interpolation requires RGB endpoints. Application types supply an
`Interpolator[T]` closure and equality:

```nim
type Reading = object
  amount: float
let reading = initTween(Reading(amount:0), Reading(amount:10),
  initDuration(seconds=1),
  interpolate=proc(a,b:Reading,t:float):Reading =
    Reading(amount:interpolate(a.amount,b.amount,t)))
```

Easing includes `linear` and `quadratic`, `cubic`, `sine`, `exponential`,
`circular`, `back`, `elastic`, `bounce` with `In`, `Out`, and `InOut` suffixes.
Custom `Easing` closures receive progress in `[0,1]`; endpoints sample exactly.

## Timelines and springs

```nim
let a = initTween(0, 10, initDuration(milliseconds=300))
let b = initTween(0.0, 1.0, initDuration(milliseconds=500))
let spring = initSpring(Vec2(x:0,y:0), Vec2(x:10,y:4))
let timeline = sequence(a, delay(initDuration(milliseconds=100)), parallel(b,spring))
animator.play(timeline)
```

Composition consumes idle, unowned children permanently. Tree structure is
immutable: duplicate children, already-owned/running nodes and attempted cycles
raise `ValueError` before taking any ownership. A running root belongs to one
animator. Construct fresh handles to reuse a clip in a different tree.
`stagger(spacing, child1, child2, ...)` starts branches at multiples of spacing.
Empty groups complete immediately. Groups use one traversal; repeating leaves
can be composed, including an infinite leaf that keeps its group alive.

Sequence time remaining after a child completes carries into the next child,
even across long gaps. A sequence waits for a paused child; cancelling that
child lets it continue. Group cancellation cancels unfinished descendants.
Completion events follow elapsed-time order across long gaps; simultaneous
parallel events follow insertion order, with a group's event after its descendants. No frame
deadline remains when the tree is paused/finished; delayed branches retain their
start deadline.

`Spring[float]` and `Spring[Vec2]` use closed-form underdamped, critically damped,
or overdamped oscillators. Defaults: 4 Hz, damping ratio 1, position and velocity
thresholds 0.001, maximum duration 10 seconds. `SpringConfig` changes those
parameters; damping zero is supported. The optional initial-velocity overload
takes `(first, target, config, initialVelocity)`.

Settling uses conservative analytical position/velocity envelopes and the
maximum duration. Its deterministic deadline does not depend on how often
`advance` is called; settling snaps exactly to the target with zero velocity.
`spring.retarget(target)` starts from its current sampled position and velocity.
Retarget after `advance(now)`; paused springs remain paused. For a retired root,
call `play` to schedule it again. Retarget a composed spring while its sequence
is at that child; to replay a finished sequence, restart the group.

## Buffer transitions and reduced motion

```nim
let transition = initTransition(outgoingBuffer, region,
  initDuration(milliseconds=250), TransitionEffect.Wipe, TransitionDirection.Left)
animator.play(transition)
# Inside draw, AFTER rendering the current destination:
transition.apply(frame.buffer[], currentRegion)
```

The outgoing frame is captured once, including edge context for clipping.
The destination is freshly rendered every frame. `Fade` (fade through an RGB
color), `Slide`, `Wipe`, and seeded `Dissolve` share tween scheduling and lifecycle
controls. Slide/wipe accept `Left`, `Right`, `Up`, and `Down` directions, naming
the direction of travel. Dissolve uses a local coordinate hash and never mutates
a global random generator. Same seed and buffers produce identical results.

Progress zero and one reproduce outgoing and incoming cells, including styles
and diff metadata. Effects only write the clipped region. Complete graphemes and
their continuations are indivisible: wipe/dissolve select connected spans from
both buffers together; slide skips partially visible glyphs and clears complete
overlaps. If a requested edge cuts through a glyph in either frame, that boundary
component stays as rendered in the destination, so outside cells remain intact.
This boundary exception applies at progress zero as well. At progress one the
destination is untouched. A change to the requested region or backing buffer
area ends the transition and shows the new layout immediately. Apply to a fresh
frame each time, never to the preceding effect output.

`Fade` needs a `Palette` closure to resolve named/indexed/default colors to RGB.
Its `ColorChannel` argument distinguishes foreground/background/underline
defaults. All three channels are resolved; no terminal theme is inferred.
RGB-only cells need no palette. Invalid resolution raises `ValueError` before
changing the destination. The demo supplies its own explicit palette.

`animator.reducedMotion` defaults to false and changes at runtime. Finite
`Decorative` clips and `Transition` clips finish immediately; infinite
`Decorative` loops reset to their initial frame and emit cancellation. Functional
clips continue normally. Re-enabling motion does not resurrect cancelled loops;
explicitly restart them. Reduced motion is shared by all roots on an animator,
so applications can use one animator for the workspace. The showcase's Jobs page
marks progress smoothing as decorative while its job simulation keeps running.

Run `nim r examples/showcase/showcase.nim` and open the Motion page for effects, direction,
pause/restart, sequence/spring demos and mouse controls. `m` toggles reduced motion
on every page. `nimble docs` generates the separate animation API alongside the
rendering and input APIs. See [animation validation](validation/animation.md)
for executed checks and platform limits.
