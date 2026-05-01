import jsonx
import jsonx/[parsejson, streams]

type
  UiKind* = enum
    ukText,
    ukCode,
    ukRadio,
    ukButtons,
    ukTextInput,
    ukMath,
    ukTranscript

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

const
  FallbackLayout* = "| main, * |"

proc readJson*(dst: var UiKind; p: var JsonParser) =
  var name: string
  readJson(name, p)
  case name
  of "text":
    dst = ukText
  of "code":
    dst = ukCode
  of "radio":
    dst = ukRadio
  of "buttons":
    dst = ukButtons
  of "textInput":
    dst = ukTextInput
  of "math":
    dst = ukMath
  of "transcript":
    dst = ukTranscript
  else:
    raiseParseErr(p, "valid UI kind")

proc writeJson*(s: Stream; x: UiKind) =
  case x
  of ukText:
    writeJson(s, "text")
  of ukCode:
    writeJson(s, "code")
  of ukRadio:
    writeJson(s, "radio")
  of ukButtons:
    writeJson(s, "buttons")
  of ukTextInput:
    writeJson(s, "textInput")
  of ukMath:
    writeJson(s, "math")
  of ukTranscript:
    writeJson(s, "transcript")

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
