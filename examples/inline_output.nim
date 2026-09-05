## A two-line progress display with log lines inserted into the main screen.
import std/os
import canopy

withTerminal(terminal,initAnsiBackend(alternateScreen=false),inlineViewport(2)):
  for step in 0..10:
    terminal.insertBefore(1,proc(buffer:var Buffer) =
      buffer.setString(0,0,"Completed task " & $step))
    discard terminal.draw(proc(frame:var Frame) =
      frame.renderWidget(initGauge().withRatio(float64(step)/10.0)
        .withGaugeStyle(initStyle().cyan()).withLabel("Working"),frame.area))
    sleep(80)

