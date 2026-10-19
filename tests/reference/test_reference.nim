## Cross-language reference parity tests.
import std/[json, options, os, sequtils, strutils, unittest]

import canopy/core/layout/geometry
import canopy/core/styling/style
import canopy/core/text/index as text
import canopy/core/rendering/buffer
import canopy/core/text/unicode
import canopy/core/layout/index as layout
import "canopy/ui/widgets/block"
import canopy/ui/widgets/[paragraph, list, table]
import ../support/paths


proc optionalInt(n: JsonNode): Option[int] =
  if n.kind == JNull: none(int) else: some(n.getInt)

proc fixture(name: string): JsonNode = parseFile(FixturesDir / name)
proc rectOf(n: JsonNode): Rect = initRect(n["x"].getInt, n["y"].getInt, n["width"].getInt, n["height"].getInt)

proc colorOf(n: JsonNode): Color =
  case n["kind"].getStr
  of "indexed": indexedColor(n["index"].getInt)
  of "rgb": rgbColor(n["r"].getInt, n["g"].getInt, n["b"].getInt)
  of "named":
    case n["name"].getStr
    of "reset": color(ColorKind.Reset)
    of "black": color(ColorKind.Black)
    of "red": color(ColorKind.Red)
    of "green": color(ColorKind.Green)
    of "yellow": color(ColorKind.Yellow)
    of "blue": color(ColorKind.Blue)
    of "magenta": color(ColorKind.Magenta)
    of "cyan": color(ColorKind.Cyan)
    of "gray": color(ColorKind.Gray)
    of "darkGray": color(ColorKind.DarkGray)
    of "lightRed": color(ColorKind.LightRed)
    of "lightGreen": color(ColorKind.LightGreen)
    of "lightYellow": color(ColorKind.LightYellow)
    of "lightBlue": color(ColorKind.LightBlue)
    of "lightMagenta": color(ColorKind.LightMagenta)
    of "lightCyan": color(ColorKind.LightCyan)
    of "white": color(ColorKind.White)
    else: raise newException(ValueError, "unknown named color")
  else: raise newException(ValueError, "unknown color tag")

proc modifierOf(name: string): Modifier =
  case name
  of "bold": Modifier.Bold
  of "dim": Modifier.Dim
  of "italic": Modifier.Italic
  of "underlined": Modifier.Underlined
  of "slowBlink": Modifier.SlowBlink
  of "rapidBlink": Modifier.RapidBlink
  of "reversed": Modifier.Reversed
  of "hidden": Modifier.Hidden
  of "crossedOut": Modifier.CrossedOut
  else: raise newException(ValueError, "unknown modifier")

proc modifiersOf(n: JsonNode): Modifiers =
  for item in n: result.incl modifierOf(item.getStr)

proc styleOf(n: JsonNode): Style =
  if n["fg"].kind != JNull: result.fg = some(colorOf(n["fg"]))
  if n["bg"].kind != JNull: result.bg = some(colorOf(n["bg"]))
  if n["underlineColor"].kind != JNull: result.underlineColor = some(colorOf(n["underlineColor"]))
  result.addModifiers = modifiersOf(n["addModifiers"])
  result.subModifiers = modifiersOf(n["subModifiers"])

proc cellOf(n: JsonNode): Cell =
  result = initCell(n["symbol"].getStr)
  result.fg = colorOf(n["fg"]); result.bg = colorOf(n["bg"]); result.underlineColor = colorOf(n["underlineColor"])
  result.modifiers = modifiersOf(n["modifiers"]); result.skip = n["skip"].getBool
  case n["diffOption"]["kind"].getStr
  of "none": result.diffKind = CellDiffKind.Normal
  of "skip": result.diffKind = CellDiffKind.Skip
  of "alwaysUpdate": result.diffKind = CellDiffKind.AlwaysUpdate
  of "forcedWidth": result.diffKind = CellDiffKind.ForcedWidth; result.forcedWidth = n["diffOption"]["width"].getInt
  else: raise newException(ValueError, "unknown diff option")

