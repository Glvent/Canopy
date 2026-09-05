## Native Ratatui 0.30.2 box-drawing merge algorithm, MIT.
## Decomposition and precedence follow ratatui-core/src/symbols/merge.rs.
type
  MergeStrategy* {.pure.} = enum Replace, Exact, Fuzzy
  LineStyle = enum
    lsNothing, lsPlain, lsRounded, lsDouble, lsThick, lsDoubleDash,
    lsDoubleDashThick, lsTripleDash, lsTripleDashThick, lsQuadrupleDash,
    lsQuadrupleDashThick
  Parts = array[4,LineStyle] # right, up, left, down

include symbol_merge_table

func parsed(symbol: string): int =
  # All recognized symbols are three-byte UTF-8, except the special empty one.
  for i,entry in symbolParts:
    if entry.symbol == symbol: return i
  -1

func represented(parts: Parts): string =
  for entry in symbolParts:
    if entry.parts == parts: return entry.symbol
  ""

func replace(parts: Parts, before, after: LineStyle): Parts =
  for i,p in parts: result[i] = if p == before: after else: p

func straight(p: Parts): bool =
  p[1] == p[3] and p[2] == p[0] and (p[1] == lsNothing or p[2] == lsNothing)

func corner(p: Parts): bool =
  # Keep the upstream match order, including empty and partial components.
  if p[3] == lsNothing and p[2] == lsNothing: p[1] == p[0]
  elif p[1] == lsNothing and p[2] == lsNothing: p[0] == p[3]
  elif p[1] == lsNothing and p[0] == lsNothing: p[3] == p[2]
  elif p[0] == lsNothing and p[3] == lsNothing: p[1] == p[2]
  else: false

func mergeSymbol*(previous, next: string, strategy: MergeStrategy): string =
  ## Replace wins unconditionally. Exact/Fuzzy preserve non-border content
  ## when overlaying a known border, matching upstream's fallback semantics.
  if strategy == MergeStrategy.Replace: return next
  let before = parsed(previous)
  let after = parsed(next)
  if after < 0: return next
  if before < 0: return previous
  let incoming = symbolParts[after].parts
  var merged: Parts
  for i in 0..3:
    merged[i] = if incoming[i] == lsNothing: symbolParts[before].parts[i] else: incoming[i]
  if strategy == MergeStrategy.Fuzzy:
    if not merged.straight:
      for dashed in [lsDoubleDash,lsTripleDash,lsQuadrupleDash]: merged = merged.replace(dashed,lsPlain)
      for dashed in [lsDoubleDashThick,lsTripleDashThick,lsQuadrupleDashThick]: merged = merged.replace(dashed,lsThick)
    if not merged.corner: merged = merged.replace(lsRounded,lsPlain)
    if lsDouble in merged and lsThick in merged:
      merged = if lsDouble in incoming: merged.replace(lsThick,lsDouble) else: merged.replace(lsDouble,lsThick)
    if represented(merged).len == 0:
      merged = if lsDouble in incoming: merged.replace(lsPlain,lsDouble) else: merged.replace(lsDouble,lsPlain)
  result = represented(merged)
  if result.len == 0: result = next

func merge*(strategy: MergeStrategy, previous,next: string): string = mergeSymbol(previous,next,strategy)
