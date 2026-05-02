type
  UiCommandKind* = enum
    uckNone,
    uckChoice,
    uckInput

  UiCommandOption* = object
    id*: string
    label*: string

  UiCommand* = object
    kind*: UiCommandKind
    title*: string
    prompt*: string
    placeholder*: string
    options*: seq[UiCommandOption]

