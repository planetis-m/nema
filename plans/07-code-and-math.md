# Plan 07: Code And Basic Math Rendering

Goal: improve display quality for code and math without expanding the UI
contract or adding markdown rendering.

## Scope

This plan should be completed after the renderer works.

## Read First

- `/home/ageralis/Projects/uirelays/src/widgets/synedit.nim`
- `/home/ageralis/Projects/uirelays/src/widgets/theme.nim`
- `docs/ui-document-format.md`

## Tasks

1. Create `src/adaptive_ui/math_view.nim`.
2. Implement basic math fallback:
   - inline math text stays inline
   - block math is centered or indented as plain text
   - common ASCII substitutions are readable
3. Keep `ukCode` backed by `SynEdit`.
4. Add language mapping for at least:
   - nim
   - c
   - cpp
   - js
   - html
   - xml
   - text

## Acceptance Criteria

- Code blocks in `ukCode` show syntax highlighting when supported by `SynEdit`.
- Unknown languages render as plain text.
- Math text does not crash the renderer.
- Long text remains scrollable through `SynEdit`.

## Notes

Do not add a Markdown renderer. The UI agent must map headings, lists, and code
blocks into explicit `UiDoc` areas before rendering. Do not add a full LaTeX
parser; the first version needs legible display, not typesetting completeness.
