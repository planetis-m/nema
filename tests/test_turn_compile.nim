import adaptive_ui/[turn_extract, turn_view, ui_compile, ui_doc]

proc hasSubmit(doc: UiDoc): bool =
  for area in doc.areas:
    if area.kind == ukButtons:
      for option in area.options:
        if option.id == "submit" and option.label == "Submit":
          return true

proc hasInputSubmit(doc: UiDoc): bool =
  for area in doc.areas:
    if area.kind == ukTextInput and area.submitLabel == "Submit":
      return true

block splitBlock:
  var visible = ""
  let command = uiCommandFromText("""
Choose a region.

```ui
choice
title: Geography
prompt: Where is your nation located?
option: a | Island nation
option: b | Mountain realm
```
""", visible)
  doAssert visible == "Choose a region."
  doAssert command.kind == uckChoice
  doAssert command.title == "Geography"
  doAssert command.options.len == 2

block choiceDoc:
  var visible = ""
  let command = uiCommandFromText("""
Choose a government.

```ui
choice
title: Government
prompt: What rules your country?
option: a | Democracy
option: b | Monarchy
option: c | Military Junta
```
""", visible)
  let doc = compileUiCommand(visible, command)
  doAssert doc.title == "Government"
  doAssert doc.focus == "choices"
  doAssert hasSubmit(doc)
  doAssert doc.areas[1].options.len == 3

block inputDoc:
  var visible = ""
  let command = uiCommandFromText("""
Your nation is ready for a name.

```ui
input
title: Nation Name
prompt: What is your nation called?
placeholder: Valdoria
```
""", visible)
  let doc = compileUiCommand(visible, command)
  doAssert doc.title == "Nation Name"
  doAssert doc.focus == "input"
  doAssert hasInputSubmit(doc)

block malformedFallsBackToText:
  var visible = ""
  let command = uiCommandFromText("""
This is still readable.

```ui
choice
title: Broken
option: a | Only one option
```
""", visible)
  let doc = compileUiCommand(visible, command)
  doAssert doc.areas.len == 1
  doAssert doc.areas[0].kind == ukText
