## Ratatui 0.30.2 layout construction with a native Cassowary solver.
import std/[math, hashes, tables, options]

import ./geometry
import ../../internal/layout/solver
export geometry.Direction

type
  ConstraintKind* {.pure.} = enum Length, Min, Max, Percentage, Ratio, Fill
  Constraint* = object
    ## `value` carries the length, bound, percentage, or fill weight; `numerator`/`denominator`
    ## are read only for Ratio.
    kind*: ConstraintKind
    value*, numerator*, denominator*: int
  Flex* {.pure.} = enum Legacy, Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly
  Layout* = object
    direction*: Direction
    constraints*: seq[Constraint]
    margin*: Margin
    spacing*: int
    flex*: Flex
  ## `spacers` has one more element than `segments`: the leading and trailing gaps are included.
  LayoutResult* = tuple[segments, spacers: seq[Rect]]
  CacheKey = tuple[layout: Layout, area: Rect]
  CacheEntry = object
    value: LayoutResult
    used: uint64

const DefaultLayoutCacheSize* = 500 ## Entries kept per thread until `setLayoutCacheSize` overrides it.
# Thread-local cache avoids solver work for repeated layout/area pairs in one thread.
var layoutCache {.threadvar.}: Table[CacheKey, CacheEntry]
var cacheCapacity {.threadvar.}: int
var cacheInitialized {.threadvar.}: bool
var cacheClock {.threadvar.}: uint64

func hash*(constraint: Constraint): Hash = hash((constraint.kind, constraint.value,
  constraint.numerator, constraint.denominator))
func hash*(layout: Layout): Hash = hash((layout.direction, layout.constraints,
  layout.margin.horizontal, layout.margin.vertical, layout.spacing, layout.flex))
func hash(key: CacheKey): Hash = hash((key.layout, key.area.x, key.area.y,
  key.area.width, key.area.height))
func length*(value: int): Constraint = Constraint(kind: ConstraintKind.Length, value: clamp(value, 0, 65535))
func minLength*(value: int): Constraint = Constraint(kind: ConstraintKind.Min, value: clamp(value, 0, 65535))
func maxLength*(value: int): Constraint = Constraint(kind: ConstraintKind.Max, value: clamp(value, 0, 65535))
func percentage*(value: int): Constraint = Constraint(kind: ConstraintKind.Percentage, value: clamp(
    value, 0, 65535))
func ratio*(numerator, denominator: int): Constraint =
  Constraint(kind: ConstraintKind.Ratio, numerator: clamp(numerator, 0, int(uint32.high)),
    denominator: clamp(denominator, 0, int(uint32.high)))

func fill*(weight = 1): Constraint =
  ## Claims leftover space in proportion to `weight` against other Fill constraints.
  Constraint(kind: ConstraintKind.Fill, value: clamp(weight, 0, 65535))

