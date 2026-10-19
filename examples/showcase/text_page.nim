## Styled text and color: modifiers, alignment, named/indexed/RGB colors, HSL and HSLuv
## conversions, Unicode display widths and the detected color depth.
import std/[monotimes, strutils]

import canopy
import canopy/runtime/terminal/input
import common

const help* = "←/→ or wheel: rotate hues"

var
  hueOffset = 0
  colorHit: Rect

proc modifierText(): Text =
  var lines: seq[Line]
  for (name, style) in [("Bold", initStyle().bold()), ("Dim", initStyle().dim()),
      ("Italic", initStyle().italic()), ("Underlined", initStyle().underlined()),
      ("Underline color", initStyle().underlined().withUnderlineColor(color(ColorKind.Red))),
      ("Reversed", initStyle().reversed()), ("Crossed out", initStyle().crossedOut()),
      ("Slow blink", initStyle().slowBlink()),
      ("Bold + italic + accent", accent().bold().italic())]:
    lines.add(initLine([initSpan("Canopy", style), initSpan("  " & name, initStyle().dim())]))
  lines.add(initLine(""))
  lines.add(initLine("Left-aligned line").leftAligned())
  lines.add(initLine("Centered line").centered())
  lines.add(initLine("Right-aligned line").rightAligned())
  lines.add(initLine(""))
  lines.add(initLine([initSpan("Spans "), initSpan("mix ", accent()),
    initSpan("styles ", initStyle().withFg(ColorKind.Yellow).bold()),
    initSpan("in one line", initStyle().withFg(ColorKind.Black).withBg(ColorKind.White))]))
  initText(lines)

proc swatch(c: Color, width = 2): Span = initSpan(repeat(' ', width), initStyle().withBg(c))

proc colorText(width: int): Text =
  var lines: seq[Line]
  lines.add(initLine(initSpan("16 named colors", accent().bold())))
  for row in 0..1:
    var spans: seq[Span]
    for i in 0..7: spans.add(swatch(color(ColorKind(ord(ColorKind.Black) + row * 8 + i)), 4))
    lines.add(initLine(spans))
  lines.add(initLine(""))
  lines.add(initLine(initSpan("256 indexed colors", accent().bold())))
  for row in 0..7:
    var spans: seq[Span]
    for i in 0..31: spans.add(swatch(indexedColor(row * 32 + i), 1))
    lines.add(initLine(spans))
  lines.add(initLine(""))
  let columns = max(1, width)
  for (title, convert) in [("HSL (colorFromHsl)", proc(h: float32): Color = colorFromHsl(h, 0.8, 0.5)),
      ("HSLuv (colorFromHsluv), perceptually even", proc(h: float32): Color = colorFromHsluv(h, 90, 60))]:
    lines.add(initLine(initSpan(title, accent().bold())))
    var spans: seq[Span]
    for x in 0..<columns: spans.add(swatch(convert(float32((x * 360 div columns + hueOffset) mod 360)), 1))
    lines.add(initLine(spans))
  lines.add(initLine(""))
  lines.add(initLine([initSpan("Detected color depth: "),
    initSpan($detectColorDepth(), accent().bold()),
    initSpan(" · colors degrade to fit automatically")]))
  initText(lines)

proc render*(frame: var Frame, area: Rect) =
  let columns = horizontal([fill(3), fill(4), fill(3)]).split(area)
  frame.renderWidget(initParagraph(modifierText())
    .withBlock(panel("Modifiers + alignment").withPadding(horizontalPadding(1))), columns[0])
  let colorBlock = panel("Color").withPadding(horizontalPadding(1))
  colorHit = columns[1]
  frame.renderWidget(initParagraph(colorText(colorBlock.inner(columns[1]).width))
    .withBlock(colorBlock), columns[1])

  var rows: seq[Row]
  for (label, sample) in [("ASCII", "canopy"), ("Latin", "café"), ("Combining", "é"),
      ("CJK", "世界"), ("Emoji", "🌿"), ("ZWJ", "👩‍💻"), ("Flag", "🇯🇵"), ("Mixed", "a世🌿b")]:
    rows.add(initRow([label, sample, $displayWidth(sample)]))
  frame.renderWidget(initTable(rows, [length(9), length(6), length(4)])
    .withHeader(initRow(["Kind", "Text", "Cols"]).withStyle(accent().bold()))
    .withBlock(panel("Unicode widths")), columns[2])

proc handle*(event: input.Event): bool =
  let delta = event.wheel(colorHit)
  if delta != 0:
    hueOffset = (hueOffset + delta * 15 + 360) mod 360
    return true
  if not event.isPress: return false
  case event.key.code
  of KeyCode.Left: hueOffset = (hueOffset + 345) mod 360
  of KeyCode.Right: hueOffset = (hueOffset + 15) mod 360
  else: return false
  true

proc update*(now: MonoTime, active: bool): int = -1
