## Block widget border, title, and padding tests.
import std/[unittest, json, os, strutils]

import canopy/core/layout/geometry
import canopy/core/styling/style
import canopy/core/text/index as text
import canopy/core/rendering/buffer
import canopy/core/rendering/symbols
import canopy/ui/widgets/[shadow]
import "canopy/ui/widgets/block"

let matrix = parseFile(currentSourcePath.parentDir / "fixtures/block_matrix.json")

func referenceColor(n: JsonNode): Color =
  if n[0].getStr == "Rgb": rgbColor(n[1].getInt, n[2].getInt, n[3].getInt)
  else: color(parseEnum[ColorKind](n[0].getStr))

proc exact(buf: Buffer, c: JsonNode) =
  for i, cell in buf.content:
    let e = c["cells"][i]
    var mods: Modifiers
    for m in Modifier:
      if (e[4].getInt and (1 shl ord(m))) != 0: mods.incl m
    if cell.symbol != e[0].getStr or cell.fg != referenceColor(e[1]) or
        cell.bg != referenceColor(e[2]) or cell.underlineColor != referenceColor(e[3]) or
        cell.modifiers != mods:
      var label = c["type"].getStr
      for key in ["i", "k", "mask", "merge", "size"]:
        if c.hasKey(key): label.add " " & key & "=" & $c[key]
      checkpoint label & " cell=" & $buf.posOf(i)
      check cell.symbol == e[0].getStr
      check cell.fg == referenceColor(e[1])
      check cell.bg == referenceColor(e[2])
      check cell.underlineColor == referenceColor(e[3])
      check cell.modifiers == mods
      return

func borders(mask: int): Borders =
  for b in Border:
    if (mask and (1 shl ord(b))) != 0: result.incl b

suite "Ratatui block and shadow exact matrix":
  test "border types, masks, merging, blank provenance and tiny areas":
    for c in matrix["cases"]:
      if c["type"].getStr != "border": continue
      let size = c["size"].getInt
      let (w, h) = [(0, 0), (1, 1), (1, 3), (3, 1), (2, 2), (5, 4)][size]
      var buf = initBuffer(initRect(0, 0, 7, 6))
      for i, cell in buf.content.mpairs:
        case c["fill"].getInt
        of 0: discard
        of 1: cell.setSymbol(" ")
        of 2: cell.setSymbol("x")
        of 3: cell.setSymbol("╋")
        else: cell.setSymbol(["─", "║", "╭", "┇"][i mod 4])
      let widget = initBlock().withBorders(borders(c["mask"].getInt)).withBorderType(BorderType(c["k"].getInt)).
        withMergeBorders(MergeStrategy(c["merge"].getInt)).withStyle(initStyle().withFg(
            ColorKind.Red)).withBorderStyle(initStyle().withBg(ColorKind.Blue))
      widget.render(initRect(1, 1, w, h), buf)
      exact(buf, c)
  test "ordered titles, alignments, grapheme truncation, top and bottom":
    for c in matrix["cases"]:
      if c["type"].getStr != "title": continue
      let i = c["i"].getInt
      let w = i mod 12; let h = (i div 12) mod 3; let mask = (i div 3) mod 16
      let a = (i div 7) mod 3; let p = (i div 11) mod 2; let content = (i div 13) mod 4
      let area = initRect(1, 1, w, h)
      var buf = initBuffer(initRect(0, 0, 14, 5))
      for cell in buf.content.mitems: cell.setSymbol(".")
      let values = [["a", "b", "c"], ["one long", "界e\u0301", "tail"], ["界界界",
          "👩‍🔬x", "a"], ["", "x", ""]][content]
      var widget = initBlock().withBorders(borders(mask)).withTitleAlignment(Alignment(
          a)).withTitlePosition(TitlePosition(p)).
        withStyle(initStyle().withFg(ColorKind.Red)).withTitleStyle(initStyle().withBg(
            ColorKind.Blue))
      for j, v in values:
        var line = initLine([initSpan(v, initStyle().withFg(ColorKind.Yellow))])
        if i mod 2 == 0: line = line.withAlignment(Alignment(j))
        if j == 1 and i mod 3 == 0: widget = widget.withTitleBottom(line)
        elif j == 2 and i mod 5 == 0: widget = widget.withTitleTop(line)
        else: widget = widget.withTitle(line)
      let inner = widget.inner(area)
      check @[inner.x, inner.y, inner.width, inner.height] == @[c["inner"][0].getInt, c["inner"][
          1].getInt, c["inner"][2].getInt, c["inner"][3].getInt]
      widget.render(area, buf)
      exact(buf, c)
  test "all shadow effects, offsets, clipping and RGB dimming":
    for c in matrix["cases"]:
      if c["type"].getStr != "shadow": continue
      let i = c["i"].getInt; let effect = i mod 7
      let (dx, dy) = [(1, 1), (-1, -1), (2, 0), (0, -2), (0, 0), (20, 20), (-20, -20)][(i div 7) mod 7]
      var buf = initBuffer(initRect(0, 0, 8, 7))
      for cell in buf.content.mitems:
        cell.setSymbol(".")
        cell.bg = if i mod 2 == 0: rgbColor(101, 202, 255) else: color(ColorKind.Green)
      let area = if i mod 11 == 0: initRect(6, 5, 4, 4) else: initRect(1, 1, 4, 3)
      var shadow = case effect
        of 0: overlayShadow()
        of 1: blockShadow()
        of 2: lightShadeShadow()
        of 3: mediumShadeShadow()
        of 4: darkShadeShadow()
        of 5: symbolShadow("界")
        else: customShadow(dimmed())
      shadow = shadow.withOffset(dx, dy)
      if i mod 3 == 0: shadow = shadow.withStyle(initStyle().withFg(ColorKind.Yellow).withBg(
          rgbColor(201, 101, 51)).italic())
      if i mod 5 == 0: shadow.render(area, buf)
      else: borderedBlock().withShadow(shadow).render(area, buf)
      exact(buf, c)
  test "every Padding constructor and saturating proportional values":
    check zeroPadding() == initPadding(0, 0, 0, 0)
    check uniformPadding(2) == initPadding(2, 2, 2, 2)
    check horizontalPadding(2) == initPadding(2, 2, 0, 0)
    check verticalPadding(2) == initPadding(0, 0, 2, 2)
    check symmetricPadding(2, 3) == initPadding(2, 2, 3, 3)
    check proportionalPadding(40000) == initPadding(65535, 65535, 40000, 40000)
    check leftPadding(2) == initPadding(2, 0, 0, 0)
    check rightPadding(2) == initPadding(0, 2, 0, 0)
    check topPadding(2) == initPadding(0, 0, 2, 0)
    check bottomPadding(2) == initPadding(0, 0, 0, 2)