proc checkBuffer(actual: Buffer, expected: JsonNode) =
  check actual.area == rectOf(expected["area"])
  check actual.content.len == expected["cells"].len
  for i, c in actual.content: check c == cellOf(expected["cells"][i])
  check expected["cursor"].kind == JNull

proc constraintOf(n: JsonNode): Constraint =
  case n["kind"].getStr
  of "length": length(n["value"].getInt)
  of "min": minLength(n["value"].getInt)
  of "max": maxLength(n["value"].getInt)
  of "percentage": percentage(n["value"].getInt)
  of "ratio": ratio(n["numerator"].getInt, n["denominator"].getInt)
  of "fill": fill(n["value"].getInt)
  else: raise newException(ValueError, "unknown constraint")

proc flexOf(s: string): Flex =
  case s.toLowerAscii
  of "legacy": Flex.Legacy
  of "start": Flex.Start
  of "end": Flex.End
  of "center": Flex.Center
  of "spacebetween": Flex.SpaceBetween
  of "spacearound": Flex.SpaceAround
  of "spaceevenly": Flex.SpaceEvenly
  else: raise newException(ValueError, "unknown flex")

suite "Ratatui 0.30.2 reference adapters":
  test "all fixtures carry pins and complete rendered cells":
    for name in ["geometry.json", "style.json", "text.json", "unicode.json", "buffer.json", "layout.json", "widgets.json"]:
      let root = fixture(name)
      check root["schemaVersion"].getInt == 1
      check root["dependencies"]["ratatui"].getStr == "0.30.2"
      check root["dependencies"]["unicodeVersion"].getStr == "17.0.0"
      for c in root["cases"]:
        check c.hasKey("name") and c.hasKey("kind") and c.hasKey("input") and c.hasKey("expected")
        proc inspectRendered(n: JsonNode) =
          if n.kind == JObject and n.hasKey("area") and n.hasKey("cells"):
            check n["cells"].len == n["area"]["width"].getInt*n["area"]["height"].getInt
            for x in n["cells"]:
              for key in ["symbol", "fg", "bg", "underlineColor", "modifiers", "skip", "diffOption"]: check x.hasKey(key)
          elif n.kind == JObject:
            for _, value in n: inspectRendered(value)
        inspectRendered(c["expected"])

  test "geometry operations are exact":
    let c = fixture("geometry.json")["cases"][0]; let i = c["input"]; let e = c["expected"]
    let a = rectOf(i["a"]); let b = rectOf(i["b"]); let m = initMargin(i["margin"]["horizontal"].getInt, i["margin"]["vertical"].getInt)
    check a.right == e["right"].getInt; check a.bottom == e["bottom"].getInt; check a.area == e["area"].getInt
    check a.isEmpty == e["isEmpty"].getBool; check a.contains(4, 5) == e["containsInside"].getBool; check a.contains(11, 9) == e["containsEdge"].getBool
    check a.intersection(b) == rectOf(e["intersection"]); check a.union(b) == rectOf(e["union"]); check a.inner(m) == rectOf(e["inner"])

  test "styles patch and reset exactly":
    let cases = fixture("style.json")["cases"]
    check initStyle() == styleOf(cases[0]["expected"])
    check resetStyle() == styleOf(cases[1]["expected"])
    check styleOf(cases[2]["input"]["base"]).patch(styleOf(cases[2]["input"]["overlay"])) == styleOf(cases[2]["expected"])

  test "Unicode segmentation and width are exact":
    for c in fixture("unicode.json")["cases"]:
      let s = c["input"]["text"].getStr
      var expected: seq[string]; for g in c["expected"]["graphemes"]: expected.add g.getStr
      check graphemes(s) == expected; check displayWidth(s) == c["expected"]["width"].getInt

  test "text metrics and rendering are exact":
    let cases = fixture("text.json")["cases"]
    let plain = initText("alpha\n界é\n"); var b = initBuffer(rectOf(cases[0]["expected"]["rendered"]["area"])); plain.render(b.area, b)
    check plain.width == cases[0]["expected"]["width"].getInt; check plain.height == cases[0]["expected"]["height"].getInt; checkBuffer(b, cases[0]["expected"]["rendered"])
    let styled = initText([initLine([initSpan("red", initStyle().withFg(ColorKind.Red)), initSpan("界", initStyle().withBg(ColorKind.Blue).bold())]).withAlignment(Alignment.Center),
      initLine("tail").withStyle(initStyle().withFg(indexedColor(99))).withAlignment(Alignment.Right)]).withStyle(initStyle().withFg(ColorKind.Green))
    var sb = initBuffer(rectOf(cases[1]["expected"]["rendered"]["area"])); styled.render(sb.area, sb)
    check styled.width == cases[1]["expected"]["width"].getInt; check styled.height == cases[1]["expected"]["height"].getInt; checkBuffer(sb, cases[1]["expected"]["rendered"])

  test "buffers, clipping, wide overwrite, and diff are exact":
    let cases = fixture("buffer.json")["cases"]
    var b = initBuffer(initRect(2, 3, 8, 2)); discard b.setString(2, 3, "clipped-right", initStyle().withFg(ColorKind.Red)); discard b.setString(2, 3, "A界B", initStyle().withBg(ColorKind.Blue).bold())
    discard b.setStringn(3, 4, "éxy", 3, initStyle().withFg(rgbColor(4, 5, 6))); checkBuffer(b, cases[0]["expected"])
    var wide = initBuffer(initRect(0, 0, 5, 1)); discard wide.setString(0, 0, "界x", initStyle().withFg(ColorKind.Green)); discard wide.setString(0, 0, "a", initStyle().withFg(ColorKind.Yellow)); checkBuffer(wide, cases[1]["expected"])
    var prev = initBuffer(["界ab"]); var next = prev; discard next.setString(0, 0, "xy", initStyle().underlined()); let updates = diff(prev, next); let expected = cases[2]["expected"]["updates"]
    check updates.len == expected.len
    for i, u in updates: check u.x == expected[i]["x"].getInt; check u.y == expected[i]["y"].getInt; check u.cell == cellOf(expected[i]["cell"])

  test "layout segments and spacers are exact":
    for c in fixture("layout.json")["cases"]:
      let i = c["input"]; var cs: seq[Constraint]; for n in i["constraints"]: cs.add constraintOf(n)
      var l = initLayout(if i["direction"].getStr == "horizontal": Direction.Horizontal else: Direction.Vertical, cs)
      l = l.withMargin(initMargin(i["margin"]["horizontal"].getInt, i["margin"]["vertical"].getInt)).withSpacing(i["spacing"].getInt).withFlex(flexOf(i["flex"].getStr))
      let actual = l.splitWithSpacers(rectOf(i["area"])); let e = c["expected"]
      check actual.segments.len == e["segments"].len; check actual.spacers.len == e["spacers"].len
      for j, r in actual.segments: check r == rectOf(e["segments"][j])
      for j, r in actual.spacers: check r == rectOf(e["spacers"][j])

  test "Paragraph rendering is exact":
    let c = fixture("widgets.json")["cases"].filterIt(it["name"].getStr == "paragraph-wrap-scroll-alignment")[0]
    let content = initText([initLine([initSpan("wide 界 ", initStyle().withFg(ColorKind.Cyan)), initSpan("words wrap here")]), initLine("second")])
    let widget = initParagraph(content).withBlock(borderedBlock().withTitle("P")).withWrap(true).withScroll(0, 1).centered.withStyle(initStyle().withBg(indexedColor(17)))
    var b = initBuffer(rectOf(c["expected"]["area"])); widget.render(b.area, b); checkBuffer(b, c["expected"])

  test "List rendering and resulting state are exact":
    let c = fixture("widgets.json")["cases"].filterIt(it["name"].getStr == "list-state-selection-multiline")[0]
    let items = [initListItem("zero"), initListItem(initLine("one 界").withStyle(initStyle().withFg(ColorKind.Green))), initListItem("two\ncontinued"), initListItem("three")]
    let widget = initList(items).withBlock(borderedBlock()).withHighlightSymbol(">>").withRepeatHighlightSymbol(true).withHighlightStyle(initStyle().withBg(ColorKind.Blue).bold()).withScrollPadding(1)
    var state = initListState().withSelected(2).withOffset(1); var b = initBuffer(rectOf(c["expected"]["area"])); widget.render(b.area, b, state)
    checkBuffer(b, c["expected"]); check state.offset == c["expected"]["state"]["offset"].getInt; check state.selected == some(c["expected"]["state"]["selected"].getInt)

  test "Table rendering and resulting row/column state are exact":
    let c = fixture("widgets.json")["cases"].filterIt(it["name"].getStr == "table-header-footer-state")[0]
    let rows = [initRow(["r0c0", "r0c1", "r0c2"]), initRow(["wide界", "styled", "tail"]).withStyle(initStyle().withFg(ColorKind.Cyan)), initRow(["r2", "long value", "x"]), initRow(["r3", "b", "c"])]
    let widget = initTable(rows, [length(7), fill(1), length(4)]).withHeader(initRow(["A", "B", "C"]).withStyle(initStyle().bold())).withFooter(initRow(["F1", "F2", "F3"]))
      .withBlock(borderedBlock()).withColumnSpacing(1).withRowHighlightStyle(initStyle().withBg(ColorKind.Blue)).withColumnHighlightStyle(initStyle().withFg(ColorKind.Yellow))
      .withCellHighlightStyle(initStyle().reversed()).withHighlightSymbol("> ")
    var state = initTableState().withSelected(2).withSelectedColumn(1).withOffset(1); var b = initBuffer(rectOf(c["expected"]["area"])); widget.render(b.area, b, state)
    checkBuffer(b, c["expected"]); check state.offset == c["expected"]["state"]["offset"].getInt; check state.selected == some(c["expected"]["state"]["selected"].getInt)
    check state.selectedColumn == some(c["expected"]["state"]["selectedColumn"].getInt)

