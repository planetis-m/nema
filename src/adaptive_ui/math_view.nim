import std/strutils

proc replaceAll(text: string; pairs: openArray[(string, string)]): string =
  result = text
  for pair in pairs:
    result = result.replace(pair[0], pair[1])

proc readGroup(text: string; pos: var int): string =
  if pos >= text.len or text[pos] != '{':
    return ""

  inc pos
  let start = pos
  var depth = 1
  while pos < text.len and depth > 0:
    if text[pos] == '{':
      inc depth
    elif text[pos] == '}':
      dec depth
    if depth > 0:
      inc pos

  if pos <= text.len and depth == 0:
    result = text[start ..< pos]
    inc pos

proc rewriteFrac(text: string): string =
  var i = 0
  while i < text.len:
    if text.continuesWith("\\frac", i):
      i += "\\frac".len
      var num = readGroup(text, i)
      var den = readGroup(text, i)
      if num.len > 0 and den.len > 0:
        result.add "(" & num & ")/(" & den & ")"
      else:
        result.add "\\frac"
    else:
      result.add text[i]
      inc i

proc stripMathDelimiters(line: string): string =
  let trimmed = line.strip()
  if trimmed.len >= 4 and trimmed.startsWith("$$") and trimmed.endsWith("$$"):
    result = trimmed[2 .. ^3].strip()
  elif trimmed.len >= 2 and trimmed.startsWith("$") and trimmed.endsWith("$"):
    result = trimmed[1 .. ^2].strip()
  elif trimmed.len >= 4 and trimmed.startsWith("\\[") and trimmed.endsWith("\\]"):
    result = trimmed[2 .. ^3].strip()
  elif trimmed.len >= 4 and trimmed.startsWith("\\(") and trimmed.endsWith("\\)"):
    result = trimmed[2 .. ^3].strip()
  else:
    result = line

proc formatMathLine*(line: string): string =
  result = stripMathDelimiters(line)
  result = rewriteFrac(result)
  result = result.replaceAll([
    ("\\times", "*"),
    ("\\cdot", "*"),
    ("\\div", "/"),
    ("\\le", "<="),
    ("\\ge", ">="),
    ("\\neq", "!="),
    ("\\to", "->"),
    ("\\sqrt", "sqrt"),
    ("\\sum", "sum"),
    ("\\int", "int"),
    ("\\pi", "pi"),
    ("\\theta", "theta"),
    ("\\alpha", "alpha"),
    ("\\beta", "beta"),
    ("\\gamma", "gamma")
  ])

proc formatMathText*(text: string): string =
  for line in text.splitLines():
    if result.len > 0:
      result.add "\n"
    result.add formatMathLine(line)
