## Inline viewport: a two-line progress display stays below log lines inserted into the
## normal scrollback, without switching to the alternate screen.
import std/os

import canopy
import common

proc runInlineDemo*() =
  withTerminal(terminal, initAnsiBackend(alternateScreen = false), inlineViewport(2)):
    for step in 0..10:
      if step > 0:
        terminal.insertBefore(1, proc(buffer: var Buffer) =
          buffer.setString(0, 0, "Completed task " & $step))
      discard terminal.draw(proc(frame: var Frame) =
        frame.renderWidget(initGauge().withRatio(float64(step)/10.0)
          .withGaugeStyle(accent()).withLabel("Working · " & $(step*10) & "%"), frame.area))
      sleep(120)
