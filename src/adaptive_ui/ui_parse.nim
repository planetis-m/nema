import std/[sets, strutils, tables]
import jsonx
import uirelays/layout
import ./ui_doc

proc fail(err: var string; message: string): bool =
  err = message
  result = false

proc validateArea(area: UiArea; index: int; err: var string): bool =
  if area.name.strip.len == 0:
    return fail(err, "area " & $index & " has empty name")

  case area.kind
  of ukRadio, ukButtons:
    if area.id.strip.len == 0:
      return fail(err, "area " & area.name & " requires id")
    if area.options.len == 0:
      return fail(err, "area " & area.name & " requires options")
    for optionIndex, option in area.options:
      if option.id.strip.len == 0:
        return fail(err, "area " & area.name &
          " option " & $optionIndex & " has empty id")
      if option.label.strip.len == 0:
        return fail(err, "area " & area.name &
          " option " & $optionIndex & " has empty label")
  of ukTextInput:
    if area.id.strip.len == 0:
      return fail(err, "area " & area.name & " requires id")
  of ukText, ukCode, ukMath, ukTranscript:
    discard

  result = true

proc validateLayoutAreas(doc: UiDoc; err: var string): bool =
  try:
    let layout = parseLayout(doc.layout)
    let cells = layout.resolve(1000, 1000, lineHeight = 20)
    if cells.len == 0:
      return fail(err, "layout has no cells")

    var names = initHashSet[string]()
    for area in doc.areas:
      if names.contains(area.name):
        return fail(err, "duplicate area name " & area.name)
      names.incl area.name
      if not cells.hasKey(area.name):
        return fail(err, "area " & area.name & " is not in layout")

    if doc.focus.strip.len > 0 and not cells.hasKey(doc.focus):
      return fail(err, "focus " & doc.focus & " is not in layout")

    result = true
  except CatchableError:
    result = fail(err, "layout parse error: " & getCurrentExceptionMsg())

proc validateUiDoc(doc: UiDoc; err: var string): bool =
  if doc.version != 1:
    return fail(err, "unsupported UI document version " & $doc.version)
  if doc.layout.strip.len == 0:
    return fail(err, "layout is empty")
  if doc.areas.len == 0:
    return fail(err, "areas is empty")

  for i, area in doc.areas:
    if not validateArea(area, i, err):
      return false

  result = validateLayoutAreas(doc, err)

proc parseUiDoc*(text: string; doc: var UiDoc; err: var string): bool =
  err = ""
  try:
    let parsed = fromJson(text, UiDoc)
    if not validateUiDoc(parsed, err):
      return false
    doc = parsed
    result = true
  except CatchableError:
    err = getCurrentExceptionMsg()
    result = false
