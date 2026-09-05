## Styled text with Ratatui-compatible wrapping, scrolling and alignment.
import std/options
import ../[geometry, style, text, buffer, unicode]
import ../internal/reflow
import "./block"
export text, geometry.Alignment

type
  Wrap* = object
    trim*: bool
  Paragraph* = object
    text*: Text
    blockWidget*: Option[Block]
    style*: Style
    wrap*: Option[Wrap]
    scroll*: Position
    alignment*: Alignment

func initWrap*(trim = false): Wrap = Wrap(trim: trim)
func initParagraph*(content: Text): Paragraph =
  Paragraph(text: content, alignment: content.alignment.get(Alignment.Left))
func initParagraph*(content: string): Paragraph = initParagraph(initText(content))
func withBlock*(p: Paragraph, b: Block): Paragraph =
  result = p; result.blockWidget = some(b)
func withStyle*(p: Paragraph, s: Style): Paragraph =
  result = p; result.style = s
func withWrap*(p: Paragraph, wrap: Wrap): Paragraph =
  result = p; result.wrap = some(wrap)
func withWrap*(p: Paragraph, trim: bool): Paragraph = p.withWrap(initWrap(trim))
func withScroll*(p: Paragraph, vertical, horizontal: int): Paragraph =
  result = p; result.scroll = initPosition(horizontal, vertical)
func withScroll*(p: Paragraph, offset: tuple[vertical,horizontal:int]): Paragraph =
  p.withScroll(offset.vertical, offset.horizontal)
func withAlignment*(p: Paragraph, alignment: Alignment): Paragraph =
  result = p; result.alignment = alignment
func leftAligned*(p: Paragraph): Paragraph = p.withAlignment(Alignment.Left)
func centered*(p: Paragraph): Paragraph = p.withAlignment(Alignment.Center)
func rightAligned*(p: Paragraph): Paragraph = p.withAlignment(Alignment.Right)

proc renderLine(line: ReflowLine, area: Rect, y: int, buf: var Buffer) =
  var x = area.x + (case line.alignment
    of Alignment.Left: 0
    of Alignment.Center: max(0, area.width div 2-line.width div 2)
    of Alignment.Right: max(0, area.width-line.width))
  for g in line.graphemes:
    let w = cellWidth(g.symbol)
    if w == 0: continue
    # Ratatui's wrapper can emit an overwidth pending word (e.g. é👩‍🔬x
    # at width two). Preserve its adjacent-cell writes inside the actual buffer.
    if buf.area.contains(initPosition(x,y)):
      buf[x,y].setSymbol(g.symbol)
      buf[x,y].setStyle(g.style)
    x += w

proc render*(p: Paragraph, area: Rect, buf: var Buffer) =
  let a = area.intersection(buf.area)
  buf.setStyle(a, p.style)
  p.blockWidget.render(a, buf)
  let inner = p.blockWidget.inner(a)
  if inner.isEmpty: return
  buf.setStyle(inner, p.style)
  var skipped = 0
  var y = inner.y
  for i,line in p.text.lines:
    if p.wrap.isSome:
      for wrapped in wrapLine(line,p.text.style,line.alignment.get(p.alignment),inner.width,p.wrap.get.trim):
        if skipped < p.scroll.y: inc skipped; continue
        renderLine(wrapped,inner,y,buf)
        inc y
        if y >= inner.bottom: return
    else:
      if i < p.scroll.y: continue
      renderLine(truncateLine(line,p.text.style,line.alignment.get(p.alignment),inner.width,p.scroll.x),inner,y,buf)
      inc y
      if y >= inner.bottom: return
