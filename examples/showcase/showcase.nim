## Canopy showcase: every widget, styling, layout, animation and input feature in one
## interactive app. Run it in a real terminal from the repository root:
##
##   nim r examples/showcase/showcase.nim
##   nim r examples/showcase/showcase.nim --inline   # inline viewport in normal scrollback
##
## Each page lives in its own module and exposes `help`, `render`, `handle` and `update`.
import std/[os, monotimes, times]

import canopy
import canopy/runtime/terminal/input
import canopy/ui/animation/index as animation
import common, recording, inline_demo
import widgets_page, charts_page, text_page, motion_page, jobs_page, input_page

const pageNames = ["Widgets", "Charts", "Text & color", "Motion", "Jobs", "Input"]

var
  page = 0
  tabHits: array[pageNames.len, Rect]
  contentArea: Rect
  pageTransition: Transition
  frames = 0
  cellUpdates = 0
  screen: Size

proc pageHelp(): string =
  case page
  of 0: widgets_page.help
  of 1: charts_page.help
  of 2: text_page.help
  of 3: motion_page.help
  of 4: jobs_page.help
  else: input_page.help

proc renderPage(frame: var Frame, area: Rect) =
  case page
  of 0: widgets_page.render(frame, area)
  of 1: charts_page.render(frame, area)
  of 2: text_page.render(frame, area)
  of 3: motion_page.render(frame, area)
  of 4: jobs_page.render(frame, area)
  else: input_page.render(frame, area)

proc handlePage(event: input.Event): bool =
  case page
  of 0: widgets_page.handle(event)
  of 1: charts_page.handle(event)
  of 2: text_page.handle(event)
  of 3: motion_page.handle(event)
  of 4: jobs_page.handle(event)
  else: input_page.handle(event)

proc updatePages(now: MonoTime): int =
  result = -1
  result.wakeWithin(widgets_page.update(now, page == 0))
  result.wakeWithin(charts_page.update(now, page == 1))
  result.wakeWithin(text_page.update(now, page == 2))
  result.wakeWithin(motion_page.update(now, page == 3))
  result.wakeWithin(jobs_page.update(now, page == 4))
  result.wakeWithin(input_page.update(now, page == 5))

proc showcase(frame: var Frame) =
  let areas = vertical([length(3), fill(), length(1), length(1)]).split(frame.area)
  var titles: seq[string]
  for i, name in pageNames: titles.add($(i + 1) & " " & name)
  let tabsBlock = panel("Canopy showcase")
  frame.renderWidget(initTabs(titles).withSelected(page)
    .withHighlightStyle(accent().bold().reversed()).withBlock(tabsBlock), areas[0])
  let tabsInner = tabsBlock.inner(areas[0])
  var x = tabsInner.x
  for i, title in titles:
    tabHits[i] = initRect(x, tabsInner.y, title.len + 2, 1).intersection(tabsInner)
    x += title.len + 3

  contentArea = areas[1]
  renderPage(frame, contentArea)
  if pageTransition != nil: pageTransition.apply(frame.buffer[], contentArea)

  let dim = initStyle().dim()
  frame.renderWidget(initLine([
    initSpan(" Frame ", dim), initSpan($frames, accent()),
    initSpan(" · cells sent last frame ", dim), initSpan($cellUpdates, accent()),
    initSpan(" · terminal ", dim), initSpan($screen.width & "×" & $screen.height, accent()),
    initSpan(" · theme ", dim), initSpan(themeNames[themeIndex], accent()),
    initSpan(" · motion ", dim), initSpan(if animator.reducedMotion: "reduced" else: "full", accent())]),
    areas[2])
  frame.renderWidget(initLine([initSpan(" " & pageHelp(), accent()),
    initSpan("  │  Tab/1-6: page · t: theme · m: reduced motion · q: quit", dim)]), areas[3])

proc showPage(index: int) =
  let next = (index + pageNames.len) mod pageNames.len
  if next == page: return
  page = next
  if lastFrame.content.len == 0 or contentArea.width == 0: return
  if pageTransition != nil: pageTransition.cancel()
  pageTransition = initTransition(lastFrame, contentArea, initDuration(milliseconds = 220),
    TransitionEffect.Wipe, TransitionDirection.Left)
  animator.play(pageTransition)

proc handle(event: input.Event): bool =
  ## Returns false when the app should exit.
  result = true
  input_page.record(event)
  if event.isPress and (event.key.text == "q" or event.key.code == KeyCode.Escape or
      (event.key.text == "c" and KeyModifier.Control in event.key.modifiers)):
    return false
  let click = event.leftClick
  if click.isSome:
    for i, hit in tabHits:
      if hit.contains(click.get): showPage(i); return
  if handlePage(event) or not event.isPress: return
  case event.key.code
  of KeyCode.Tab:
    showPage(page + (if KeyModifier.Shift in event.key.modifiers: -1 else: 1))
  of KeyCode.BackTab: showPage(page - 1)
  else:
    case event.key.text
    of "1", "2", "3", "4", "5", "6": showPage(ord(event.key.text[0]) - ord('1'))
    of "t": themeIndex = (themeIndex + 1) mod themeNames.len
    of "m": animator.reducedMotion = not animator.reducedMotion
    else: discard

proc run() =
  var capabilities = defaultInputCapabilities()
  capabilities.mouseCapture = true
  # RecordingBackend is the custom-backend demo: it wraps the ANSI backend and counts cells.
  withTerminal(terminal, initRecordingBackend(initAnsiBackend())):
    withInput(events, initInput(capabilities = capabilities, rawMode = false)):
      discard animator.advance(getMonoTime())
      while true:
        var timeout = updatePages(getMonoTime())
        discard animator.advance(getMonoTime())
        screen = terminal.size()
        terminal.backend.cellUpdates = 0
        lastFrame = terminal.draw(showcase).buffer
        cellUpdates = terminal.backend.cellUpdates
        inc frames
        let wake = animator.nextWake(getMonoTime())
        if wake.isSome:
          timeout.wakeWithin(int((wake.get.inNanoseconds + 999_999) div 1_000_000))
        let event = events.poll(timeout)
        if events.eof: break
        if event.isSome:
          discard animator.advance(getMonoTime())
          if not handle(event.get): break

if "--inline" in commandLineParams(): runInlineDemo()
else: run()
