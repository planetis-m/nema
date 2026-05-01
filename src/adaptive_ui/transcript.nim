import std/strutils
import ./[agent, ui_doc]

proc roleLabel(role: AgentRole): string =
  case role
  of amUser:
    "User"
  of amAssistant:
    "Assistant"

proc formatTranscript*(history: openArray[AgentMessage]): string =
  if history.len == 0:
    return "No messages yet."

  for msg in history:
    if result.len > 0:
      result.add "\n\n"
    result.add roleLabel(msg.role)
    result.add ":\n"
    result.add msg.content.strip()

proc transcriptUiDoc*(history: openArray[AgentMessage];
    title = "Transcript"): UiDoc =
  UiDoc(
    version: 1,
    title: title,
    layout: "| transcript, * |",
    areas: @[
      UiArea(
        name: "transcript",
        kind: ukTranscript,
        text: formatTranscript(history)
      )
    ],
    focus: "transcript"
  )
