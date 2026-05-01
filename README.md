# Adaptive UI

Nim-only AI-driven adaptive UI app. A chat agent handles task logic and a UI
subagent generates interactive surfaces from structured JSON.

The app has a stable text input at the bottom and an adaptive surface above it.
The adaptive surface renders `UiDoc` JSON documents containing text, code,
radio groups, button rows, multiline text inputs, math text, and chat
transcripts. Quiz and essay flows are built-in modes, not the app's only
identity.

## Build

The repo includes `config.nims`, so SDL3 is enabled by default.

Run all tests and example compile checks:

```sh
nim c -r tests/tester.nim
```

## Running

Adaptive app (no API key required to open):

```sh
nim c -r examples/adaptive_app.nim
./examples/adaptive_app
```

Without an API key the app shows the adaptive surface intro screen and reports
that live generation needs configuration.

With an API key:

```sh
cp adaptive_ui.example.json adaptive_ui.json
export OPENAI_API_KEY=...
./examples/adaptive_app
```

Input commands:

- `/adaptive plan a product launch checklist`
- `/chat ask a normal question`
- `/quiz Nim basics`
- `/essay ownership in Nim`
- `/debug`

Plain input stays in adaptive task mode. Quiz and essay are explicit shortcuts.

Component gallery:

```sh
nim c -r examples/adaptive_gallery.nim
./examples/adaptive_gallery
```

Scripted quiz demo:

```sh
nim c -r examples/learning_demo.nim
./examples/learning_demo
```

## Design

Read `docs/design-v2.md` for the full specification. It covers the UiDoc
contract, component rendering, layout strategy, agent roles, data flow, error
handling, config, and testing.

## Files To Read Before Coding

- `docs/design-v2.md`
- `docs/dependency-review.md`
- `AGENTS.md`

## Notes

- Application code is Nim only.
- Use `uirelays/layout.parseLayout` for generated layouts.
- Use `SynEdit` for text-like surfaces.
- Use `jsonx` for config, state, and agent response models.
- Do not use `std/json` for project data models.
