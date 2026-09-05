import std/[json, strutils, options]
import canopy/[geometry,style,text,buffer,symbols,layout]
import canopy/widgets/[canvas,chart]
import "../src/canopy/widgets/block"

proc decodeColor(v: JsonNode): Color =
  if v.isNil or v.kind == JNull: return color(ColorKind.Reset)
  if v.kind == JString: return color(parseEnum[ColorKind](v.getStr))
  if v.kind == JInt: return indexedColor(v.getInt)
  if v.kind == JArray: return rgbColor(v[0].getInt,v[1].getInt,v[2].getInt)
proc decodeStyle(v: JsonNode): Style =
  if v{"reset"}.getBool: result = resetStyle()
  for field in ["fg","bg","underlineColor"]:
    if not v{field}.isNil:
      case field
      of "fg": result.fg = some(decodeColor(v[field]))
      of "bg": result.bg = some(decodeColor(v[field]))
      else: result.underlineColor = some(decodeColor(v[field]))
  for modifier in Modifier:
    if (v{"add"}.getInt and (1 shl ord(modifier))) != 0: result.addModifiers.incl modifier
    if (v{"remove"}.getInt and (1 shl ord(modifier))) != 0: result.subModifiers.incl modifier
proc decodeLine(v: JsonNode): text.Line =
  if v.kind == JString: return initLine(v.getStr)
  for span in v{"spans"}.getElems:
    result.spans.add initSpan(span{"text"}.getStr,decodeStyle(span{"style"}))
  result.style = decodeStyle(v{"style"})
  if not v{"alignment"}.isNil: result.alignment = some(parseEnum[Alignment](v["alignment"].getStr))
proc decodeBounds(v: JsonNode): CanvasBounds =
  if not v.isNil: [v[0].getFloat,v[1].getFloat] else: [0.0,0.0]
proc decodeCoords(v: JsonNode): seq[CanvasPoint] =
  for point in v.getElems: result.add (point[0].getFloat,point[1].getFloat)
proc decodeBlock(v: JsonNode): Block =
  result = initBlock().withStyle(decodeStyle(v{"style"})).withBorderStyle(decodeStyle(v{"borderStyle"}))
  if v{"bordered"}.getBool(true): result = result.withBorders(AllBorders)
  if not v{"title"}.isNil: result = result.withTitle(decodeLine(v["title"]))
type CanvasPixels = object
  coords: seq[CanvasPoint]
  color: Color
proc draw(shape: CanvasPixels, painter: var Painter) =
  for p in shape.coords: painter.paint(int(p.x),int(p.y),shape.color)
proc paintActions(ctx: var CanvasContext, actions: JsonNode) =
  for a in actions:
    let x = a{"x"}.getFloat
    let y = a{"y"}.getFloat
    let x2 = a{"x2"}.getFloat
    let y2 = a{"y2"}.getFloat
    let color = decodeColor(a{"color"})
    case a["kind"].getStr
    of "line": ctx.draw(initCanvasLine(x,y,x2,y2,color))
    of "filledLine": ctx.draw(initFilledLine(x,y,x2,y2,a{"fillToY"}.getFloat,color))
    of "rectangle": ctx.draw(initRectangle(x,y,a{"width"}.getFloat,a{"height"}.getFloat,color))
    of "circle": ctx.draw(initCircle(x,y,a{"radius"}.getFloat,color))
    of "points": ctx.draw(initPoints(decodeCoords(a{"coords"}),color))
    of "pixels": ctx.draw(CanvasPixels(coords:decodeCoords(a{"coords"}),color:color))
    of "map": ctx.draw(initMap(parseEnum[MapResolution](a{"resolution"}.getStr("Low")),color))
    of "print": ctx.print(x,y,decodeLine(a["line"]))
    of "layer": ctx.layer()
    of "marker": ctx.setMarker(parseEnum[Marker](a{"marker"}.getStr("Braille")),a{"customSymbol"}.getStr("*"))
    else: raise newException(ValueError,"Unknown action")
proc decodeAxis(v: JsonNode): Axis =
  result = initAxis().withBounds(decodeBounds(v{"bounds"})).withStyle(decodeStyle(v{"style"}))
    .withLabelsAlignment(parseEnum[Alignment](v{"alignment"}.getStr("Left")))
  for label in v{"labels"}.getElems: result.labels.add decodeLine(label)
  if not v{"title"}.isNil: result = result.withTitle(decodeLine(v["title"]))
