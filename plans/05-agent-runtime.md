# Plan 05: Agent Runtime With Relay And OpenAI

Goal: add non-blocking model requests for chat and UI generation.

## Scope

This plan should be completed after the local demo works.

## Read First

- `docs/dependency-review.md`
- `deps/relay/README.md`
- `deps/openai/README.md`
- `deps/openai/examples/live_batch_chat_polling.nim`
- `deps/openai/examples/live_tool_calling_llama.nim`
- `prompts/ui-subagent-system.md`

## Tasks

1. Create `src/adaptive_ui/config.nim`.
2. Define typed config:
   - API URL
   - API key environment variable name
   - chat model
   - UI model
   - timeout ms
3. Create `src/adaptive_ui/agent.nim`.
4. Define conversation message storage using OpenAI chat message types where practical.
5. Initialize one `Relay` client in `AppState`.
6. Add request ids that distinguish chat and UI requests.
7. Enqueue chat request when bottom input is submitted.
8. Poll `Relay.pollForResult` every frame.
9. Parse chat responses with `chatParse`.
10. Enqueue UI request after a chat response arrives.
11. Use `formatJsonSchema` or strict JSON response format for `UiDoc`.
12. Parse UI response with `parseUiDoc`.
13. Never call blocking `makeRequest` from the render loop.

## Acceptance Criteria

- App starts without API key and keeps local demo mode available.
- With API key configured, a submitted message triggers chat and UI requests.
- Network errors are shown in status and do not close the app.
- Failed UI JSON keeps the previous UI document.
- Relay is closed from the same thread that created it.

## Notes

The first live version can use sequential chat then UI generation. Do not add streaming until this path is stable.
