import ./ui_doc

type
  DebugLog* = object
    entries*: seq[string]
    maxEntries*: int

proc initDebugLog*(maxEntries = 20): DebugLog =
  DebugLog(maxEntries: maxEntries)

proc addDebug*(log: var DebugLog; text: string) =
  if text.len == 0:
    return

  if log.maxEntries <= 0:
    log.maxEntries = 20
  log.entries.add text
  while log.entries.len > log.maxEntries:
    log.entries.delete(0)

proc debugText*(log: DebugLog): string =
  for i, entry in log.entries:
    if result.len > 0:
      result.add "\n\n"
    result.add "#"
    result.add $(i + 1)
    result.add "\n"
    result.add entry

proc debugUiDoc*(log: DebugLog): UiDoc =
  var text = log.debugText()
  if text.len == 0:
    text = "No debug entries."

  UiDoc(
    version: 1,
    title: "Debug Log",
    layout: "| debug, * |",
    areas: @[
      UiArea(
        name: "debug",
        kind: ukText,
        text: text
      )
    ],
    focus: "debug"
  )
