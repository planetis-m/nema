# Adaptive UI Design Specification

## 1. Scope

The adaptive UI app is a Nim desktop application that renders locally generated
UI documents. The core system is not a quiz app, essay app, chat client, tutor, or
workflow engine. It is a generic `UiDoc` renderer plus a non-blocking agent
runtime.

The product exists to turn the next action in a chat-agent response into an
interface. It must not simply display assistant text when an action is available.
A multiple-choice prompt should become selectable controls, and typed input
should become a text input with a Submit affordance.

There is no markdown renderer in the adaptive surface. Text areas display plain
text. The chat agent may append a compact fenced `ui` directive; Nim chooses the
layout and builds the controls.

Task-specific workflows must be expressed as generated `UiDoc` data and normal
`UiEvent` summaries. Do not add hardcoded core modes, prompts, commands, or
embedded instruction files for a specific use case.

## 2. Visible UI

The window has two stable zones:

- Adaptive surface: renders the current `UiDoc`.
- Input bar: persistent multiline `SynEdit` input.

The app also has a one-line status area. The status area is for runtime state
such as missing API key, network errors, parse errors, and pending requests.

## 3. Supported Primitives

The core renderer supports these primitives:

- `text`
- `code`
- `math`
- `radio`
- `buttons`
- `textInput`

These primitives are composable. They are not application modes.

## 4. Hard Constraints

- Application code is Nim only.
- Build with `-d:sdl3`.
- Use `uirelays` for the window, events, and drawing surface.
- Use `uirelays/layout.parseLayout` and `resolve` for layout rectangles.
- Use `SynEdit` for all text-like surfaces.
- Use `jsonx` for config, state, and agent response objects.
- Do not use `std/json` for project data models.
- Use `relay` and `openai/chat` for model requests.
- Never call blocking request APIs from the render loop.
- Use procedural modules, plain state objects, and procs.
- Keep exports narrow.

## 5. Source Layout

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
```

Core modules:

- `app.nim`: owns `AppState`, the window loop, outer layout, commands, input
  routing, and agent polling.
- `agent.nim`: owns `AgentState`, conversation history, Relay requests, OpenAI
  parsing, retry, and chat flow.
- `turn_extract.nim`: parses optional fenced `ui` directives from chat text.
- `turn_view.nim`: owns the directive data types.
- `ui_compile.nim`: compiles directives into local `UiDoc` values.
- `ui_doc.nim`: owns the typed document and event contract.
- `ui_render.nim`: resolves layouts and renders areas.
- `components.nim`: stores persistent component state and creates events.
- `interaction.nim`: converts events and current UI values into text.
- `live_flow.nim`: parses generic commands and creates the intro document.

Removed from core:

- Skill-file loading.
- Automatic prompt injection from local `SKILL.md` files.
- Dedicated modes or commands for any specific task class.

## 6. Runtime Flow

One normal submitted turn:

1. User submits text from the bottom input.
2. `handleSubmittedInput` parses generic slash commands.
3. Normal text calls `submitChat`.
4. `submitChat` starts a Relay request and stores the submitted text as pending
   state.
5. Each frame calls `pollAgent`.
6. When chat text arrives, the pending user text and assistant text are
   committed to history.
7. `turn_extract.nim` removes an optional fenced `ui` directive from visible
   text.
8. `ui_compile.nim` builds a local `UiDoc`.
9. The new document replaces the current document.

The app has one pending phase at a time: idle or waiting for chat.
`AgentState` stores the active Relay request id and ignores stale results.
This keeps execution deterministic and avoids competing writes to conversation
state.

## 7. Commands

The input bar recognizes only generic commands:

| Command | Behavior |
|---|---|
| `/new` | Clear conversation and component state. |
| anything else | Submit text to the current adaptive session. |

Do not add commands for a narrow workflow. A generated document can include
buttons or inputs for workflow steps.

## 8. UiDoc

Nim constructs one `UiDoc` value:

```nim
type
  UiKind* = enum
    ukText, ukCode, ukRadio, ukButtons, ukTextInput, ukMath

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
```

JSON kind names are exact:

| JSON | Nim |
|---|---|
| `text` | `ukText` |
| `code` | `ukCode` |
| `radio` | `ukRadio` |
| `buttons` | `ukButtons` |
| `textInput` | `ukTextInput` |
| `math` | `ukMath` |

Validation:

- `version == 1`.
- `layout.strip.len > 0`.
- `parseLayout(layout)` succeeds.
- `areas.len > 0`.
- Every `area.name` is non-empty, unique, and present in the layout.
- `focus`, when non-empty, is present in the layout.
- `radio` and `buttons` require non-empty `id` and non-empty `options`.
- Each option requires non-empty `id` and `label`.
- `textInput` requires non-empty `id`.

## 9. Events

```nim
type
  UiEventKind* = enum
    ueNone, ueClick, ueSelect, ueSubmitText

  UiEvent* = object
    kind*: UiEventKind
    area*: string
    id*: string
    value*: string
