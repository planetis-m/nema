import std/[strutils, tables]
from std/os import fileExists
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[
  agent, components, config, debug_log, interaction, live_flow,
  skill_files, ui_doc, transcript, ui_render
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
    appAdaptive,
    appChat,
    appQuiz,
    appEssay

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
    doc: UiDoc
    debugLog: DebugLog
    status: string
    theme: Theme
    agent: AgentRuntime
    agentReady: bool

proc initAppState(width, height: int; font: Font; theme: Theme;
    cfg: AppConfig; skills: SkillLibrary; status = ""): AppState =
  result.width = width
  result.height = height
  result.outerLayout = parseLayout(OuterLayoutSpec)
  result.rt = initUiRuntime()
  result.input = createSynEdit(font, theme)
  result.input.lang = langNone
  result.focus = afAdaptive
  result.mode = appAdaptive
  result.doc = flowIntroDoc(lfAdaptive)
  result.debugLog = initDebugLog()
  result.status = status
  result.theme = theme
  result.agent = initAgentRuntime(cfg, skills)
  result.agentReady = true
  if result.status.len == 0:
    result.status = result.agent.lastStatus

proc close(state: var AppState) =
  if state.agentReady:
    state.agent.close()
    state.agentReady = false

proc currentStatus(state: AppState): string =
  if state.status.len > 0:
    result = state.status
  else:
    result = state.agent.lastStatus

proc flowKind(mode: AppMode): LiveFlowKind =
  case mode
  of appAdaptive:
    lfAdaptive
  of appChat:
    lfChat
  of appQuiz:
    lfQuiz
  of appEssay:
    lfEssay

proc toAppMode(kind: LiveFlowKind): AppMode =
  case kind
  of lfAdaptive:
    appAdaptive
  of lfChat:
    appChat
  of lfQuiz:
    appQuiz
  of lfEssay:
    appEssay

proc inputEvent(state: var AppState; e: Event; submitted: var string): Event =
  result = e
  if state.focus == afInput and e.kind == KeyDownEvent and
      e.key == KeyEnter and (CtrlPressed in e.mods or GuiPressed in e.mods):
    let text = state.input.fullText
    if text.len > 0:
      submitted = text
      state.input.clear()
    result = default Event

proc submitText(state: var AppState; text: string) =
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
    state.doc = transcriptUiDoc(state.agent.history, "Waiting")
  else:
    state.status = err

proc switchFlow(state: var AppState; kind: LiveFlowKind; text: string) =
  state.mode = toAppMode(kind)
  state.rt = initUiRuntime()
  state.status = flowTitle(kind) & " mode"
  state.doc = flowIntroDoc(kind)
  if text.strip().len > 0:
    state.submitText(text)

proc handleSubmittedInput(state: var AppState; text: string) =
  if text.strip().len == 0:
    return

  let cmd = parseLiveCommand(text)
  case cmd.kind
  of lcNone:
    state.submitText(cmd.text)
  of lcAdaptive, lcChat, lcQuiz, lcEssay:
    state.switchFlow(flowForCommand(cmd.kind), cmd.text)
  of lcDebug:
    state.doc = debugUiDoc(state.debugLog)
    state.status = "Debug log"

proc handleUiEvent(state: var AppState; ev: UiEvent) =
  case ev.kind
  of ueNone:
    discard
  of ueSelect:
    state.status = "Selected " & ev.value
  of ueClick, ueSubmitText:
    if ev.area == "actions" and ev.id in ["chat", "quiz", "essay"]:
      case ev.id
      of "chat":
        state.switchFlow(lfChat, "")
      of "quiz":
        state.switchFlow(lfQuiz, "")
      of "essay":
        state.switchFlow(lfEssay, "")
      else:
        discard
    else:
      state.submitText(uiEventText(state.doc, state.rt, ev))

proc pollAgent(state: var AppState) =
  if not state.agentReady:
    return

  var item: AgentResult
  while state.agent.pollAgent(item):
    case item.kind
    of agNone:
      discard
    of agError:
      state.status = item.error
      if item.text.len > 0:
        state.debugLog.addDebug(item.text)
      if state.doc.areas.len == 0:
        state.doc = textUiDoc("Agent Error", item.error)
    of agChatText:
      state.doc = transcriptUiDoc(state.agent.history)
      var err = ""
      if state.agent.enqueueUiDoc(
          state.doc, err, uiFlowHint(state.mode.flowKind())):
        state.status = state.agent.lastStatus
      else:
        state.status = err
    of agUiDoc:
      state.doc = item.doc
      state.status = state.agent.lastStatus

proc drawStatus(font: Font; r: Rect; text: string; theme: Theme) =
  let bg = theme.scrollTrackColor
  fillRect(r, bg)
  discard drawText(font, r.x + 8, r.y + 5, text, theme.fg[TokenClass.Text], bg)

proc insetRect(r: Rect; pad: int): Rect =
  rect(r.x + pad, r.y + pad, max(0, r.w - pad * 2), max(0, r.h - pad * 2))

proc readAppConfig(path: string; status: var string): AppConfig =
  var err = ""
  if loadConfig(path, result, err):
    if not fileExists(path):
      status = "Using default config"
  else:
    result = initAppConfig()
    status = "Config error: " & err

proc runApp*(configPath = "adaptive_ui.json";
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
    cfg,
    skills,
    status
  )
  if not state.agent.hasLiveConfig():
    state.status = state.agent.lastStatus & ". Set OPENAI_API_KEY for generated UI."
    state.doc = flowIntroDoc(lfAdaptive)

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

    state.pollAgent()
    fillRect(rect(0, 0, state.width, state.height), state.theme.scrollTrackColor)

    let adaptiveEvent = if state.focus == afAdaptive: e else: default Event
    let ev = renderUiDoc(state.doc, state.rt, adaptiveEvent,
      cells["adaptive"], font, fm, state.theme)
    state.handleUiEvent(ev)

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
