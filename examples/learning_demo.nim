import std/[strutils, tables]
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import adaptive_ui/[components, learning, ui_doc, ui_render]

const
  OuterLayoutSpec = """
| adaptive, * |
| input, 4 lines |
| status, 1 line |
"""

type
  Focus = enum
    fAdaptive, fInput

  DemoState = object
    width, height: int
    outerLayout: Layout
    rt: UiRuntime
    input: SynEdit
    focus: Focus
    learning: LearningState
    theme: Theme

proc initDemoState(width, height: int; font: Font; theme: Theme): DemoState =
  result.width = width
  result.height = height
  result.outerLayout = parseLayout(OuterLayoutSpec)
  result.rt = initUiRuntime()
  result.input = createSynEdit(font, theme)
  result.input.lang = langNone
  result.focus = fAdaptive
  result.learning = initLearningState()
  result.theme = theme

proc drawStatus(font: Font; r: Rect; text: string; theme: Theme) =
  let bg = theme.scrollTrackColor
  fillRect(r, bg)
  discard drawText(font, r.x + 8, r.y + 5, text, theme.fg[TokenClass.Text], bg)

proc insetRect(r: Rect; pad: int): Rect =
  rect(r.x + pad, r.y + pad, max(0, r.w - pad * 2), max(0, r.h - pad * 2))

proc main =
  initBackend()
  let win = createWindow(900, 600)
  var fm: FontMetrics
  let font = openFont("", 16, fm)
  let theme = catppuccinMocha()
  setWindowTitle("Adaptive UI Learning Demo")

  var state = initDemoState(win.width, win.height, font, theme)
  var running = true

  while running:
    let cells = state.outerLayout.resolve(
      state.width, state.height, fm.lineHeight, gap = 2)
    let inputFlags =
      if state.focus == fInput: {WantTextInput}
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
        state.focus = fInput
      elif cells["adaptive"].contains(point(e.x, e.y)):
        state.focus = fAdaptive
    of KeyDownEvent:
      if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
        running = false
    else:
      discard

    fillRect(rect(0, 0, state.width, state.height), theme.scrollTrackColor)

    let adaptiveEvent = if state.focus == fAdaptive: e else: default Event
    let ev = renderUiDoc(state.learning.doc, state.rt, adaptiveEvent,
      cells["adaptive"], font, fm, theme)
    state.learning.handleLearningEvent(state.rt, ev)

    var submitted = ""
    var inputDrawEvent = if state.focus == fInput: e else: default Event
    if state.focus == fInput and e.kind == KeyDownEvent and
        e.key == KeyEnter and (CtrlPressed in e.mods or GuiPressed in e.mods):
      let text = state.input.fullText
      if text.len > 0:
        submitted = text
        state.input.clear()
      inputDrawEvent = default Event

    fillRect(cells["input"], state.theme.bg)
    discard state.input.draw(inputDrawEvent, cells["input"].insetRect(8),
      state.focus == fInput)

    if submitted.strip().len > 0:
      state.learning.status = "Input captured: " & $submitted.len & " characters"

    drawStatus(font, cells["status"], state.learning.status, theme)
    refresh()

  closeFont(font)
  shutdown()

when isMainModule:
  main()
