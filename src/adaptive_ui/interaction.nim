import std/strutils
import ./[components, ui_doc]

proc findArea*(doc: UiDoc; name: string; area: var UiArea): bool =
  for item in doc.areas:
    if item.name == name:
      area = item
      return true
  result = false

proc optionLabel*(area: UiArea; optionId: string): string =
  for option in area.options:
    if option.id == optionId:
      return option.label
  result = ""

proc valueText(area: UiArea; value: string): string =
  result = value
  let label = area.optionLabel(value)
  if label.strip().len > 0:
    result.add " ("
    result.add label
    result.add ")"

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
      result.add area.valueText(value)

proc uiEventText*(doc: UiDoc; rt: UiRuntime; ev: UiEvent): string =
  case ev.kind
  of ueNone:
    result = ""
  of ueSelect:
    var area: UiArea
    result = "Selected option for " & ev.id & ": "
    if doc.findArea(ev.area, area):
      result.add area.valueText(ev.value)
    else:
      result.add ev.value
  of ueSubmitText:
    result = "Submitted text for " & ev.id & ":\n" & ev.value
  of ueClick:
    var area: UiArea
    result = "Clicked button "
    if doc.findArea(ev.area, area):
      result.add area.valueText(ev.id)
    else:
      result.add ev.id
    result.add " in area "
    result.add ev.area
    result.add "."
    let values = uiValuesText(doc, rt)
    if values.len > 0:
      result.add "\nCurrent UI values:\n"
      result.add values
