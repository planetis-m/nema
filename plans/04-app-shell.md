# Plan 04: App Shell And Scripted Learning Demo

Goal: connect the outer app layout, bottom input, adaptive renderer, and a local scripted learning flow.

## Scope

This plan should be completed in one agent session after Plan 03.

## Read First

- `docs/architecture.md`
- `/home/ageralis/Projects/uirelays/examples/editor.nim`
- `/home/ageralis/Projects/uirelays/examples/todo.nim`

## Tasks

1. Expand `src/adaptive_ui/app.nim`.
2. Define `AppState` with:
   - window width and height
   - outer layout
   - current `UiDoc`
   - `UiRuntime`
   - bottom input `SynEdit`
   - status text
   - scripted quiz state
3. Use this outer layout:

```text
| adaptive, * |
| input, 4 lines |
| status, 1 line |
```

4. Render bottom input as editable `SynEdit`.
5. Submit bottom input on Enter or Ctrl+Enter, whichever is easier and documented in code.
6. Add a local quiz script with at least 3 questions.
7. Convert each quiz step into a `UiDoc`.
8. Handle UI events:
   - radio select updates runtime state
   - submit moves to feedback or next question
   - final screen shows score and correct answers
9. Create `examples/learning_demo.nim`.

## Acceptance Criteria

- The example runs without network access.
- The user can complete the quiz from start to final score.
- The bottom input remains visible and editable.
- Status shows useful errors or current mode.
- No model API key is required.

## Notes

This demo is the first end-to-end proof. Keep it local and predictable.
