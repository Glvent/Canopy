## Run in a terminal; q, Escape or Ctrl-C exits. Input remains application-owned.
import canopy
import canopy/input

withTerminal(terminal,initAnsiBackend()):
  withInput(events,initInput(rawMode=false)):
    var message = "Press any key; q or Escape exits."
    var running = true
    while running:
      discard terminal.draw(proc(frame:var Frame) =
        let border = borderedBlock().withTitle("Canopy · keyboard")
        frame.renderWidget(border,frame.area)
        frame.renderWidget(initParagraph(message).withWrap(initWrap(true)),border.inner(frame.area)))
      let event = events.read()
      case event.kind
      of EventKind.Key:
        running = event.key.code != KeyCode.Escape and event.key.text != "q" and
          not (event.key.text == "c" and KeyModifier.Control in event.key.modifiers)
        message = $event.key.code & " " & event.key.text
      of EventKind.Paste: message = event.text
      of EventKind.Unsupported: message = "Unsupported terminal sequence"
      else: discard
