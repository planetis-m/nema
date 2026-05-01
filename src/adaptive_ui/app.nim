import std/[strutils, tables]
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[
  agent, components, config, debug_log, interaction, live_flow,
  ui_doc, ui_render
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
  AppFocus = enum
    afAdaptive,
    afInput

  AppState = object
    width, height: int
    outerLayout: Layout
    rt: UiRuntime
    input: SynEdit
    focus: AppFocus
    doc: UiDoc
    mainDoc: UiDoc
    debugLog: DebugLog
    status: string
    theme: Theme
    agent: AgentState

proc initAppState(width, height: int; font: Font; theme: Theme;
    cfg: AppConfig; status = ""): AppState =
  let initStatus =
    if status.len > 0: status
    elif cfg.hasKey(): "Agent ready"
    else: "Set apiKey in config or OPENAI_API_KEY."
  result = AppState(
    width: width,
    height: height,
    outerLayout: parseLayout(OuterLayoutSpec),
    rt: initUiRuntime(),
    input: createSynEdit(font, theme),
    focus: afAdaptive,
    doc: introUiDoc(),
    mainDoc: introUiDoc(),
    debugLog: initDebugLog(),
    status: initStatus,
    theme: theme,
    agent: initAgentState(cfg)
  )
  result.input.lang = langNone

proc close(state: var AppState) =
  state.agent.close()

proc currentStatus(state: AppState): string =
  if state.status.len > 0:
    result = state.status
  elif state.agent.hasPendingChat():
    result = "Working..."
  elif state.agent.hasPendingUi():
    result = "Designing the next screen..."
  else:
    result = ""

proc inputEvent(state: var AppState; e: Event; submitted: var string): Event =
  result = e
  if state.focus == afInput and e.kind == KeyDownEvent and
      e.key == KeyEnter and (CtrlPressed in e.mods or GuiPressed in e.mods):
    let text = state.input.fullText
    if text.len > 0:
      submitted = text
      state.input.clear()
    result = default Event

proc replaceDoc(state: var AppState; doc: UiDoc; rememberMain = true) =
  state.doc = doc
  if rememberMain:
    state.mainDoc = doc
  state.rt.focus = ""

proc submitText(state: var AppState; text: string) =
  let err = state.agent.submitChat(text)
  if err.len > 0:
    state.status = err
  else:
    state.status = ""

proc startNewSession(state: var AppState; text: string) =
  state.rt = initUiRuntime()
  state.agent.clearHistory()
  state.replaceDoc(introUiDoc())
  state.status = "New adaptive session"
  if text.strip().len > 0:
    state.submitText(text)

proc showDebugLog(state: var AppState) =
  state.replaceDoc(debugUiDoc(state.debugLog), rememberMain = false)
  state.status = "Diagnostics"

proc handleSubmittedInput(state: var AppState; text: string) =
  if text.strip().len == 0:
    return

  let cmd = parseLiveCommand(text)
  case cmd.kind
  of lcNone:
    state.submitText(cmd.text)
  of lcNew:
    state.startNewSession(cmd.text)
  of lcDebug:
    state.showDebugLog()

proc handleUiEvent(state: var AppState; ev: UiEvent) =
  case ev.kind
  of ueNone:
    discard
  of ueSelect:
    state.status = "Selected " & ev.value
  of ueClick, ueSubmitText:
    if ev.id == "back" and ev.area == "utility_actions":
      state.replaceDoc(state.mainDoc)
      state.status = ""
    else:
      state.submitText(uiEventText(state.doc, state.rt, ev))

proc pollAgent(state: var AppState) =
  var res: AgentResult
  while state.agent.poll(res):
    case res.kind
    of resError:
      state.status = res.error
      if res.text.len > 0:
        state.debugLog.addDebug(res.text)
    of resChatText:
      let err = state.agent.enqueueUi(state.mainDoc)
      if err.len > 0:
        state.status = err
      else:
        state.status = "Designing the next screen..."
    of resUiDoc:
      state.replaceDoc(res.doc)
      state.status = ""

proc drawStatus(font: Font; r: Rect; text: string; theme: Theme) =
  let bg = theme.scrollTrackColor
  fillRect(r, bg)
  discard drawText(font, r.x + 8, r.y + 5, text, theme.fg[TokenClass.Text], bg)

proc readAppConfig(path: string): AppConfig =
  try:
    result = loadConfig(path)
  except CatchableError as e:
    quit "Config error in " & path & ": " & e.msg, 1

proc runApp*(configPath = "adaptive_ui.json";
    title = DefaultWindowTitle; width = DefaultWindowWidth;
    height = DefaultWindowHeight) =
  initBackend()
  let win = createWindow(width, height)

  var fm: FontMetrics
  let font = openFont("", 16, fm)
  let theme = catppuccinMocha()
  setWindowTitle(title)

  let cfg = readAppConfig(configPath)
  var state = initAppState(
    win.width,
    win.height,
    font,
    theme,
    cfg
  )

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
    discard state.input.draw(inputDrawEvent, cells["input"].inset(8),
      state.focus == afInput)
    state.handleSubmittedInput(submitted)

    drawStatus(font, cells["status"], state.currentStatus(), state.theme)
    refresh()

  state.close()
  closeFont(font)
  shutdown()
