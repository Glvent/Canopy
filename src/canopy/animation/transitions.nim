## Effects run on a freshly rendered destination, before terminal diffing.
import std/math
import ../buffer
import ./[tween, playback]
export buffer, tween
type
  CellSpan = tuple[first,last:int]
  TransitionEffect* {.pure.} = enum Fade, Slide, Wipe, Dissolve
  TransitionDirection* {.pure.} = enum Left, Right, Up, Down
  ColorChannel* {.pure.} = enum Foreground, Background, Underline
  Palette* = proc(color: Color, channel: ColorChannel): Color {.closure.}
  Transition* = ref object
    progress*: Tween[float]
    source: Buffer
    region: Rect
    effect: TransitionEffect
    direction: TransitionDirection
    through: Color
    palette: Palette
    seed: uint32
    ended: bool
    sourceSpans: seq[seq[CellSpan]]

proc spans(buffer: Buffer, y: int): seq[CellSpan] =
  var x = buffer.area.x
  while x < buffer.area.right:
    let last = min(buffer.area.right,x+max(1,buffer[x,y].cellWidth))
    result.add((x,last))
    x = last

converter asAnimation*(t: Transition): Animation = t.progress.animation
func animation*(t: Transition): Animation = t.progress.animation
func value*(t: Transition): float = t.progress.value

proc initTransition*(outgoing: Buffer, region: Rect, duration: Duration,
    effect = TransitionEffect.Wipe, direction = TransitionDirection.Left,
    through = rgbColor(0,0,0), palette: Palette = nil, seed = 302'u32,
    easing: Easing = linear): Transition =
  if effect == TransitionEffect.Fade and through.kind != ColorKind.Rgb:
    raise newException(ValueError,"Fade-through color must be RGB")
  result = Transition(region:region,effect:effect,direction:direction,
    through:through,palette:palette,seed:seed,
    progress:initTween(0.0,1.0,duration,easing=easing,role=MotionRole.Transition))
  # Keep edge context so a glyph crossing the requested boundary is never split.
  result.source = initBuffer(outgoing.area)
  for i,cell in outgoing.content: result.source.content[i] = cell
  for y in outgoing.area.y..<outgoing.area.bottom: result.sourceSpans.add(outgoing.spans(y))

proc safeRegionRow(source,destination:seq[CellSpan],region:Rect): CellSpan =
  result = (region.x,region.right)
  # A boundary-crossing destination glyph remains untouched, including continuations.
  # Source boundary fragments are also excluded instead of emitting half a glyph.
  while result.first < result.last:
    let before = result
    for spans in [source,destination]:
      for span in spans:
        if span.first < result.first and span.last > result.first: result.first = span.last
        if span.first < result.last and span.last > result.last: result.last = span.first
    if result == before: break

func randomAt(seed:uint32,x,y:int):float =
  var h = seed xor (uint32(x)*0x9e3779b9'u32) xor (uint32(y)*0x85ebca6b'u32)
  h = (h xor (h shr 16))*0x7feb352d'u32
  h = (h xor (h shr 15))*0x846ca68b'u32
  h = h xor (h shr 16)
  float(h)/4294967296.0

proc resolve(t:Transition,c:Color,channel:ColorChannel):Color =
  if c.kind == ColorKind.Rgb: return c
  if t.palette == nil: raise newException(ValueError,"RGB fade requires a palette for non-RGB colors")
  result = t.palette(c,channel)
  if result.kind != ColorKind.Rgb: raise newException(ValueError,"Palette must return RGB colors")

proc fade(t:Transition,cell:Cell,p:float):Cell =
  result = cell
  let amount = if p < 0.5: p*2 else: (1-p)*2
  result.fg = interpolate(t.resolve(cell.fg,ColorChannel.Foreground),t.through,amount)
  result.bg = interpolate(t.resolve(cell.bg,ColorChannel.Background),t.through,amount)
  result.underlineColor = interpolate(t.resolve(cell.underlineColor,ColorChannel.Underline),t.through,amount)

