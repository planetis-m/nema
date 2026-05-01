import std/strutils
import ./ui_doc

type
  LiveCommandKind* = enum
    lcNone,
    lcNew,
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
| guide, * |
""",
    areas: @[
      UiArea(
        name: "title",
        kind: ukText,
        text: "Adaptive UI"
      ),
      UiArea(
        name: "guide",
        kind: ukText,
        text: "Type what you want in the input box below, then press Ctrl+Enter. The screen will adapt when the response is ready. Use /new to start over."
      )
    ],
    focus: "guide"
  )
