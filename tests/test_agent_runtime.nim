import std/strutils
import adaptive_ui/[agent, config]

let cfgMissing = AppConfig(
  apiUrl: "https://example.invalid/v1/chat/completions",
  apiKey: "",
  chatModel: "chat-model",
  timeoutMs: 1000
)

let cfgWithKey = AppConfig(
  apiUrl: "https://example.invalid/v1/chat/completions",
  apiKey: "sk-test",
  chatModel: "chat-model",
  timeoutMs: 1000
)

block configHasKey:
  doAssert not cfgMissing.hasKey()
  doAssert AppConfig(
    apiUrl: "", apiKey: "sk-test", chatModel: "",
    timeoutMs: 0
  ).hasKey()

block promptWorkflowRules:
  doAssert "Chat Agent" in ChatBasePrompt
  doAssert "lettered lines" in ChatBasePrompt
  doAssert "The app always provides a text input" in ChatBasePrompt
  doAssert "UI event summaries" in ChatBasePrompt
  doAssert "```ui" in ChatBasePrompt

  doAssert "quiz-style" notin ChatBasePrompt

block apiOpenAIError:
  let text = apiErrorMessage(422,
    """{"error":{"message":"Field required","type":"invalid_request_error","param":"messages","code":null}}""")
  doAssert text == "HTTP 422: Field required (type: invalid_request_error, param: messages)"

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

block pendingSubmit:
  var state = initAgentState(cfgWithKey)
  defer: state.close()

  doAssert state.submitChat("hello") == ""
  doAssert state.hasPending()
  doAssert state.hasPendingChat()
  doAssert state.chatHistory.len == 0

  let err = state.submitChat("again")
  doAssert "in progress" in err
  doAssert state.chatHistory.len == 0

  state.clearPending()
  doAssert not state.hasPending()
  doAssert state.chatHistory.len == 0

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
