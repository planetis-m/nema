import adaptive_ui/[components, learning, ui_doc]

proc click(id: string): UiEvent =
  UiEvent(kind: ueClick, area: "actions", id: id)

let answerArea = UiArea(name: "choices", kind: ukRadio, id: "answer")

block:
  var state = initLearningState()
  var rt = initUiRuntime()

  doAssert state.phase == qpAnswering
  doAssert state.doc.title == "Local Quiz"
  doAssert state.questionIndex == 0
  doAssert state.score == 0

  state.handleLearningEvent(rt, click("submit"))
  doAssert state.phase == qpAnswering
  doAssert state.status == "Choose an answer first"

  rt.setSelected(answerArea, "b")
  state.handleLearningEvent(rt, click("submit"))
  doAssert state.phase == qpFeedback
  doAssert state.score == 1
  doAssert state.answers == @["b"]
  doAssert state.status == "Correct"
  doAssert state.doc.title == "Feedback"

  state.handleLearningEvent(rt, click("next"))
  doAssert state.phase == qpAnswering
  doAssert state.questionIndex == 1
  doAssert state.doc.title == "Local Quiz"

  rt.setSelected(answerArea, "a")
  state.handleLearningEvent(rt, click("submit"))
  doAssert state.phase == qpFeedback
  doAssert state.score == 1
  doAssert state.answers == @["b", "a"]
  doAssert state.status == "Review the feedback"

block:
  var state = initLearningState()
  var rt = initUiRuntime()

  for q in 0 ..< state.questions.len:
    rt.setSelected(answerArea, state.questions[q].correct)
    state.handleLearningEvent(rt, click("submit"))
    if q + 1 < state.questions.len:
      state.handleLearningEvent(rt, click("next"))
    else:
      state.handleLearningEvent(rt, click("finish"))

  doAssert state.phase == qpDone
  doAssert state.score == state.questions.len
  doAssert state.doc.title == "Score"

  state.handleLearningEvent(rt, click("restart"))
  doAssert state.phase == qpAnswering
  doAssert state.questionIndex == 0
  doAssert state.score == 0
  doAssert state.answers.len == 0
