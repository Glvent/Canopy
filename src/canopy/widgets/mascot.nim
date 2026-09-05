## Ratatui mascot rendered using half-block cells (MIT upstream artwork).
import std/options
import ../[geometry,style,buffer,unicode]
import ../internal/mascot_data
type
  MascotEyeColor* {.pure.} = enum Default, Red
  RatatuiMascot* = object
    eyeState*: MascotEyeColor
  Mascot* = RatatuiMascot
func initRatatuiMascot*(): RatatuiMascot = RatatuiMascot()
func initMascot*(): Mascot = initRatatuiMascot()
func withEye*(m: RatatuiMascot, eye: MascotEyeColor): RatatuiMascot = RatatuiMascot(eyeState:eye)
func setEye*(m: RatatuiMascot, eye: MascotEyeColor): RatatuiMascot = m.withEye(eye)
func colorFor(m: RatatuiMascot, pixel:string): Option[Color] =
  case pixel
  of "█": some(indexedColor(252))
  of "h": some(indexedColor(231))
  of "e": some(indexedColor(if m.eyeState == MascotEyeColor.Default: 236 else: 196))
  of "░": some(indexedColor(232))
  of "▒": some(indexedColor(237))
  of "▓": some(indexedColor(248))
  else: none(Color)
proc render*(m: RatatuiMascot, area: Rect, buf: var Buffer) =
  let a = area.intersection(buf.area)
  for y in 0..<min(a.height,MascotPixels.len div 2):
    let top = graphemes(MascotPixels[y*2])
    let bottom = graphemes(MascotPixels[y*2+1])
    for x in 0..<min(a.width,min(top.len,bottom.len)):
      let c = top[x]
      let d = bottom[x]
      var fg,bg: Option[Color]
      if c == " " and d == " ": discard
      elif d == " ": fg = m.colorFor(c)
      elif c == " ": fg = m.colorFor(d)
      elif c == "░" and d == "▒":
        fg = m.colorFor("▒")
        bg = m.colorFor("░")
      elif c == "░" or d == "░":
        fg = m.colorFor(if c == "░": d else: c)
        bg = m.colorFor("░")
      else:
        fg = m.colorFor(c)
        bg = m.colorFor(d)
      var symbol = ""
      if c == " " and d == " ": discard
      elif c == "░" and d == "░": symbol = " "
      elif d == " " or d == "░": symbol = "▀"
      elif c == " " or c == "░": symbol = "▄"
      elif c == d: symbol = "█"
      else: symbol = "▀"
      if fg.isSome: buf[a.x+x,a.y+y].fg = fg.get
      if bg.isSome: buf[a.x+x,a.y+y].bg = bg.get
      if symbol.len > 0: buf[a.x+x,a.y+y].symbol = symbol
