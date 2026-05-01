# Plan 00: Bootstrap The Workspace

Goal: make the repository compile a minimal uirelays SDL3 window.

## Scope

This plan should be completed in one agent session.

## Read First

- `docs/dependency-review.md`
- `/home/ageralis/Projects/uirelays/README.md`
- `/home/ageralis/Projects/uirelays/examples/hello.nim`
- `/home/ageralis/Projects/uirelays/examples/layout_demo.nim`

## Tasks

1. Add `uirelays` to `ui.nimble`.
2. Refresh dependency paths using the repository's Atlas workflow if available.
3. If Atlas cannot fetch in the current environment, add a documented temporary local path for `/home/ageralis/Projects/uirelays/src` and do not hide that workaround.
4. Create `src/adaptive_ui.nim` as the public re-export placeholder.
5. Create `src/adaptive_ui/app.nim` with a minimal SDL3 window, event loop, and shutdown.
6. Compile the main app target as the minimal window smoke test.
7. Compile with:

```sh
nim c -d:sdl3 src/adaptive_ui_app.nim
```

## Acceptance Criteria

- The example compiles with `-d:sdl3`.
- The window opens, handles close events, and exits cleanly.
- No live network calls are added.
- No adaptive UI logic is added yet.

## Notes

Use the uirelays pattern:

```nim
let win = createWindow(900, 600)
while running:
  var e = default Event
  while pollEvent(e):
    case e.kind
    of QuitEvent, WindowCloseEvent:
      running = false
    else:
      discard
  refresh()
shutdown()
```
