# Implementation Plans

These plans are ordered so each one fits a limited-context agent session.

1. `00-bootstrap.md`: make the repo compile a minimal uirelays SDL3 app.
2. `01-ui-doc-model.md`: define and parse the UI document contract.
3. `02-component-state.md`: add persistent component state and events.
4. `03-renderer.md`: render a static adaptive UI document.
5. `04-app-shell.md`: connect the app shell and generic local renderer demo.
6. `05-agent-runtime.md`: add non-blocking OpenAI/Relay calls.
7. `06-skill-files.md`: retired; ambient local skill loading was removed from core.
8. `07-code-and-math.md`: improve code and basic math display.
9. `08-live-learning-flow.md`: retired; task-specific live modes were removed from core.

Each plan lists its own read-first files, scope, tasks, and acceptance criteria. Agents should complete one plan at a time and avoid pulling in later-plan work unless a compile blocker requires a tiny placeholder.