proc decodeConstraint(v: JsonNode): Constraint =
  let n = v{"value"}.getInt
  case v{"kind"}.getStr("ratio")
  of "length": length(n)
  of "min": minLength(n)
  of "max": maxLength(n)
  of "percentage": percentage(n)
  of "fill": fill(n)
  else: ratio(v{"numerator"}.getInt(1),v{"denominator"}.getInt(4))
proc encodeColor(c: Color): JsonNode =
  case c.kind
  of ColorKind.Indexed: %*{"indexed":int(c.index)}
  of ColorKind.Rgb: %*{"rgb":[int(c.r),int(c.g),int(c.b)]}
  else: %($c.kind)
proc encodeCell(c: Cell): JsonNode =
  var modifiers = 0
  for m in c.modifiers: modifiers = modifiers or (1 shl ord(m))
  %*{"symbol":c.symbol,"fg":encodeColor(c.fg),"bg":encodeColor(c.bg),"underlineColor":encodeColor(c.underlineColor),
      "modifiers":modifiers,"skip":c.skip,"diffOption":(if c.diffKind == CellDiffKind.Normal: "None" else: $c.diffKind)}
proc checkFixtures*(source: string): int =
  let document = parseJson(source)
  for item in document["cases"]:
    let v = item["input"]
    let a = v["area"]
    let area = initRect(a["x"].getInt,a["y"].getInt,a["width"].getInt,a["height"].getInt)
    var initial = initCell(v{"initialSymbol"}.getStr(" "))
    initial.setStyle(decodeStyle(v{"initialStyle"}))
    var buf = initBuffer(area,initial)
    if v["kind"].getStr == "canvas":
      let actions = v["actions"]
      var c = initCanvas().withMarker(parseEnum[Marker](v{"marker"}.getStr("Braille")),v{"customSymbol"}.getStr("*"))
        .withXBounds(decodeBounds(v{"xBounds"})).withYBounds(decodeBounds(v{"yBounds"}))
        .withBackgroundColor(decodeColor(v{"backgroundColor"}))
        .withPaint(proc(ctx: var CanvasContext) = ctx.paintActions(actions))
      if not v{"block"}.isNil: c = c.withBlock(decodeBlock(v["block"]))
      c.render(area,buf)
    else:
      var datasets: seq[Dataset]
      for d in v["datasets"]:
        var dataset = initDataset(decodeCoords(d{"data"})).withMarker(parseEnum[Marker](d{"marker"}.getStr("Dot")),d{"customSymbol"}.getStr("*"))
          .withStyle(decodeStyle(d{"style"})).withGraphType(parseEnum[GraphType](d{"graphType"}.getStr("Scatter"))).withFillToY(d{"fillToY"}.getFloat)
        if not d{"name"}.isNil: dataset = dataset.withName(decodeLine(d["name"]))
        datasets.add dataset
      var c = initChart(datasets).withXAxis(decodeAxis(v{"xAxis"})).withYAxis(decodeAxis(v{"yAxis"})).withStyle(decodeStyle(v{"style"}))
      if not v{"block"}.isNil: c = c.withBlock(decodeBlock(v["block"]))
      if not v{"hiddenLegendConstraints"}.isNil:
        c = c.withHiddenLegendConstraints((decodeConstraint(v["hiddenLegendConstraints"][0]),decodeConstraint(v["hiddenLegendConstraints"][1])))
      if not v{"legendPosition"}.isNil:
        c.legendPosition = if v["legendPosition"].kind == JNull: none(LegendPosition) else: some(parseEnum[LegendPosition](v["legendPosition"].getStr))
      c.render(area,buf)
    let expectedArea = item["expected"]["area"]
    var failed = %*{"x":buf.area.x,"y":buf.area.y,"width":buf.area.width,"height":buf.area.height} != expectedArea or
      buf.content.len != item["expected"]["cells"].len
    if failed and result < 20: echo item["name"]," buffer area or cell count differs"
    for i,cell in buf.content:
      let expected = item["expected"]["cells"][i]
      let actual = encodeCell(cell)
      if actual != expected:
        if not failed and result < 20: echo item["name"]," cell=",i," expected=",expected," actual=",actual
        failed = true
    if failed: inc result
  echo document["cases"].len," cases; ",result," mismatches"
