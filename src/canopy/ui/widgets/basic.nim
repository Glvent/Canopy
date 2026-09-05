## Clearing and uniform fill widgets.
import ../../core/layout/geometry
import ../../core/styling/style
import ../../core/rendering/buffer

type
  Clear* = object
  Fill* = object
    symbol*: string
    style*: Style

func initClear*(): Clear = Clear()
func initFill*(symbol: string): Fill = Fill(symbol: symbol)
func withSymbol*(widget: Fill, symbol: string): Fill =
  result = widget
  result.symbol = symbol

func withStyle*(widget: Fill, style: Style): Fill =
  result = widget
  result.style = style

proc render*(widget: Clear, area: Rect, buf: var Buffer) =
  ## Resets cells to unwritten, which lets a popup hide whatever was rendered underneath.
  for p in area.intersection(buf.area).positions: buf[p].reset()

proc render*(widget: Fill, area: Rect, buf: var Buffer) =
  for p in area.intersection(buf.area).positions:
    buf[p].setSymbol(widget.symbol)
    buf[p].setStyle(widget.style)
