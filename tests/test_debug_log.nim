import std/strutils
import adaptive_ui/debug_log
import adaptive_ui/ui_doc

block empty:
  let log = initDebugLog()
  doAssert log.entries.len == 0
  doAssert log.debugText() == ""

block bounded:
  var log = initDebugLog(maxEntries = 2)
  log.addDebug("first")
  log.addDebug("")
  log.addDebug("second")
  log.addDebug("third")

  doAssert log.entries == @["second", "third"]
  doAssert "#1\nsecond" in log.debugText()
  doAssert "#2\nthird" in log.debugText()
  doAssert "first" notin log.debugText()

block defaultLimit:
  var log = initDebugLog()
  log.addDebug("entry")
  doAssert log.maxEntries == 20
  doAssert log.entries == @["entry"]

block minimumLimit:
  var log = initDebugLog(maxEntries = 0)
  log.addDebug("first")
  log.addDebug("second")
  doAssert log.maxEntries == 1
  doAssert log.entries == @["second"]

block uiDoc:
  var log = initDebugLog()
  doAssert log.debugUiDoc().areas[0].text == "No debug entries."

  log.addDebug("bad json")
  let doc = log.debugUiDoc()
  doAssert doc.title == "Debug Log"
  doAssert "utility_actions" in doc.layout
  doAssert doc.focus == "debug"
  doAssert doc.areas.len == 2
  doAssert doc.areas[0].kind == ukText
  doAssert doc.areas[1].kind == ukButtons
  doAssert doc.areas[1].options[0].id == "back"
  doAssert "bad json" in doc.areas[0].text
