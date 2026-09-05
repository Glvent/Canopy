## Extended grapheme segmentation and terminal display width, Unicode 17.0.0.
## Invalid UTF-8: each invalid byte is measured as U+FFFD; segmentation and
## truncation preserve the original bytes. Control characters have string width
## one (CRLF has width one), matching unicode-width's string API.
import internal/[unicode_props, unicode_width]

const
  unicodeSegmentationVersion* = "1.13.3"
  unicodeWidthVersion* = "0.2.2"
  unicodeVersion* = "17.0.0"

proc hasBoundary(runes: seq[DecodedRune], i, regionalCount: int): bool =
  let before = GraphemeCategory(runes[i-1].property.category)
  let after = GraphemeCategory(runes[i].property.category)
  if before == gcCR and after == gcLF: return false # GB3
  if before in {gcControl, gcCR, gcLF}: return true # GB4
  if after in {gcControl, gcCR, gcLF}: return true # GB5
  if before == gcL and after in {gcL, gcV, gcLV, gcLVT}: return false
  if before in {gcLV, gcV} and after in {gcV, gcT}: return false
  if before in {gcLVT, gcT} and after == gcT: return false
  if after in {gcExtend, gcZWJ, gcSpacingMark}: return false
  if before == gcPrepend: return false
  if after == gcInCBConsonant: # GB9c
    var j = i-1
    var linker = false
    while j >= 0:
      let p = runes[j].property
      if (p.incb and 2) != 0: linker = true
      elif (p.incb and 1) == 0:
        return not (linker and GraphemeCategory(p.category) == gcInCBConsonant)
      dec j
    return true
  if before == gcZWJ and after == gcExtendedPictographic: # GB11
    var j = i-2
    while j >= 0 and GraphemeCategory(runes[j].property.category) == gcExtend: dec j
    return j < 0 or GraphemeCategory(runes[j].property.category) != gcExtendedPictographic
  if before == gcRegionalIndicator and after == gcRegionalIndicator: # GB12/13
    return regionalCount mod 2 == 0
  true

proc graphemes*(s: string): seq[string] =
  ## Split into extended grapheme clusters, preserving every input byte.
  let runes = decode(s)
  if runes.len == 0: return
  var first = 0
  var regionalCount = ord(GraphemeCategory(runes[0].property.category) == gcRegionalIndicator)
  for i in 1..<runes.len:
    if hasBoundary(runes, i, regionalCount):
      result.add s[first..<runes[i].first]
      first = runes[i].first
    if GraphemeCategory(runes[i].property.category) == gcRegionalIndicator: inc regionalCount
    else: regionalCount = 0
  result.add s[first..<s.len]

proc displayWidth*(s: string): int = stringWidth(s)

proc graphemeWidth*(s: string): int =
  ## Width of a cluster; accepting arbitrary strings follows displayWidth.
  displayWidth(s)

proc cellWidth*(s: string): int =
  ## Ratatui's terminal-cell adjustment for halfwidth voiced sound marks.
  result = displayWidth(s)
  for r in decode(s):
    if r.code in [0xFF9E, 0xFF9F]: inc result

proc truncateWidth*(s: string, maxWidth: int): string =
  ## Longest leading whole-cluster prefix fitting maxWidth. Width is measured
  ## over each prefix because contextual ligatures can cross cluster boundaries.
  if maxWidth < 0: return
  var prefix = ""
  for cluster in graphemes(s):
    prefix.add cluster
    if displayWidth(prefix) <= maxWidth: result = prefix
