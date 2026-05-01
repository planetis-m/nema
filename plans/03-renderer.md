# Plan 03: Adaptive Renderer

Goal: render a `UiDoc` into the adaptive area using `uirelays/layout` and basic components.

## Scope

This plan should be completed in one agent session after Plans 01 and 02.

## Read First

- `docs/architecture.md`
- `docs/ui-document-format.md`
- `/home/ageralis/Projects/uirelays/examples/layout_demo.nim`
- `/home/ageralis/Projects/uirelays/examples/todo.nim`
- `/home/ageralis/Projects/uirelays/src/widgets/synedit.nim`

## Tasks

1. Create `src/adaptive_ui/ui_render.nim`.
2. Resolve `doc.layout` with `parseLayout` and `resolve`.
3. Offset resolved inner rects into the adaptive parent rect.
4. Route one `Event` into the component for the focused area.
5. Render:
   - `ukText` with read-only `SynEdit`
   - `ukCode` with read-only `SynEdit`, line numbers, and language mapping
   - `ukRadio` with direct drawing and click hit testing
   - `ukButtons` with direct drawing and click hit testing
   - `ukTextInput` with editable `SynEdit`
   - `ukMath` as text for now
6. Return a `UiEvent` from the renderer when a component action happens.
7. Keep drawing simple: background, border, text, selected state, hover state.
8. Add a renderer smoke example with a hardcoded generic document.

## Acceptance Criteria

- Hardcoded generic UI renders.
- Mouse click selects a radio option.
- Submit button emits a `ueClick`.
- Text and code areas render through `SynEdit`.
- Layout errors fall back to a single text area instead of crashing.

## Notes

Do not add model calls in this plan. Keep the renderer usable with static documents.
