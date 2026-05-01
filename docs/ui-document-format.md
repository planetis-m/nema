# UI Document Format

The UI document is the contract between the UI subagent and the Nim renderer.

The subagent returns a JSON object that maps cleanly into Nim objects with `jsonx`. The layout itself is still a markdown table and must be parsed by `uirelays/layout`.

## Example

```json
{
  "version": 1,
  "title": "Decision",
  "layout": "| title, 2 lines |\\n| summary, * |\\n| choices, 7 lines |\\n| actions, 2 lines |",
  "focus": "choices",
  "areas": [
    {
      "name": "title",
      "kind": "text",
      "text": "Choose an approach"
    },
    {
      "name": "summary",
      "kind": "text",
      "text": "The user asked for help comparing two implementation options."
    },
    {
      "name": "choices",
      "kind": "radio",
      "id": "approach",
      "options": [
        { "id": "simple", "label": "Simple implementation" },
        { "id": "extensible", "label": "Extensible implementation" }
      ]
    },
    {
      "name": "actions",
      "id": "decision_actions",
      "kind": "buttons",
      "options": [
        { "id": "apply", "label": "Apply" }
      ]
    }
  ]
}
```

## Required Fields

- `version`: must be `1`.
- `layout`: markdown table accepted by `uirelays/layout.parseLayout`.
- `areas`: list of named areas to render.

## Area Rules

- `name` must match a cell in `layout`.
- `kind` must be one of:
  - `text`
  - `code`
  - `radio`
  - `buttons`
  - `textInput`
  - `math`
  - `transcript`
- `id` is required for interactive controls.
- `options` is required for `radio` and `buttons`.
- `language` is used by `code`.
- `placeholder` is used by `textInput`.
- `submitLabel` is used by `textInput` when a submit affordance is drawn inside the same area.

## Kind Mapping

| JSON kind | Nim enum | Renderer |
| --- | --- | --- |
| `text` | `ukText` | read-only `SynEdit` |
| `code` | `ukCode` | read-only `SynEdit` with language |
| `radio` | `ukRadio` | direct-drawn choices |
| `buttons` | `ukButtons` | direct-drawn buttons |
| `textInput` | `ukTextInput` | editable `SynEdit` |
| `math` | `ukMath` | basic math text view |
| `transcript` | `ukTranscript` | read-only `SynEdit` optimized for chat history |

Implement explicit `readJson` and `writeJson` conversions for `UiKind` if the default enum mapping does not match these exact JSON strings. Do not change the JSON contract to expose Nim enum names.

## Event Mapping

Components emit:

```nim
type
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
```

Meanings:

- `ueSelect`: radio option changed. `id` is the control id and `value` is option id.
- `ueClick`: button clicked. `id` is button id.
- `ueSubmitText`: text input submitted. `id` is input id and `value` is text.

## Fallback Document

Use this if parsing or layout fails:

```json
{
  "version": 1,
  "title": "Adaptive UI",
  "layout": "| main, * |",
  "areas": [
    {
      "name": "main",
      "kind": "text",
      "text": "The generated UI could not be rendered."
    }
  ]
}
```
