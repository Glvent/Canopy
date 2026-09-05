## Interactive demo: tabs, simulated jobs, settings, keyboard and mouse input.
## --snapshot renders without taking over the terminal.
import std/[os,strutils,monotimes,times]
import canopy
import canopy/input
import canopy/animation

const
  tabNames = ["Overview", "Jobs", "Settings"]
  jobNames = ["Compile", "Compatibility tests", "Documentation"]
  jobDescriptions = ["Build the native library and examples.",
    "Compare rendering, layout and state with pinned fixtures.",
    "Generate the rendering and input API documentation."]
  speedNames = ["Slow", "Normal", "Fast"]
  themeNames = ["Cyan", "Green", "Magenta"]

type Job = object
  progress: int
  running: bool

var
  activeTab = 0
  selection = initListState().withSelected(0)
  settingSelection = initListState().withSelected(0)
  jobs: array[3, Job]
  speed = 1
  theme = 0
  advanceSelection = false
  tabHits: array[3, Rect]
  listHit, startHit, resetHit: Rect
  animator = initAnimator()
  progress: array[3,Tween[float]]
  tabTransition: Transition
  lastFrame: Buffer
  contentArea: Rect

for i in 0..<progress.len:
  progress[i] = initTween(0.0,0.0,DurationZero)

proc syncProgress(i:int) =
  # Simulated work remains functional; smoothing is purely presentational.
  progress[i].cancel()
  progress[i] = initTween(progress[i].value,float(jobs[i].progress)/100,
    initDuration(milliseconds=180),easing=cubicOut,role=MotionRole.Decorative)
  animator.play(progress[i])

proc changeTab(previous:int) =
  if previous == activeTab or lastFrame.content.len == 0: return
  if tabTransition != nil: tabTransition.cancel()
  tabTransition = initTransition(lastFrame,contentArea,initDuration(milliseconds=220),
    TransitionEffect.Wipe,TransitionDirection.Left)
  animator.play(tabTransition)

proc accent(): Style =
  initStyle().withFg(color([ColorKind.Cyan,ColorKind.Green,ColorKind.Magenta][theme]))

func status(job: Job): string =
  if job.progress == 100: "Done"
  elif job.running: "Running"
  elif job.progress > 0: "Paused"
  else: "Ready"

proc toggleJob() =
  let index = selection.selected.get(0)
  if jobs[index].progress == 100: jobs[index].progress = 0
  jobs[index].running = not jobs[index].running

proc changeSetting() =
  case settingSelection.selected.get(0)
  of 0: speed = (speed+1) mod speedNames.len
  of 1: advanceSelection = not advanceSelection
  of 2: theme = (theme+1) mod themeNames.len
  else: animator.reducedMotion = not animator.reducedMotion

proc moveSelection(delta: int) =
  if activeTab == 2:
    settingSelection.select((settingSelection.selected.get(0)+delta+4) mod 4)
  else:
    selection.select((selection.selected.get(0)+delta+jobs.len) mod jobs.len)

