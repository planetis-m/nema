import std/strutils
import adaptive_ui/[live_flow, ui_doc]

block commands:
  doAssert parseLiveCommand("hello").kind == lcNone
  doAssert parseLiveCommand("/chat").kind == lcChat
  doAssert parseLiveCommand("/quiz nim basics").kind == lcQuiz
  doAssert parseLiveCommand("/quiz nim basics").text == "nim basics"
  doAssert parseLiveCommand(" /essay compare ARC and ORC ").kind == lcEssay
  doAssert parseLiveCommand(" /essay compare ARC and ORC ").text == "compare ARC and ORC"

block flowMapping:
  doAssert flowForCommand(lcChat) == lfChat
  doAssert flowForCommand(lcQuiz) == lfQuiz
  doAssert flowForCommand(lcEssay) == lfEssay
  doAssert flowTitle(lfQuiz) == "Quiz"

block prompts:
  doAssert flowPrompt(lfChat, "hello") == "hello"
  doAssert "one question at a time" in flowPrompt(lfQuiz, "nim")
  doAssert "User input:\nnim" in flowPrompt(lfQuiz, "nim")
  doAssert "rubric" in flowPrompt(lfEssay, "history")

block uiHints:
  doAssert "normal chat" in uiFlowHint(lfChat)
  doAssert "radio area" in uiFlowHint(lfQuiz)
  doAssert "textInput" in uiFlowHint(lfEssay)

block introDocs:
  let doc = flowIntroDoc(lfEssay)
  doAssert doc.version == 1
  doAssert doc.title == "Essay"
  doAssert doc.areas.len == 1
  doAssert doc.areas[0].kind == ukText
