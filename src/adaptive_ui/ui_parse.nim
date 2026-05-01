import std/[sets, strutils, tables]
import jsonx
import uirelays/layout
import ./ui_doc

proc requireValid(condition: bool; message: string) =
  if not condition:
    raise newException(ValueError, message)

proc validateArea(area: UiArea; index: int) =
  requireValid(area.name.strip.len > 0, "area " & $index & " has empty name")

  case area.kind
  of ukRadio, ukButtons:
    requireValid(area.id.strip.len > 0, "area " & area.name & " requires id")
    requireValid(area.options.len > 0,
      "area " & area.name & " requires options")
    for optionIndex, option in area.options:
      requireValid(option.id.strip.len > 0,
        "area " & area.name & " option " & $optionIndex & " has empty id")
      requireValid(option.label.strip.len > 0,
        "area " & area.name & " option " & $optionIndex &
        " has empty label")
  of ukTextInput:
    requireValid(area.id.strip.len > 0, "area " & area.name & " requires id")
  of ukText, ukCode, ukMath:
    discard

proc validateLayoutAreas(doc: UiDoc) =
  try:
    let layout = parseLayout(doc.layout)
    let cells = layout.resolve(1000, 1000, lineHeight = 20)
    requireValid(cells.len > 0, "layout has no cells")

    var names = initHashSet[string]()
    for area in doc.areas:
      requireValid(not names.contains(area.name),
        "duplicate area name " & area.name)
      names.incl area.name
      requireValid(cells.hasKey(area.name),
        "area " & area.name & " is not in layout")

    requireValid(doc.focus.strip.len == 0 or cells.hasKey(doc.focus),
      "focus " & doc.focus & " is not in layout")
  except CatchableError:
    raise newException(ValueError,
      "layout parse error: " & getCurrentExceptionMsg())

proc validateUiDoc(doc: UiDoc) =
  requireValid(doc.version == 1,
    "unsupported UI document version " & $doc.version)
  requireValid(doc.layout.strip.len > 0, "layout is empty")
  requireValid(doc.areas.len > 0, "areas is empty")

  for i, area in doc.areas:
    validateArea(area, i)

  validateLayoutAreas(doc)

proc parseUiDoc*(text: string; doc: var UiDoc; err: var string): bool =
  err = ""
  try:
    let parsed = fromJson(text, UiDoc)
    validateUiDoc(parsed)
    doc = parsed
    result = true
  except CatchableError:
    err = getCurrentExceptionMsg()
    result = false
