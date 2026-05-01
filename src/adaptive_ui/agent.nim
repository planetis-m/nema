import std/[options, strutils]
import jsonx
import relay
import openai/chat
import openai/retry
import ./[config, ui_doc, ui_parse, ui_schema]

{.passL: "-lcurl".}

const
  ChatBasePrompt* = "You are the chat agent for an adaptive desktop app. " &
    "Answer the user plainly. " &
    "Keep enough visible state in each response for a separate UI subagent to " &
    "render the next screen. " &
    "When the input describes UI values, clicked buttons, selected options, or " &
    "submitted text, treat that as the user's interaction with the current generated UI. " &
    "Do not force tasks into a fixed interaction pattern unless the user explicitly " &
    "asks for that shape."

  UiBasePrompt = "You are the UI subagent for a Nim desktop app. " &
    "Return only one valid UiDoc JSON object. " &
    "Use only supported area kinds and keep the layout compact.\n\n" &
    "UiDoc contract:\n" &
    "- Return JSON only.\n" &
    "- version must be 1.\n" &
    "- layout must be a uirelays markdown table.\n" &
    "- Every area name must exist in layout.\n" &
    "- Supported kinds: text, code, radio, buttons, textInput, math, transcript.\n" &
    "- radio/buttons require id and non-empty options.\n" &
    "- textInput requires id and may use placeholder and submitLabel.\n" &
    "- Choose the smallest supported UI that fits the task. Do not default to a " &
    "specific interaction pattern unless the conversation requires it."

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
    apWaitingChat,
    apWaitingUi

  ResultKind* = enum
    resChatText,
    resUiDoc,
    resError

  AgentResult* = object
    kind*: ResultKind
    text*: string
    doc*: UiDoc
    error*: string

  AgentState* = object
    client*: Relay
    endpoint: OpenAIConfig
    cfg*: AppConfig
    chatMessages: seq[ChatMessage]
    chatHistory*: seq[ChatEntry]
    uiSystemMsg: ChatMessage
    uiFormat: ResponseFormat
    phase: AgentPhase
    attempt: int
    pendingDoc: UiDoc
    nextId: int64

  ApiErrorObject = object
    message: string
    `type`: string
    param: Option[string]
    code: Option[string]

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
      maxInFlight = 2,
      defaultTimeoutMs = cfg.timeoutMs,
      maxRedirects = 5
    ),
    chatMessages: @[systemMessageText(ChatBasePrompt)],
    uiSystemMsg: systemMessageText(UiBasePrompt),
    uiFormat: uiDocFmt,
    nextId: 1
  )

proc close*(state: var AgentState) =
  if state.client != nil:
    state.client.close()
    state.client = nil

proc hasPending*(state: AgentState): bool =
  state.phase != apIdle

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

proc optionText(value: Option[string]): string =
  if value.isSome:
    result = value.get()

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
      var details = ""
      details.appendField("type", parsed.error.`type`)
      details.appendField("param", parsed.error.param.optionText())
      details.appendField("code", parsed.error.code.optionText())
      message = prefix & parsed.error.message.strip()
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

proc clearHistory*(state: var AgentState) =
  let sysMsg = if state.chatMessages.len > 0: state.chatMessages[0]
               else: systemMessageText(ChatBasePrompt)
  state.chatMessages = @[sysMsg]
  state.chatHistory.setLen(0)
  state.phase = apIdle
  state.attempt = 0

proc formatUiUserMsg(chatHistory: seq[ChatEntry]; currentDoc: UiDoc): string =
  result = "Conversation so far:\n"
  if chatHistory.len == 0:
    result.add "(empty)\n"
  else:
    for entry in chatHistory:
      result.add "- "
      result.add if entry.role == arUser: "User" else: "Assistant"
      result.add ": "
      result.add entry.content.strip()
      result.add "\n"
  result.add "\nCurrent UiDoc JSON:\n"
  result.add toJson(currentDoc)
  result.add "\n\nReturn the next UiDoc JSON only."

proc enqueue(state: var AgentState; messages: seq[ChatMessage];
    model: string; maxTokens: int; responseFormat: ResponseFormat) =
  let requestId = state.nextId
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
    requestId = requestId,
    timeoutMs = state.cfg.timeoutMs
  )
  state.client.startRequests(batch)

proc buildUiMessages(state: AgentState): seq[ChatMessage] =
  result.add state.uiSystemMsg
  result.add userMessageText(formatUiUserMsg(state.chatHistory, state.pendingDoc))

proc submitChat*(state: var AgentState; userText: string): string =
  let text = userText.strip()
  if text.len == 0:
    return "input is empty"
  if state.client == nil:
    return "agent is closed"
  if not state.cfg.hasKey():
    return "Set OPENAI_API_KEY for generated UI."
  state.chatMessages.add userMessageText(text)
  state.chatHistory.add ChatEntry(role: arUser, content: text)
  state.phase = apWaitingChat
  state.attempt = 1
  try:
    state.enqueue(state.chatMessages, state.cfg.chatModel, 800, formatText)
  except IOError:
    state.phase = apIdle
    return getCurrentExceptionMsg()
  result = ""

proc enqueueUi*(state: var AgentState; currentDoc: UiDoc): string =
  if state.client == nil:
    return "agent is closed"
  state.pendingDoc = currentDoc
  state.phase = apWaitingUi
  state.attempt = 1
  try:
    state.enqueue(state.buildUiMessages(), state.cfg.uiModel, 1200,
      state.uiFormat)
  except IOError:
    state.phase = apIdle
    return getCurrentExceptionMsg()
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
    result = $parsed.firstText()
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
  case state.phase
  of apWaitingChat:
    state.enqueue(state.chatMessages, state.cfg.chatModel, 800, formatText)
  of apWaitingUi:
    state.enqueue(state.buildUiMessages(), state.cfg.uiModel, 1200,
      state.uiFormat)
  else:
    return false
  result = true

proc poll*(state: var AgentState; outResult: var AgentResult): bool =
  if state.client == nil or state.phase == apIdle:
    return false

  var item: RequestResult
  if not state.client.pollForResult(item):
    return false

  try:
    let text = extractText(item)
    let phase = state.phase
    state.phase = apIdle
    if phase == apWaitingChat:
      state.chatMessages.add assistantMessageText(text)
      state.chatHistory.add ChatEntry(role: arAssistant, content: text)
      outResult = AgentResult(kind: resChatText, text: text)
    else:
      var doc: UiDoc
      var parseErr = ""
      if parseUiDoc(text, doc, parseErr):
        outResult = AgentResult(kind: resUiDoc, text: text, doc: doc)
      else:
        outResult = AgentResult(kind: resError,
          error: "invalid UI document: " & parseErr, text: text)
  except CatchableError:
    let err = getCurrentExceptionMsg()
    let attemptBefore = state.attempt
    if isRetriable(item) and state.retryCurrent():
      outResult = AgentResult(kind: resError,
        error: "retrying (" & $attemptBefore & "/" & $MaxRetries & "): " & err)
    else:
      state.phase = apIdle
      outResult = AgentResult(kind: resError, error: err)
  return true
