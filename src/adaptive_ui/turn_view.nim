type
  TurnActionKind* = enum
    takNone,
    takChoose,
    takType

  TurnOption* = object
    id*: string
    label*: string

  TurnView* = object
    title*: string
    body*: string
    actionKind*: TurnActionKind
    actionPrompt*: string
    options*: seq[TurnOption]

