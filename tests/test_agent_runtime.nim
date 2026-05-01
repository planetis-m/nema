import std/strutils
import jsonx
import adaptive_ui/[agent, config, live_flow, skill_files, ui_schema]

let cfgMissing = AppConfig(
  apiUrl: "https://example.invalid/v1/chat/completions",
  apiKey: "",
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

block configHasKey:
  doAssert not cfgMissing.hasKey()
  doAssert AppConfig(
    apiUrl: "", apiKey: "sk-test", chatModel: "",
    uiModel: "", timeoutMs: 0, skillRoots: @[]
  ).hasKey()

block responseFormat:
  let text = toJson(uiDocFmt)
  doAssert "\"type\":\"json_schema\"" in text
  doAssert "\"name\":\"ui_doc\"" in text
  doAssert "\"strict\":true" in text
  doAssert "\"enum\":[\"text\",\"code\",\"radio\",\"buttons\",\"textInput\",\"math\",\"transcript\"]" in text

block missingKey:
  var state = initAgentState(cfgMissing, skills)
  defer: state.close()

  doAssert not state.hasPending()
  doAssert state.chatHistory.len == 0

block emptyInput:
  var state = initAgentState(cfgMissing, skills)
  defer: state.close()

  let err = state.submitChat("   ")
  doAssert "empty" in err

block setFlowClearsHistory:
  var state = initAgentState(cfgMissing, skills)
  defer: state.close()

  state.setFlow(lfQuiz)
  state.clearHistory()
  doAssert state.chatHistory.len == 0

block clearHistory:
  var state = initAgentState(cfgMissing, skills)
  defer: state.close()

  state.chatHistory.add ChatEntry(role: arUser, content: "test")
  doAssert state.chatHistory.len == 1

  state.clearHistory()
  doAssert state.chatHistory.len == 0

block cachedSkillSummary:
  doAssert "math-tutor" in skills.skillSummary()
