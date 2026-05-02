import std/strutils
import ./[components, ui_doc]

proc findArea*(doc: UiDoc; name: string; area: var UiArea): bool =
  for item in doc.areas:
    if item.name == name:
      area = item
      return true
  result = false

proc areaByName(doc: UiDoc; name: string): UiArea =
  for area in doc.areas:
    if area.name == name:
      return area
  raise newException(ValueError, "unknown UI area: " & name)

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
    let value =
      case area.kind
      of ukRadio: rt.selectedOption(area)
      of ukTextInput: rt.textValue(area)
      of ukText, ukCode, ukButtons, ukMath: ""
    if value.strip().len > 0:
      if result.len > 0:
        result.add "\n"
      result.add "- "
      result.add if area.id.len > 0: area.id else: area.name
      result.add ": "
      result.add area.valueText(value)

proc uiEventText*(doc: UiDoc; rt: UiRuntime; ev: UiEvent): string =
  case ev.kind
  of ueNone:
    result = ""
  of ueSelect:
    let area = doc.areaByName(ev.area)
    result = "Selected option for " & ev.id & ": "
    result.add area.valueText(ev.value)
  of ueSubmitText:
    result = "Submitted text for " & ev.id & ":\n" & ev.value
  of ueClick:
    let area = doc.areaByName(ev.area)
    result = "Clicked button "
    result.add area.valueText(ev.id)
    result.add " in area "
    result.add ev.area
    result.add "."
    let values = uiValuesText(doc, rt)
    if values.len > 0:
      result.add "\nCurrent UI values:\n"
      result.add values
