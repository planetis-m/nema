import std/strutils
import adaptive_ui/[agent, transcript, ui_doc]

block empty:
  doAssert formatTranscript([]) == "No messages yet."

block format:
  let history = @[
    ChatEntry(role: arUser, content: " Make a quiz. "),
    ChatEntry(role: arAssistant, content: "Question 1")
  ]
  let text = formatTranscript(history)
  doAssert text.startsWith("User:\nMake a quiz.")
  doAssert "\n\nAssistant:\nQuestion 1" in text

block uiDoc:
  let doc = transcriptUiDoc(@[
    ChatEntry(role: arUser, content: "hello")
  ])
  doAssert doc.version == 1
  doAssert doc.title == "Transcript"
  doAssert doc.layout == "| transcript, * |"
  doAssert doc.focus == "transcript"
  doAssert doc.areas.len == 1
  doAssert doc.areas[0].kind == ukTranscript
  doAssert "User:" in doc.areas[0].text