proc apply*(t:Transition,destination:var Buffer,region:Rect) =
  ## Sampling does not advance time. On layout/region change the live destination wins.
  if t.ended: return
  if region != t.region or destination.area != t.source.area:
    t.ended = true
    t.animation.finish()
    return
  let p = clamp(t.value,0.0,1.0)
  if p >= 1: return
  let clipped = region.intersection(destination.area)
  if clipped.isEmpty: return
  # Build transactionally: palette errors must not leave a half-modified frame.
  var output = initBuffer(destination.area)
  for i,cell in destination.content: output.content[i] = cell
  var destRows: seq[seq[CellSpan]]
  var safeRows: seq[CellSpan]
  for y in clipped.y..<clipped.bottom:
    destRows.add(destination.spans(y))
    safeRows.add(safeRegionRow(t.sourceSpans[y-t.source.area.y],destRows[^1],clipped))
  for y in clipped.y..<clipped.bottom:
    let safe = safeRows[y-clipped.y]
    if p == 0:
      for x in safe.first..<safe.last: output[x,y] = t.source[x,y]
    elif t.effect == TransitionEffect.Slide:
      for x in safe.first..<safe.last: output[x,y] = initCell()
    else:
      # Connected spans in BOTH frames form an indivisible selection unit.
      let sourceSpans = t.sourceSpans[y-t.source.area.y]
      let destSpans = destRows[y-clipped.y]
      var x = safe.first
      var sourceIndex, destIndex = 0
      while x < safe.last:
        var last = x+1
        while true:
          let before = last
          while sourceIndex < sourceSpans.len and sourceSpans[sourceIndex].first < last:
            last = max(last,sourceSpans[sourceIndex].last)
            inc sourceIndex
          while destIndex < destSpans.len and destSpans[destIndex].first < last:
            last = max(last,destSpans[destIndex].last)
            inc destIndex
          if last == before: break
        if last > safe.last: break
        let chooseDestination = case t.effect
          of TransitionEffect.Fade: p >= 0.5
          of TransitionEffect.Dissolve: randomAt(t.seed,x-clipped.x,y-clipped.y) < p
          of TransitionEffect.Wipe:
            case t.direction
            of TransitionDirection.Left: float(clipped.right-x)/float(clipped.width) <= p
            of TransitionDirection.Right: float(last-clipped.x)/float(clipped.width) <= p
            of TransitionDirection.Up: float(clipped.bottom-y)/float(clipped.height) <= p
            of TransitionDirection.Down: float(y-clipped.y+1)/float(clipped.height) <= p
          of TransitionEffect.Slide: false
        for at in x..<last:
          let cell = if chooseDestination: destination[at,y] else: t.source[at,y]
          output[at,y] = if t.effect == TransitionEffect.Fade: t.fade(cell,p) else: cell
        x = last
  if p > 0 and t.effect == TransitionEffect.Slide:
    let horizontal = t.direction in {TransitionDirection.Left,TransitionDirection.Right}
    let distance = if horizontal: clipped.width else: clipped.height
    let travel = int(round(float(distance)*p))
    let sign = if t.direction in {TransitionDirection.Left,TransitionDirection.Up}: -1 else: 1
    # Track output glyph extents so overlap eviction is linear, without rescanning rows.
    var owners = newSeq[CellSpan](clipped.area)
    for y in clipped.y..<clipped.bottom:
      for x in clipped.x..<clipped.right:
        owners[(y-clipped.y)*clipped.width+x-clipped.x] = (x,x+1)
    # Source first, then destination. Evict entire overlapping output glyphs.
    for layer in 0..1:
      let buffer = if layer == 0: t.source else: destination
      let shift = if layer == 0: sign*travel else: sign*(travel-distance)
      for y in clipped.y..<clipped.bottom:
        let targetY = y+(if horizontal: 0 else: shift)
        if targetY < clipped.y or targetY >= clipped.bottom: continue
        let fromSafe = safeRows[y-clipped.y]
        let toSafe = safeRows[targetY-clipped.y]
        let row = if layer == 0: t.sourceSpans[y-t.source.area.y] else: destRows[y-clipped.y]
        for span in row:
          let first = span.first+(if horizontal: shift else: 0)
          let last = span.last+(if horizontal: shift else: 0)
          if span.first < fromSafe.first or span.last > fromSafe.last or
              first < toSafe.first or last > toSafe.last: continue
          let offset = (targetY-clipped.y)*clipped.width-clipped.x
          for x in first..<last:
            let old = owners[offset+x]
            for at in old.first..<old.last:
              output[at,targetY] = initCell()
              owners[offset+at] = (at,at+1)
          for i in 0..<(last-first):
            output[first+i,targetY] = buffer[span.first+i,y]
            owners[offset+first+i] = (first,last)
  destination = move(output)

proc apply*(t:Transition,destination:var Buffer) = t.apply(destination,t.region)
