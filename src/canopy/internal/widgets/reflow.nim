## Native port of Ratatui 0.30.2 word wrapping and line truncation.
import ../../core/text/index as text
import ../../core/text/unicode
import ../../core/layout/geometry

import std/unicode as nimUnicode

type ReflowLine* = object
  graphemes*: seq[StyledGrapheme]
  width*: int
  alignment*: Alignment

proc whitespace(g: StyledGrapheme): bool =
  # Zero-width space breaks lines even though it is not White_Space; no-break space does not,
  # even though it is.
  if g.symbol == "\u200B": return true
  if g.symbol == "\u00A0": return false
  for r in nimUnicode.runes(g.symbol):
    # Rust char::is_whitespace is Unicode White_Space, including NEL.
    if int(r) notin [9, 10, 11, 12, 13, 32, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F,
        0x3000] and int(r) notin 0x2000..0x200A: return false
  true

proc reflowLine(gs: seq[StyledGrapheme], alignment: Alignment): ReflowLine =
  result = ReflowLine(graphemes: gs, alignment: alignment)
  for g in gs: result.width += cellWidth(g.symbol)

proc wrapLine*(line: Line, base: Style, alignment: Alignment, maxWidth: int,
    trim: bool): seq[ReflowLine] =
  ## Word-wraps to `maxWidth` cells, always producing at least one line. With `trim`, leading
  ## whitespace of a wrapped line is dropped; without it, indentation is preserved.
  ## Graphemes wider than `maxWidth` are skipped, since they can never fit.
  if maxWidth <= 0: return
  # `pending` is the line being built, `word` the current word, and `spaces` the run of whitespace
  # between them, held back so it can be dropped at a wrap point.
  var pending, word, spaces: seq[StyledGrapheme]
  var lineWidth, wordWidth, spaceWidth: int
  var previousNonspace = false
  for g in line.styledGraphemes(base):
    let isSpace = whitespace(g)
    let w = cellWidth(g.symbol)
    if w > maxWidth: continue
    let wordFound = previousNonspace and isSpace
    let trimmedOverflow = pending.len == 0 and trim and wordWidth + w > maxWidth
    let whitespaceOverflow = pending.len == 0 and trim and spaceWidth + w > maxWidth
    let untrimmedOverflow = pending.len == 0 and not trim and wordWidth + spaceWidth + w > maxWidth
    if wordFound or trimmedOverflow or whitespaceOverflow or untrimmedOverflow:
      if pending.len != 0 or not trim:
        pending.add spaces
        lineWidth += spaceWidth
      pending.add word
      word.setLen(0)
      lineWidth += wordWidth
      spaces.setLen(0)
      spaceWidth = 0
      wordWidth = 0
    if lineWidth >= maxWidth or (w > 0 and lineWidth + spaceWidth + wordWidth >= maxWidth):
      var remaining = max(0, maxWidth-lineWidth)
      result.add reflowLine(pending, alignment)
      pending = @[]
      lineWidth = 0
      var consumed = 0
      while consumed < spaces.len:
        let width = cellWidth(spaces[consumed].symbol)
        if width > remaining: break
        spaceWidth -= width
        remaining -= width
        inc consumed
      if consumed > 0: spaces = spaces[consumed..<spaces.len]
      if isSpace and spaces.len == 0: continue
    if isSpace:
      spaceWidth += w
      spaces.add g
    else:
      wordWidth += w
      word.add g
    previousNonspace = not isSpace
  if pending.len == 0 and word.len == 0 and spaces.len > 0 and trim:
    result.add reflowLine(@[], alignment)
  if pending.len != 0 or not trim: pending.add spaces
  pending.add word
  if pending.len > 0: result.add reflowLine(pending, alignment)
  if result.len == 0: result.add reflowLine(@[], alignment)

proc truncateLine*(line: Line, base: Style, alignment: Alignment, maxWidth: int,
    horizontalOffset = 0): ReflowLine =
  ## Cuts the line to `maxWidth` cells. `horizontalOffset` scrolls left-aligned content by
  ## replacing the skipped graphemes with empty symbols, keeping styles positioned.
  result.alignment = alignment
  if maxWidth <= 0: return
  var offset = max(0, horizontalOffset)
  for g in line.styledGraphemes(base):
    let w = cellWidth(g.symbol)
    if w > maxWidth: continue
    if result.width + w > maxWidth: break
    var symbol = g.symbol
    if offset != 0 and alignment == Alignment.Left:
      if w > offset:
        # A wide grapheme spanning the offset is retained in full.
        offset = 0
      else:
        offset -= w
        symbol = ""
    result.width += cellWidth(symbol)
    result.graphemes.add StyledGrapheme(symbol: symbol, style: g.style)
