# Dependency Review

This repository is an Atlas-style Nim workspace. The root currently declares:

- `jsonx`
- `relay`
- `openai`
- `sdl3`
- `uirelays`

The checked-out dependency state needed by the current app is:

- `deps/sdl3`: `master`, because the older selected checkout did not include `sdl3_ttf.nim`.
- `deps/uirelays`: `highdpi`, because the initial release checkout did not include `uirelays/layout` plus `widgets/synedit`.

Do not run `atlas install` blindly until these dependency pins are represented in the Atlas workflow, because Atlas may choose older release commits.

## uirelays

Source reviewed:

- `/home/ageralis/Projects/uirelays/README.md`
- `/home/ageralis/Projects/uirelays/examples/layout_demo.nim`
- `/home/ageralis/Projects/uirelays/examples/editor.nim`
- `/home/ageralis/Projects/uirelays/examples/todo.nim`
- `/home/ageralis/Projects/uirelays/src/uirelays/layout.nim`
- `/home/ageralis/Projects/uirelays/src/widgets/synedit.nim`
- `/home/ageralis/Projects/uirelays/src/widgets/theme.nim`

Important facts:

- `import uirelays` re-exports the main UI surface and initializes the platform backend.
- This app should compile with `-d:sdl3`.
- `uirelays/layout` parses a markdown table into named `Rect`s. Use `parseLayout` and `resolve`. Do not build a separate layout solver.
- Layout syntax uses rows split by `|`. Each cell is `name, size`.
- Sizes are `Npx`, `N line`, `N lines`, `*`, or `N*`.
- `;` inside a cell creates a vertical stack of subcells.
- `hitTest(cells, x, y)` maps a point to the named layout cell.
- `SynEdit` is the ready-made immediate-mode text widget. One `draw(e, area, focused)` call handles input and rendering.
- `SynEdit` can serve as editor, read-only label, code view, console, and multiline text input.
- `SynEdit.setLabel(text)` makes a read-only text display.
- `SynEdit.setText(text)` makes editable content.
- `SynEdit.lang` selects highlighting. `fileExtToLanguage` maps file extensions to supported languages.
- `SynEdit.flags` supports markdown image lines and color literal chips.

Design consequence:

Use `uirelays/layout` for screen regions and build thin component wrappers around `SynEdit` plus a few directly drawn controls. Keep every component immediate-mode: input handling and drawing happen from one per-frame call.

## relay

Source reviewed:

- `deps/relay/README.md`
- `deps/relay/examples/basic_get.nim`
- `deps/relay/examples/streaming.nim`
- `deps/relay/src/relay.nim`

Important facts:

- `newRelay(maxInFlight, defaultTimeoutMs)` starts a worker thread.
- Use one Relay instance owned by the UI/main thread.
- Call `close` from the same thread that created the client.
- For UI apps, prefer `startRequest` or `startRequests`, then drain with `pollForResult` each frame.
- `makeRequest` is blocking and should not run from the render loop.
- Check both `item.error.kind == teNone` and HTTP status before parsing.
- Link with curl where needed: `{.passL: "-lcurl".}`.

Design consequence:

The UI loop should enqueue model calls and poll for network completions without blocking the frame loop.

## openai

Source reviewed:

- `deps/openai/README.md`
- `deps/openai/examples/live_batch_chat_polling.nim`
- `deps/openai/examples/live_tool_calling_llama.nim`
- `deps/openai/src/openai/chat.nim`

Important facts:

- The SDK is relay-native. It builds `RequestSpec`s through `chatRequest` and `chatAdd`.
- Use `chatCreate`, `systemMessageText`, `userMessageText`, and `assistantMessageText`.
- Use `formatJsonSchema` for structured output from the UI subagent, and
  validate the returned document locally with `parseUiDoc`.
- Use `chatParse` to parse raw response JSON into `ChatCreateResult`.
- Use `firstText`, `parseFirstTextJson`, `calls`, `parseFirstCallArgs`, and related accessors.
- Tool-calling support exists, but the first UI prototype can avoid tool execution unless needed.

Design consequence:

Run two logical model roles through the same SDK:

- Chat agent: produces normal assistant content and task reasoning.
- UI agent: converts the latest task state into a strict UI document.

The UI agent should return structured JSON containing a markdown layout table
and named areas. The app then uses `jsonx` to parse the result and
`uirelays/layout` to resolve the layout.

## jsonx

Source reviewed:

- `deps/jsonx/README.md`
- `deps/jsonx/src/jsonx.nim`

Important facts:

- Use `toJson` and `fromJson` for direct object serialization.
- Use `RawJson` only when a field needs to carry arbitrary JSON.
- Custom `readJson` and `writeJson` are available for discriminated shapes.
- Compile-time defines exist:
  - `jsonxLenient` skips unknown fields.
  - `jsonxNormalized` matches Nim-style names.

Design consequence:

Use typed object models for config, session state snapshots, UI documents, and UI agent responses. Avoid `std/json` for project data models.

## sdl3

The repository already declares `sdl3`. `uirelays` uses this dependency when built with `-d:sdl3`. Keep the app's documented build path on SDL3 first so behavior is consistent across platforms.

## Dependency Line

The `uirelays` dependency line is:

```nim
requires "https://github.com/nim-lang/uirelays"
```

Atlas currently writes this dependency path:

```text
--path:"deps/uirelays/src"
```
