import std/strutils
import adaptive_ui/[components, interaction, ui_doc]

let doc = UiDoc(
  version: 1,
  title: "Question",
  layout: "| choices, * |\n| answer, 4 lines |\n| actions, 2 lines |",
  areas: @[
    UiArea(
      name: "choices",
      kind: ukRadio,
      id: "q1",
      options: @[
        UiOption(id: "a", label: "A"),
        UiOption(id: "b", label: "B")
      ]
    ),
    UiArea(
      name: "answer",
      kind: ukTextInput,
      id: "open_response"
    ),
    UiArea(
      name: "actions",
      kind: ukButtons,
      id: "buttons",
      options: @[UiOption(id: "submit", label: "Submit")]
    )
  ]
)

block findArea:
  var area: UiArea
  doAssert doc.findArea("choices", area)
  doAssert area.id == "q1"
  doAssert area.optionLabel("b") == "B"
  doAssert area.optionLabel("missing") == ""
  doAssert not doc.findArea("missing", area)

block valuesText:
  var rt = initUiRuntime()
  rt.setSelected(doc.areas[0], "b")
  rt.setText(doc.areas[1], "Open response")

  let values = uiValuesText(doc, rt)
  doAssert "- q1: b (B)" in values
  doAssert "- open_response: Open response" in values

block eventText:
  var rt = initUiRuntime()
  rt.setSelected(doc.areas[0], "a")

  let click = UiEvent(kind: ueClick, area: "actions", id: "submit")
  let text = uiEventText(doc, rt, click)
  doAssert text.startsWith("Clicked button submit (Submit)")
  doAssert "Current UI values" in text
  doAssert "- q1: a (A)" in text

  let selected = UiEvent(kind: ueSelect, area: "choices", id: "q1", value: "b")
  doAssert uiEventText(doc, rt, selected) == "Selected option for q1: b (B)"

  let submit = UiEvent(kind: ueSubmitText, area: "answer", id: "open_response",
    value: "A long answer")
  doAssert uiEventText(doc, rt, submit) ==
    "Submitted text for open_response:\nA long answer"
