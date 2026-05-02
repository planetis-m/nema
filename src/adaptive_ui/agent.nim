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

proc initAgentState*(cfg: AppConfig): AgentState =
  AgentState(
    cfg: cfg,
    endpoint: OpenAIConfig(url: cfg.apiUrl, apiKey: cfg.apiKey),
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

proc openAiErrorDetail(body: string): string =
  try:
    let parsed = fromJson(body, ApiErrorEnvelope)
    if parsed.error.message.strip().len > 0:
      result = parsed.error.message.strip().shortened(120)
      var details = ""
      details.appendField("type", parsed.error.`type`)
      details.appendField("param", parsed.error.param)
      if details.len > 0:
        result.add " (" & details & ")"
  except CatchableError:
    discard

proc apiErrorMessage*(status: int; body: string): string =
  let detail = openAiErrorDetail(body)
  if detail.len > 0:
    result = "HTTP " & $status & ": " & detail
  elif body.strip().len > 0:
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

proc sendChatRequest(state: var AgentState; messages: seq[ChatMessage]) =
  let reqId = state.nextId
  inc state.nextId
  let spec = chatRequest(
    cfg = state.endpoint,
    params = chatCreate(
      model = state.cfg.chatModel,
      messages = messages,
      temperature = 0.2,
      maxTokens = 800,
      toolChoice = ToolChoice.none,
      responseFormat = formatText
    ),
    requestId = reqId,
    timeoutMs = state.cfg.timeoutMs
  )
  state.client.startRequest(spec)
  state.activeRequestId = reqId

proc submitChat*(state: var AgentState; userText: string): string =
  let text = userText.strip()
  if text.len == 0:
    return "input is empty"
  if state.client == nil:
    return "agent is closed"
  if state.phase != apIdle:
    return "request already in progress"
  if not state.cfg.hasKey():
    return "Set apiKey in config or OPENAI_API_KEY."
  let messages = state.chatMessages & @[userMessageText(text)]
  try:
    state.sendChatRequest(messages)
  except IOError:
    state.resetPending()
    return getCurrentExceptionMsg()
  state.phase = apWaitingChat
  state.attempt = 1
  state.pendingChatMessages = messages
  state.pendingUserText = text

proc extractResult(item: RequestResult): AgentResult =
  if item.error.kind != teNone:
    result = AgentResult(kind: resError,
      error: $item.error.kind & ": " & item.error.message)
  elif not isHttpSuccess(item.response.code):
    result = AgentResult(kind: resError,
      error: apiErrorMessage(item.response.code, item.response.body))
  else:
    var parsed: ChatCreateResult
    if not chatParse(item.response.body, parsed):
      result = AgentResult(kind: resError, error: "failed to parse chat response")
    else:
      try:
        result = AgentResult(kind: resChatText, text: parsed.firstText())
      except ValueError:
        result = AgentResult(kind: resError,
          error: "response has no text content: " & getCurrentExceptionMsg())

proc commitChatResult(state: var AgentState; text: string) =
  state.chatMessages = state.pendingChatMessages
  state.chatMessages.add assistantMessageText(text)
  state.chatHistory.add ChatEntry(role: arUser, content: state.pendingUserText)
  state.chatHistory.add ChatEntry(role: arAssistant, content: text)
  state.resetPending()

proc poll*(state: var AgentState; reply: var AgentResult): bool =
  if state.client == nil:
    return false

  var item: RequestResult
  while state.client.pollForResult(item):
    if state.phase == apIdle or
        item.response.request.requestId != state.activeRequestId:
      discard
    elif state.phase == apWaitingChat:
      reply = extractResult(item)
      if reply.kind == resChatText:
        state.commitChatResult(reply.text)
        return true

      let retriable =
        if item.error.kind != teNone:
          isRetriableTransport(item.error.kind)
        else:
          isRetriableStatus(item.response.code)
      if retriable and state.attempt < MaxRetries:
        inc state.attempt
        try:
          state.sendChatRequest(state.pendingChatMessages)
          reply = AgentResult(kind: resError,
            error: "retrying (" & $(state.attempt - 1) & "/" & $MaxRetries & "): " & reply.error)
        except IOError:
          state.resetPending()
          reply = AgentResult(kind: resError,
            error: "retry failed: " & getCurrentExceptionMsg())
      else:
        state.resetPending()
      return true
