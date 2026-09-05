## Styled, grapheme-aware text. Rendering is provided by canopy/buffer.
import std/[strutils, options]
import ./[geometry, style, unicode]
export geometry.Alignment, style, options

type
  Span* = object
    content*: string
    style*: Style
  Line* = object
    spans*: seq[Span]
    style*: Style
    alignment*: Option[Alignment]
  Text* = object
    lines*: seq[Line]
    style*: Style
    alignment*: Option[Alignment]
  StyledGrapheme* = object
    symbol*: string
    style*: Style

func initSpan*(content: string, style: Style = initStyle()): Span = Span(content: content, style: style)
func initLine*(spans: openArray[Span]): Line = Line(spans: @spans)
func initLine*(content: string): Line =
  if content.len == 0: return
  let lines = content.split('\n')
  for i,line in lines:
    if i == lines.high and line.len == 0: break
    let value = if i < lines.high and line.endsWith("\r"): line[0..<line.len-1] else: line
    result.spans.add(initSpan(value))
func initLine*(span: Span): Line = initLine([span])
func initText*(lines: openArray[Line]): Text = Text(lines: @lines)
func initText*(content: string): Text =
  # Rust str::lines omits the trailing newline and recognizes CRLF only.
  if content.len == 0: return initText([initLine("")])
  var lines = content.split('\n')
  if lines[^1].len == 0: lines.setLen(lines.len-1)
  for i,line in lines:
    let hasNewline = i < lines.high or content.endsWith("\n")
    result.lines.add(initLine(if hasNewline and line.endsWith("\r"): line[0..<line.len-1] else: line))
proc width*(s: Span): int = displayWidth(s.content)
proc width*(line: Line): int =
  for span in line.spans: result += span.width
proc width*(text: Text): int =
  for line in text.lines: result = max(result, line.width)
func height*(text: Text): int = text.lines.len
func withStyle*(s: Span, style: Style): Span =
  result = s
  result.style = style
func withStyle*(s: Line, style: Style): Line =
  result = s
  result.style = style
func withStyle*(s: Text, style: Style): Text =
  result = s
  result.style = style
func patchStyle*(s: Span, style: Style): Span = s.withStyle(s.style.patch(style))
func patchStyle*(s: Line, style: Style): Line = s.withStyle(s.style.patch(style))
func patchStyle*(s: Text, style: Style): Text = s.withStyle(s.style.patch(style))
func resetStyle*(s: Span): Span = s.patchStyle(style.resetStyle())
func resetStyle*(s: Line): Line = s.patchStyle(style.resetStyle())
func resetStyle*(s: Text): Text = s.patchStyle(style.resetStyle())
func withAlignment*(s: Line, alignment: Alignment): Line =
  result = s
  result.alignment = some(alignment)
func withAlignment*(s: Text, alignment: Alignment): Text =
  result = s
  result.alignment = some(alignment)
func `$`*(s: Span): string = s.content
func `$`*(s: Line): string =
  for span in s.spans: result.add(span.content)
func `$`*(s: Text): string =
  for i, line in s.lines:
    if i > 0: result.add('\n')
    result.add($line)
proc pushSpan*(line: var Line, span: Span) = line.spans.add(span)
proc pushLine*(text: var Text, line: Line) = text.lines.add(line)
proc pushSpan*(text: var Text, span: Span) =
  if text.lines.len == 0: text.lines.add(initLine([span]))
  else: text.lines[^1].spans.add(span)
func leftAligned*(line: Line): Line = line.withAlignment(Alignment.Left)
func centered*(line: Line): Line = line.withAlignment(Alignment.Center)
func rightAligned*(line: Line): Line = line.withAlignment(Alignment.Right)
func leftAligned*(text: Text): Text = text.withAlignment(Alignment.Left)
func centered*(text: Text): Text = text.withAlignment(Alignment.Center)
func rightAligned*(text: Text): Text = text.withAlignment(Alignment.Right)
func leftAligned*(span: Span): Line = initLine(span).leftAligned()
func centered*(span: Span): Line = initLine(span).centered()
func rightAligned*(span: Span): Line = initLine(span).rightAligned()
func `+`*(line: Line, span: Span): Line =
  result = line
  result.spans.add(span)
func `+`*(a,b: Line): Text = initText([a,b])
iterator items*(line: Line): Span =
  for span in line.spans: yield span
iterator mitems*(line: var Line): var Span =
  for span in line.spans.mitems: yield span
iterator items*(text: Text): Line =
  for line in text.lines: yield line
iterator mitems*(text: var Text): var Line =
  for line in text.lines.mitems: yield line
func hasControl*(s: string): bool =
  for i,c in s:
    if ord(c) < 32 or ord(c) == 127: return true
    if c == '\xC2' and i+1 < s.len and ord(s[i+1]) in 128..159: return true
iterator styledGraphemes*(span: Span, base: Style = initStyle()): StyledGrapheme =
  let combined = base.patch(span.style)
  for symbol in graphemes(span.content):
    if not hasControl(symbol): yield StyledGrapheme(symbol:symbol, style:combined)
iterator styledGraphemes*(line: Line, base: Style = initStyle()): StyledGrapheme =
  for span in line.spans:
    for g in span.styledGraphemes(base.patch(line.style)): yield g

template styledShortcuts(T: typedesc) =
  func withFg*(s: T, c: Color): T = s.patchStyle(initStyle().withFg(c))
  func withFg*(s: T, c: ColorKind): T = s.withFg(color(c))
  func withBg*(s: T, c: Color): T = s.patchStyle(initStyle().withBg(c))
  func withBg*(s: T, c: ColorKind): T = s.withBg(color(c))
  func bold*(s: T): T = s.patchStyle(initStyle().bold())
  func italic*(s: T): T = s.patchStyle(initStyle().italic())
  func underlined*(s: T): T = s.patchStyle(initStyle().underlined())
styledShortcuts(Span)
styledShortcuts(Line)
styledShortcuts(Text)
