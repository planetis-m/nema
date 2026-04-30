import std/strutils
import jsonx
import adaptive_ui/[ui_doc, ui_parse]

const ValidQuiz = """{
  "version": 1,
  "title": "Quiz",
  "layout": "| title, 2 lines |\n| prompt, * |\n| choices, 7 lines |\n| actions, 2 lines |",
  "focus": "choices",
  "areas": [
    {
      "name": "title",
      "kind": "text",
      "text": "Question 1 of 3"
    },
    {
      "name": "prompt",
      "kind": "text",
      "text": "Which keyword declares an immutable local binding in Nim?"
    },
    {
      "name": "choices",
      "kind": "radio",
      "id": "q1_answer",
      "options": [
        { "id": "a", "label": "var" },
        { "id": "b", "label": "let" },
        { "id": "c", "label": "type" }
      ]
    },
    {
      "name": "actions",
      "kind": "buttons",
      "id": "q1_actions",
      "options": [
        { "id": "submit", "label": "Submit" }
      ]
    }
  ]
}"""

proc parses(text: string; doc: var UiDoc; err: var string): bool =
  parseUiDoc(text, doc, err)

block:
  var doc: UiDoc
  var err = ""
  doAssert parses(ValidQuiz, doc, err), err
  doAssert doc.version == 1
  doAssert doc.title == "Quiz"
  doAssert doc.focus == "choices"
  doAssert doc.areas.len == 4
  doAssert doc.areas[2].kind == ukRadio
  doAssert doc.areas[2].options[1].label == "let"

block:
  let json = toJson(UiArea(name: "main", kind: ukText, text: "hello"))
  doAssert "\"kind\":\"text\"" in json

block:
  let json = """{"version":2,"layout":"| main, * |","areas":[{"name":"main","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "version" in err

block:
  let json = """{"version":1,"layout":"","areas":[{"name":"main","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "layout" in err

block:
  let json = """{"version":1,"layout":"| main, * |","areas":[{"name":"main","kind":"radio","id":"answer"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "options" in err

block:
  let json = """{"version":1,"layout":"| main, * |","areas":[{"name":"main","kind":"textInput"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "id" in err

block:
  let json = """{"version":1,"layout":"| main, * |","areas":[{"name":"main","kind":"slider"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert err.len > 0

block:
  let doc = fallbackUiDoc("The generated UI could not be rendered.")
  doAssert doc.version == 1
  doAssert doc.layout == FallbackLayout
  doAssert doc.areas.len == 1
  doAssert doc.areas[0].name == "main"
