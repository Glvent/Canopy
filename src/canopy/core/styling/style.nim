## Composable terminal styles. Missing colors inherit; Reset explicitly clears.
import std/[options, json, strutils]

export options

type
  ColorKind* {.pure.} = enum
    Reset, Black, Red, Green, Yellow, Blue, Magenta, Cyan, Gray, DarkGray,
    LightRed, LightGreen, LightYellow, LightBlue, LightMagenta, LightCyan,
    White, Indexed, Rgb
  Color* = object
    ## `index` is read only for Indexed and `r`/`g`/`b` only for Rgb; other kinds ignore both.
    kind*: ColorKind
    index*, r*, g*, b*: uint8
  Modifier* {.pure.} = enum
    Bold, Dim, Italic, Underlined, SlowBlink, RapidBlink, Reversed, Hidden, CrossedOut
  Modifiers* = set[Modifier]
  Style* = object
    ## Patch, not a full state: `none` inherits, `some(Reset)` clears, and the two modifier
    ## sets stay disjoint so composition never both sets and unsets an attribute.
    fg*, bg*, underlineColor*: Option[Color]
    addModifiers*, subModifiers*: Modifiers

func color*(kind: ColorKind): Color = Color(kind: kind)
func indexedColor*(index: int): Color = Color(kind: ColorKind.Indexed, index: uint8(clamp(index, 0, 255)))
func rgbColor*(r, g, b: int): Color = Color(kind: ColorKind.Rgb, r: uint8(clamp(r, 0, 255)),
    g: uint8(clamp(g, 0, 255)), b: uint8(clamp(b, 0, 255)))
func initStyle*(): Style = Style()
func resetStyle*(): Style =
  ## Style that overrides every inherited attribute back to the terminal default.
  Style(fg: some(color(ColorKind.Reset)), bg: some(color(
    ColorKind.Reset)), underlineColor: some(color(ColorKind.Reset)), subModifiers: {low(
    Modifier)..high(Modifier)})

func patch*(base, overlay: Style): Style =
  ## Overlay wins on explicit fields; modifier add/remove sets compose without clobbering.
  result = base
  if overlay.fg.isSome: result.fg = overlay.fg
  if overlay.bg.isSome: result.bg = overlay.bg
  if overlay.underlineColor.isSome: result.underlineColor = overlay.underlineColor
  result.addModifiers = (base.addModifiers - overlay.subModifiers) + overlay.addModifiers
  result.subModifiers = (base.subModifiers - overlay.addModifiers) + overlay.subModifiers

func withFg*(s: Style, c: Color): Style =
  result = s
  result.fg = some(c)

func withFg*(s: Style, c: ColorKind): Style = s.withFg(color(c))
func withBg*(s: Style, c: Color): Style =
  result = s
  result.bg = some(c)

func withBg*(s: Style, c: ColorKind): Style = s.withBg(color(c))
func withUnderlineColor*(s: Style, c: Color): Style =
  result = s
  result.underlineColor = some(c)

func withAddModifier*(s: Style, m: Modifiers): Style =
  result = s
  result.addModifiers = s.addModifiers + m
  result.subModifiers = s.subModifiers - m

func withAddModifier*(s: Style, m: Modifier): Style = s.withAddModifier({m})
func withRemoveModifier*(s: Style, m: Modifiers): Style =
  result = s
  result.subModifiers = s.subModifiers + m
  result.addModifiers = s.addModifiers - m

func withRemoveModifier*(s: Style, m: Modifier): Style = s.withRemoveModifier({m})
func bold*(s: Style): Style = s.withAddModifier(Modifier.Bold)
func dim*(s: Style): Style = s.withAddModifier(Modifier.Dim)
func italic*(s: Style): Style = s.withAddModifier(Modifier.Italic)
func underlined*(s: Style): Style = s.withAddModifier(Modifier.Underlined)
func reversed*(s: Style): Style = s.withAddModifier(Modifier.Reversed)
func crossedOut*(s: Style): Style = s.withAddModifier(Modifier.CrossedOut)
func hidden*(s: Style): Style = s.withAddModifier(Modifier.Hidden)
func slowBlink*(s: Style): Style = s.withAddModifier(Modifier.SlowBlink)
func rapidBlink*(s: Style): Style = s.withAddModifier(Modifier.RapidBlink)
func hasModifier*(s: Style, modifier: Modifier): bool = modifier in s.addModifiers
func `$`*(c: Color): string =
  case c.kind
  of ColorKind.Rgb: "#" & toHex(c.r, 2) & toHex(c.g, 2) & toHex(c.b, 2)
  of ColorKind.Indexed: $c.index
  else: $c.kind

