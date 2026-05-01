import std/strutils
import jsonx
import adaptive_ui/[agent, config, skill_files, ui_doc]

let cfg = AppConfig(
  apiUrl: "https://example.invalid/v1/chat/completions",
  apiKeyEnv: "ADAPTIVE_UI_TEST_MISSING_KEY",
  chatModel: "chat-model",
  uiModel: "ui-model",
  timeoutMs: 1000,
  skillRoots: @[]
)

let skills = SkillLibrary(skills: @[
  SkillInfo(
    name: "math-tutor",
    description: "Explain math carefully.",
    path: "tests/fixtures/skills/math/SKILL.md",
    content: "# Math"
  )
])

block promptBuilders:
  let messages = buildChatMessages([], skills, "Teach fractions")
  doAssert messages.len == 2

  let prompt = buildUiPrompt(@[
    AgentMessage(role: amUser, content: "Quiz me"),
    AgentMessage(role: amAssistant, content: "Question: 2 + 2?")
  ], textUiDoc("Current", "Old screen"), skills)
  doAssert "Conversation so far" in prompt
  doAssert "math-tutor" in prompt
  doAssert "\"version\":1" in prompt
  doAssert "Return the next UiDoc JSON only." in prompt

block responseFormat:
  let text = toJson(uiDocResponseFormat())
  doAssert "\"type\":\"json_schema\"" in text
  doAssert "\"name\":\"ui_doc\"" in text
  doAssert "\"strict\":true" in text

block missingKey:
  var rt = initAgentRuntime(cfg, skills, "UI prompt")
  defer: rt.close()

  doAssert not rt.hasLiveConfig()
  doAssert rt.pendingRequests() == 0

  var err = ""
  doAssert not rt.submitUserText("hello", err)
  doAssert "API key missing" in err
  doAssert rt.history.len == 0

block emptyInput:
  var rt = initAgentRuntime(cfg, skills, "UI prompt")
  defer: rt.close()

  var err = ""
  doAssert not rt.submitUserText("   ", err)
  doAssert "empty" in err
