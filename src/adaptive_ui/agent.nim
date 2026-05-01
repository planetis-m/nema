import std/strutils
import jsonx
import relay
import openai/chat
import openai/retry
import ./[config, ui_doc, ui_parse, ui_schema]

{.passL: "-lcurl".}

const
  ChatBasePrompt* = """
You are the Chat Agent for an adaptive desktop app. Answer the user's task and
keep the task state in visible text. Use this simple structure when it applies:
a short heading, body text, optional fenced code blocks with language names,
exactly one 'Next action: choose one|type|none' line, and an 'Options:' list
only for choice steps. For choice steps, provide short option labels. For type
steps, use 'Next action: type' and ask for exactly the needed input. For
completed steps, use 'Next action: none'. Treat UI values, clicks, selections,
and submitted text as the user's interaction with the current screen. Do not
mention JSON, layouts, renderers, tabs, or implementation details."""

  UiBasePrompt* = """
You are the UI Agent for a Nim desktop app. Your only job is to convert the
latest Chat Agent response into one valid UiDoc JSON object.

Execution path:
1. Read the latest assistant message, then ignore older messages except for
brief context.
2. Map structure to explicit components: heading or title -> text area; body
paragraphs -> text area; fenced code -> code area with language; choice prompt
and Options -> radio area plus buttons area; free-form prompt -> textInput area;
math-heavy content -> math area.
3. If 'Next action: choose one' appears, render choices and one Submit button.
If 'Next action: type' appears, render one textInput with a clear submitLabel.
If 'Next action: none' appears, render only content areas.
4. Choose a compact layout that fits the available adaptive surface. Prefer one
vertical flow. Use side-by-side areas only for comparison.

Contract:
- Return JSON only. version must be 1.
- Do not ask the renderer to interpret markdown. Strip heading markers from text
areas and put code blocks in code areas.
- layout must be a uirelays markdown table and every area name must exist in
layout.
- If you include a radio or buttons area, include that exact area name in layout.
- Supported kinds: text, code, radio, buttons, textInput, math.
- radio/buttons options must be objects like {"id":"a","label":"Choice A"};
never use string options.
- radio/buttons require id and non-empty options. textInput requires id.
- Keep component ids stable, lowercase, and specific to the current step.
- Example choice layout: {"version":1,"title":"Quiz","layout":"| prompt, * |\n| choices, 7 lines |\n| actions, 2 lines |","areas":[{"name":"prompt","kind":"text","text":"Question text"},{"name":"choices","kind":"radio","id":"answer","options":[{"id":"a","label":"First"},{"id":"b","label":"Second"}]},{"name":"actions","kind":"buttons","id":"actions","options":[{"id":"submit","label":"Submit"}]}],"focus":"choices"}.
- Keep the screen focused on the current user task."""

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
    phase: AgentPhase
    attempt: int
    activeRequestId: int64
    pendingChatMessages: seq[ChatMessage]
    pendingUserText: string
    pendingDoc: UiDoc
    nextId: int64

  ApiErrorObject = object
    message: string
    `type`: string
    param: string
    code: int

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
  state.phase == apWaitingUi

proc resetPending(state: var AgentState) =
  state.phase = apIdle
  state.attempt = 0
  state.activeRequestId = 0
  state.pendingChatMessages.setLen(0)
  state.pendingUserText = ""
  state.pendingDoc = UiDoc()

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

proc formatUiUserMsg(chatHistory: seq[ChatEntry]; currentDoc: UiDoc): string =
  var latestAssistant = ""
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
      if entry.role == arAssistant:
        latestAssistant = entry.content.strip()

  result.add "\nLatest assistant message to turn into UI:\n"
  if latestAssistant.len > 0:
    result.add latestAssistant
    result.add "\n"
  else:
    result.add "(none)\n"
  result.add "\nCurrent UiDoc JSON:\n"
  result.add toJson(currentDoc)
  result.add "\n\nReturn the next UiDoc JSON only."

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

proc buildUiMessages(state: AgentState; currentDoc: UiDoc): seq[ChatMessage] =
  result.add systemMessageText(UiBasePrompt)
  result.add userMessageText(formatUiUserMsg(state.chatHistory, currentDoc))

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

proc enqueueUi*(state: var AgentState; currentDoc: UiDoc): string =
  if state.client == nil:
    return "agent is closed"
  let busy = state.busyError()
  if busy.len > 0:
    return busy
  try:
    state.activeRequestId = state.enqueue(state.buildUiMessages(currentDoc),
      state.cfg.uiModel, 1200, uiDocFmt)
  except IOError:
    let err = getCurrentExceptionMsg()
    state.resetPending()
    return err
  state.phase = apWaitingUi
  state.attempt = 1
  state.pendingDoc = currentDoc
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
  try:
    case state.phase
    of apWaitingChat:
      state.activeRequestId = state.enqueue(state.pendingChatMessages,
        state.cfg.chatModel, 800, formatText)
    of apWaitingUi:
      state.activeRequestId = state.enqueue(
        state.buildUiMessages(state.pendingDoc), state.cfg.uiModel, 1200,
        uiDocFmt)
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

proc finishUi(state: var AgentState; text: string; outResult: var AgentResult) =
  var doc: UiDoc
  var parseErr = ""
  state.resetPending()
  if parseUiDoc(text, doc, parseErr):
    outResult = AgentResult(kind: resUiDoc, text: text, doc: doc)
  else:
    outResult = AgentResult(kind: resError,
      error: "invalid UI document: " & parseErr, text: text)

proc finishSuccess(state: var AgentState; text: string;
    outResult: var AgentResult) =
  case state.phase
  of apWaitingChat:
    state.finishChat(text, outResult)
  of apWaitingUi:
    state.finishUi(text, outResult)
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
