# Plan 02: Component State And Events

Goal: implement persistent state for the basic component set without drawing yet.

## Scope

This plan should be completed in one agent session.

## Read First

- `docs/architecture.md`
- `docs/ui-document-format.md`
- `/home/ageralis/Projects/uirelays/src/widgets/synedit.nim`

## Tasks

1. Create `src/adaptive_ui/components.nim`.
2. Define `ComponentState` with enough state for:
   - selected radio option
   - text buffer identity
   - focus marker if needed
3. Define `UiRuntime` with:
   - table of component states keyed by component id
   - current focus area
   - status message
4. Add pure or simple procs:
   - `componentKey(area: UiArea): string`
   - `selectedOption(rt: UiRuntime; area: UiArea): string`
   - `setSelected(rt: var UiRuntime; area: UiArea; optionId: string)`
   - `eventForSelect(area: UiArea; optionId: string): UiEvent`
   - `eventForClick(area: UiArea; optionId: string): UiEvent`
   - `eventForSubmit(area: UiArea; value: string): UiEvent`
5. Create `tests/test_control_events.nim`.

## Acceptance Criteria

- Radio selection state persists by component id.
- Event constructors produce expected `UiEvent` values.
- No UI drawing is implemented in this plan.
- Tests are deterministic and use `doAssert`.

## Notes

Use `std/tables` for state storage. Keep fields plain and visible inside the module. Export only the procs needed by render and app modules.
