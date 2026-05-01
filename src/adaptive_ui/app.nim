import std/[strutils, tables]
from std/os import fileExists
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[
  agent, components, config, interaction, learning, live_flow, skill_files,
  ui_doc, transcript, ui_render
]

const
  DefaultWindowWidth* = 900
  DefaultWindowHeight* = 600
  DefaultWindowTitle* = "Adaptive UI"
  OuterLayoutSpec = """
| adaptive, * |
| input, 4 lines |
| status, 1 line |
"""

type
  AppMode* = enum
    appLocalDemo,
    appLiveChat,
    appLiveQuiz,
    appLiveEssay

  AppFocus = enum
    afAdaptive,
    afInput

  AppState = object
    width, height: int
    outerLayout: Layout
    rt: UiRuntime
    input: SynEdit
    focus: AppFocus
    mode: AppMode
    learning: LearningState
    liveDoc: UiDoc
    status: string
    theme: Theme
    agent: AgentRuntime
    agentReady: bool

proc runMinWindow*(title = DefaultWindowTitle;
    width = DefaultWindowWidth; height = DefaultWindowHeight) =
  initBackend()
  let win = createWindow(width, height)
  var screenW = win.width
  var screenH = win.height

  var fm: FontMetrics
  let font = openFont("", 18, fm)
  let theme = catppuccinMocha()
  setWindowTitle(title)

  var running = true
  while running:
    var e = default Event
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent:
        screenW = e.x
        screenH = e.y
      of KeyDownEvent:
        if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
          running = false
      else:
        discard

    fillRect(rect(0, 0, screenW, screenH), theme.bg)
    fillRect(rect(0, 0, screenW, 44), theme.scrollTrackColor)
    discard drawText(font, 14, 12, title,
      theme.fg[TokenClass.Text], theme.scrollTrackColor)
    discard drawText(font, 14, 64,
      "Bootstrap window. Press Esc or Ctrl+Q to quit.",
      theme.fg[TokenClass.Comment], theme.bg)

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

proc initAppState(width, height: int; font: Font; theme: Theme; mode: AppMode;
    cfg = initAppConfig(); skills = SkillLibrary(); status = ""): AppState =
  result.width = width
  result.height = height
  result.outerLayout = parseLayout(OuterLayoutSpec)
  result.rt = initUiRuntime()
  result.input = createSynEdit(font, theme)
  result.input.lang = langNone
  result.focus = afAdaptive
  result.mode = mode
  result.learning = initLearningState()
  result.liveDoc = textUiDoc(
    "Adaptive UI",
    "Ask for study notes, a quiz, an essay prompt, or a normal chat response."
  )
  result.status = status
  result.theme = theme
  if mode != appLocalDemo:
    result.agent = initAgentRuntime(cfg, skills)
    result.agentReady = true
    if result.status.len == 0:
      result.status = result.agent.lastStatus

proc close(state: var AppState) =
  if state.agentReady:
    state.agent.close()
    state.agentReady = false

proc currentStatus(state: AppState): string =
  if state.mode == appLocalDemo:
    result = state.learning.status
  elif state.status.len > 0:
    result = state.status
  else:
    result = state.agent.lastStatus

proc currentDoc(state: AppState): UiDoc =
  case state.mode
  of appLocalDemo:
    state.learning.doc
  of appLiveChat, appLiveQuiz, appLiveEssay:
    state.liveDoc

proc isLiveMode(mode: AppMode): bool =
  mode in {appLiveChat, appLiveQuiz, appLiveEssay}

proc flowKind(mode: AppMode): LiveFlowKind =
  case mode
  of appLocalDemo, appLiveChat:
    lfChat
  of appLiveQuiz:
    lfQuiz
  of appLiveEssay:
    lfEssay

proc appMode(kind: LiveFlowKind): AppMode =
  case kind
  of lfChat:
    appLiveChat
  of lfQuiz:
    appLiveQuiz
  of lfEssay:
    appLiveEssay

