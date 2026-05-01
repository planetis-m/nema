import std/strutils
import adaptive_ui/[agent, transcript, ui_doc]

block empty:
  doAssert formatTranscript([]) == "No messages yet."

block format:
  let history = @[
    ChatEntry(role: arUser, content: " Make a plan. "),
    ChatEntry(role: arAssistant, content: "Question 1")
  ]
  let text = formatTranscript(history)
  doAssert text.startsWith("User:\nMake a plan.")
  doAssert "\n\nAssistant:\nQuestion 1" in text

block uiDoc:
  let doc = transcriptUiDoc(@[
    ChatEntry(role: arUser, content: "hello")
  ])
  doAssert doc.version == 1
  doAssert doc.title == "Transcript"
  doAssert "utility_actions" in doc.layout
  doAssert doc.focus == "transcript"
  doAssert doc.areas.len == 2
  doAssert doc.areas[0].kind == ukTranscript
  doAssert doc.areas[1].kind == ukButtons
  doAssert doc.areas[1].options[0].id == "back"
  doAssert "User:" in doc.areas[0].text
