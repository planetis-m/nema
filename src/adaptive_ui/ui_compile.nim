import ./[turn_view, ui_doc]

proc textArea(name, text: string): UiArea =
  UiArea(name: name, kind: ukText, text: text)

proc submitArea(): UiArea =
  UiArea(
    name: "actions",
    kind: ukButtons,
    id: "actions",
    options: @[UiOption(id: "submit", label: "Submit")]
  )

proc titleFor(command: UiCommand): string =
  if command.title.len > 0:
    result = command.title
  else:
    result = "Assistant"

proc promptText(visible: string; command: UiCommand): string =
  result = visible.strip()
  if command.prompt.len > 0:
    if result.len > 0:
      result.add "\n\n"
    result.add command.prompt
  if result.len == 0:
    result = command.titleFor()

proc compileChoice(visible: string; command: UiCommand): UiDoc =
  result = UiDoc(
    version: 1,
    title: command.titleFor(),
    layout: "| prompt, * |\n| choices, 7 lines |\n| actions, 2 lines |",
    areas: @[
      textArea("prompt", promptText(visible, command)),
      UiArea(name: "choices", kind: ukRadio, id: "choice", options: @[]),
      submitArea()
    ],
    focus: "choices"
  )
  for option in command.options:
    result.areas[1].options.add UiOption(id: option.id, label: option.label)

proc compileInput(visible: string; command: UiCommand): UiDoc =
  result = UiDoc(
    version: 1,
    title: command.titleFor(),
    layout: "| prompt, * |\n| input, 4 lines |",
    areas: @[
      textArea("prompt", promptText(visible, command)),
      UiArea(
        name: "input",
        kind: ukTextInput,
        id: "input",
        placeholder: command.placeholder,
        submitLabel: "Submit"
      )
    ],
    focus: "input"
  )

proc compileUiCommand*(visible: string; command: UiCommand): UiDoc =
  case command.kind
  of uckChoice:
    if command.options.len >= 2:
      result = compileChoice(visible, command)
    else:
      result = textUiDoc(command.titleFor(), visible)
  of uckInput:
    result = compileInput(visible, command)
  of uckNone:
    result = textUiDoc(command.titleFor(), visible)

