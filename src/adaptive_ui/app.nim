import std/[strutils, tables]
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[
  agent, components, config, interaction, live_flow,
  turn_extract, ui_compile, ui_doc, ui_render
]

const
  DefaultWindowWidth* = 900
  DefaultWindowHeight* = 600
  DefaultWindowTitle* = "Adaptive UI"
  InputPad = 8
  SendButtonWidth = 96
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
  else:
    result = ""

proc sendButtonRect(r: Rect): Rect =
  rect(
    r.x + max(0, r.w - SendButtonWidth - InputPad),
    r.y + InputPad,
    min(SendButtonWidth, max(0, r.w - InputPad * 2)),
    max(0, r.h - InputPad * 2)
  )

proc inputEditorRect(r: Rect): Rect =
  let button = sendButtonRect(r)
  rect(
    r.x + InputPad,
    r.y + InputPad,
    max(0, button.x - r.x - InputPad * 2),
    max(0, r.h - InputPad * 2)
  )

proc takeInputText(state: var AppState; submitted: var string) =
  let text = state.input.fullText
  if text.strip().len > 0:
    submitted = text
    state.input.clear()

proc isSendTrigger(focus: AppFocus; e: Event; r: Rect): bool =
  focus == afInput and (
    (e.kind == KeyDownEvent and e.key == KeyEnter and
      (CtrlPressed in e.mods or GuiPressed in e.mods)) or
    (e.kind == MouseDownEvent and e.button == LeftButton and
      sendButtonRect(r).contains(point(e.x, e.y))))

proc inputEvent(state: var AppState; e: Event; submitted: var string;
    r: Rect): Event =
  result = e
  if isSendTrigger(state.focus, e, r):
    state.takeInputText(submitted)
    result = default Event

proc drawRectBorder(r: Rect; c: Color) =
  if r.w > 0 and r.h > 0:
    drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
    drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
    drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1,
      r.y + r.h - 1, c)
    drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1,
      r.y + r.h - 1, c)

proc drawSendButton(font: Font; r: Rect; enabled: bool; theme: Theme) =
  let bg =
    if enabled: theme.selBg
    else: theme.scrollTrackColor
  let fg =
    if enabled: theme.fg[TokenClass.Text]
    else: theme.fg[TokenClass.Comment]
  fillRect(r, bg)
  drawRectBorder(r, theme.fg[TokenClass.Operator])
  let label = "Send"
  let size = measureText(font, label)
  discard drawText(font, r.x + max(4, (r.w - size.w) div 2),
    r.y + max(4, (r.h - fontLineSkip(font)) div 2),
    label, fg, bg)

proc replaceDoc(state: var AppState; doc: UiDoc) =
  state.doc = doc
  state.rt = initUiRuntime()

proc submitText(state: var AppState; text: string) =
  let err = state.agent.submitChat(text)
  if err.len > 0:
    state.status = err
  else:
    state.status = ""

proc startNewSession(state: var AppState) =
  state.agent.clearHistory()
  state.replaceDoc(introUiDoc())
  state.status = "New adaptive session"

proc handleSubmittedInput(state: var AppState; text: string) =
  let trimmed = text.strip()
  if trimmed.len == 0:
    return

  if isNewCommand(trimmed):
    state.startNewSession()
  else:
    state.submitText(trimmed)

proc handleUiEvent(state: var AppState; ev: UiEvent) =
  case ev.kind
  of ueNone:
    discard
  of ueSelect:
    state.status = "Selected " & ev.value
  of ueClick, ueSubmitText:
    state.submitText(uiEventText(state.doc, state.rt, ev))

proc pollAgent(state: var AppState) =
  var res: AgentResult
  while state.agent.poll(res):
    case res.kind
    of resError:
      state.status = res.error
    of resChatText:
      var visible = ""
      let command = uiCommandFromText(res.text, visible)
      state.replaceDoc(compileUiCommand(visible, command))
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
    of WindowResizeEvent:
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
    let inputDrawEvent = state.inputEvent(inputSourceEvent, submitted,
      cells["input"])
    fillRect(cells["input"], state.theme.bg)
    discard state.input.draw(inputDrawEvent, inputEditorRect(cells["input"]),
      state.focus == afInput)
    drawSendButton(font, sendButtonRect(cells["input"]),
      state.input.fullText.strip().len > 0, state.theme)
    state.handleSubmittedInput(submitted)

    drawStatus(font, cells["status"], state.currentStatus(), state.theme)
    refresh()

  state.close()
  closeFont(font)
  shutdown()
