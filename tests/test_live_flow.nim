import std/strutils
import adaptive_ui/[live_flow, ui_doc]

block commands:
  doAssert parseLiveCommand("hello").kind == lcNone
  doAssert parseLiveCommand("/adaptive").kind == lcAdaptive
  doAssert parseLiveCommand("/adaptive plan a trip").text == "plan a trip"
  doAssert parseLiveCommand("/chat").kind == lcChat
  doAssert parseLiveCommand("/quiz nim basics").kind == lcQuiz
  doAssert parseLiveCommand("/quiz nim basics").text == "nim basics"
  doAssert parseLiveCommand(" /essay compare ARC and ORC ").kind == lcEssay
  doAssert parseLiveCommand(" /essay compare ARC and ORC ").text == "compare ARC and ORC"
  doAssert parseLiveCommand("/debug").kind == lcDebug

block flowMapping:
  doAssert flowForCommand(lcNone) == lfAdaptive
  doAssert flowForCommand(lcAdaptive) == lfAdaptive
  doAssert flowForCommand(lcChat) == lfChat
  doAssert flowForCommand(lcQuiz) == lfQuiz
  doAssert flowForCommand(lcEssay) == lfEssay
  doAssert flowForCommand(lcDebug) == lfAdaptive
  doAssert flowTitle(lfAdaptive) == "Adaptive"
  doAssert flowTitle(lfQuiz) == "Quiz"

block prompts:
  doAssert "Adaptive task mode" in flowPrompt(lfAdaptive, "plan")
  doAssert "Do not force the task into a quiz or essay" in flowPrompt(lfAdaptive, "plan")
  doAssert "User input:\nplan" in flowPrompt(lfAdaptive, "plan")
  doAssert "Normal chat mode" in flowPrompt(lfChat, "hello")
  doAssert "one question at a time" in flowPrompt(lfQuiz, "nim")
  doAssert "current UI values as the user's answer" in flowPrompt(lfQuiz, "Selected option")
  doAssert "option id and visible label" in flowPrompt(lfQuiz, "Selected option")
  doAssert "User input:\nnim" in flowPrompt(lfQuiz, "nim")
  doAssert "submitted text" in flowPrompt(lfEssay, "essay answer")
  doAssert "rubric" in flowPrompt(lfEssay, "history")

block uiHints:
  doAssert "adaptive task" in uiFlowHint(lfAdaptive)
  doAssert "Do not default to quiz or essay" in uiFlowHint(lfAdaptive)
  doAssert "normal chat" in uiFlowHint(lfChat)
  doAssert "radio area" in uiFlowHint(lfQuiz)
  doAssert "stable" in uiFlowHint(lfQuiz)
  doAssert "textInput" in uiFlowHint(lfEssay)
  doAssert "submitLabel" in uiFlowHint(lfEssay)

block introDocs:
  let adaptiveDoc = flowIntroDoc(lfAdaptive)
  doAssert adaptiveDoc.title == "Adaptive UI"
  doAssert adaptiveDoc.areas.len == 4
  doAssert adaptiveDoc.areas[3].kind == ukButtons

  let doc = flowIntroDoc(lfEssay)
  doAssert doc.version == 1
  doAssert doc.title == "Essay"
  doAssert doc.areas.len == 1
  doAssert doc.areas[0].kind == ukText
