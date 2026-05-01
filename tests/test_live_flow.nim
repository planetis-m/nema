import adaptive_ui/[live_flow, ui_doc]

block commands:
  doAssert parseLiveCommand("hello").kind == lcNone
  doAssert parseLiveCommand("/new").kind == lcNew
  doAssert parseLiveCommand("/new plan a trip").text == "plan a trip"
  doAssert parseLiveCommand("/debug").kind == lcDebug

block introDoc:
  let doc = introUiDoc()
  doAssert doc.version == 1
  doAssert doc.title == "Adaptive UI"
  doAssert doc.areas.len == 2
  doAssert doc.areas[1].name == "guide"
