import std/tables
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[components, learning, ui_render]

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
    learning: LearningState
    theme: Theme

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

proc initAppState(width, height: int; font: Font; theme: Theme): AppState =
  result.width = width
  result.height = height
  result.outerLayout = parseLayout(OuterLayoutSpec)
  result.rt = initUiRuntime()
  result.input = createSynEdit(font, theme)
  result.input.lang = langNone
  result.focus = afAdaptive
  result.learning = initLearningState()
  result.theme = theme

proc inputEvent(state: var AppState; e: Event): Event =
  result = e
  if state.focus == afInput and e.kind == KeyDownEvent and
      e.key == KeyEnter and (CtrlPressed in e.mods or GuiPressed in e.mods):
    let text = state.input.fullText
    if text.len > 0:
      state.learning.status = "Input captured: " & $text.len & " characters"
      state.input.clear()
    result = default Event

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

  var state = initAppState(win.width, win.height, font, theme)
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
    let ev = renderUiDoc(state.learning.doc, state.rt, adaptiveEvent,
      cells["adaptive"], font, fm, state.theme)
    state.learning.handleLearningEvent(state.rt, ev)

    let inputDrawEvent = state.inputEvent(if state.focus == afInput: e else: default Event)
    fillRect(cells["input"], state.theme.bg)
    discard state.input.draw(inputDrawEvent, cells["input"].insetRect(8),
      state.focus == afInput)

    drawStatus(font, cells["status"], state.learning.status, state.theme)

    refresh()

  closeFont(font)
  shutdown()
