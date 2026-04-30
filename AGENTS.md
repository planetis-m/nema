# Repository Guidance

This repository is for a Nim-only adaptive UI app.

Before implementing, read:

- `docs/architecture.md`
- `docs/dependency-review.md`
- `docs/agent-guidance.md`
- the specific file under `plans/` for the task

Core rules:

- Use `uirelays` with `-d:sdl3` for UI.
- Use `uirelays/layout.parseLayout` for generated layouts.
- Use `SynEdit` for text, code, transcript, and multiline input surfaces.
- Use `jsonx` for config, state, and agent response parsing.
- Do not use `std/json` for project data models.
- Use `relay` and `openai/chat` for model requests.
- Keep the UI loop non-blocking.
- Keep Nim code procedural with explicit state objects and narrow exports.

The implementation plan is split across `plans/README.md`. Complete one plan at a time.
