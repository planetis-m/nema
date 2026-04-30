import adaptive_ui
import uirelays
import uirelays/backend
import widgets/theme

const GalleryDoc = UiDoc(
  version: 1,
  title: "Adaptive Gallery",
  layout: """
| title, 2 lines |
| notes, * | code, * |
| choice, 6 lines | answer, 6 lines |
| math, 3 lines |
| actions, 2 lines |
""",
  focus: "choice",
  areas: @[
    UiArea(
      name: "title",
      kind: ukText,
      text: "Adaptive UI gallery"
    ),
    UiArea(
      name: "notes",
      kind: ukText,
      text: "This document exercises the first supported component set.\n\n- text\n- code\n- radio\n- text input\n- math\n- buttons"
    ),
    UiArea(
      name: "code",
      kind: ukCode,
      language: "nim",
      text: "proc greet(name: string) =\n  echo \"Hello, \" & name"
    ),
    UiArea(
      name: "choice",
      kind: ukRadio,
      id: "sample_choice",
      options: @[
        UiOption(id: "notes", label: "Study notes"),
        UiOption(id: "quiz", label: "Quiz"),
        UiOption(id: "essay", label: "Essay")
      ]
    ),
    UiArea(
      name: "answer",
      kind: ukTextInput,
      id: "sample_answer",
      text: "Type here. Ctrl+Enter submits."
    ),
    UiArea(
      name: "math",
      kind: ukMath,
      text: "Basic math text: x^2 + y^2 = z^2"
    ),
    UiArea(
      name: "actions",
      kind: ukButtons,
      id: "gallery_actions",
      options: @[
        UiOption(id: "primary", label: "Primary"),
        UiOption(id: "secondary", label: "Secondary")
      ]
    )
  ]
)

proc main =
  initBackend()
  let win = createWindow(1000, 720)
  var width = win.width
  var height = win.height

  var fm: FontMetrics
  let font = openFont("", 16, fm)
  let theme = catppuccinMocha()
  setWindowTitle("Adaptive UI Gallery")

  var rt = initUiRuntime()
  var status = "Interact with the generated document"
  var running = true

  while running:
    var e = default Event
    discard waitEvent(e, 16, {WantTextInput})
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

    fillRect(rect(0, 0, width, height), theme.scrollTrackColor)
    let ev = renderUiDoc(GalleryDoc, rt, e,
      rect(0, 0, width, max(0, height - 28)), font, fm, theme)
    case ev.kind
    of ueNone:
      discard
    of ueSelect:
      status = "Selected " & ev.value
    of ueClick:
      status = "Clicked " & ev.id
    of ueSubmitText:
      status = "Submitted " & $ev.value.len & " characters"

    fillRect(rect(0, max(0, height - 28), width, 28), theme.scrollTrackColor)
    discard drawText(font, 8, max(0, height - 23),
      status, theme.fg[TokenClass.Text], theme.scrollTrackColor)
    refresh()

  closeFont(font)
  shutdown()

when isMainModule:
  main()
