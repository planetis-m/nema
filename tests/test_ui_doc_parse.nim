import std/strutils
import jsonx
import adaptive_ui/[ui_doc, ui_parse]

const ValidDoc = """{
  "version": 1,
  "title": "Workspace",
  "layout": "| title, 2 lines |\n| summary, * |\n| choices, 7 lines |\n| actions, 2 lines |",
  "focus": "choices",
  "areas": [
    {
      "name": "title",
      "kind": "text",
      "text": "Workspace"
    },
    {
      "name": "summary",
      "kind": "text",
      "text": "Choose how to continue."
    },
    {
      "name": "choices",
      "kind": "radio",
      "id": "next_step",
      "options": [
        { "id": "inspect", "label": "Inspect" },
        { "id": "edit", "label": "Edit" },
        { "id": "run", "label": "Run" }
      ]
    },
    {
      "name": "actions",
      "kind": "buttons",
      "id": "actions",
      "options": [
        { "id": "continue", "label": "Continue" }
      ]
    }
  ]
}"""

proc parses(text: string; doc: var UiDoc; err: var string): bool =
  parseUiDoc(text, doc, err)

block:
  var doc: UiDoc
  var err = ""
  doAssert parses(ValidDoc, doc, err), err
  doAssert doc.version == 1
  doAssert doc.title == "Workspace"
  doAssert doc.focus == "choices"
  doAssert doc.areas.len == 4
  doAssert doc.areas[2].kind == ukRadio
  doAssert doc.areas[2].options[1].label == "Edit"

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
  let json = """{"version":1,"layout":"not a layout","areas":[{"name":"main","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "layout" in err

block:
  let json = """{"version":1,"layout":"| main, * |","areas":[{"name":"other","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "not in layout" in err

block:
  let json = """{"version":1,"layout":"| main, * |","focus":"other","areas":[{"name":"main","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "focus other is not in layout" in err

block:
  let json = """{"version":1,"layout":"| main, * |","areas":[{"name":"main","kind":"text"},{"name":"main","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert not parses(json, doc, err)
  doAssert "duplicate area name main" in err

block:
  let json = """{"version":1,"layout":"| main, *; detail, 2 lines |","areas":[{"name":"detail","kind":"text"}]}"""
  var doc: UiDoc
  var err = ""
  doAssert parses(json, doc, err), err
