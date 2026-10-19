## Transition preset timing and sampling tests.
import std/unittest

import canopy
import canopy/ui/animation/index as animation

let origin = getMonoTime()
let duration = initDuration(seconds = 1)

proc palette(c: Color, channel: ColorChannel): Color =
  if c.kind == ColorKind.Rgb: c
  elif channel == ColorChannel.Background: rgbColor(10, 20, 30)
  else: rgbColor(210, 220, 230)

proc sample(source, dest: Buffer, region: Rect, effect: TransitionEffect, p: float,
    direction = TransitionDirection.Left, seed = 302'u32): Buffer =
  let a = initAnimator()
  let t = initTransition(source, region, duration, effect, direction, palette = palette, seed = seed)
  a.play(t)
  discard a.advance(origin)
  discard a.advance(origin+initDuration(nanoseconds = int64(p*1e9)))
  result = dest
  t.apply(result, region)

proc same(a, b: Buffer): bool = a.area == b.area and a.content == b.content
proc completeGlyphs(b: Buffer) =
  for y in b.area.y..<b.area.bottom:
    var x = b.area.x
    while x < b.area.right:
      let width = max(1, b[x, y].cellWidth)
      check x+width <= b.area.right
      for i in 1..<width: check b[x+i, y].symbol == " "
      x+=width

suite "buffer transitions":
  test "all effects have exact complete-cell endpoints, styles and nonzero origin":
    let area = initRect(3, 2, 12, 3)
    var source = initBuffer(area)
    var dest = initBuffer(area)
    source.setString(3, 2, "界é👩‍💻 old", initStyle().withFg(ColorKind.Cyan).bold())
    dest.setString(3, 2, "🙂新 café", initStyle().withBg(ColorKind.Blue).underlined())
    source.setString(3, 3, "outgoing")
    dest.setString(3, 3, "incoming")
    for effect in TransitionEffect:
      for direction in TransitionDirection:
        check same(sample(source, dest, area, effect, 0, direction), source)
        check same(sample(source, dest, area, effect, 1, direction), dest)
        for p in [0.1, 0.25, 0.5, 0.75, 0.9]:
          completeGlyphs(sample(source, dest, area, effect, p, direction))
  test "wipe and slide intermediate complete buffers in all directions":
    let source = initBuffer(["abcd", "efgh"])
    let dest = initBuffer(["1234", "5678"])
    let wipeExpected = [initBuffer(["ab34", "ef78"]), initBuffer(["12cd", "56gh"]),
      initBuffer(["abcd", "5678"]), initBuffer(["1234", "efgh"])]
    let slideExpected = [initBuffer(["cd12", "gh56"]), initBuffer(["34ab", "78ef"]),
      initBuffer(["efgh", "1234"]), initBuffer(["5678", "abcd"])]
    for direction in TransitionDirection:
      check same(sample(source, dest, source.area, TransitionEffect.Wipe, 0.5, direction),
          wipeExpected[ord(direction)])
      check same(sample(source, dest, source.area, TransitionEffect.Slide, 0.5, direction),
          slideExpected[ord(direction)])
  test "wide overlapping boundaries select whole source and destination spans":
    let source = initBuffer(["界ab"])
    let dest = initBuffer(["x界y"])
    check same(sample(source, dest, source.area, TransitionEffect.Wipe, 0.5,
        TransitionDirection.Right), source)
    var expected = source
    expected[3, 0] = dest[3, 0]
    check same(sample(source, dest, source.area, TransitionEffect.Wipe, 0.5), expected)
    check same(sample(source, dest, source.area, TransitionEffect.Wipe, 0.75,
        TransitionDirection.Right), initBuffer(["x界b"]))
  test "Unicode slide intermediates match complete buffers":
    let source = initBuffer(["界ab", "é🙂x"])
    let dest = initBuffer(["好12", "z👩‍💻3"])
    let expected = [initBuffer(["ab好", " xz "]), initBuffer(["12界", " 3é "]),
      initBuffer(["é🙂x", "好12"]), initBuffer(["z👩‍💻3", "界ab"])]
    for direction in TransitionDirection:
      check same(sample(source, dest, source.area, TransitionEffect.Slide, 0.5, direction),
          expected[ord(direction)])
  test "clipping cannot split glyphs or write outside requested region":
    var source = initBuffer(["界abcd界", "abcdefgh"])
    var dest = initBuffer(["a界xyz界", "12345678"])
    for effect in TransitionEffect:
      for direction in TransitionDirection:
        for region in [initRect(1, 0, 6, 1), initRect(2, 0, 1, 1), initRect(3, 1, 1, 1), initRect(0,
            0, 0, 0), initRect(80, 80, 3, 2)]:
          for p in [0.0, 0.25, 0.5, 0.75, 1.0]:
            let got = sample(source, dest, region, effect, p, direction)
            completeGlyphs(got)
            for point in dest.area.positions:
              if not region.contains(point): check got[point] == dest[point]
  test "fade uses explicit palette and complete logical cell fields":
    let source = initBuffer(["old"])
    let dest = initBuffer(["new"])
    let a = initAnimator()
    let t = initTransition(source, source.area, duration, TransitionEffect.Fade)
    a.play(t)
    discard a.advance(origin)
    discard a.advance(origin+initDuration(milliseconds = 250))
    var frame = dest
    expect ValueError: t.apply(frame)
    check same(frame, dest)
    for p in [0.25, 0.5, 0.75]:
      let got = sample(source, dest, source.area, TransitionEffect.Fade, p)
      var expected = if p < 0.5: source else: dest
      let amount = if p < 0.5: p*2 else: (1-p)*2
      for cell in expected.content.mitems:
        cell.fg = interpolate(palette(cell.fg, ColorChannel.Foreground), rgbColor(0, 0, 0), amount)
        cell.bg = interpolate(palette(cell.bg, ColorChannel.Background), rgbColor(0, 0, 0), amount)
        cell.underlineColor = interpolate(palette(cell.underlineColor, ColorChannel.Underline),
            rgbColor(0, 0, 0), amount)
      check same(got, expected)
  test "dissolve seeds are stable, distinct and monotonic":
    let source = initBuffer(["abcdefghijklmnopqrst", "abcdefghijklmnopqrst"])
    let dest = initBuffer(["ABCDEFGHIJKLMNOPQRST", "ABCDEFGHIJKLMNOPQRST"])
    let half = sample(source, dest, source.area, TransitionEffect.Dissolve, 0.5)
    check same(half, sample(source, dest, source.area, TransitionEffect.Dissolve, 0.5))
    check not same(half, sample(source, dest, source.area, TransitionEffect.Dissolve, 0.5, seed = 99))
    let later = sample(source, dest, source.area, TransitionEffect.Dissolve, 0.75)
    for i, cell in half.content:
      check cell == source.content[i] or cell == dest.content[i]
      if cell == dest.content[i]: check later.content[i] == cell
  test "destination stays live; resize ends effect and reduced motion completes":
    let source = initBuffer(["aaaa"])
    let a = initAnimator()
    let t = initTransition(source, source.area, duration, TransitionEffect.Wipe)
    a.play(t)
    discard a.advance(origin)
    discard a.advance(origin+initDuration(milliseconds = 500))
    var frame = initBuffer(["1234"])
    t.apply(frame)
    check same(frame, initBuffer(["aa34"]))
    frame = initBuffer(["5678"])
    t.apply(frame)
    check same(frame, initBuffer(["aa78"]))
    frame = initBuffer(["resized!"])
    let expected = frame
    t.apply(frame)
    check same(frame, expected) and t.completed
    check a.advance(origin+initDuration(milliseconds = 500)).events.len == 1
    let reduced = initTransition(source, source.area, duration)
    a.play(reduced)
    a.reducedMotion = true
    check reduced.value == 1
    frame = initBuffer(["live"])
    reduced.apply(frame)
    check same(frame, initBuffer(["live"]))
  test "sampling same value produces no terminal cell updates":
    let source = initBuffer(["abcdef"])
    let dest = initBuffer(["123456"])
    let one = sample(source, dest, source.area, TransitionEffect.Slide, 0.501)
    let two = sample(source, dest, source.area, TransitionEffect.Slide, 0.502)
    check diff(one, two).len == 0
  test "failed presentation never rewinds time and recovery paints latest sample":
    let a = initAnimator()
    let t = initTween(0, 9, duration)
    a.play(t)
    discard a.advance(origin)
    var terminal = initTerminal(initTestBackend(3, 1))
    defer: terminal.restore()
    proc draw(frame: var Frame) = frame.renderWidget(initLine($t.value), frame.area)
    discard terminal.draw(draw)
    terminal.backend.failFlush = true
    discard a.advance(origin+initDuration(milliseconds = 500))
    expect IOError: discard terminal.draw(draw)
    check t.value == 5
    terminal.backend.failFlush = false
    discard a.advance(origin+initDuration(milliseconds = 750))
    let latest = terminal.draw(draw)
    check t.value == 7
    check latest.buffer[0, 0].symbol == "7"
    check terminal.backend.buffer[0, 0].symbol == "7"
