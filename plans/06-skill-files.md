# Plan 06: SKILL File Support

Goal: load local `SKILL.md` files and make them available to the chat agent context.

## Scope

This plan should be completed after basic agent runtime exists. It should not implement a full plugin marketplace.

## Read First

- `docs/architecture.md`
- Existing local skill files under `/home/ageralis/.agents/skills` and `/home/ageralis/.codex/skills` for shape reference.

## Tasks

1. Create `src/adaptive_ui/skill_files.nim`.
2. Define:
   - `SkillInfo`
   - `SkillLibrary`
3. Support explicit skill roots from config.
4. Recursively find files named `SKILL.md`.
5. Parse only the frontmatter fields needed for first version:
   - `name`
   - `description`
6. Store:
   - name
   - description
   - path
   - full markdown content
7. Add lookup by skill name.
8. Add a summarizer proc that emits a compact list for prompts.
9. Add deterministic tests with temporary fixture folders under `tests/fixtures` or `/tmp`.

## Acceptance Criteria

- Loads multiple `SKILL.md` files.
- Handles missing frontmatter gracefully.
- Lookup by name is deterministic.
- Agent prompt context can include a compact skill list.
- No network or model call is required for tests.

## Notes

Do not execute code from skill files. This plan only reads markdown instructions for context.
