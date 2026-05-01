# Plan 06: Retired Ambient Skill Loading

This plan is intentionally retired.

Ambient loading of local `SKILL.md` files was removed from the core app because
it made behavior depend on machine-local instruction files and injected
unbounded task-specific context into every request.

Future domain extensions may add explicit optional instruction packs only if
they satisfy the rules in `docs/design-v2.md`:

- disabled by default
- no changes to generic core prompts
- no narrow default commands
- deterministic tests
- all UI expressed through `UiDoc`