func apply*(constraint: Constraint, size: int): int =
  ## Compatibility for upstream's deprecated single-constraint application.
  let size = clamp(size, 0, 65535)
  case constraint.kind
  of ConstraintKind.Percentage:
    int(min(float32(constraint.value) / 100'f32 * float32(size), float32(size)))
  of ConstraintKind.Ratio:
    int(min(float32(constraint.numerator) / float32(max(1, constraint.denominator)) * float32(size),
        float32(size)))
  of ConstraintKind.Min: max(size, constraint.value)
  else: min(size, constraint.value)

func fromLengths*(values: openArray[int]): seq[Constraint] =
  for value in values: result.add length(value)

func fromMins*(values: openArray[int]): seq[Constraint] =
  for value in values: result.add minLength(value)

func fromMaxes*(values: openArray[int]): seq[Constraint] =
  for value in values: result.add maxLength(value)

func fromPercentages*(values: openArray[int]): seq[Constraint] =
  for value in values: result.add percentage(value)

func fromFills*(values: openArray[int]): seq[Constraint] =
  for value in values: result.add fill(value)

func fromRatios*(values: openArray[tuple[numerator, denominator: int]]): seq[Constraint] =
  for value in values: result.add ratio(value.numerator, value.denominator)

func isLength*(c: Constraint): bool = c.kind == ConstraintKind.Length
func isMin*(c: Constraint): bool = c.kind == ConstraintKind.Min
func isMax*(c: Constraint): bool = c.kind == ConstraintKind.Max
func isPercentage*(c: Constraint): bool = c.kind == ConstraintKind.Percentage
func isRatio*(c: Constraint): bool = c.kind == ConstraintKind.Ratio
func isFill*(c: Constraint): bool = c.kind == ConstraintKind.Fill
func initLayout*(direction = Direction.Vertical, constraints: openArray[Constraint] = []): Layout =
  Layout(direction: direction, constraints: @constraints, flex: Flex.Start)

func horizontal*(constraints: openArray[Constraint]): Layout = initLayout(Direction.Horizontal, constraints)
func vertical*(constraints: openArray[Constraint]): Layout = initLayout(Direction.Vertical, constraints)
func withDirection*(layout: Layout, direction: Direction): Layout =
  result = layout; result.direction = direction

func withConstraints*(layout: Layout, constraints: openArray[Constraint]): Layout =
  result = layout; result.constraints = @constraints

func withMargin*(layout: Layout, margin: Margin): Layout =
  result = layout; result.margin = margin

func withMargin*(layout: Layout, margin: int): Layout = layout.withMargin(initMargin(margin, margin))
func withHorizontalMargin*(layout: Layout, margin: int): Layout =
  result = layout; result.margin.horizontal = clamp(margin, 0, 65535)

func withVerticalMargin*(layout: Layout, margin: int): Layout =
  result = layout; result.margin.vertical = clamp(margin, 0, 65535)

func withSpacing*(layout: Layout, spacing: int): Layout =
  result = layout; result.spacing = clamp(spacing, -32768, 32767)

func withFlex*(layout: Layout, flex: Flex): Layout =
  result = layout; result.flex = flex

proc setLayoutCacheSize*(capacity: int) =
  ## Resizes the calling thread's cache and drops its entries; capacity 0 disables caching.
  cacheCapacity = max(0, capacity)
  cacheInitialized = true
  layoutCache.clear()

proc clearLayoutCache*() = layoutCache.clear()
proc layoutCacheSize*(): int = layoutCache.len

# Constraint strengths ordered by upstream priority: a stronger class always wins over the
# weaker ones, so the ratios matter more than the absolute magnitudes.
const
  SpacerEqual = Required / 10.0
  MinGreater = 100_000_000.0
  MaxLess = 100_000_000.0
  LengthEqual = 10_000_000.0
  PercentageEqual = 1_000_000.0
  RatioEqual = 100_000.0
  MinMaxEqual = 10_000.0
  FillGrow = 1_000.0
  Grow = 100.0
  SpaceGrow = 10.0

proc compute(layout: Layout, outer: Rect): LayoutResult =
  # Variables alternate spacer/segment edges: index 0 and `last` pin the area, odd indices open a
  # segment, even indices open a spacer.
  var solver = initSolver()
  let area = outer.inner(layout.margin)
  let count = layout.constraints.len
  let last = count * 2 + 1
  # Solver variables use centi-cell integers to match upstream Ratatui scaling.
  let areaStart = float64(if layout.direction == Direction.Horizontal: area.x else: area.y) * 100.0
  let areaEnd = float64(if layout.direction == Direction.Horizontal: area.right else: area.bottom) * 100.0
  let areaSize = variable(last) - variable(0)
  template size(start: int): Expression = variable(start + 1) - variable(start)
  template eq(left, right: Expression, strength: float64) =
    solver.addConstraint(left - right, Relation.Equal, strength)
  template empty(start: int) = eq(size(start), constant(0), Required - 1.0)
  template spacerMin(start: int) =
    solver.addConstraint(size(start) - float64(layout.spacing) * 100.0,
      Relation.GreaterOrEqual, SpacerEqual)
  eq(variable(0), constant(areaStart), Required)
  eq(variable(last), constant(areaEnd), Required)
  for i in 0..last:
    solver.addConstraint(variable(i) - variable(0), Relation.GreaterOrEqual)
    solver.addConstraint(variable(i) - variable(last), Relation.LessOrEqual)
  for i in 0..<count:
    solver.addConstraint(variable(i*2+1) - variable(i*2+2), Relation.LessOrEqual)
  case layout.flex
  of Flex.Legacy, Flex.Start, Flex.End, Flex.Center:
    for i in 1..<count:
      eq(size(i*2), constant(float64(layout.spacing) * 100.0), SpacerEqual)
    case layout.flex
    of Flex.Legacy:
      empty(0); empty(count*2)
    of Flex.Start:
      empty(0); eq(size(count*2), areaSize, Grow)
    of Flex.End:
      empty(count*2); eq(size(0), areaSize, Grow)
    of Flex.Center:
      eq(size(0), areaSize, Grow)
      eq(size(count*2), areaSize, Grow)
      eq(size(0), size(count*2), SpacerEqual)
    else: discard
  of Flex.SpaceBetween:
    for i in 1..<count:
      for j in i+1..<count: eq(size(i*2), size(j*2), SpacerEqual)
    for i in 1..<count:
      spacerMin(i*2)
      eq(size(i*2), areaSize, SpaceGrow)
    empty(0); empty(count*2)
  of Flex.SpaceAround, Flex.SpaceEvenly:
    if layout.flex == Flex.SpaceEvenly or count <= 1:
      for i in 0..count:
        for j in i+1..count: eq(size(i*2), size(j*2), SpacerEqual)
    else:
      for i in 1..<count:
        for j in i+1..<count: eq(size(i*2), size(j*2), SpacerEqual)
      eq(size(2), size(0) * 2.0, SpacerEqual)
      eq(size(2), size(count*2) * 2.0, SpacerEqual)
    for i in 0..count:
      spacerMin(i*2)
      eq(size(i*2), areaSize, SpaceGrow)
  var fills: seq[tuple[index: int, weight: float64]]
  for i, constraint in layout.constraints:
    let segment = size(i*2+1)
    let value = float64(constraint.value) * 100.0
    case constraint.kind
    of ConstraintKind.Max:
      solver.addConstraint(segment - value, Relation.LessOrEqual, MaxLess)
      eq(segment, constant(value), MinMaxEqual)
    of ConstraintKind.Min:
      # Upstream casts its u16 minimum to i16 before constructing this bound.
      let signed = if constraint.value >= 32768: constraint.value - 65536 else: constraint.value
      solver.addConstraint(segment - float64(signed) * 100.0, Relation.GreaterOrEqual, MinGreater)
      if layout.flex == Flex.Legacy: eq(segment, constant(value), MinMaxEqual)
      else:
        eq(segment, areaSize, FillGrow)
        fills.add (i, 1.0)
    of ConstraintKind.Length: eq(segment, constant(value), LengthEqual)
    of ConstraintKind.Percentage:
      eq(segment, (areaSize * float64(constraint.value)) / 100.0, PercentageEqual)
    of ConstraintKind.Ratio:
      eq(segment, (areaSize * float64(constraint.numerator)) / float64(max(1,
          constraint.denominator)), RatioEqual)
    of ConstraintKind.Fill:
      eq(segment, areaSize, FillGrow)
      fills.add (i, max(1e-6, float64(constraint.value)))
  for i in 0..<fills.len:
    for j in i+1..<fills.len:
      eq(size(fills[i].index*2+1) * fills[j].weight,
        size(fills[j].index*2+1) * fills[i].weight, Grow)
  if layout.flex != Flex.Legacy:
    for i in 0..<count-1: eq(size(i*2+1), size(i*2+3), 1.0)
  proc rectangle(start: int): Rect =
    # Double rounding matches upstream: solver output is rounded in centi-cells before scaling.
    let a = clamp(int(round(round(solver.value(start)) / 100.0)), 0, 65535)
    let b = clamp(int(round(round(solver.value(start+1)) / 100.0)), 0, 65535)
    if layout.direction == Direction.Horizontal:
      Rect(x: a, y: area.y, width: max(0, b-a), height: area.height)
    else:
      Rect(x: area.x, y: a, width: area.width, height: max(0, b-a))
  for i in 0..<count: result.segments.add rectangle(i*2+1)
  for i in 0..count: result.spacers.add rectangle(i*2)

proc splitWithSpacers*(layout: Layout, area: Rect): LayoutResult =
  ## Solves the layout, reusing the thread-local cache for repeated layout/area pairs.
  if not cacheInitialized:
    cacheCapacity = DefaultLayoutCacheSize
    cacheInitialized = true
  if cacheCapacity == 0: return compute(layout, area)
  let key = (layout, area)
  inc cacheClock
  if key in layoutCache:
    layoutCache[key].used = cacheClock
    return layoutCache[key].value
  result = compute(layout, area)
  # Evict least-recently-used entry when the thread-local cache is full.
  if layoutCache.len >= cacheCapacity:
    var oldest: CacheKey
    var age = uint64.high
    for candidate, entry in layoutCache:
      if entry.used < age:
        oldest = candidate; age = entry.used
    layoutCache.del(oldest)
  layoutCache[key] = CacheEntry(value: result, used: cacheClock)

proc split*(layout: Layout, area: Rect): seq[Rect] = layout.splitWithSpacers(area).segments
proc spacers*(layout: Layout, area: Rect): seq[Rect] = layout.splitWithSpacers(area).spacers
proc tryAreas*[N: static[int]](layout: Layout, area: Rect): Option[array[N, Rect]] =
  ## Returns `none` when the constraint count differs from `N`, where `areas` would raise.
  let segments = layout.split(area)
  if segments.len != N: return none(array[N, Rect])
  var fixed: array[N, Rect]
  for i in 0..<N: fixed[i] = segments[i]
  some(fixed)

proc areas*[N: static[int]](layout: Layout, area: Rect): array[N, Rect] =
  ## Raises ValueError when the layout does not produce exactly `N` segments.
  let segments = layout.split(area)
  if segments.len != N:
    raise newException(ValueError, "Layout constraint count does not match requested array length")
  for i in 0..<N: result[i] = segments[i]

proc spacerAreas*[N: static[int]](layout: Layout, area: Rect): array[N, Rect] =
  ## Raises ValueError unless the layout produces exactly `N` spacers, one more than its segments.
  let spacers = layout.spacers(area)
  if spacers.len != N:
    raise newException(ValueError, "Layout spacer count does not match requested array length")
  for i in 0..<N: result[i] = spacers[i]

proc centeredHorizontally*(area: Rect, constraint: Constraint): Rect =
  horizontal([constraint]).withFlex(Flex.Center).split(area)[0]

proc centeredVertically*(area: Rect, constraint: Constraint): Rect =
  vertical([constraint]).withFlex(Flex.Center).split(area)[0]

proc centered*(area: Rect, horizontalConstraint, verticalConstraint: Constraint): Rect =
  area.centeredHorizontally(horizontalConstraint).centeredVertically(verticalConstraint)

proc layoutVec*(area: Rect, layout: Layout): seq[Rect] = layout.split(area)
proc layout*[N: static[int]](area: Rect, layout: Layout): array[N, Rect] = areas[N](layout, area)
proc tryLayout*[N: static[int]](area: Rect, layout: Layout): Option[array[N, Rect]] = tryAreas[N](
    layout, area)
