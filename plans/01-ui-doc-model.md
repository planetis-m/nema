# Plan 01: UI Document Model And Parser

Goal: define and parse the UI document contract with `jsonx`.

## Scope

This plan should be completed in one agent session. Do not implement rendering in this step.

## Read First

- `docs/architecture.md`
- `docs/ui-document-format.md`
- `deps/jsonx/README.md`

## Tasks

1. Create `src/adaptive_ui/ui_doc.nim`.
2. Define:
   - `UiKind`
   - `UiOption`
   - `UiArea`
   - `UiDoc`
   - `UiEventKind`
   - `UiEvent`
3. Add constructors for fallback documents:
   - `fallbackUiDoc(message: string): UiDoc`
   - `textUiDoc(title, text: string): UiDoc`
4. Create `src/adaptive_ui/ui_parse.nim`.
5. Add `parseUiDoc(text: string; doc: var UiDoc; err: var string): bool`.
6. Use `jsonx.fromJson`, not `std/json`.
7. Add explicit `UiKind` JSON mapping if needed so JSON uses `text`, `code`, `radio`, `buttons`, `textInput`, `math`, and `transcript`.
8. Validate after parsing:
   - `version == 1`
   - layout is non-empty
   - area names are non-empty
   - interactive areas have ids
   - radio/buttons have options
9. Create `tests/test_ui_doc_parse.nim`.

## Acceptance Criteria

- Valid sample JSON from `docs/ui-document-format.md` parses.
- Invalid version fails.
- Empty layout fails.
- Radio without options fails.
- Parser returns `false` and a useful `err` instead of raising to callers.

## Notes

Keep layout parsing validation shallow in this plan. Calling `parseLayout` can happen later in renderer tests.
