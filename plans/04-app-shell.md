# Plan 04: App Shell And Generic Renderer Demo

Goal: connect the outer app layout, bottom input, adaptive renderer, and generic
local documents.

## Scope

This plan should be completed after Plan 03.

## Read First

- `docs/architecture.md`
- `/home/ageralis/Projects/uirelays/examples/editor.nim`
- `/home/ageralis/Projects/uirelays/examples/todo.nim`

## Tasks

1. Expand `src/adaptive_ui/app.nim`.
2. Define explicit `AppState` with window size, outer layout, current `UiDoc`,
   `UiRuntime`, bottom input `SynEdit`, status, debug log, and agent state.
3. Use this outer layout:

```text
| adaptive, * |
| input, 4 lines |
| status, 1 line |
```

4. Render bottom input as editable `SynEdit`.
5. Submit bottom input on Ctrl+Enter or Cmd+Enter.
6. Add a generic intro document with neutral actions.
7. Support only generic commands: `/new` and `/debug`.
8. Route renderer events through `interaction.nim`.
9. Keep optional domain demos out of `app.nim`.

## Acceptance Criteria

- The app starts without network access.
- The bottom input remains visible and editable.
- Static `UiDoc` examples render.
- Generic command parsing is tested.
- No core command, prompt, or state enum is tied to a narrow workflow.
