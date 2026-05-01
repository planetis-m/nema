import std/strutils
import jsonx
import adaptive_ui/[agent, config, ui_schema]

let cfgMissing = AppConfig(
  apiUrl: "https://example.invalid/v1/chat/completions",
  apiKey: "",
  chatModel: "chat-model",
  uiModel: "ui-model",
  timeoutMs: 1000
)

block configHasKey:
  doAssert not cfgMissing.hasKey()
  doAssert AppConfig(
    apiUrl: "", apiKey: "sk-test", chatModel: "",
    uiModel: "", timeoutMs: 0
  ).hasKey()

block responseFormat:
  let text = toJson(uiDocFmt)
  doAssert "\"type\":\"json_schema\"" in text
  doAssert "\"name\":\"ui_doc\"" in text
  doAssert "\"strict\":true" in text
  doAssert "\"enum\":[\"text\",\"code\",\"radio\",\"buttons\",\"textInput\",\"math\",\"transcript\"]" in text
  doAssert "\"required\":[\"version\",\"title\",\"layout\",\"focus\",\"areas\"]" in text
  doAssert "\"required\":[\"id\",\"label\",\"selected\"]" in text

block apiOpenAIError:
  let text = apiErrorMessage(422,
    """{"error":{"message":"Field required","type":"invalid_request_error","param":"messages","code":null}}""")
  doAssert text == "HTTP 422: Field required (type: invalid_request_error, param: messages)"

block apiFastApiError:
  let text = apiErrorMessage(422,
    """{"detail":[{"type":"missing","loc":["body","prompt"],"msg":"Field required","input":{}}]}""")
  doAssert text == "HTTP 422: Field required (type: missing, field: body.prompt)"

block missingKey:
  var state = initAgentState(cfgMissing)
  defer: state.close()

  doAssert not state.hasPending()
  doAssert state.chatHistory.len == 0

block emptyInput:
  var state = initAgentState(cfgMissing)
  defer: state.close()

  let err = state.submitChat("   ")
  doAssert "empty" in err

block missingKeySubmit:
  var state = initAgentState(cfgMissing)
  defer: state.close()

  let err = state.submitChat("hello")
  doAssert "OPENAI_API_KEY" in err
  doAssert state.chatHistory.len == 0
  doAssert not state.hasPending()

block clearNewState:
  var state = initAgentState(cfgMissing)
  defer: state.close()

  state.clearHistory()
  doAssert state.chatHistory.len == 0

block clearHistory:
  var state = initAgentState(cfgMissing)
  defer: state.close()

  state.chatHistory.add ChatEntry(role: arUser, content: "test")
  doAssert state.chatHistory.len == 1

  state.clearHistory()
  doAssert state.chatHistory.len == 0