proc inputEvent(state: var AppState; e: Event; submitted: var string): Event =
  result = e
  if state.focus == afInput and e.kind == KeyDownEvent and
      e.key == KeyEnter and (CtrlPressed in e.mods or GuiPressed in e.mods):
    let text = state.input.fullText
    if text.len > 0:
      submitted = text
      state.input.clear()
    result = default Event

proc submitLiveText(state: var AppState; text: string) =
  if not state.agentReady:
    state.status = "Agent runtime is not available"
    return
  if state.agent.pendingRequests() > 0:
    state.status = "Waiting for the current agent request"
    return

  var err = ""
  let prompt = flowPrompt(state.mode.flowKind(), text)
  if state.agent.submitUserText(prompt, err, text):
    state.status = state.agent.lastStatus
    state.liveDoc = transcriptUiDoc(state.agent.history, "Waiting")
  else:
    state.status = err

proc switchLiveFlow(state: var AppState; kind: LiveFlowKind; text: string) =
  state.mode = appMode(kind)
  state.status = flowTitle(kind) & " mode"
  state.liveDoc = flowIntroDoc(kind)
  if text.strip().len > 0:
    state.submitLiveText(text)

proc handleSubmittedInput(state: var AppState; text: string) =
  if text.strip().len == 0:
    return

  case state.mode
  of appLocalDemo:
    state.learning.status = "Input captured: " & $text.len & " characters"
  of appLiveChat, appLiveQuiz, appLiveEssay:
    let cmd = parseLiveCommand(text)
    case cmd.kind
    of lcNone:
      state.submitLiveText(cmd.text)
    of lcChat, lcQuiz, lcEssay:
      state.switchLiveFlow(flowForCommand(cmd.kind), cmd.text)

proc handleLiveUiEvent(state: var AppState; ev: UiEvent) =
  case ev.kind
  of ueNone:
    discard
  of ueSelect:
    state.status = "Selected " & ev.value
  of ueClick, ueSubmitText:
    state.submitLiveText(uiEventText(state.liveDoc, state.rt, ev))

proc handleAdaptiveEvent(state: var AppState; ev: UiEvent) =
  case state.mode
  of appLocalDemo:
    state.learning.handleLearningEvent(state.rt, ev)
  of appLiveChat, appLiveQuiz, appLiveEssay:
    state.handleLiveUiEvent(ev)

proc pollLiveAgent(state: var AppState) =
  if not state.mode.isLiveMode() or not state.agentReady:
    return

  var item: AgentResult
  while state.agent.pollAgent(item):
    case item.kind
    of agNone:
      discard
    of agError:
      state.status = item.error
      if state.liveDoc.areas.len == 0:
        state.liveDoc = textUiDoc("Agent Error", item.error)
    of agChatText:
      state.liveDoc = transcriptUiDoc(state.agent.history)
      var err = ""
      if state.agent.enqueueUiDoc(
          state.liveDoc, err, uiFlowHint(state.mode.flowKind())):
        state.status = state.agent.lastStatus
      else:
        state.status = err
    of agUiDoc:
      state.liveDoc = item.doc
      state.status = state.agent.lastStatus

proc drawStatus(font: Font; r: Rect; text: string; theme: Theme) =
  let bg = theme.scrollTrackColor
  fillRect(r, bg)
  discard drawText(font, r.x + 8, r.y + 5, text, theme.fg[TokenClass.Text], bg)

proc insetRect(r: Rect; pad: int): Rect =
  rect(r.x + pad, r.y + pad, max(0, r.w - pad * 2), max(0, r.h - pad * 2))

