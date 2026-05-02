# Adaptive UI Architecture

This document defines the current implementation target for the adaptive UI app.
The core app is a generic renderer plus a non-blocking agent runtime. It must not
contain task-specific modes for narrow workflows. Domain workflows are represented
by chat state plus compact adaptive UI directives.

The central product rule is that the interface adapts to the structure and
intent of the chat agent's latest response. The app must not ask the model to
generate JSON or layouts. Nim maps small `ui` directives to explicit components:
choices become selectable controls and free-form prompts become input areas.

## Product Shape

The app has two visible zones:

- Top adaptive surface: renders the current `UiDoc`.
- Bottom input bar: persistent `SynEdit` text input.

The adaptive surface can render text, code, math text, choices, button rows,
and multiline input. These are primitives, not product modes.

## Hard Constraints

- Nim only for application code.
- Use `uirelays` and build with `-d:sdl3`.
- Use `uirelays/layout.parseLayout` for all layout rectangles.
- Use `SynEdit` for text-like surfaces: labels, code, and text inputs.
- Use `jsonx` for config, state, and agent response parsing.
- Do not use `std/json` for project data models.
- Use `relay` and `openai/chat` for model requests.
- Keep the UI loop non-blocking. Enqueue requests and poll each frame.
- Keep modules procedural with explicit state objects and narrow exports.

## Source Layout

```text
src/
  adaptive_ui.nim
  adaptive_ui_app.nim
  adaptive_ui/
    app.nim
    config.nim
    agent.nim
    turn_extract.nim
    turn_view.nim
    ui_compile.nim
    ui_doc.nim
    ui_render.nim
    components.nim
    interaction.nim
    live_flow.nim
    math_view.nim
tests/
  tester.nim
examples/
  adaptive_gallery.nim
```

Module responsibilities:

- `adaptive_ui.nim`: public renderer contract re-export for examples and
  embedders.
- `adaptive_ui_app.nim`: main executable entrypoint.
- `app.nim`: window setup, event loop, outer layout, input routing, commands.
- `config.nim`: typed app config loaded and saved with `jsonx`.
- `agent.nim`: OpenAI/Relay request construction, enqueue, poll, parse.
- `turn_extract.nim`: parses compact fenced `ui` directives from chat text.
- `turn_view.nim`: typed directive data.
- `ui_compile.nim`: builds local `UiDoc` screens from directives.
- `ui_doc.nim`: typed UI document and interaction event types.
- `ui_render.nim`: resolve layout and call component renderers.
- `components.nim`: persistent component state and event constructors.
- `interaction.nim`: convert UI events and current values into user text.
- `live_flow.nim`: generic command parsing and the intro `UiDoc`.
- `math_view.nim`: basic math text fallback.

## Runtime Data Flow

One submitted turn follows this path:

1. The user types in the bottom input and presses Ctrl+Enter or Cmd+Enter.
2. `app.nim` reads the input, clears the editor, and parses generic commands.
3. Normal text is submitted through `relay.startRequests`. The submitted user
   text is held as pending state until the chat response succeeds.
4. Each frame, `pollAgent` calls `poll` to drain completed network results.
5. When chat text arrives, the user text and assistant text are committed to
   history.
6. `turn_extract.nim` removes an optional fenced `ui` directive from the visible
   text.
7. `ui_compile.nim` builds a local `UiDoc` for choice, input, or text display.
8. `ui_render.nim` resolves `doc.layout` with `parseLayout` and `resolve`.
9. Components draw inside named cells and may emit one `UiEvent`.
10. `interaction.nim` converts component events into text for the next turn.

The app tracks one pending chat request and one active Relay request id at a
time. Old results whose request id no longer matches the active request are
ignored. The render loop never blocks.

## Commands

Commands are generic:

- `/new`: clear conversation and reset runtime component state.
- Any other input: submit text to the current adaptive session.

Do not add core commands for specific tasks. If a workflow needs special
behavior, model it through a compact `ui` directive and normal event text.

## UiDoc Contract

Nim owns `UiDoc` construction:

```nim
type
  UiDoc* = object
    version*: int
    title*: string
    layout*: string
    areas*: seq[UiArea]
    focus*: string
```

The layout is a `uirelays` markdown table chosen by local code. Each area name
must match a layout cell. Area content cannot create new cells.

Supported area kinds:

- `text`: read-only plain text through `SynEdit`.
- `code`: read-only code through `SynEdit`.
- `math`: readable text with simple math substitutions.
- `radio`: choice list with persistent selected option.
- `buttons`: button row.
- `textInput`: editable multiline `SynEdit`.

Validation rules:

- `version` must be `1`.
- `layout` must be non-empty and accepted by `parseLayout`.
- Area names must be unique and must exist in the layout.
- `focus`, when non-empty, must name a layout cell.
- `radio` and `buttons` require a non-empty `id` and at least one option.
- `textInput` requires a non-empty `id`.
- Unknown kinds fail parsing.

## Component State

`UiRuntime` owns all persistent component state. Component keys use `area.id`
when present, otherwise `area.name`.

Persist only state needed across frames:

- `SynEdit` instances and last displayed text/language.
- selected radio option.
- text input value.
- current focus name.

Do not build a retained widget tree.

## Layout Strategy

The outer app layout is fixed in `app.nim`:

```text
| adaptive, * |
| input, 4 lines |
| status, 1 line |
```

The inner adaptive layout comes from `UiDoc.layout`. Resolve it using the
adaptive rect's width and height, then offset each resolved rect by the adaptive
rect origin.

## Agent Role

Chat agent:

- Answers the submitted text.
- Maintains task state in visible response text.
- May append one compact fenced `ui` directive for the next action.
- Treats UI event summaries as user interaction with the current generated UI.
- Does not force any fixed workflow unless the user asks for that shape.

The app does not load local `SKILL.md` files or inject ambient skill summaries
into prompts. Future domain packs must be explicit optional modules with tests
and must not alter the default core prompt.

## Error Handling

- Network error: show status, keep the previous `UiDoc`, and keep running.
- API error body: parse common provider error JSON and show a concise message.
- Missing API key: open in preview mode with the intro document.
- Invalid config JSON: fail at startup with the config path and parser message.

## Evidence Required

The current concept is considered working only when these are true:

- Renderer tests cover component state, selection, submit events, and layout
  resolution.
- `tests/tester.nim` compiles and runs all non-network tests with `-d:sdl3`.
- The app target and examples compile without requiring an API key.
- Live model calls, when configured, use Relay polling and never call blocking
  request APIs from the frame loop.
