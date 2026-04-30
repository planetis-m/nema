import std/strutils
import jsonx
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

  result = true

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
