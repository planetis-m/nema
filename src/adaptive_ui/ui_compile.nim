import std/[strutils]
import jsonx
import ./[turn_view, ui_doc, ui_parse]

proc validId(text, fallback: string): string =
  for ch in text.toLowerAscii():
    if ch.isAlphaNumeric:
      result.add ch
    elif ch in {' ', '-', '_'} and result.len > 0 and result[^1] != '_':
      result.add '_'
  result = result.strip(chars = {'_'})
  if result.len == 0:
    result = fallback

proc textArea(name, text: string): UiArea =
  UiArea(name: name, kind: ukText, text: text)

proc submitArea(): UiArea =
  UiArea(
    name: "actions",
    kind: ukButtons,
    id: "actions",
    options: @[UiOption(id: "submit", label: "Submit")]
  )

proc compileChoice(view: TurnView): UiDoc =
  let promptText =
    if view.body.len > 0: view.body & "\n\n" & view.actionPrompt
    else: view.actionPrompt
  result = UiDoc(
    version: 1,
    title: view.title,
    layout: "| prompt, * |\n| choices, 7 lines |\n| actions, 2 lines |",
    areas: @[
      textArea("prompt", promptText),
      UiArea(
        name: "choices",
        kind: ukRadio,
        id: view.actionPrompt.validId("choice"),
        options: @[]
      ),
      submitArea()
    ],
    focus: "choices"
  )
  for option in view.options:
    result.areas[1].options.add UiOption(id: option.id, label: option.label)

proc compileType(view: TurnView): UiDoc =
  let promptText =
    if view.body.len > 0: view.body
    else: view.actionPrompt
  result = UiDoc(
    version: 1,
    title: view.title,
    layout: "| prompt, * |\n| input, 4 lines |",
    areas: @[
      textArea("prompt", promptText),
      UiArea(
        name: "input",
        kind: ukTextInput,
        id: view.actionPrompt.validId("input"),
        placeholder: view.actionPrompt,
        submitLabel: "Submit"
      )
    ],
    focus: "input"
  )

proc compileContent(view: TurnView): UiDoc =
  let text =
    if view.body.len > 0: view.body
    elif view.actionPrompt.len > 0: view.actionPrompt
    else: view.title
  UiDoc(
    version: 1,
    title: view.title,
    layout: "| content, * |",
    areas: @[textArea("content", text)],
    focus: "content"
  )

proc compileUiDoc*(view: TurnView): UiDoc =
  case view.actionKind
  of takChoose:
    if view.options.len >= 2:
      result = compileChoice(view)
    else:
      result = compileType(view)
  of takType:
    result = compileType(view)
  of takNone:
    result = compileContent(view)

  var ignored: UiDoc
  var err = ""
  if not parseUiDoc(toJson(result), ignored, err):
    raise newException(ValueError, "compiled invalid UI document: " & err)
