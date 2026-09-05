## A custom widget needs a render procedure; no inheritance or registration.
import canopy

type Badge = object
  text: string
  style: Style

proc render(badge: Badge, area: Rect, buffer: var Buffer) =
  let border = borderedBlock().withBorderStyle(badge.style)
  border.render(area, buffer)
  initLine(badge.text).centered().render(border.inner(area), buffer)

withTerminal(terminal, initTestBackend(28, 3)):
  let completed = terminal.draw(proc(frame: var Frame) =
    frame.renderWidget(Badge(text: "Custom widget", style: initStyle().green()), frame.area))
  for y in 0..<completed.area.height:
    var row = ""
    for x in 0..<completed.area.width: row.add(completed.buffer[x, y].symbol)
    echo row
