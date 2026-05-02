type
  UiKind* = enum
    ukText,
    ukCode,
    ukRadio,
    ukButtons,
    ukTextInput,
    ukMath

  UiOption* = object
    id*: string
    label*: string
    selected*: bool

  UiArea* = object
    name*: string
    kind*: UiKind
    text*: string
    id*: string
    options*: seq[UiOption]
    language*: string
    placeholder*: string
    submitLabel*: string

  UiDoc* = object
    version*: int
    title*: string
    layout*: string
    areas*: seq[UiArea]
    focus*: string

  UiEventKind* = enum
    ueNone,
    ueClick,
    ueSelect,
    ueSubmitText

  UiEvent* = object
    kind*: UiEventKind
    area*: string
    id*: string
    value*: string

const FallbackLayout* = "| main, * |"

proc textUiDoc*(title, text: string): UiDoc =
  UiDoc(
    version: 1,
    title: title,
    layout: FallbackLayout,
    areas: @[
      UiArea(
        name: "main",
        kind: ukText,
        text: text
      )
    ]
  )
