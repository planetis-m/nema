# Plan 08: Live Learning Flow

Goal: use the chat agent and UI agent together for quiz and essay workflows.

## Scope

This plan should be completed after Plans 04 and 05.

## Read First

- `docs/architecture.md`
- `prompts/ui-subagent-system.md`
- `plans/05-agent-runtime.md`

## Tasks

1. Add a mode enum:
   - local demo
   - live chat
   - live quiz
   - live essay
2. For live quiz:
   - user asks for a topic
   - chat agent creates one question at a time
   - UI agent renders question, choices, and submit button
   - app sends selected answer back to chat agent
   - chat agent tracks score
3. For live essay:
   - chat agent creates prompt and grading rubric
   - UI agent renders prompt and text input
   - app sends essay response back to chat agent
   - chat agent returns grade and feedback
4. Keep state machine explicit in `AppState`.
5. Add transcript display mode so the user can see normal chat output if UI generation fails.

## Acceptance Criteria

- A quiz can proceed one question at a time through generated UI.
- An essay answer can be submitted and graded.
- The user can return to normal chat mode.
- Failed UI generation falls back to transcript text.

## Notes

Do not try to support arbitrary games yet. The same event model will support yes/no decision games after quiz and essay are stable.
