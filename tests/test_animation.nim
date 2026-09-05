import std/[unittest, math]
import canopy/animation

let origin = getMonoTime()
proc at(ms:int):MonoTime = origin+initDuration(milliseconds=ms)
proc near(a,b:float):bool = abs(a-b)<1e-8

suite "animation primitives":
  test "easing endpoints and interior values":
    let curves = [linear,quadraticIn,quadraticOut,quadraticInOut,
      cubicIn,cubicOut,cubicInOut,sineIn,sineOut,sineInOut,
      exponentialIn,exponentialOut,exponentialInOut,circularIn,circularOut,circularInOut,
      backIn,backOut,backInOut,elasticIn,elasticOut,elasticInOut,bounceIn,bounceOut,bounceInOut]
    for curve in curves:
      check near(curve(0),0)
      check near(curve(1),1)
      check curve(0.37).classify notin {fcNan,fcInf,fcNegInf}
    check quadraticIn(0.5)==0.25
    check cubicOut(0.5)==0.875
    check near(sineInOut(0.5),0.5)
    check backIn(0.2)<0
    check bounceOut(0.5)==0.765625
  test "rounding, limits and custom types":
    check interpolate(0,3,0.5)==2
    check interpolate(0'u8,255'u8,2.0)==255'u8
    check interpolate(-100'i16,100'i16,0.25) == -50'i16
    check interpolate(initPosition(2,4),initPosition(5,8),0.5)==initPosition(4,6)
    check interpolate(initSize(0,0),initSize(65535,10),2)==initSize(65535,20)
    check initTween(Position(x: -10,y:99999),initPosition(1,2),initDuration(seconds=1)).value==initPosition(0,65535)
    check interpolate(initRect(0,0,4,4),initRect(65530,0,5,5),2).right==65535
    check interpolate(rgbColor(0,0,0),rgbColor(255,100,0),0.5)==rgbColor(128,50,0)
    expect ValueError: discard initTween(color(ColorKind.Red),color(ColorKind.Blue),initDuration(seconds=1))
    type Custom = object
      n:int
    let t = initTween(Custom(n:0),Custom(n:10),initDuration(seconds=1),
      interpolate=proc(a,b:Custom,p:float):Custom = Custom(n:interpolate(a.n,b.n,p)))
    let a = initAnimator()
    a.play(t)
    discard a.advance(at(0))
    discard a.advance(at(500))
    check t.value.n==5
  test "invalid durations and zero duration completion":
    expect ValueError: discard initAnimator(fps=1e-100)
    expect ValueError: discard initTween(0,1,initDuration(seconds= -1))
    expect ValueError: discard initTween(0,1,DurationZero,iterations= -1)
    let a = initAnimator()
    let t = initTween(0,1,DurationZero)
    a.play(t)
    check t.value==1
    check a.advance(at(0)).events.len==1
    check a.advance(at(1)).events.len==0

suite "playback and composition":
  test "elapsed time, pause, deadlines, no backlog and rounded changes":
    let a=initAnimator()
    let t=initTween(0,100,initDuration(seconds=1))
    a.play(t)
    discard a.advance(at(0))
    check a.nextWake(at(0)).get.inMilliseconds==16
    check a.advance(at(1)).changed.len==0
    discard a.advance(at(250))
    check t.value==25
    t.pause()
    check a.nextWake(at(250)).isNone
    discard a.advance(at(5000))
    t.resume()
    discard a.advance(at(5250))
    check t.value==50
    check a.nextWake(at(6000)).get==DurationZero
    let u=a.advance(at(10000))
    check t.value==100 and t.completed
    check u.events.len==1 and u.events[0].kind==animation.EventKind.Completed
    check a.nextWake(at(10000)).isNone
    expect ValueError: discard a.advance(at(0))
  test "delays and alternating traversal counts":
    let a=initAnimator()
    let t=initTween(0.0,10.0,initDuration(seconds=1),iterations=4,alternate=true,delay=initDuration(seconds=2))
    a.play(t)
    discard a.advance(at(0))
    check a.nextWake(at(0)).get==initDuration(seconds=2)
    discard a.advance(at(3500))
    check near(t.value,5)
    discard a.advance(at(6000))
    check t.value==0 and t.completed
    t.restart()
    a.play(t)
    discard a.advance(at(6000))
    t.finish()
    check t.value==0
    check a.advance(at(6000)).events.len==1
  test "sequence consumes overshoot and preserves event order":
    let a=initAnimator()
    let x=initTween(0,10,initDuration(seconds=1))
    let y=initTween(0,20,initDuration(seconds=1))
    let group=sequence(x,delay(initDuration(milliseconds=100)),y)
    a.play(group)
    discard a.advance(at(0))
    let u=a.advance(at(2200))
    check x.value==10 and y.value==20 and group.completed
    check u.events.len==4
    check u.events[0].animation==x.animation
    check u.events[2].animation==y.animation
    check u.events[3].animation==group
  test "ownership rejects duplicates and cycles before mutation":
    let x=initTween(0,1,initDuration(seconds=1))
    expect ValueError: discard parallel(x,x)
    let group=sequence(x)
    expect ValueError: discard parallel(group,x)
    let a=initAnimator()
    a.play(group)
    expect ValueError: a.play(x)
    expect ValueError: a.play(group)
    expect ValueError: discard sequence(group)
    expect ValueError: x.restart()
  test "parallel cancellation and finish are once only":
    let a=initAnimator()
    let x=initTween(0,10,initDuration(seconds=1))
    let y=initTween(0,20,initDuration(seconds=2))
    let g=parallel(x,y)
    a.play(g)
    discard a.advance(at(0))
    discard a.advance(at(500))
    g.cancel()
    g.cancel()
    g.finish()
    let u=a.advance(at(500))
    check x.value==5 and y.value==5
    check u.events.len==3
    check u.events[0].animation==x.animation and u.events[1].animation==y.animation
    for event in u.events: check event.kind==animation.EventKind.Cancelled
    check a.advance(at(500)).events.len==0
  test "parallel completions are chronological, ties use insertion order":
    let a=initAnimator()
    let slow=initTween(0,1,initDuration(seconds=2))
    let fast=initTween(0,1,initDuration(seconds=1))
    let tie=initTween(0,1,initDuration(seconds=1))
    let group=parallel(slow,fast,tie)
    a.play(group)
    discard a.advance(at(0))
    let events=a.advance(at(3000)).events
    check events.len==4
    check events[0].animation==fast.animation
    check events[1].animation==tie.animation
    check events[2].animation==slow.animation
    check events[3].animation==group
  test "stagger and all paused children have exact idle deadlines":
    let a=initAnimator()
    let x=initTween(0,10,initDuration(seconds=1))
    let y=initTween(0,10,initDuration(seconds=1))
    let g=stagger(initDuration(seconds=2),x,y)
    a.play(g)
    discard a.advance(at(0))
    x.pause()
    check a.nextWake(at(0)).get==initDuration(seconds=2)
    discard a.advance(at(2500))
    check y.value==5
    y.pause()
    check a.nextWake(at(2500)).isNone
  test "huge intervals skip infinite loop traversals":
    let a=initAnimator()
    let t=initTween(0.0,1.0,initDuration(milliseconds=1),iterations= -1,alternate=true)
    a.play(t)
    discard a.advance(at(0))
    discard a.advance(at(1_000_000_000))
    check t.value==0 and t.state==PlaybackState.Playing
  test "empty groups, sub-frame deadlines, delayed zero and replay":
    let a=initAnimator(fps=30)
    let empty=parallel()
    a.play(empty)
    check empty.completed
    check a.advance(at(0)).events.len==1
    let t=initTween(0,10,DurationZero,delay=initDuration(milliseconds=5))
    a.play(t)
    check t.value==0
    check a.nextWake(at(0)).get==initDuration(milliseconds=5)
    check a.advance(at(5)).events.len==1
    a.restart(t)
    check a.advance(at(10)).events.len==1
    let short=initTween(0,10,initDuration(milliseconds=2))
    a.play(short)
    check a.nextWake(at(10)).get==initDuration(milliseconds=2)
    short.finish()
    check short.value==10
    let other=initAnimator()
    expect ValueError: other.play(short)
    discard a.advance(at(10))
    other.play(short)
    check short.value==0

