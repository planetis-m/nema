import std/strutils
import ./turn_view

const
  FenceStart = "```ui"
  FenceEnd = "```"

proc cleanTitle(text: string): string =
  result = text.strip()
  if result.len == 0:
    result = "Assistant"

proc splitUiBlock*(text: string; visible, uiBlock: var string): bool =
  let start = text.find(FenceStart)
  if start < 0:
    visible = text
    uiBlock = ""
    return false

  let contentStart = start + FenceStart.len
  let stop = text.find(FenceEnd, contentStart)
  if stop < 0:
    visible = text
    uiBlock = ""
    return false

  visible = (text[0 ..< start] & text[stop + FenceEnd.len .. ^1]).strip()
  uiBlock = text[contentStart ..< stop].strip()
  result = true

proc parseOption(value: string; option: var UiCommandOption): bool =
  let sep = value.find("|")
  if sep <= 0:
    return false

  let id = value[0 ..< sep].strip().toLowerAscii()
  let label = value[sep + 1 .. ^1].strip()
  if id.len == 0 or label.len == 0:
    return false

  option = UiCommandOption(id: id, label: label)
  result = true

proc parseUiCommand*(uiBlock: string): UiCommand =
  for rawLine in uiBlock.splitLines:
    let line = rawLine.strip()
    if line.len == 0:
      discard
    elif line == "choice":
      result.kind = uckChoice
    elif line == "input":
      result.kind = uckInput
    elif line == "none":
      result.kind = uckNone
    elif line.startsWith("title:"):
      result.title = line["title:".len .. ^1].cleanTitle()
    elif line.startsWith("prompt:"):
      result.prompt = line["prompt:".len .. ^1].strip()
    elif line.startsWith("placeholder:"):
      result.placeholder = line["placeholder:".len .. ^1].strip()
    elif line.startsWith("option:"):
      var option: UiCommandOption
      if parseOption(line["option:".len .. ^1], option):
        result.options.add option

proc uiCommandFromText*(text: string; visible: var string): UiCommand =
  var uiBlock = ""
  if splitUiBlock(text, visible, uiBlock):
    result = parseUiCommand(uiBlock)
  else:
    visible = text
