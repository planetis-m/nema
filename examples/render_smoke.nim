import adaptive_ui
import uirelays
import uirelays/backend
import widgets/theme

const QuizDoc = UiDoc(
  version: 1,
  title: "Quiz",
  layout: """
| title, 2 lines |
| prompt, * |
| choices, 7 lines |
| actions, 2 lines |
""",
  focus: "choices",
  areas: @[
    UiArea(
      name: "title",
      kind: ukText,
      text: "Question 1 of 3"
    ),
    UiArea(
      name: "prompt",
      kind: ukText,
      text: "Which keyword declares an immutable local binding in Nim?"
    ),
    UiArea(
      name: "choices",
      kind: ukRadio,
      id: "q1_answer",
      options: @[
        UiOption(id: "a", label: "var"),
        UiOption(id: "b", label: "let"),
        UiOption(id: "c", label: "type")
      ]
    ),
    UiArea(
      name: "actions",
      kind: ukButtons,
      id: "q1_actions",
      options: @[UiOption(id: "submit", label: "Submit")]
    )
  ]
)

proc main =
  initBackend()
  let win = createWindow(900, 650)
  var width = win.width
  var height = win.height

  var fm: FontMetrics
  let font = openFont("", 16, fm)
  let theme = catppuccinMocha()
  setWindowTitle("Adaptive Renderer Smoke")

  var rt = initUiRuntime()
  var lastEvent = "No event"
  var running = true

  while running:
    var e = default Event
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = e.x
        height = e.y
      of KeyDownEvent:
        if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
          running = false
      else:
        discard

      let ev = renderUiDoc(QuizDoc, rt, e,
        rect(0, 0, width, max(0, height - 28)), font, fm, theme)
      case ev.kind
      of ueNone:
        discard
      of ueSelect:
        lastEvent = "Selected " & ev.value
      of ueClick:
        lastEvent = "Clicked " & ev.id
      of ueSubmitText:
        lastEvent = "Submitted " & $ev.value.len & " chars"

    discard renderUiDoc(QuizDoc, rt, default Event,
      rect(0, 0, width, max(0, height - 28)), font, fm, theme)
    fillRect(rect(0, max(0, height - 28), width, 28), theme.scrollTrackColor)
    discard drawText(font, 8, max(0, height - 23),
      lastEvent, theme.fg[TokenClass.Text], theme.scrollTrackColor)

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

when isMainModule:
  main()
