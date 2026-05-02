import std/strutils
import jsonx
import relay
import openai/chat
import openai/retry
import ./config

{.passL: "-lcurl".}

const
  ChatBasePrompt* = """
You are the Chat Agent for an adaptive desktop app. Answer the user's task and
keep the task state in visible plain text.

Do not mention JSON, layouts, renderers, tabs, or implementation details.
Do not rely on hidden state for information the user needs to choose the next
step.
Treat UI event summaries from buttons, selections, and text inputs as the
user's answer to the current screen.

When choices are useful, write them as short lettered lines:
A) First option
B) Second option

When typed input is useful, ask directly for the exact input needed.
The app always provides a text input below your response, so do not create or
describe UI controls in prose.

When the response should create adaptive controls, append one small fenced
directive block at the end. The user will not see this block.

For choices:
```ui
choice
title: Short screen title
prompt: Short question
option: a | First option label
option: b | Second option label
```

For typed input:
```ui
input
title: Short screen title
prompt: Ask for the exact input needed
placeholder: Example input
```

Only use the directive block for the current next action. Keep labels concise."""

  MaxRetries = 3

type
  AgentRole* = enum
    arUser,
    arAssistant

  ChatEntry* = object
    role*: AgentRole
    content*: string

  AgentPhase = enum
    apIdle,
    apWaitingChat

  ResultKind* = enum
    resChatText,
    resError

  AgentResult* = object
    kind*: ResultKind
    text*: string
    error*: string

  AgentState* = object
    client*: Relay
    endpoint: OpenAIConfig
    cfg*: AppConfig
    chatMessages: seq[ChatMessage]
    chatHistory*: seq[ChatEntry]
    phase: AgentPhase
    attempt: int
    activeRequestId: int64
    pendingChatMessages: seq[ChatMessage]
    pendingUserText: string
    nextId: int64

  ApiErrorObject = object
    message: string
    `type`: string
    param: string
    code: RawJson

  ApiErrorEnvelope = object
    error: ApiErrorObject

  ApiDetailItem = object
    `type`: string
    loc: seq[string]
    msg: string

  ApiDetailListEnvelope = object
    detail: seq[ApiDetailItem]

proc initAgentState*(cfg: AppConfig): AgentState =
  result = AgentState(
    cfg: cfg,
    endpoint: OpenAIConfig(
      url: cfg.apiUrl,
      apiKey: cfg.apiKey
    ),
    client: newRelay(
      maxInFlight = 1,
      defaultTimeoutMs = cfg.timeoutMs,
      maxRedirects = 5
    ),
    chatMessages: @[systemMessageText(ChatBasePrompt)],
    nextId: 1
  )

proc close*(state: var AgentState) =
  if state.client != nil:
    state.client.close()
    state.client = nil

proc hasPending*(state: AgentState): bool =
  state.phase != apIdle

proc hasPendingChat*(state: AgentState): bool =
  state.phase == apWaitingChat

proc hasPendingUi*(state: AgentState): bool =
  false

proc resetPending(state: var AgentState) =
  state.phase = apIdle
  state.attempt = 0
  state.activeRequestId = 0
  state.pendingChatMessages.setLen(0)
  state.pendingUserText = ""

proc appendField(text: var string; name, value: string) =
  if value.strip().len == 0:
    return
  if text.len > 0:
    text.add ", "
  text.add name
  text.add ": "
  text.add value.strip()

proc shortened(text: string; limit = 700): string =
  result = text.strip()
  if result.len > limit:
    result = result[0 ..< limit] & "..."

proc apiDetailLocation(item: ApiDetailItem): string =
  for part in item.loc:
    if part.len > 0:
      if result.len > 0:
        result.add "."
      result.add part

proc openAiErrorMessage(status: int; body: string; message: var string): bool =
  let prefix = "HTTP " & $status & ": "
  result = false
  try:
    let parsed = fromJson(body, ApiErrorEnvelope)
    if parsed.error.message.strip().len > 0:
      message = prefix & parsed.error.message.strip().shortened(120)
      var details = ""
      details.appendField("type", parsed.error.`type`)
      details.appendField("param", parsed.error.param)
      if details.len > 0:
        message.add " (" & details & ")"
      result = true
  except CatchableError:
    discard

proc validationErrorMessage(status: int; body: string; message: var string): bool =
  let prefix = "HTTP " & $status & ": "
  result = false
  try:
    let parsed = fromJson(body, ApiDetailListEnvelope)
    if parsed.detail.len > 0:
      let item = parsed.detail[0]
      message = prefix
      if item.msg.strip().len > 0:
        message.add item.msg.strip()
      else:
        message.add "request validation failed"
      let loc = item.apiDetailLocation()
      var details = ""
      details.appendField("type", item.`type`)
      details.appendField("field", loc)
      if details.len > 0:
        message.add " (" & details & ")"
      if parsed.detail.len > 1:
        message.add " +" & $(parsed.detail.len - 1) & " more"
      result = true
  except CatchableError:
    discard

