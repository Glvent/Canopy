## State and helpers shared by every showcase page.
import canopy
import canopy/runtime/terminal/input
import canopy/ui/animation/index as animation

const themeNames* = ["Cyan", "Green", "Magenta", "Yellow"]

var
  themeIndex* = 0
  animator* = initAnimator()
    ## One animator drives every page, so reduced motion applies everywhere at once.

proc accentColor*(): Color =
  color([ColorKind.Cyan, ColorKind.Green, ColorKind.Magenta, ColorKind.Yellow][themeIndex])

proc accent*(): Style = initStyle().withFg(accentColor())
proc highlight*(): Style = initStyle().withFg(ColorKind.Black).withBg(accentColor())
proc panel*(title: string): Block = borderedBlock().withTitle(title).withBorderStyle(accent())

func isPress*(event: input.Event): bool =
  event.kind == input.EventKind.Key and event.key.kind != KeyEventKind.Release

func leftClick*(event: input.Event): Option[Position] =
  if event.kind == input.EventKind.Mouse and event.mouse.kind == MouseEventKind.Down and
      event.mouse.button == some(MouseButton.Left):
    result = some(initPosition(event.mouse.column, event.mouse.row))

func wheel*(event: input.Event, area: Rect): int =
  ## -1 or 1 when the mouse wheel turns over `area`, otherwise 0.
  if event.kind != input.EventKind.Mouse or
      not area.contains(initPosition(event.mouse.column, event.mouse.row)): return 0
  case event.mouse.kind
  of MouseEventKind.ScrollUp: -1
  of MouseEventKind.ScrollDown: 1
  else: 0

proc wakeWithin*(timeout: var int, milliseconds: int) =
  ## Shortens the event-poll timeout; a negative value means "no deadline".
  if milliseconds >= 0:
    timeout = if timeout < 0: milliseconds else: min(timeout, milliseconds)

func centeredRect*(area: Rect, width, height: int): Rect =
  let w = min(width, area.width)
  let h = min(height, area.height)
  initRect(area.x + (area.width - w) div 2, area.y + (area.height - h) div 2, w, h)

var lastFrame*: Buffer
  ## The previously drawn screen; buffer transitions animate from it.