func parseColor*(value: string): Color =
  ## Accepts a color name, a 0..255 index, or `#rrggbb`; raises ValueError otherwise.
  ## Name matching ignores case, separators, and the bright/grey/silver spellings.
  let normalized = value.toLowerAscii.replace(" ", "").replace("-", "").replace("_", "").replace(
      "bright", "light").replace("grey", "gray").replace("silver", "gray").replace("lightblack",
      "darkgray").replace("lightwhite", "white").replace("lightgray", "white")
  # Indexed and Rgb are excluded: they are the two kinds that need components.
  for kind in ColorKind.Reset..ColorKind.White:
    if ($kind).toLowerAscii == normalized: return color(kind)
  if value.len > 0:
    var digits = value
    if digits[0] == '+': digits = digits[1..^1]
    if digits.len > 0 and digits.allCharsInSet({'0'..'9'}):
      try:
        let index = parseInt(digits)
        if index in 0..255: return indexedColor(index)
      except ValueError: discard
  if value.len == 7 and value[0] == '#' and value[1..^1].allCharsInSet(HexDigits):
    return rgbColor(parseHexInt(value[1..2]), parseHexInt(value[3..4]), parseHexInt(value[5..6]))
  raise newException(ValueError, "Invalid color: " & value)

proc toJson*(c: Color): JsonNode =
  case c.kind
  of ColorKind.Indexed: result = %*{"indexed": int(c.index)}
  of ColorKind.Rgb: result = %*{"rgb": [int(c.r), int(c.g), int(c.b)]}
  else: result = %($c.kind)

proc colorFromJson*(node: JsonNode): Color =
  ## Parses `"Red"`, `{"indexed": n}`, or `{"rgb": [r, g, b]}`; raises ValueError on anything else.
  ## This is Canopy's own JSON shape, not a Rust serde encoding.
  if node.kind == JString:
    try:
      let kind = parseEnum[ColorKind](node.getStr)
      if kind in {ColorKind.Indexed, ColorKind.Rgb}: raise newException(ValueError, "Color requires components")
      return color(kind)
    except ValueError: raise newException(ValueError, "Invalid named color: " & node.getStr)
  if node.kind == JObject and node.len == 1:
    if node.hasKey("indexed") and node["indexed"].kind == JInt and node["indexed"].getInt in 0..255:
      return indexedColor(node["indexed"].getInt)
    if node.hasKey("rgb") and node["rgb"].kind == JArray and node["rgb"].len == 3:
      let rgb = node["rgb"]
      for component in rgb:
        if component.kind != JInt or component.getInt notin 0..255: raise newException(ValueError, "Invalid RGB component")
      return rgbColor(rgb[0].getInt, rgb[1].getInt, rgb[2].getInt)
  raise newException(ValueError, "Invalid color JSON")

proc toJson*(s: Style): JsonNode =
  ## Omits inherited (`none`) colors; the modifier arrays are always present, possibly empty.
  result = newJObject()
  if s.fg.isSome: result["fg"] = s.fg.get.toJson
  if s.bg.isSome: result["bg"] = s.bg.get.toJson
  if s.underlineColor.isSome: result["underlineColor"] = s.underlineColor.get.toJson
  result["addModifiers"] = newJArray()
  result["subModifiers"] = newJArray()
  for m in s.addModifiers: result["addModifiers"].add(%($m))
  for m in s.subModifiers: result["subModifiers"].add(%($m))

proc styleFromJson*(node: JsonNode): Style =
  ## Inverse of `toJson`; unknown keys, bad modifier names, and a modifier appearing in both
  ## add and sub sets all raise ValueError.
  if node.kind != JObject: raise newException(ValueError, "Style must be an object")
  for key, value in node:
    case key
    of "fg": result.fg = some(colorFromJson(value))
    of "bg": result.bg = some(colorFromJson(value))
    of "underlineColor": result.underlineColor = some(colorFromJson(value))
    of "addModifiers", "subModifiers":
      if value.kind != JArray: raise newException(ValueError, "Modifiers must be an array")
      var modifiers: Modifiers
      for item in value:
        if item.kind != JString: raise newException(ValueError, "Modifier must be a string")
        modifiers.incl(parseEnum[Modifier](item.getStr))
      if key == "addModifiers": result.addModifiers = modifiers
      else: result.subModifiers = modifiers
    else: raise newException(ValueError, "Unknown style key: " & key)
  if (result.addModifiers * result.subModifiers) != {}: raise newException(ValueError, "Conflicting modifiers")
