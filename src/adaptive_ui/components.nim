import std/tables
import widgets/synedit
import ./ui_doc

type
  ComponentState* = object
    selectedOption*: string
    text*: string
    hasEditor*: bool
    editor*: SynEdit
    lastText*: string
    lastLanguage*: string
    lastKind*: UiKind

  UiRuntime* = object
    components*: Table[string, ComponentState]
    focus*: string

proc initUiRuntime*(): UiRuntime =
  UiRuntime(components: initTable[string, ComponentState]())

proc componentKey*(area: UiArea): string =
  if area.id.len > 0:
    result = area.id
  else:
    result = area.name

proc ensureState(rt: var UiRuntime; area: UiArea): string =
  let key = componentKey(area)
  if not rt.components.hasKey(key):
    rt.components[key] = ComponentState()
  result = key

proc selectedOption*(rt: UiRuntime; area: UiArea): string =
  let key = componentKey(area)
  if rt.components.hasKey(key) and
      rt.components[key].selectedOption.len > 0:
    return rt.components[key].selectedOption

  for option in area.options:
    if option.selected:
      return option.id

  result = ""

proc setSelected*(rt: var UiRuntime; area: UiArea; optionId: string) =
  let key = rt.ensureState(area)
  rt.components[key].selectedOption = optionId

proc setText*(rt: var UiRuntime; area: UiArea; text: string) =
  let key = rt.ensureState(area)
  rt.components[key].text = text

proc textValue*(rt: UiRuntime; area: UiArea): string =
  let key = componentKey(area)
  if rt.components.hasKey(key):
    result = rt.components[key].text
  else:
    result = ""

proc setFocus*(rt: var UiRuntime; areaName: string) =
  rt.focus = areaName

proc eventForSelect*(area: UiArea; optionId: string): UiEvent =
  UiEvent(
    kind: ueSelect,
    area: area.name,
    id: area.id,
    value: optionId
  )

proc eventForClick*(area: UiArea; optionId: string): UiEvent =
  UiEvent(
    kind: ueClick,
    area: area.name,
    id: optionId
  )

proc eventForSubmit*(area: UiArea; value: string): UiEvent =
  UiEvent(
    kind: ueSubmitText,
    area: area.name,
    id: area.id,
    value: value
  )
