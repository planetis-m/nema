import std/[sequtils, strutils]
import ./turn_view

const
  MaxOptions = 6

proc stripMarkdownMarkers(text: string): string =
  result = text.strip()
  while result.startsWith("#"):
    result = result[1..^1].strip()
  if result.startsWith("**") and result.endsWith("**") and result.len >= 4:
    result = result[2 .. ^3].strip()
  result = result.replace("**", "")
  result = result.replace("__", "")
  result = result.strip()

proc isHorizontalRule(line: string): bool =
  let stripped = line.strip()
  stripped == "---" or stripped == "***" or stripped == "___"

proc optionFromLine(line: string; option: var TurnOption): bool =
  let stripped = line.strip()
  if stripped.len < 3:
    return false
  if not stripped[0].isAlphaAscii:
    return false
  if stripped[1] != ')' and stripped[1] != '.':
    return false

  let label = stripped[2..^1].strip().stripMarkdownMarkers()
  if label.len == 0:
    return false

  option = TurnOption(id: ($stripped[0]).toLowerAscii(), label: label)
  result = true

proc looksLikeTypePrompt(line: string): bool =
  let lowered = line.toLowerAscii()
  result =
    lowered.contains("please type") or
    lowered.contains("please provide") or
    lowered.contains("provide a name") or
    lowered.contains("enter") or
    lowered.contains("type") or
    lowered.contains("what is the name") or
    lowered.contains("what is your nation called") or
    lowered.contains("what is it called")

proc isNextActionLine(line: string): bool =
  let lowered = line.strip().toLowerAscii()
  lowered.startsWith("next action:") or lowered.startsWith("nextaction:")

proc nextActionKind(text: string): TurnActionKind =
  for line in text.splitLines:
    let lowered = line.strip().toLowerAscii()
    let normalized = line.strip().normalize()
    if line.isNextActionLine():
      if lowered.contains("choose one") or normalized.contains("chooseone"):
        return takChoose
      if lowered.contains("type"):
        return takType
      if lowered.contains("none"):
        return takNone
  result = takNone

proc usefulLines(text: string): seq[string] =
  for rawLine in text.splitLines:
    if not rawLine.isHorizontalRule() and not rawLine.isNextActionLine():
      let line = rawLine.stripMarkdownMarkers()
      if line.len > 0:
        result.add line

proc titleFrom(lines: seq[string]): string =
  for line in lines:
    if line.normalize() notin ["pickone.", "chooseone."]:
      return line
  result = "Adaptive UI"

proc actionPromptFrom(lines: seq[string]; options: seq[TurnOption];
    actionKind: TurnActionKind): string =
  if actionKind == takType:
    for i in countdown(lines.high, 0):
      if lines[i].looksLikeTypePrompt():
        return lines[i]

  if actionKind == takChoose:
    for i in countdown(lines.high, 0):
      let line = lines[i]
      var option: TurnOption
      if not optionFromLine(line, option) and
          line.normalize() notin ["pickone.", "chooseone."]:
        return line

  if lines.len > 0:
    result = lines[^1]

proc bodyFrom(lines: seq[string]; options: seq[TurnOption];
    actionPrompt: string): string =
  let optionIds = options.mapIt(it.id)
  for line in lines:
    var option: TurnOption
    let isOption = optionFromLine(line, option) and option.id in optionIds
    let isPromptMarker = line.normalize() in ["pickone.", "chooseone."]
    if not isOption and not isPromptMarker and line != actionPrompt:
      if result.len > 0:
        result.add "\n"
      result.add line

proc extractTurnView*(text: string): TurnView =
  let lines = usefulLines(text)
  var options: seq[TurnOption]
  for line in lines:
    var option: TurnOption
    if optionFromLine(line, option):
      options.add option

  var kind = nextActionKind(text)
  if options.len >= 2 and options.len <= MaxOptions:
    kind = takChoose
  elif kind == takNone:
    for i in countdown(lines.high, 0):
      if lines[i].looksLikeTypePrompt():
        kind = takType
        break

  let prompt = actionPromptFrom(lines, options, kind)
  result = TurnView(
    title: titleFrom(lines),
    body: bodyFrom(lines, options, prompt),
    actionKind: kind,
    actionPrompt: prompt,
    options: options
  )
  if result.body.len == 0 and prompt.len > 0:
    result.body = prompt
