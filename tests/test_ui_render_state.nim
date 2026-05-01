import std/tables
import adaptive_ui/[components, ui_doc, ui_render]
import uirelays

let font = Font(0)
let fm = FontMetrics(ascent: 12, descent: 4, lineHeight: 16)

block:
  let area = UiArea(
    name: "choices",
    kind: ukRadio,
    id: "answer",
    options: @[
      UiOption(id: "a", label: "A"),
      UiOption(id: "b", label: "B")
    ]
  )
  var rt = initUiRuntime()
  let ev = radioHitEvent(rt, area,
    Event(kind: MouseDownEvent, x: 20, y: 20, button: LeftButton),
    rect(0, 0, 240, 120), fm)

  doAssert ev.kind == ueSelect
  doAssert ev.id == "answer"
  doAssert ev.value == "a"
  doAssert rt.selectedOption(area) == "a"

block:
  let area = UiArea(
    name: "actions",
    kind: ukButtons,
    id: "actions",
    options: @[UiOption(id: "submit", label: "Submit")]
  )
  let ev = buttonHitEvent(area,
    Event(kind: MouseDownEvent, x: 20, y: 20, button: LeftButton),
    rect(0, 0, 240, 80), font)

  doAssert ev.kind == ueClick
  doAssert ev.id == "submit"

block:
  let doc = UiDoc(
    version: 1,
    layout: """
| title, 2 lines |
| body, * |
""",
    focus: "body",
    areas: @[
      UiArea(name: "title", kind: ukText, text: "Title"),
      UiArea(name: "body", kind: ukText, text: "Body")
    ]
  )
  var rt = initUiRuntime()
  var renderDoc: UiDoc
  let cells = resolveUiDocCells(doc, rt, rect(10, 20, 300, 200),
    fm.lineHeight, renderDoc)

  doAssert renderDoc.title == ""
  doAssert cells.hasKey("title")
  doAssert cells.hasKey("body")
  doAssert cells["title"].x == 10
  doAssert cells["title"].y == 20
  doAssert cells["body"].x == 10
  doAssert cells["body"].y > cells["title"].y

block:
  let doc = UiDoc(
    version: 1,
    layout: """
| title, 2 lines |
| body, * |
| aside, 3 lines |
""",
    areas: @[
      UiArea(name: "title", kind: ukText, text: "Title"),
      UiArea(name: "body", kind: ukText, text: "Body")
    ]
  )
  var rt = initUiRuntime()
  var renderDoc: UiDoc
  let cells = resolveUiDocCells(doc, rt, rect(0, 0, 300, 200),
    fm.lineHeight, renderDoc)
  let missing = renderDoc.missingCellNames(cells)

  doAssert cells.hasKey("aside")
  doAssert missing.len == 1
  doAssert missing[0] == "aside"

block:
  let doc = UiDoc(
    version: 1,
    layout: "not a layout",
    areas: @[UiArea(name: "main", kind: ukText, text: "ignored")]
  )
  var rt = initUiRuntime()
  var renderDoc: UiDoc
  let cells = resolveUiDocCells(doc, rt, rect(0, 0, 240, 80),
    fm.lineHeight, renderDoc)

  doAssert renderDoc.title == "Adaptive UI"
  doAssert cells.hasKey("main")

block:
  let area = UiArea(
    name: "answer",
    kind: ukTextInput,
    id: "open_response",
    submitLabel: "Submit"
  )
  let r = rect(0, 0, 320, 160)
  let b = textInputButtonRect(r, font, area.submitLabel)
  let editor = textInputEditorRect(area, r, font)

  doAssert b.w > 0
  doAssert b.h > 0
  doAssert b.x >= r.x
  doAssert b.y > r.y
  doAssert editor.h < r.h

  let ev = textInputSubmitEvent(area,
    Event(kind: MouseDownEvent, x: b.x + 2, y: b.y + 2, button: LeftButton),
    r, font, "response text")
  doAssert ev.kind == ueSubmitText
  doAssert ev.id == "open_response"
  doAssert ev.value == "response text"

block:
  let area = UiArea(name: "answer", kind: ukTextInput, id: "open_response")
  let r = rect(0, 0, 320, 160)
  let b = textInputButtonRect(r, font, area.submitLabel)
  let editor = textInputEditorRect(area, r, font)

  doAssert b.w == 0
  doAssert b.h == 0
  doAssert editor == r

block:
  let area = UiArea(
    name: "answer",
    kind: ukTextInput,
    id: "open_response",
    placeholder: "Write your answer"
  )
  doAssert textInputPlaceholder(area, "") == "Write your answer"
  doAssert textInputPlaceholder(area, "draft") == ""

block:
  let area = UiArea(name: "answer", kind: ukTextInput, id: "open_response")
  doAssert textInputPlaceholder(area, "") == ""