suite "Pinned text widget configuration matrix":
  test "1428 exact buffers and resulting selections":
    let matrix = fixture("widget_text_matrix.json")
    var failures = 0
    var count = 0
    for c in matrix["cases"]:
      let w = c["width"].getInt
      let h = c["height"].getInt
      let area = initRect(2, 1, w, h)
      var b = initBuffer(initRect(0, 0, w+4, h+2), initCell("."))
      var resultingState: seq[Option[int]]
      case c["kind"].getStr
      of "paragraph":
        let raw = c["text"].getStr
        let content = if c["styled"].getBool:
          initText([initLine([initSpan(raw, initStyle().withFg(ColorKind.Yellow).italic())])])
          else: initText(raw)
        var widget = initParagraph(content).withStyle(initStyle().withFg(ColorKind.Red).withBg(ColorKind.Blue)).
          withAlignment(Alignment(c["align"].getInt)).withScroll(c["scroll"][0].getInt, c["scroll"][1].getInt)
        if c["wrap"].getInt > 0: widget = widget.withWrap(c["wrap"].getInt == 2)
        widget.render(area, b)
      of "list":
        var items: seq[ListItem]
        if not c["empty"].getBool:
          for i, value in ["zero", "中 é\nsecond", "two", "three\nline2\nline3", "four", "five"]:
            items.add initListItem(value).withStyle(if i mod 2 == 0: initStyle().withFg(ColorKind.Green) else: initStyle())
        var widget = initList(items).withStyle(initStyle().withFg(ColorKind.Red).withBg(ColorKind.Blue)).
          withHighlightStyle(initStyle().withFg(ColorKind.Yellow).reversed()).
          withHighlightSymbol(initLine(">").withStyle(initStyle().withFg(ColorKind.Cyan))).
          withRepeatHighlightSymbol(c["repeat"].getBool).withHighlightSpacing(HighlightSpacing(c["spacing"].getInt)).
          withScrollPadding(c["padding"].getInt).withDirection(ListDirection(c["direction"].getInt))
        if c["block"].getBool: widget = widget.withBlock(borderedBlock())
        var state = initListState().withSelected(optionalInt(c["selected"])).withOffset(c["offset"].getInt)
        widget.render(area, b, state)
        resultingState = @[some(state.offset), state.selected]
      of "table":
        let margins = c["margins"].getBool
        var rows: seq[Row]
        if not c["empty"].getBool:
          rows = @[
            initRow([initTableCell("zero").withColumnSpan(if c["spans"].getBool: 2 else: 1), initTableCell("中a"), initTableCell("x")]).withStyle(initStyle().withFg(ColorKind.Green)),
            initRow(["one\nline2", "éb\nsecond", "y"]).withHeight(2).withTopMargin(ord(margins)),
            initRow(["two", "👩‍🔬", "z"]).withBottomMargin(ord(margins)),
            initRow(["three\nline2\nline3", "last", "!"]).withHeight(3)]
        let widths = if c["explicit"].getBool: @[length(3), minLength(2), fill(1)] else: @[]
        var widget = initTable(rows, widths).withColumnSpacing(c["columnSpacing"].getInt).
          withHighlightSpacing(HighlightSpacing(c["spacing"].getInt)).
          withStyle(initStyle().withFg(ColorKind.Red).withBg(ColorKind.Blue)).withHighlightSymbol(">\nv").
          withRowHighlightStyle(initStyle().withFg(ColorKind.Yellow)).withColumnHighlightStyle(initStyle().withBg(ColorKind.Green)).
          withCellHighlightStyle(initStyle().reversed()).withFlex(Flex(c["flex"].getInt))
        if c["header"].getBool:
          widget = widget.withHeader(initRow(["H0", "H1", "H2"]).withStyle(initStyle().withFg(ColorKind.Cyan)).withBottomMargin(ord(margins)))
        if c["footer"].getBool:
          widget = widget.withFooter(initRow(["F0", "F1", "F2"]).withStyle(initStyle().withFg(ColorKind.Magenta)).withTopMargin(ord(margins)))
        var state = initTableState().withSelected(optionalInt(c["selected"])).withSelectedColumn(optionalInt(c["column"])).withOffset(c["offset"].getInt)
        widget.render(area, b, state)
        resultingState = @[some(state.offset), state.selected, state.selectedColumn]
      else: raise newException(ValueError, "unknown text widget fixture")
      var mismatch = ""
      for i, cell in b.content:
        let expected = c["cells"][i]
        var modifiers: Modifiers
        let bits = expected[4].getInt
        for m in Modifier:
          if (bits and (1 shl ord(m))) != 0: modifiers.incl m
        if cell.symbol != expected[0].getStr or cell.fg != color(parseEnum[ColorKind](expected[1].getStr)) or
            cell.bg != color(parseEnum[ColorKind](expected[2].getStr)) or
            cell.underlineColor != color(parseEnum[ColorKind](expected[3].getStr)) or cell.modifiers != modifiers:
          mismatch = "cell " & $i & " actual " & $cell & " expected " & $expected
          break
      if c.hasKey("state"):
        for i, value in resultingState:
          if value != optionalInt(c["state"][i]): mismatch.add " state " & $resultingState & " expected " & $c["state"]
      if mismatch.len > 0:
        if failures < 12:
          var input = c.copy
          input.delete("cells")
          echo "Matrix case ", count, " ", input, " ", mismatch
        inc failures
      inc count
    check count == 1428
    check failures == 0