proc runLearningDemo*(title = "Adaptive UI Learning Demo";
    width = DefaultWindowWidth; height = DefaultWindowHeight) =
  initBackend()
  let win = createWindow(width, height)

  var fm: FontMetrics
  let font = openFont("", 16, fm)
  let theme = catppuccinMocha()
  setWindowTitle(title)

  var state = initAppState(win.width, win.height, font, theme, appLocalDemo)
  var running = true

  while running:
    let cells = state.outerLayout.resolve(
      state.width, state.height, fm.lineHeight, gap = 2)
    let inputFlags =
      if state.focus == afInput: {WantTextInput}
      else: {}

    var e = default Event
    discard waitEvent(e, 16, inputFlags)
    case e.kind
    of QuitEvent, WindowCloseEvent:
      running = false
    of WindowResizeEvent, WindowMetricsEvent:
      state.width = e.x
      state.height = e.y
    of MouseDownEvent:
      if cells["input"].contains(point(e.x, e.y)):
        state.focus = afInput
      elif cells["adaptive"].contains(point(e.x, e.y)):
        state.focus = afAdaptive
    of KeyDownEvent:
      if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
        running = false
    else:
      discard

    fillRect(rect(0, 0, state.width, state.height), state.theme.scrollTrackColor)

    let adaptiveEvent = if state.focus == afAdaptive: e else: default Event
    let ev = renderUiDoc(state.currentDoc(), state.rt, adaptiveEvent,
      cells["adaptive"], font, fm, state.theme)
    state.handleAdaptiveEvent(ev)

    var submitted = ""
    let inputSourceEvent = if state.focus == afInput: e else: default Event
    let inputDrawEvent = state.inputEvent(inputSourceEvent, submitted)
    fillRect(cells["input"], state.theme.bg)
    discard state.input.draw(inputDrawEvent, cells["input"].insetRect(8),
      state.focus == afInput)
    state.handleSubmittedInput(submitted)

    drawStatus(font, cells["status"], state.currentStatus(), state.theme)

    refresh()

  state.close()
  closeFont(font)
  shutdown()

proc readAppConfig(path: string; status: var string): AppConfig =
  var err = ""
  if loadConfig(path, result, err):
    if not fileExists(path):
      status = "Using default config"
  else:
    result = initAppConfig()
    status = "Config error: " & err

proc runAdaptiveApp*(configPath = "adaptive_ui.json";
    title = DefaultWindowTitle; width = DefaultWindowWidth;
    height = DefaultWindowHeight) =
  initBackend()
  let win = createWindow(width, height)

  var fm: FontMetrics
  let font = openFont("", 16, fm)
  let theme = catppuccinMocha()
  setWindowTitle(title)

  var status = ""
  let cfg = readAppConfig(configPath, status)
  let skills = loadSkills(cfg.skillRoots)
  var state = initAppState(
    win.width,
    win.height,
    font,
    theme,
    appLiveChat,
    cfg,
    skills,
    status
  )
  if not state.agent.hasLiveConfig():
    state.mode = appLocalDemo
    state.learning.status = "Local demo: " & state.agent.lastStatus

  var running = true
  while running:
    let cells = state.outerLayout.resolve(
      state.width, state.height, fm.lineHeight, gap = 2)
    let inputFlags =
      if state.focus == afInput: {WantTextInput}
      else: {}

    var e = default Event
    discard waitEvent(e, 16, inputFlags)
    case e.kind
    of QuitEvent, WindowCloseEvent:
      running = false
    of WindowResizeEvent, WindowMetricsEvent:
      state.width = e.x
      state.height = e.y
    of MouseDownEvent:
      if cells["input"].contains(point(e.x, e.y)):
        state.focus = afInput
      elif cells["adaptive"].contains(point(e.x, e.y)):
        state.focus = afAdaptive
    of KeyDownEvent:
      if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
        running = false
    else:
      discard

    state.pollLiveAgent()
    fillRect(rect(0, 0, state.width, state.height), state.theme.scrollTrackColor)

    let adaptiveEvent = if state.focus == afAdaptive: e else: default Event
    let ev = renderUiDoc(state.currentDoc(), state.rt, adaptiveEvent,
      cells["adaptive"], font, fm, state.theme)
    state.handleAdaptiveEvent(ev)

    var submitted = ""
    let inputSourceEvent = if state.focus == afInput: e else: default Event
    let inputDrawEvent = state.inputEvent(inputSourceEvent, submitted)
    fillRect(cells["input"], state.theme.bg)
    discard state.input.draw(inputDrawEvent, cells["input"].insetRect(8),
      state.focus == afInput)
    state.handleSubmittedInput(submitted)

    drawStatus(font, cells["status"], state.currentStatus(), state.theme)
    refresh()

  state.close()
  closeFont(font)
  shutdown()
