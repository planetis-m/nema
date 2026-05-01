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
  elif lowered == "/transcript" or lowered == "/conversation":
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

proc fingerprint(text: string): string =
  var value = 0
  for ch in text:
    value = (value * 33 + ord(ch)) mod 100000
  result = $value

proc nextAction(text: string): string =
  for line in text.splitLines:
    let trimmed = line.strip()
    if trimmed.toLowerAscii().startsWith("next action:"):
      return trimmed[12 .. ^1].strip().toLowerAscii()
  result = "none"

proc optionLabel(line: string): string =
  result = line.strip()
  if result.startsWith("- ") or result.startsWith("* "):
    result = result[2 .. ^1].strip()
  elif result.len > 2 and result[0].isAlphaNumeric and result[1] in {')', '.', ':'}:
    result = result[2 .. ^1].strip()

proc choiceOptions(text: string): seq[UiOption] =
  var inOptions = false
  var index = 0
  for line in text.splitLines:
    let trimmed = line.strip()
    let lowered = trimmed.toLowerAscii()
    if lowered == "options:" or lowered.startsWith("options:"):
      inOptions = true
      let inline = trimmed[8 .. ^1].strip()
      if inline.len > 0:
        inc index
        result.add UiOption(id: "choice_" & $index, label: inline)
    elif inOptions and trimmed.len > 0:
      if lowered.startsWith("next action:"):
        inOptions = false
      else:
        let label = optionLabel(trimmed)
        if label.len > 0:
          inc index
          result.add UiOption(id: "choice_" & $index, label: label)

proc cleanResponseText(text: string): string =
  var skipOptions = false
  for line in text.splitLines:
    let trimmed = line.strip()
    let lowered = trimmed.toLowerAscii()
    if lowered.startsWith("next action:"):
      discard
    elif lowered == "options:" or lowered.startsWith("options:"):
      skipOptions = true
    elif skipOptions and trimmed.len > 0:
      discard
    else:
      skipOptions = false
      if result.len > 0:
        result.add "\n"
      result.add line

  result = result.strip()

proc responseUiDoc*(assistantText: string): UiDoc =
  let action = nextAction(assistantText)
  var prompt = cleanResponseText(assistantText)
  if prompt.len == 0:
    prompt = assistantText.strip()
  let idSuffix = fingerprint(assistantText)

  if "choose" in action:
    let options = choiceOptions(assistantText)
    if options.len > 0:
      return UiDoc(
        version: 1,
        title: "Response",
        layout: """
| prompt, * |
| choices, 8 lines |
| actions, 3 lines |
""",
        areas: @[
          UiArea(name: "prompt", kind: ukText, text: prompt),
          UiArea(
            name: "choices",
            kind: ukRadio,
            id: "choice_" & idSuffix,
            options: options
          ),
          UiArea(
            name: "actions",
            kind: ukButtons,
            id: "actions_" & idSuffix,
            options: @[UiOption(id: "submit", label: "Submit")]
          )
        ],
        focus: "choices"
      )

  if "type" in action:
    return UiDoc(
      version: 1,
      title: "Response",
      layout: """
| prompt, * |
| answer, 5 lines |
""",
      areas: @[
        UiArea(name: "prompt", kind: ukText, text: prompt),
        UiArea(
          name: "answer",
          kind: ukTextInput,
          id: "answer_" & idSuffix,
          placeholder: "Type your answer here.",
          submitLabel: "Send"
        )
      ],
      focus: "answer"
    )

  textUiDoc("Response", prompt)

