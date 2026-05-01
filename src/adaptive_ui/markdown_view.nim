import std/strutils

proc headingText(line: string): string =
  var i = 0
  while i < line.len and line[i] == '#':
    inc i

  if i > 0 and i <= 6 and i < line.len and line[i] == ' ':
    result = line[i + 1 .. ^1].strip()
  else:
    result = line

proc fenceText(line: string; inFence: var bool): string =
  let trimmed = line.strip()
  if trimmed.startsWith("```"):
    inFence = not inFence
    if inFence:
      let lang = trimmed[3 .. ^1].strip()
      if lang.len > 0:
        result = "[code: " & lang & "]"
      else:
        result = "[code]"
    else:
      result = "[/code]"
  else:
    result = line

proc readableMarkdownLine*(line: string; inFence: var bool): string =
  let fenced = fenceText(line, inFence)
  if fenced != line:
    return fenced
  if inFence:
    return line

  let trimmed = line.strip()
  if trimmed.len == 0:
    return ""
  if trimmed.startsWith("#"):
    return headingText(trimmed)
  if trimmed.startsWith("- ") or trimmed.startsWith("* "):
    return "- " & trimmed[2 .. ^1].strip()
  if trimmed.startsWith(">"):
    return "| " & trimmed[1 .. ^1].strip()

  result = line

proc formatMarkdownText*(text: string): string =
  var inFence = false
  for line in text.splitLines():
    if result.len > 0:
      result.add "\n"
    result.add readableMarkdownLine(line, inFence)