```

Event meaning:

- `ueSelect`: a radio option changed. `id` is the control id. `value` is the
  option id.
- `ueClick`: a button was clicked. `id` is the button option id.
- `ueSubmitText`: a text input was submitted. `id` is the input id. `value` is
  the submitted text.

`interaction.nim` must include current UI values when a button click depends on
selections or text input.

## 10. Rendering

Rendering is immediate-mode. `renderUiDoc` receives the current document, runtime
state, one routed event, the adaptive rect, font metrics, and theme. It returns
zero or one `UiEvent`.

Rules:

- Resolve `doc.layout` inside the adaptive rect.
- Offset resolved cells by the adaptive rect origin.
- Draw missing cells as empty panels.
- Set initial focus from `doc.focus` when runtime focus is empty.
- Route keyboard input only to the focused area.
- Route mouse clicks by layout hit testing.
- Reuse `SynEdit` instances from `UiRuntime.components`.
- Store component state by `area.id` when present, otherwise `area.name`.

## 11. Agent Prompts

`ChatBasePrompt` must stay generic:

- Answer the user.
- Maintain enough visible task state for UI generation, including one
  `Next action: choose one|type|none` line when an action is needed.
- Put choice labels under `Options:` and put code in fenced blocks with a
  language name.
- Treat UI event summaries as user interaction.
- Do not force a fixed interaction pattern unless the user requested it.

`UiBasePrompt` must stay generic:

- Return only one valid `UiDoc` JSON object.
- Convert the latest chat response structure into explicit components.
- Use only supported kinds.
- Keep layouts compact.
- Choose the smallest UI that fits current task state.
- Put code in `code` areas and choices in `radio`/`buttons`; do not rely on
  markdown rendering.
- Emit plain text in `text` areas; do not pass markdown for the renderer to
  interpret.
- Do not reference unsupported app capabilities.

Do not add prompt branches for specific workflows in `agent.nim`. Optional
domain behavior must be passed as explicit user/session context in a future
extension point, not loaded implicitly from local files.

## 12. Config

`AppConfig` contains only runtime configuration:

```json
{
  "apiUrl": "https://api.openai.com/v1/chat/completions",
  "apiKey": "",
  "chatModel": "gpt-4.1-mini",
  "timeoutMs": 30000
}
```

`initAppConfig` reads `OPENAI_API_KEY` and sets the built-in defaults.
`loadConfig(path)` starts from those defaults, then overlays `path` with
`jsonx.fromFile(Path(path), result)` when the file exists. `saveConfig` must
never write the API key.

## 13. Error Handling

- Invalid config: fail startup with the config path and parser message.
- Missing API key: show intro document and status. Do not start model requests.
- Chat request error: parse provider error JSON when possible, show a clear
  status message, and keep the current document.
- Closed agent: return an error string to the app instead of raising.

## 14. Tests

Tests use standalone Nim files and `doAssert`.

Required coverage:

- Config parse/save and API key omission.
- Directive parsing and local `UiDoc` compilation.
- Component keys, selection state, text state, and event constructors.
- Interaction text conversion.
- Generic command parsing.
- Agent state initialization, empty input, and history clearing.
- Provider API error parsing for OpenAI-style responses.
- Renderer state helpers and layout resolution.
- Debug log and math helpers.

Run:

```sh
nim c -d:sdl3 -r tests/tester.nim
```

The app target and examples must compile without network access.

## 15. Current Evidence

The core concept is proven for the current generic path:

- Directive parsing and local `UiDoc` compilation exist.
- Static renderer examples compile.
- Component state and event conversion are tested.
- The app uses Relay polling instead of blocking network calls.
- Live provider probes confirm chat responses can drive adaptive controls through
  fenced `ui` directives.

Remaining risks:

- Automated visual assertions for rendered output.
- Long-session component cleanup under unstable generated ids.
- Persistence of conversation or generated documents.

## 16. Future Extension Rules

Any future domain extension must satisfy these rules:

- It is optional and disabled by default.
- It does not change the generic core prompts.
- It does not add default core commands for a narrow use case.
- It has deterministic tests.
- It expresses UI through the same `UiDoc` contract.
- It documents exactly what state it owns and how it is reset.
