import std/strutils
import ./[components, ui_doc]

proc findArea*(doc: UiDoc; name: string; area: var UiArea): bool =
  for item in doc.areas:
    if item.name == name:
      area = item
      return true
  result = false

proc uiValuesText*(doc: UiDoc; rt: UiRuntime): string =
  for area in doc.areas:
    var value = ""
    case area.kind
    of ukRadio:
      value = rt.selectedOption(area)
    of ukTextInput:
      value = rt.textValue(area)
    of ukText, ukCode, ukButtons, ukMath, ukTranscript:
      discard

    if value.strip().len > 0:
      if result.len > 0:
        result.add "\n"
      result.add "- "
      if area.id.len > 0:
        result.add area.id
      else:
        result.add area.name
      result.add ": "
      result.add value

proc uiEventText*(doc: UiDoc; rt: UiRuntime; ev: UiEvent): string =
  case ev.kind
  of ueNone:
    result = ""
  of ueSelect:
    result = "Selected option for " & ev.id & ": " & ev.value
  of ueSubmitText:
    result = "Submitted text for " & ev.id & ":\n" & ev.value
  of ueClick:
    result = "Clicked button " & ev.id & " in area " & ev.area & "."
    let values = uiValuesText(doc, rt)
    if values.len > 0:
      result.add "\nCurrent UI values:\n"
      result.add values
