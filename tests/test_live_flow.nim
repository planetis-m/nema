import adaptive_ui/[live_flow, ui_doc]

block commands:
  doAssert isNewCommand("/new")
  doAssert isNewCommand(" /NEW ")
  doAssert not isNewCommand("hello")
  doAssert not isNewCommand("/new plan a trip")
  doAssert not isNewCommand("/help")

block introDoc:
  let doc = introUiDoc()
  doAssert doc.version == 1
  doAssert doc.title == "Adaptive UI"
  doAssert doc.areas.len == 2
  doAssert doc.areas[1].name == "guide"