proc dashboard(frame:var Frame) =
  let areas = vertical([length(3),fill(),length(3),length(2)]).withMargin(1).split(frame.area)
  let tabsBlock = borderedBlock().withTitle("Canopy · interactive demo")
  frame.renderWidget(initTabs(tabNames).withSelected(activeTab)
    .withHighlightStyle(accent().bold().reversed()).withBlock(tabsBlock),areas[0])
  let tabsInner = tabsBlock.inner(areas[0])
  var x = tabsInner.x
  for i,name in tabNames:
    tabHits[i] = initRect(x,tabsInner.y,name.len+2,1).intersection(tabsInner)
    x += name.len+3

  let columns = horizontal([length(min(28,areas[1].width div 2)),fill()])
    .withSpacing(1).split(areas[1])
  contentArea = areas[1]
  startHit = initRect(0,0,0,0)
  resetHit = initRect(0,0,0,0)
  let selected = selection.selected.get(0)
  if activeTab == 2:
    let settingsBlock = borderedBlock().withTitle("Settings · Enter to change")
    let labels = ["Speed: " & speedNames[speed],
      "Auto-select next: " & (if advanceSelection: "On" else: "Off"),
      "Theme: " & themeNames[theme],
      "Reduced motion: " & (if animator.reducedMotion: "On" else: "Off")]
    var items: seq[ListItem]
    for label in labels: items.add(initListItem(label))
    frame.renderStatefulWidget(initList(items).withBlock(settingsBlock)
      .withHighlightSymbol("▶ ").withHighlightStyle(accent().bold()),columns[0],settingSelection)
    listHit = settingsBlock.inner(columns[0])
    let descriptions = [
      "Demo speed\n\nChoose Slow, Normal or Fast. Running jobs use the new speed immediately.",
      "Automatic selection\n\nMove to the next job when the selected job completes.",
      "Accent color\n\nChoose Cyan, Green or Magenta. The whole dashboard updates immediately.",
      "Reduced motion\n\nFinish visual transitions immediately. Simulated jobs continue at the selected speed."]
    frame.renderWidget(initParagraph(descriptions[settingSelection.selected.get(0)] &
      "\n\nClick a setting or press Enter to change it.\n\nSettings last for this session.")
      .withWrap(true).withBlock(borderedBlock().withTitle("Preferences").withPadding(uniformPadding(1))),columns[1])
  else:
    let jobsBlock = borderedBlock().withTitle("Demo jobs")
    var items: seq[ListItem]
    for i,name in jobNames:
      items.add(initListItem(name & "\n  " & jobs[i].status & " · " & $jobs[i].progress & "%"))
    frame.renderStatefulWidget(initList(items).withBlock(jobsBlock)
      .withHighlightSymbol("▶ ").withHighlightStyle(accent().bold()),columns[0],selection)
    listHit = jobsBlock.inner(columns[0])
    let details = vertical([fill(),length(3)]).split(columns[1])
    if activeTab == 0:
      let rows = [initRow(["Unicode","17.0","native"]),
        initRow(["Layout","Cassowary","cached"]),
        initRow(["Backend","ANSI / VT","portable"]),
        initRow(["Selected",jobNames[selected],jobs[selected].status])]
      frame.renderWidget(initTable(rows,[length(10),fill(),length(8)])
        .withHeader(initRow(["Component","Mode","Status"]).withStyle(accent().bold()))
        .withBlock(borderedBlock().withTitle("System overview")),details[0])
    else:
      frame.renderWidget(initParagraph(jobDescriptions[selected] & "\n\nStatus: " & jobs[selected].status &
        "\nProgress: " & $jobs[selected].progress & "%\n\nThese jobs simulate progress; they do not run commands.")
        .withWrap(true).withBlock(borderedBlock().withTitle(jobNames[selected]).withPadding(uniformPadding(1))),details[0])
    let buttons = horizontal([fill(),fill()]).withSpacing(1).split(details[1])
    startHit = buttons[0]
    resetHit = buttons[1]
    let action = if jobs[selected].running: "Pause" elif jobs[selected].progress == 100: "Run again" else: "Start / resume"
    frame.renderWidget(initParagraph(action).withAlignment(Alignment.Center).withStyle(accent().bold())
      .withBlock(borderedBlock()),startHit)
    frame.renderWidget(initParagraph("Reset").withAlignment(Alignment.Center).withBlock(borderedBlock()),resetHit)

  if tabTransition != nil: tabTransition.apply(frame.buffer[],contentArea)
  frame.renderWidget(initGauge().withRatio(progress[selected].value)
    .withLabel(jobNames[selected] & " · " & jobs[selected].status & " · " & $jobs[selected].progress & "%")
    .withGaugeStyle(accent()).withBlock(borderedBlock().withTitle("Simulated progress")),areas[2])
  frame.renderWidget(initParagraph("←/→ or Tab: tabs · ↑/↓: select · Enter/Space: act\n" &
    "Click: tabs, rows, buttons · r: reset job · 1/2/3: tabs · q: quit"),areas[3])

