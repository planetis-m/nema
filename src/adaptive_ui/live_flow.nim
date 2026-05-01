import std/strutils
import ./ui_doc

proc isNewCommand*(input: string): bool =
  input.strip().toLowerAscii() == "/new"

proc introUiDoc*(): UiDoc =
  UiDoc(
    version: 1,
    title: "Adaptive UI",
    layout: """
| title, 2 lines |
| guide, * |
""",
    areas: @[
      UiArea(
        name: "title",
        kind: ukText,
        text: "Adaptive UI"
      ),
      UiArea(
        name: "guide",
        kind: ukText,
        text: "Type what you want in the input box below, then press Ctrl+Enter. The screen will adapt when the response is ready. Use /new to start over."
      )
    ],
    focus: "guide"
  )
