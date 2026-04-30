import std/tables
import uirelays
import uirelays/backend
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[components, ui_doc, ui_render]

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

  QuizPhase = enum
    qpAnswering,
    qpFeedback,
    qpDone

  QuizQuestion = object
    prompt: string
    options: seq[UiOption]
    correct: string
    explanation: string

  AppState = object
    width, height: int
    outerLayout: Layout
    doc: UiDoc
    rt: UiRuntime
    input: SynEdit
    status: string
    focus: AppFocus
    questions: seq[QuizQuestion]
    questionIndex: int
    answers: seq[string]
    score: int
    phase: QuizPhase
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

proc makeQuestions(): seq[QuizQuestion] =
  @[
    QuizQuestion(
      prompt: "Which keyword declares an immutable local binding in Nim?",
      options: @[
        UiOption(id: "a", label: "var"),
        UiOption(id: "b", label: "let"),
        UiOption(id: "c", label: "type")
      ],
      correct: "b",
      explanation: "`let` creates an immutable local binding."
    ),
    QuizQuestion(
      prompt: "Which module should this project use for typed JSON mapping?",
      options: @[
        UiOption(id: "a", label: "std/json"),
        UiOption(id: "b", label: "jsonx"),
        UiOption(id: "c", label: "parseopt")
      ],
      correct: "b",
      explanation: "`jsonx` maps JSON directly to Nim objects."
    ),
    QuizQuestion(
      prompt: "Which uirelays module parses markdown table layouts?",
      options: @[
        UiOption(id: "a", label: "uirelays/layout"),
        UiOption(id: "b", label: "widgets/theme"),
        UiOption(id: "c", label: "relay/http")
      ],
      correct: "a",
      explanation: "`uirelays/layout` provides `parseLayout` and `resolve`."
    )
  ]

proc questionDoc(q: QuizQuestion; index, total: int): UiDoc =
  UiDoc(
    version: 1,
    title: "Local Quiz",
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
        text: "Question " & $(index + 1) & " of " & $total
      ),
      UiArea(
        name: "prompt",
        kind: ukText,
        text: q.prompt
      ),
      UiArea(
        name: "choices",
        kind: ukRadio,
        id: "answer",
        options: q.options
      ),
      UiArea(
        name: "actions",
        kind: ukButtons,
        id: "question_actions",
        options: @[UiOption(id: "submit", label: "Submit")]
      )
    ]
  )

proc feedbackDoc(q: QuizQuestion; selected: string; correct: bool;
    index, total: int): UiDoc =
  let resultText =
    if correct:
      "Correct.\n\n" & q.explanation
    else:
      "Not quite. You selected `" & selected & "`.\n\n" & q.explanation
  let button =
    if index + 1 < total:
      UiOption(id: "next", label: "Next")
    else:
      UiOption(id: "finish", label: "Finish")

  UiDoc(
    version: 1,
    title: "Feedback",
    layout: """
| title, 2 lines |
| result, * |
| actions, 2 lines |
""",
    focus: "actions",
    areas: @[
      UiArea(
        name: "title",
        kind: ukText,
        text: "Question " & $(index + 1) & " feedback"
      ),
      UiArea(
        name: "result",
        kind: ukText,
        text: resultText
      ),
      UiArea(
        name: "actions",
        kind: ukButtons,
        id: "feedback_actions",
        options: @[button]
      )
    ]
  )

proc scoreDoc(questions: seq[QuizQuestion]; answers: seq[string];
    score: int): UiDoc =
  var text = "Score: " & $score & " / " & $questions.len & "\n\n"
  for i, q in questions:
    let selected = if i < answers.len: answers[i] else: ""
    text.add $(i + 1) & ". Correct answer: `" & q.correct & "`"
    if selected.len > 0:
      text.add "  Selected: `" & selected & "`"
    text.add "\n"

  UiDoc(
    version: 1,
    title: "Score",
    layout: """
| title, 2 lines |
| summary, * |
| actions, 2 lines |
""",
    focus: "actions",
    areas: @[
      UiArea(name: "title", kind: ukText, text: "Quiz complete"),
      UiArea(name: "summary", kind: ukText, text: text),
      UiArea(
        name: "actions",
        kind: ukButtons,
        id: "score_actions",
        options: @[UiOption(id: "restart", label: "Restart")]
      )
    ]
  )

proc resetQuiz(state: var AppState) =
  state.rt = initUiRuntime()
  state.questionIndex = 0
  state.answers.setLen 0
  state.score = 0
  state.phase = qpAnswering
  state.doc = questionDoc(state.questions[0], 0, state.questions.len)
  state.status = "Local quiz mode"
  state.focus = afAdaptive

proc initAppState(width, height: int; font: Font; theme: Theme): AppState =
  result.width = width
  result.height = height
  result.outerLayout = parseLayout(OuterLayoutSpec)
  result.rt = initUiRuntime()
  result.input = createSynEdit(font, theme)
  result.input.lang = langNone
  result.status = "Local quiz mode"
  result.focus = afAdaptive
  result.questions = makeQuestions()
  result.theme = theme
  result.resetQuiz()

proc selectedAnswer(state: UiRuntime): string =
  state.selectedOption(UiArea(name: "choices", kind: ukRadio, id: "answer"))

proc handleAdaptiveEvent(state: var AppState; ev: UiEvent) =
  case ev.kind
  of ueNone:
    discard
  of ueSelect:
    state.status = "Selected " & ev.value
  of ueClick:
    case ev.id
    of "submit":
      let selected = state.rt.selectedAnswer()
      if selected.len == 0:
        state.status = "Choose an answer first"
        return

      let q = state.questions[state.questionIndex]
      let correct = selected == q.correct
      state.answers.add selected
      if correct:
        inc state.score
      state.phase = qpFeedback
      state.doc = feedbackDoc(q, selected, correct,
        state.questionIndex, state.questions.len)
      state.status = if correct: "Correct" else: "Review the feedback"
    of "next":
      inc state.questionIndex
      state.phase = qpAnswering
      state.doc = questionDoc(
        state.questions[state.questionIndex],
        state.questionIndex,
        state.questions.len
      )
      state.status = "Question " & $(state.questionIndex + 1)
    of "finish":
      state.phase = qpDone
      state.doc = scoreDoc(state.questions, state.answers, state.score)
      state.status = "Quiz complete"
    of "restart":
      state.resetQuiz()
    else:
      state.status = "Clicked " & ev.id
  of ueSubmitText:
    state.status = "Submitted " & $ev.value.len & " characters"

proc inputEvent(state: var AppState; e: Event): Event =
  result = e
  if state.focus == afInput and e.kind == KeyDownEvent and
      e.key == KeyEnter and (CtrlPressed in e.mods or GuiPressed in e.mods):
    let text = state.input.fullText
    if text.len > 0:
      state.status = "Input captured: " & $text.len & " characters"
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
    let ev = renderUiDoc(state.doc, state.rt, adaptiveEvent,
      cells["adaptive"], font, fm, state.theme)
    state.handleAdaptiveEvent(ev)

    let inputDrawEvent = state.inputEvent(if state.focus == afInput: e else: default Event)
    fillRect(cells["input"], state.theme.bg)
    discard state.input.draw(inputDrawEvent, cells["input"].insetRect(8),
      state.focus == afInput)

    drawStatus(font, cells["status"], state.status, state.theme)

    refresh()

  closeFont(font)
  shutdown()
