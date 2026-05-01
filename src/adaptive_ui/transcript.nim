import std/strutils
import ./[agent, ui_doc]

proc roleLabel(role: AgentRole): string =
  case role
  of arUser:
    "User"
  of arAssistant:
    "Assistant"

proc formatTranscript*(history: openArray[ChatEntry]): string =
  if history.len == 0:
    return "No messages yet."

  for entry in history:
    if result.len > 0:
      result.add "\n\n"
    result.add roleLabel(entry.role)
    result.add ":\n"
    result.add entry.content.strip()

proc transcriptUiDoc*(history: openArray[ChatEntry];
    title = "Transcript"): UiDoc =
  UiDoc(
    version: 1,
    title: title,
    layout: """
| transcript, * |
| utility_actions, 3 lines |
""",
    areas: @[
      UiArea(
        name: "transcript",
        kind: ukTranscript,
        text: formatTranscript(history)
      ),
      UiArea(
        name: "utility_actions",
        kind: ukButtons,
        id: "utility_actions",
        options: @[UiOption(id: "back", label: "Back")]
      )
    ],
    focus: "transcript"  )
