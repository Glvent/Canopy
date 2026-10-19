## A small application: simulated jobs with progress smoothed by tweens, settings, buttons
## and mouse hit-testing. The jobs only simulate progress; they run no commands.
import std/[monotimes, times]

import canopy
import canopy/runtime/terminal/input
import canopy/ui/animation/index as animation
import common

const
  help* = "↑/↓: job · Enter/Space: start/pause · x: reset · s: speed · a: auto-advance · click"
  jobNames = ["Compile", "Compatibility tests", "Documentation"]
  jobDescriptions = ["Build the native library and examples.",
    "Compare rendering, layout and state with pinned fixtures.",
    "Generate the rendering and input API documentation."]
  speedNames = ["Slow", "Normal", "Fast"]
  tickMs = 200

type Job = object
  progress: int
  running: bool

var
  jobs: array[3, Job]
  selection = initListState().withSelected(0)
  speed = 1
  autoAdvance = true
  progress: array[3, Tween[float]]
  listHit, startHit, resetHit: Rect
  lastTick: MonoTime

for i in 0..<progress.len: progress[i] = initTween(0.0, 0.0, DurationZero)

func status(job: Job): string =
  if job.progress == 100: "Done"
  elif job.running: "Running"
  elif job.progress > 0: "Paused"
  else: "Ready"

proc syncProgress(i: int) =
  # The simulation stays exact; the tween only smooths what the gauge shows.
  progress[i].cancel()
  progress[i] = initTween(progress[i].value, float(jobs[i].progress) / 100,
    initDuration(milliseconds = 180), easing = cubicOut, role = MotionRole.Decorative)
  animator.play(progress[i])

proc selected(): int = selection.selected.get(0)

proc toggleJob() =
  let i = selected()
  if jobs[i].progress == 100:
    jobs[i].progress = 0
    syncProgress(i)
  jobs[i].running = not jobs[i].running

proc resetJob() =
  jobs[selected()] = Job()
  syncProgress(selected())

proc render*(frame: var Frame, area: Rect) =
  let rows = vertical([fill(), length(3), length(3)]).withSpacing(1).split(area)
  let columns = horizontal([length(30), fill()]).withSpacing(1).split(rows[0])
  let i = selected()

  var items: seq[ListItem]
  for j, name in jobNames:
    items.add(initListItem(name & "\n  " & jobs[j].status & " · " & $jobs[j].progress & "%"))
  let jobsBlock = panel("Jobs")
  frame.renderStatefulWidget(initList(items).withBlock(jobsBlock)
    .withHighlightSymbol("▶ ").withHighlightStyle(accent().bold()), columns[0], selection)
  listHit = jobsBlock.inner(columns[0])

  let right = vertical([fill(), length(6)]).split(columns[1])
  frame.renderWidget(initParagraph(jobDescriptions[i] & "\n\nStatus: " & jobs[i].status &
      "\nProgress: " & $jobs[i].progress & "%")
    .withWrap(true).withBlock(panel(jobNames[i]).withPadding(uniformPadding(1))), right[0])
  frame.renderWidget(initTable([
      initRow(["Speed (s)", speedNames[speed]]),
      initRow(["Auto-advance (a)", if autoAdvance: "On" else: "Off"]),
      initRow(["Theme (t)", themeNames[themeIndex]]),
      initRow(["Reduced motion (m)", if animator.reducedMotion: "On" else: "Off"])],
    [length(20), fill()]).withBlock(panel("Settings")), right[1])

  let buttons = horizontal([fill(), fill()]).withSpacing(2).split(rows[1])
  startHit = buttons[0]
  resetHit = buttons[1]
  let action = if jobs[i].running: "Pause"
               elif jobs[i].progress == 100: "Run again"
               else: "Start / resume"
  frame.renderWidget(initParagraph(initText([buttonLabel(action, true)])).withBlock(button(true)),
    startHit)
  frame.renderWidget(initParagraph(initText([buttonLabel("Reset", false)]))
    .withBlock(button(false)), resetHit)
  frame.renderWidget(initGauge().withRatio(clamp(progress[i].value, 0.0, 1.0)).withUseUnicode()
    .withLabel(jobNames[i] & " · " & $jobs[i].progress & "%").withGaugeStyle(meter())
    .withBlock(panel("Progress")), rows[2])

proc handle*(event: input.Event): bool =
  result = true
  let delta = event.wheel(listHit)
  if delta != 0: selection.select((selected() + delta + jobs.len) mod jobs.len); return
  let click = event.leftClick
  if click.isSome:
    let point = click.get
    if listHit.contains(point):
      let index = selection.offset + (point.y - listHit.y) div 2
      if index < jobs.len: selection.select(index)
    elif startHit.contains(point): toggleJob()
    elif resetHit.contains(point): resetJob()
    else: result = false
    return
  if not event.isPress: return false
  case event.key.code
  of KeyCode.Up: selection.select((selected() + jobs.len - 1) mod jobs.len)
  of KeyCode.Down: selection.select((selected() + 1) mod jobs.len)
  of KeyCode.Enter: toggleJob()
  else:
    case event.key.text
    of " ": toggleJob()
    of "x": resetJob()
    of "s": speed = (speed + 1) mod speedNames.len
    of "a": autoAdvance = not autoAdvance
    else: result = false

proc update*(now: MonoTime, active: bool): int =
  ## Jobs keep running while other pages are shown.
  var running = false
  for job in jobs: running = running or job.running
  if not running:
    lastTick = now
    return -1
  let ticks = int((now - lastTick).inMilliseconds div tickMs)
  if ticks > 0:
    lastTick = now
    for i, job in jobs.mpairs:
      if job.running:
        job.progress = min(100, job.progress + ticks * [1, 2, 5][speed])
        syncProgress(i)
        if job.progress == 100:
          job.running = false
          if autoAdvance and selected() == i: selection.select((i + 1) mod jobs.len)
  int(max(0'i64, tickMs - (now - lastTick).inMilliseconds))
