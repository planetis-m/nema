import ./[components, ui_doc]

type
  QuizPhase* = enum
    qpAnswering,
    qpFeedback,
    qpDone

  QuizQuestion* = object
    prompt*: string
    options*: seq[UiOption]
    correct*: string
    explanation*: string

  LearningState* = object
    questions*: seq[QuizQuestion]
    questionIndex*: int
    answers*: seq[string]
    score*: int
    phase*: QuizPhase
    doc*: UiDoc
    status*: string

proc makeDefaultQuestions*(): seq[QuizQuestion] =
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

proc answerArea(): UiArea =
  UiArea(name: "choices", kind: ukRadio, id: "answer")

proc reset*(state: var LearningState) =
  state.questionIndex = 0
  state.answers.setLen 0
  state.score = 0
  state.phase = qpAnswering
  state.doc = questionDoc(state.questions[0], 0, state.questions.len)
  state.status = "Local quiz mode"

proc initLearningState*(questions: sink seq[QuizQuestion]): LearningState =
  result.questions = questions
  result.reset()

proc initLearningState*(): LearningState =
  initLearningState(makeDefaultQuestions())

proc handleLearningEvent*(state: var LearningState; rt: var UiRuntime;
    ev: UiEvent) =
  case ev.kind
  of ueNone:
    discard
  of ueSelect:
    state.status = "Selected " & ev.value
  of ueClick:
    case ev.id
    of "submit":
      let selected = rt.selectedOption(answerArea())
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
      state.reset()
      rt = initUiRuntime()
    else:
      state.status = "Clicked " & ev.id
  of ueSubmitText:
    state.status = "Submitted " & $ev.value.len & " characters"