suite "analytical springs and motion preferences":
  test "critical analytic value and retarget velocity":
    let a=initAnimator()
    let s=initSpring(0.0,1.0)
    a.play(s)
    discard a.advance(at(0))
    discard a.advance(at(100))
    let w=8*PI
    check near(s.value,1-(1+w*0.1)*exp(-w*0.1))
    let v=s.velocity
    let p=s.value
    s.retarget(2.0)
    check s.velocity==v and s.value==p
    discard a.advance(at(100))
    check near(s.velocity,v) and near(s.value,p)
    discard a.advance(at(100000))
    check s.value==2 and s.velocity==0 and s.completed
  test "all damping regimes and sequence settling are frame independent":
    for damping in [0.0,0.3,1.0,2.0]:
      var config=defaultSpringConfig()
      config.damping=damping
      let a=initAnimator()
      let b=initAnimator()
      let x=initSpring(Vec2(x:0,y:2),Vec2(x:10,y:0),config)
      let y=initSpring(Vec2(x:0,y:2),Vec2(x:10,y:0),config)
      let tail=initTween(0,100,initDuration(seconds=1))
      a.play(sequence(x,tail))
      b.play(y)
      discard a.advance(at(0))
      discard b.advance(at(0))
      for i in 1..20: discard b.advance(at(i*10))
      discard a.advance(at(200))
      check near(x.value.x,y.value.x) and near(x.velocity.y,y.velocity.y)
      discard a.advance(at(20000))
      check x.value==Vec2(x:10,y:0) and tail.value==100
  test "runtime reduced motion preserves functional state":
    let a=initAnimator()
    let functional=initTween(0,100,initDuration(seconds=1))
    let loop=initTween(0,100,initDuration(seconds=1),iterations= -1,role=MotionRole.Decorative)
    let transition=initTween(0,100,initDuration(seconds=1),role=MotionRole.Transition)
    a.play(parallel(functional,loop,transition))
    discard a.advance(at(0))
    discard a.advance(at(250))
    a.reducedMotion=true
    discard a.advance(at(250))
    check functional.value==25 and loop.value==0 and transition.value==100
    check loop.state==PlaybackState.Cancelled
    a.reducedMotion=false
    discard a.advance(at(500))
    check functional.value==50 and loop.value==0
  test "reduced loops require explicit restart, paused retarget stays paused":
    let a=initAnimator()
    let t=initTween(0,100,initDuration(seconds=1),iterations= -1,role=MotionRole.Decorative)
    a.play(t)
    discard a.advance(at(0))
    a.reducedMotion=true
    check a.advance(at(1)).events.len==1
    a.reducedMotion=false
    check a.nextWake(at(1)).isNone
    a.restart(t)
    discard a.advance(at(501))
    check t.value==50
    let s=initSpring(0.0,1.0)
    a.play(s)
    discard a.advance(at(601))
    s.pause()
    s.retarget(2.0)
    let value=s.value
    discard a.advance(at(1000))
    check s.state==PlaybackState.Paused and s.value==value