proc handle(event: input.Event): bool =
  result = true
  case event.kind
  of input.EventKind.Key:
    if event.key.kind == KeyEventKind.Release: return
    if event.key.text == "q" or event.key.code == KeyCode.Escape or
        (event.key.text == "c" and KeyModifier.Control in event.key.modifiers): return false
    case event.key.code
    of KeyCode.Right: activeTab = (activeTab+1) mod 3
    of KeyCode.Left, KeyCode.BackTab: activeTab = (activeTab+2) mod 3
    of KeyCode.Tab: activeTab = (activeTab + (if KeyModifier.Shift in event.key.modifiers: 2 else: 1)) mod 3
    of KeyCode.Up: moveSelection(-1)
    of KeyCode.Down: moveSelection(1)
    of KeyCode.Enter:
      if activeTab == 2: changeSetting() else: toggleJob()
    else:
      case event.key.text
      of "1", "2", "3": activeTab = parseInt(event.key.text)-1
      of " ":
        if activeTab == 2: changeSetting() else: toggleJob()
      of "r": jobs[selection.selected.get(0)] = Job()
      else: discard
  of input.EventKind.Mouse:
    let point = initPosition(event.mouse.column,event.mouse.row)
    if event.mouse.kind in {MouseEventKind.ScrollUp,MouseEventKind.ScrollDown}:
      if listHit.contains(point): moveSelection(if event.mouse.kind == MouseEventKind.ScrollUp: -1 else: 1)
    elif event.mouse.kind == MouseEventKind.Down and event.mouse.button == some(MouseButton.Left):
      for i,hit in tabHits:
        if hit.contains(point): activeTab = i; return
      if listHit.contains(point):
        let row = point.y-listHit.y
        let index = row div (if activeTab == 2: 1 else: 2)
        if activeTab == 2:
          let selected = settingSelection.offset+index
          if selected < 4: settingSelection.select(selected); changeSetting()
        else:
          let selected = selection.offset+index
          if selected < jobs.len: selection.select(selected)
      elif startHit.contains(point): toggleJob()
      elif resetHit.contains(point): jobs[selection.selected.get(0)] = Job()
  else: discard

if "--snapshot" in commandLineParams():
  withTerminal(terminal,initTestBackend(80,24)):
    let frame = terminal.draw(dashboard)
    for y in 0..<frame.buffer.area.height:
      var row = ""
      var x = 0
      while x < frame.buffer.area.width:
        let cell = frame.buffer[x,y]
        row.add(cell.symbol)
        x += max(1,cell.cellWidth)
      echo row.strip(leading=false)
else:
  var capabilities = defaultInputCapabilities()
  capabilities.mouseCapture = true
  withTerminal(terminal,initAnsiBackend()):
    withInput(events,initInput(capabilities=capabilities,rawMode=false)):
      var lastTick = getMonoTime()
      discard animator.advance(lastTick)
      while true:
        discard animator.advance(getMonoTime())
        lastFrame = terminal.draw(dashboard).buffer
        let now = getMonoTime()
        var timeout = -1
        for job in jobs:
          if job.running:
            timeout = int(max(0'i64,200-(now-lastTick).inMilliseconds))
            break
        let wake = animator.nextWake(now)
        if wake.isSome:
          let animationTimeout = int((wake.get.inNanoseconds+999_999) div 1_000_000)
          timeout = if timeout < 0: animationTimeout else: min(timeout,animationTimeout)
        let event = events.poll(timeout)
        discard animator.advance(getMonoTime())
        let previousTab = activeTab
        var before: array[3,int]
        var hadRunning = false
        for i,job in jobs:
          before[i] = job.progress
          hadRunning = hadRunning or job.running
        if events.eof or (event.isSome and not handle(event.get)): break
        changeTab(previousTab)
        let tickNow = getMonoTime()
        if not hadRunning: lastTick = tickNow
        let ticks = int((tickNow-lastTick).inMilliseconds div 200)
        if ticks > 0:
          lastTick = tickNow
          for i,job in jobs.mpairs:
            if job.running:
              job.progress = min(100,job.progress+min(ticks,100)*[1,2,5][speed])
              if job.progress == 100:
                job.running = false
                if advanceSelection and selection.selected == some(int(i)):
                  selection.select((i+1) mod jobs.len)
        for i,job in jobs:
          if before[i] != job.progress: syncProgress(i)
