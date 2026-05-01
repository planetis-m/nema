# Agent Implementation Guidance

Use this file as the standing instruction for coding agents working in this repository.

## Style

- Write Nim code only unless a C FFI binding is explicitly needed.
- Indent with 2 spaces.
- Use `PascalCase` for types and `camelCase` for procs, vars, and fields.
- Prefer plain `object` state passed by `var`.
- Prefer top-level helper procs.
- Use `proc` by default. Use `func` only for pure query helpers.
- Avoid `method` unless runtime dispatch is truly needed.
- Keep exported API narrow.
- Do not hide app state in globals. Backend relay globals from `uirelays` are fine because that is how the library works.

## Dependency Rules

- Use `jsonx` for app data, config, and model response objects.
- Do not use `std/json` for data models.
- Use `relay` request polling in the UI loop. Do not block the UI loop with `makeRequest`.
- Use `openai/chat` helpers for model requests.
- Use `uirelays/layout.parseLayout`; do not write a replacement layout parser.
- Use `SynEdit` for labels, code, transcript views, and text inputs unless there is a concrete reason not to.

## UI Rules

- Immediate mode only for the first version.
- One frame should process one input event batch, draw the UI, and refresh.
- Component state must be stored in `AppState`, `UiRuntime`, or `ComponentState`.
- Components receive the current `Event`, target `Rect`, focus state, and relevant persistent state.
- Components return zero or one `UiEvent`.
- Route focus by area name from layout hit testing.
- Keep the bottom input area stable even when the adaptive UI fails.

## Parsing Rules

- The UI agent returns JSON parsed by `jsonx`.
- The `layout` field is the only layout definition.
- `layout` is passed to `parseLayout`.
- Area content is not allowed to create new layout cells.
- Unknown area fields are ignored only if the parser is explicitly built with a lenient path.

## Testing Rules

- Tests are standalone Nim files using `doAssert`.
- Avoid `unittest` unless the repository later standardizes on it.
- Test pure parsing and state transitions first.
- UI rendering can start with smoke builds because pixel-perfect tests are not needed for the first pass.

## Build Rules

Preferred compile checks after implementation starts:

```sh
nim c -d:sdl3 -r tests/tester.nim
```

When live OpenAI calls are added, keep those examples opt-in through environment variables. Tests must not require network access or API keys.
