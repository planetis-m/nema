import std/tables
import adaptive_ui/[components, ui_doc]

let radio = UiArea(
  name: "choices",
  kind: ukRadio,
  id: "q1_answer",
  options: @[
    UiOption(id: "a", label: "var"),
    UiOption(id: "b", label: "let", selected: true),
    UiOption(id: "c", label: "type")
  ]
)

let buttons = UiArea(
  name: "actions",
  kind: ukButtons,
  id: "q1_actions",
  options: @[
    UiOption(id: "submit", label: "Submit")
  ]
)

let essay = UiArea(
  name: "answer",
  kind: ukTextInput,
  id: "essay_response"
)

block:
  doAssert componentKey(radio) == "q1_answer"
  doAssert componentKey(UiArea(name: "main", kind: ukText)) == "main"

block:
  var rt = initUiRuntime()
  doAssert rt.selectedOption(radio) == "b"
  rt.setSelected(radio, "c")
  doAssert rt.selectedOption(radio) == "c"

  let sameControlMoved = UiArea(
    name: "other_choices",
    kind: ukRadio,
    id: "q1_answer",
    options: radio.options
  )
  doAssert rt.selectedOption(sameControlMoved) == "c"

block:
  var rt = initUiRuntime()
  rt.setText(essay, "Nim uses let for immutable bindings.")
  doAssert rt.textValue(essay) == "Nim uses let for immutable bindings."

block:
  var rt = initUiRuntime()
  rt.setFocus("choices")
  doAssert rt.focus == "choices"
  doAssert rt.components["choices"].focused
  rt.setFocus("answer")
  doAssert rt.focus == "answer"
  doAssert not rt.components["choices"].focused
  doAssert rt.components["answer"].focused

block:
  let ev = eventForSelect(radio, "a")
  doAssert ev.kind == ueSelect
  doAssert ev.area == "choices"
  doAssert ev.id == "q1_answer"
  doAssert ev.value == "a"

block:
  let ev = eventForClick(buttons, "submit")
  doAssert ev.kind == ueClick
  doAssert ev.area == "actions"
  doAssert ev.id == "submit"
  doAssert ev.value == ""

block:
  let ev = eventForSubmit(essay, "hello")
  doAssert ev.kind == ueSubmitText
  doAssert ev.area == "answer"
  doAssert ev.id == "essay_response"
  doAssert ev.value == "hello"
