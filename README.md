# Adaptive UI

Nim-only AI-driven adaptive UI app. A chat agent handles task state and can
append tiny `ui` directives. The app compiles those directives into interactive
surfaces locally.

The app has a stable text input at the bottom and an adaptive surface above it.
The adaptive surface renders generic primitives: text, code, math, radio
choices, button rows, and multiline text input.

The UI adapts to the next action in the chat response. It does not ask the
model to generate JSON or layout strings.

## Build

The main executable is `src/adaptive_ui_app.nim`.

```sh
nim c -d:sdl3 src/adaptive_ui_app.nim
./src/adaptive_ui_app
```

Run core tests and compile checks:

```sh
nim c -d:sdl3 -r tests/tester.nim
```

## Configuration

The app reads `adaptive_ui.json` from the current working directory. If the file
is missing, defaults are used.

```json
{
  "apiUrl": "https://api.openai.com/v1/chat/completions",
  "apiKey": "",
  "chatModel": "gpt-4.1-mini",
  "timeoutMs": 30000
}
```

Set the API key with the environment variable:

```sh
export OPENAI_API_KEY="sk-..."
./src/adaptive_ui_app
```

To use a different endpoint, edit `apiUrl` in `adaptive_ui.json`. Leave
`apiKey` empty unless you intentionally want the key stored in that local file.

## Commands

- `/new`: reset the session.
- Anything else: submit text to the adaptive session.

## Design

Read `docs/design-v2.md` for the executable specification.
