## Terminal color depth and nearest-color downsampling for terminals without truecolor.
## A Canopy extension; Ratatui has no equivalent.
import ./style
export style

type ColorDepth* {.pure.} = enum
  ## Colors an output terminal can show. `Monochrome` keeps text modifiers but no colors.
  Monochrome, Ansi16, Ansi256, TrueColor

const
  # xterm's default 16-color palette in ColorKind order. Terminal themes vary; this is the usual
  # reference for picking the nearest named color.
  Ansi16Rgb: array[16, array[3, uint8]] = [
    [0'u8, 0, 0], [205'u8, 0, 0], [0'u8, 205, 0], [205'u8, 205, 0],
    [0'u8, 0, 238], [205'u8, 0, 205], [0'u8, 205, 205], [229'u8, 229, 229],
    [127'u8, 127, 127], [255'u8, 0, 0], [0'u8, 255, 0], [255'u8, 255, 0],
    [92'u8, 92, 255], [255'u8, 0, 255], [0'u8, 255, 255], [255'u8, 255, 255]]
  CubeLevels = [0, 95, 135, 175, 215, 255]

func distance(r1, g1, b1, r2, g2, b2: int): int =
  ## "Redmean" weighted RGB distance: cheap and closer to perceived difference than plain RGB.
  let mean = (r1+r2) div 2
  let dr = r1-r2; let dg = g1-g2; let db = b1-b2
  ((512+mean)*dr*dr shr 8) + 4*dg*dg + ((767-mean)*db*db shr 8)

func namedColor(index: int): Color = color(ColorKind(ord(ColorKind.Black)+index))

func paletteRgb*(index: uint8): array[3, uint8] =
  ## RGB of an xterm 256-color palette entry: 16 named colors, the 6x6x6 cube, then 24 grays.
  let i = int(index)
  if i < 16: Ansi16Rgb[i]
  elif i < 232:
    let c = i-16
    [uint8(CubeLevels[c div 36]), uint8(CubeLevels[(c div 6) mod 6]), uint8(CubeLevels[c mod 6])]
  else:
    let level = uint8(8+10*(i-232))
    [level, level, level]

func nearestLevel(value: int): int =
  for i in 1..<CubeLevels.len:
    if abs(value-CubeLevels[i]) < abs(value-CubeLevels[result]): result = i

func nearestAnsi256*(r, g, b: uint8): uint8 =
  ## Nearest entry among the cube and gray ramp (16..255). Entries 0..15 follow the terminal
  ## theme, so they are never chosen for an exact RGB request.
  let r = int(r); let g = int(g); let b = int(b)
  let qr = nearestLevel(r); let qg = nearestLevel(g); let qb = nearestLevel(b)
  let cube = 16+36*qr+6*qg+qb
  let gray = clamp(((r+g+b) div 3-3) div 10, 0, 23)
  let level = 8+10*gray
  if distance(CubeLevels[qr], CubeLevels[qg], CubeLevels[qb], r, g, b) <= distance(level, level, level, r, g, b):
    uint8(cube)
  else: uint8(232+gray)

func nearestAnsi16*(r, g, b: uint8): Color =
  ## Nearest named color by the xterm default palette.
  var best = 0
  var bestDistance = high(int)
  for i, entry in Ansi16Rgb:
    let d = distance(int(entry[0]), int(entry[1]), int(entry[2]), int(r), int(g), int(b))
    if d < bestDistance: best = i; bestDistance = d
  namedColor(best)

func downsample*(c: Color, depth: ColorDepth): Color =
  ## Converts `c` to the nearest color `depth` can show. Reset and named colors survive every
  ## depth except `Monochrome`, which maps everything to Reset.
  case depth
  of ColorDepth.TrueColor: c
  of ColorDepth.Ansi256:
    if c.kind == ColorKind.Rgb: indexedColor(int(nearestAnsi256(c.r, c.g, c.b))) else: c
  of ColorDepth.Ansi16:
    case c.kind
    of ColorKind.Rgb: nearestAnsi16(c.r, c.g, c.b)
    of ColorKind.Indexed:
      if c.index < 16: namedColor(int(c.index))
      else:
        let rgb = paletteRgb(c.index)
        nearestAnsi16(rgb[0], rgb[1], rgb[2])
    else: c
  of ColorDepth.Monochrome: color(ColorKind.Reset)
