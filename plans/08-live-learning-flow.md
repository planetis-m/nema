# Plan 08: Retired Task-Specific Live Modes

This plan is intentionally retired.

The core app no longer has dedicated live modes for narrow workflows. The live
runtime is a generic chat-to-UI pipeline:

1. Submit text.
2. Receive assistant text.
3. Generate a `UiDoc`.
4. Render the `UiDoc`.
5. Convert UI events back into text for the next turn.

Future workflow-specific behavior must be optional and expressed through the
same `UiDoc` contract. Do not add default core modes, commands, or prompt
branches for a specific domain.
