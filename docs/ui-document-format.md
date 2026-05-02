# UI Document Format

`UiDoc` is an internal Nim data shape. The model does not generate it, and the
app does not parse `UiDoc` JSON at runtime.

The chat agent may append a compact fenced `ui` directive. Local code parses that
directive and builds a `UiDoc` with known layouts and controls.

## Core Shape

```nim
type
  UiDoc* = object
    version*: int
    title*: string
    layout*: string
    areas*: seq[UiArea]
    focus*: string
```

`layout` is a markdown table accepted by `uirelays/layout.parseLayout`. Area
names must match layout cells.

## Supported Areas

- `ukText`: read-only `SynEdit`
- `ukCode`: read-only `SynEdit` with language
- `ukRadio`: direct-drawn choices
- `ukButtons`: direct-drawn buttons
- `ukTextInput`: editable `SynEdit`
- `ukMath`: basic math text view

## Event Mapping

Components emit `UiEvent` values:

- `ueSelect`: radio option changed.
- `ueClick`: button clicked.
- `ueSubmitText`: text input submitted.

`interaction.nim` turns these events plus current component values into plain
user text for the next chat turn.

## Fallback

Use `textUiDoc(title, text)` for plain visible text when there is no adaptive
directive or the directive is not useful.
