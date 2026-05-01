import std/strutils
import ./ui_doc

type
  LiveCommandKind* = enum
    lcNone,
    lcNew,
    lcTranscript,
    lcDebug

  LiveCommand* = object
    kind*: LiveCommandKind
    text*: string

proc commandPayload(input, command: string): string =
  if input.len == command.len:
    result = ""
  else:
    result = input[command.len + 1 .. ^1].strip()

proc isCommand(input, command: string): bool =
  input == command or input.startsWith(command & " ")

proc parseLiveCommand*(input: string): LiveCommand =
  let trimmed = input.strip()
  let lowered = trimmed.toLowerAscii()
  if lowered.isCommand("/new"):
    result = LiveCommand(kind: lcNew, text: commandPayload(trimmed, "/new"))
  elif lowered == "/transcript":
    result = LiveCommand(kind: lcTranscript)
  elif lowered == "/debug":
    result = LiveCommand(kind: lcDebug)
  else:
    result = LiveCommand(kind: lcNone, text: trimmed)

proc introUiDoc*(): UiDoc =
  UiDoc(
    version: 1,
    title: "Adaptive UI",
    layout: """
| title, 2 lines |
| overview, * | contract, * |
| actions, 3 lines |
""",
    areas: @[
      UiArea(
        name: "title",
        kind: ukText,
        text: "Adaptive UI"
      ),
      UiArea(
        name: "overview",
        kind: ukText,
        text: "Submit a task. The model returns a complete UI document for the next screen."
      ),
      UiArea(
        name: "contract",
        kind: ukText,
        text: "The core renderer supports text, transcript, code, math, choices, buttons, and text input. Task-specific flows are expressed by generated UiDoc data, not built into the runtime."
      ),
      UiArea(
        name: "actions",
        kind: ukButtons,
        id: "intro_actions",
        options: @[
          UiOption(id: "new", label: "New session"),
          UiOption(id: "transcript", label: "Transcript"),
          UiOption(id: "debug", label: "Debug")
        ]
      )
    ],
    focus: "overview"
  )