proc apiErrorMessage*(status: int; body: string): string =
  var message = ""
  if openAiErrorMessage(status, body, message):
    return message
  if validationErrorMessage(status, body, message):
    return message

  if body.strip().len > 0:
    result = "HTTP " & $status & ": " & body.shortened()
  else:
    result = "HTTP " & $status & ": empty error response"

proc clearPending*(state: var AgentState) =
  state.resetPending()
  if state.client != nil:
    state.client.clearQueue()

proc clearHistory*(state: var AgentState) =
  state.chatMessages = @[systemMessageText(ChatBasePrompt)]
  state.chatHistory.setLen(0)
  state.clearPending()

proc enqueue(state: var AgentState; messages: seq[ChatMessage];
    model: string; maxTokens: int; responseFormat: ResponseFormat): int64 =
  result = state.nextId
  inc state.nextId
  var batch: RequestBatch
  chatAdd(
    batch = batch,
    cfg = state.endpoint,
    params = chatCreate(
      model = model,
      messages = messages,
      temperature = 0.2,
      maxTokens = maxTokens,
      toolChoice = ToolChoice.none,
      responseFormat = responseFormat
    ),
    requestId = result,
    timeoutMs = state.cfg.timeoutMs
  )
  state.client.startRequests(batch)

proc busyError(state: AgentState): string =
  if state.phase != apIdle:
    result = "request already in progress"

proc submitChat*(state: var AgentState; userText: string): string =
  let text = userText.strip()
  if text.len == 0:
    return "input is empty"
  if state.client == nil:
    return "agent is closed"
  let busy = state.busyError()
  if busy.len > 0:
    return busy
  if not state.cfg.hasKey():
    return "Set apiKey in config or OPENAI_API_KEY."
  let messages = state.chatMessages & @[userMessageText(text)]
  try:
    state.activeRequestId = state.enqueue(messages, state.cfg.chatModel, 800,
      formatText)
  except IOError:
    state.resetPending()
    return getCurrentExceptionMsg()
  state.phase = apWaitingChat
  state.attempt = 1
  state.pendingChatMessages = messages
  state.pendingUserText = text
  result = ""

proc extractText(item: RequestResult): string =
  if item.error.kind != teNone:
    raise newException(IOError, $item.error.kind & ": " & item.error.message)
  if not isHttpSuccess(item.response.code):
    raise newException(IOError,
      apiErrorMessage(item.response.code, item.response.body))
  var parsed: ChatCreateResult
  if not chatParse(item.response.body, parsed):
    raise newException(ValueError, "failed to parse chat response")
  try:
    result = parsed.firstText()
  except ValueError:
    raise newException(ValueError,
      "response has no text content: " & getCurrentExceptionMsg())

proc isRetriable(item: RequestResult): bool =
  if item.error.kind != teNone:
    return isRetriableTransport(item.error.kind)
  return isRetriableStatus(item.response.code)

proc retryCurrent(state: var AgentState): bool =
  if state.attempt >= MaxRetries:
    return false
  inc state.attempt
  try:
    case state.phase
    of apWaitingChat:
      state.activeRequestId = state.enqueue(state.pendingChatMessages,
        state.cfg.chatModel, 800, formatText)
    of apIdle:
      return false
    result = true
  except IOError:
    state.resetPending()
    raise

proc pollActiveResult(state: var AgentState; item: var RequestResult): bool =
  if state.client == nil:
    return false

  while state.client.pollForResult(item):
    if state.phase != apIdle and
        item.response.request.requestId == state.activeRequestId:
      return true

  result = false

proc finishChat(state: var AgentState; text: string; outResult: var AgentResult) =
  state.chatMessages = state.pendingChatMessages
  state.chatMessages.add assistantMessageText(text)
  state.chatHistory.add ChatEntry(role: arUser, content: state.pendingUserText)
  state.chatHistory.add ChatEntry(role: arAssistant, content: text)
  state.resetPending()
  outResult = AgentResult(kind: resChatText, text: text)

proc finishSuccess(state: var AgentState; text: string;
    outResult: var AgentResult) =
  case state.phase
  of apWaitingChat:
    state.finishChat(text, outResult)
  of apIdle:
    discard

proc poll*(state: var AgentState; outResult: var AgentResult): bool =
  var item: RequestResult
  if not state.pollActiveResult(item):
    return false

  try:
    let text = extractText(item)
    state.finishSuccess(text, outResult)
  except CatchableError:
    let err = getCurrentExceptionMsg()
    let attemptBefore = state.attempt
    try:
      if isRetriable(item) and state.retryCurrent():
        outResult = AgentResult(kind: resError,
          error: "retrying (" & $attemptBefore & "/" & $MaxRetries & "): " & err)
      else:
        state.resetPending()
        outResult = AgentResult(kind: resError, error: err)
    except CatchableError:
      outResult = AgentResult(kind: resError,
        error: "retry failed: " & getCurrentExceptionMsg())
  return true
