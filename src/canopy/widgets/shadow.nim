## Shadows modify offset cells outside a base rectangle, matching Ratatui 0.30.2.
import ../[geometry,style,buffer]

type
  CellEffect* = proc(shadowArea, baseArea: Rect, buf: var Buffer) {.closure.}
  ShadowEffectKind* {.pure.} = enum Overlay, Symbol, Custom
  Shadow* = object
    effectKind*: ShadowEffectKind
    symbol*: string
    effect*: CellEffect
    style*: Style
    offset*: Offset
  Dimmed* = object

func dimmed*(): Dimmed = Dimmed()
func overlayShadow*(): Shadow = Shadow(offset:initOffset(1,1))
func initShadow*(): Shadow = overlayShadow()
func symbolShadow*(symbol: string): Shadow =
  Shadow(effectKind:ShadowEffectKind.Symbol,symbol:symbol,offset:initOffset(1,1))
func blockShadow*(): Shadow = symbolShadow("█")
func lightShadeShadow*(): Shadow = symbolShadow("░")
func mediumShadeShadow*(): Shadow = symbolShadow("▒")
func darkShadeShadow*(): Shadow = symbolShadow("▓")
func customShadow*(effect: CellEffect): Shadow =
  Shadow(effectKind:ShadowEffectKind.Custom,effect:effect,offset:initOffset(1,1))
func initShadow*(effect: CellEffect): Shadow = customShadow(effect)
func withStyle*(shadow: Shadow, style: Style): Shadow =
  result = shadow; result.style = style
func withOffset*(shadow: Shadow, offset: Offset): Shadow =
  result = shadow; result.offset = offset
func withOffset*(shadow: Shadow, x,y: int): Shadow = shadow.withOffset(initOffset(x,y))

proc apply*(effect: Dimmed, shadowArea, baseArea: Rect, buf: var Buffer) =
  let clipped = shadowArea.intersection(buf.area)
  for y in clipped.y..<clipped.bottom:
    for x in clipped.x..<clipped.right:
      if baseArea.contains(x,y): continue
      buf[x,y].modifiers.incl Modifier.Dim
      let bg = buf[x,y].bg
      if bg.kind == ColorKind.Rgb:
        buf[x,y].bg = rgbColor(int(bg.r) div 2,int(bg.g) div 2,int(bg.b) div 2)
      else: buf[x,y].bg = color(ColorKind.Black)

proc customShadow*[T](effect: T): Shadow =
  ## User effects implement apply(effect, shadowArea, baseArea, var Buffer).
  mixin apply
  customShadow(proc(shadowArea,baseArea:Rect,buf:var Buffer) = effect.apply(shadowArea,baseArea,buf))
proc initShadow*[T](effect: T): Shadow = customShadow(effect)

proc render*(shadow: Shadow, area: Rect, buf: var Buffer) =
  let shadowArea = area.offset(shadow.offset).intersection(buf.area)
  for y in shadowArea.y..<shadowArea.bottom:
    for x in shadowArea.x..<shadowArea.right:
      if area.contains(x,y): continue
      buf[x,y].setStyle(shadow.style)
      if shadow.effectKind == ShadowEffectKind.Symbol: buf[x,y].setSymbol(shadow.symbol)
  if shadow.effectKind == ShadowEffectKind.Custom and shadow.effect != nil:
    shadow.effect(shadowArea,area,buf)
