import std/[random, strutils, times]
import jsonx
import relay
import openai/chat
import openai/retry
import ./[config, live_flow, skill_files, ui_doc, ui_parse]

{.passL: "-lcurl".}

const
  ChatBasePrompt* = "You are the chat agent for an adaptive desktop app. " &
    "Answer the user plainly. " &
    "When a learning, quiz, essay, or decision flow is active, keep enough task state " &
    "in your response for a separate UI subagent to render the next screen. " &
    "When the input describes UI values, clicked buttons, selected options, or " &
    "submitted text, treat that as the user's interaction with the current generated UI."

  FlowPrompts: array[LiveFlowKind, string] = [
    lfAdaptive: "Adaptive task mode. " &
      "Help with the user's task directly. The task can be notes, planning, coding, " &
      "math, forms, decisions, study, games, or normal chat. " &
      "Keep enough visible task state in the response for the UI subagent to choose " &
      "an appropriate supported interface. " &
      "Do not force the task into a quiz or essay unless the user asks for that.",
    lfChat: "Normal chat mode. " &
      "Answer conversationally. The UI subagent should usually render this as a " &
      "transcript or simple text.",
    lfQuiz: "Live quiz mode. " &
      "Create or continue a quiz one question at a time. " &
      "Track score and correct answers in the conversation. " &
      "When asking a question, include enough structured detail for the UI subagent " &
      "to render a radio group and submit button. " &
      "When the input describes a selected option or clicked submit button, treat " &
      "the current UI values as the user's answer. " &
      "When grading an answer, compare both the option id and visible label, explain " &
      "briefly, and then move to the next question or final score.",
    lfEssay: "Live essay mode. " &
      "Create or continue an essay practice flow. " &
      "When starting, provide one essay prompt and a short rubric. " &
      "When the input describes submitted text, treat that text as the user's essay answer. " &
      "When the user submits an answer, grade it against the rubric and provide concise feedback. " &
      "Include enough task state for the UI subagent to render either a text input or feedback screen."
  ]

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
    "- textInput requires id and may use placeholder and submitLabel."

  UiFlowHints: array[LiveFlowKind, string] = [
    lfAdaptive: "Current flow: adaptive task. Choose the smallest supported UI that " &
      "fits the task: text, transcript, code, math, radio/buttons for decisions, " &
      "textInput for open responses. Do not default to quiz or essay unless requested.",
    lfChat: "Current flow: normal chat. Prefer transcript or text unless the response " &
      "clearly asks for interactive controls.",
    lfQuiz: "Current flow: quiz. Prefer one radio area for answer choices and one " &
      "buttons area for submit/next/finish actions. Keep option ids stable between turns.",
    lfEssay: "Current flow: essay. Prefer one prompt area, one textInput area for " &
      "the answer, and one buttons area for submit actions. Use submitLabel on textInput " &
      "when the input should submit directly."
  ]

  MaxRetries = 3

type
  AgentRole* = enum
    arUser,
    arAssistant

  ChatEntry* = object
    role*: AgentRole
    content*: string

  RequestKind = enum
    rkChat,
    rkUi

  ResultKind* = enum
    resNone,
    resChatText,
    resUiDoc,
    resError

  AgentResult* = object
    kind*: ResultKind
    text*: string
    doc*: UiDoc
    error*: string

  PendingRequest = object
    requestId: int64
    kind: RequestKind
    savedMessages: seq[ChatMessage]
    model: string
    maxTokens: int
    responseFormat: ResponseFormat
    attempt: int

  AgentState* = object
    client*: Relay
    endpoint: OpenAIConfig
    cfg*: AppConfig
    chatMessages: seq[ChatMessage]
    chatHistory*: seq[ChatEntry]
    uiSystemMsg: ChatMessage
    uiFormat: ResponseFormat
    skillSummary: string
    pending: seq[PendingRequest]
    nextId: int64
    rng: Rand

type
  SchemaProp = object
    `type`: string
    description: string

  SchemaEnumProp = object
    `type`: string
    description: string
    `enum`: seq[string]

  UiOptionSchema = object
    `type`: string
    properties: tuple[
      id: SchemaProp,
      label: SchemaProp,
      selected: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

  UiOptionArraySchema = object
    `type`: string
    description: string
    items: UiOptionSchema

  UiAreaSchema = object
    `type`: string
    properties: tuple[
      name: SchemaProp,
      kind: SchemaEnumProp,
      text: SchemaProp,
      id: SchemaProp,
      options: UiOptionArraySchema,
      language: SchemaProp,
      placeholder: SchemaProp,
      submitLabel: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

  UiAreaArraySchema = object
    `type`: string
    description: string
    items: UiAreaSchema

  UiDocSchema = object
    `type`: string
    properties: tuple[
      version: SchemaProp,
      title: SchemaProp,
      layout: SchemaProp,
      focus: SchemaProp,
      areas: UiAreaArraySchema
    ]
    required: seq[string]
    additionalProperties: bool

proc schemaProp(kind, description: string): SchemaProp =
  SchemaProp(`type`: kind, description: description)

proc schemaEnumProp(kind, description: string;
    values: openArray[string]): SchemaEnumProp =
  SchemaEnumProp(
    `type`: kind,
    description: description,
    `enum`: @values
  )

proc uiOptionSchema(): UiOptionSchema =
  UiOptionSchema(
    `type`: "object",
    properties: (
      id: schemaProp("string", "Stable option id."),
      label: schemaProp("string", "Visible option label."),
      selected: schemaProp("boolean", "Whether this option is selected.")
    ),
    required: @["id", "label"],
    additionalProperties: false
  )

proc uiAreaSchema(): UiAreaSchema =
  UiAreaSchema(
    `type`: "object",
    properties: (
      name: schemaProp("string", "Layout cell name."),
      kind: schemaEnumProp("string", "One supported UiKind string.", [
        "text", "code", "radio", "buttons", "textInput", "math", "transcript"
      ]),
      text: schemaProp("string", "Markdown-like text content."),
      id: schemaProp("string", "Stable component id for interactive areas."),
      options: UiOptionArraySchema(
        `type`: "array",
        description: "Options for radio groups and button rows.",
        items: uiOptionSchema()
      ),
      language: schemaProp("string", "Code language name."),
      placeholder: schemaProp("string", "Text input placeholder."),
      submitLabel: schemaProp("string", "Text input submit button label.")
    ),
    required: @["name", "kind"],
    additionalProperties: false
  )

proc uiDocSchema(): UiDocSchema =
  UiDocSchema(
    `type`: "object",
    properties: (
      version: schemaProp("integer", "UiDoc version. Must be 1."),
      title: schemaProp("string", "Short screen title."),
      layout: schemaProp("string", "uirelays markdown table layout."),
      focus: schemaProp("string", "Optional focused area name."),
      areas: UiAreaArraySchema(
        `type`: "array",
        description: "Areas rendered into layout cells.",
        items: uiAreaSchema()
      )
    ),
    required: @["version", "title", "layout", "areas"],
    additionalProperties: false
  )

proc uiDocResponseFormat*(): ResponseFormat =
  formatJsonSchema("ui_doc", uiDocSchema(), strict = true)

proc initAgentState*(cfg: AppConfig; skills = SkillLibrary()): AgentState =
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
    uiSystemMsg: systemMessageText(UiBasePrompt & "\n\n" & UiFlowHints[lfAdaptive]),
    uiFormat: uiDocResponseFormat(),
    skillSummary: skills.skillSummary(),
    nextId: 1,
    rng: initRand(epochTime().int64)
  )

proc close*(state: var AgentState) =
  if state.client != nil:
    state.client.close()
    state.client = nil

proc hasPending*(state: AgentState): bool =
  state.pending.len > 0 or state.client.hasRequests()

proc setFlow*(state: var AgentState; kind: LiveFlowKind) =
  let sysText = ChatBasePrompt & "\n\n" & FlowPrompts[kind]
  if state.chatMessages.len > 0 and state.chatMessages[0].role == ChatMessageRole.system:
    state.chatMessages[0] = systemMessageText(sysText)
  else:
    state.chatMessages.insert(systemMessageText(sysText), 0)
  let uiSysText = UiBasePrompt & "\n\n" & UiFlowHints[kind]
  state.uiSystemMsg = systemMessageText(uiSysText)

proc clearHistory*(state: var AgentState) =
  let sysMsg = if state.chatMessages.len > 0: state.chatMessages[0]
               else: systemMessageText(ChatBasePrompt)
  state.chatMessages = @[sysMsg]
  state.chatHistory.setLen(0)

proc formatUiUserMsg(chatHistory: seq[ChatEntry]; currentDoc: UiDoc;
    skillSummary: string): string =
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

template chatModel(state: AgentState): string = state.cfg.chatModel
template uiModel(state: AgentState): string = state.cfg.uiModel

proc enqueue(state: var AgentState; kind: RequestKind;
    messages: seq[ChatMessage]; model: string;
    maxTokens: int; responseFormat: ResponseFormat): int64 =
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
  state.pending.add PendingRequest(
    requestId: result,
    kind: kind,
    savedMessages: messages,
    model: model,
    maxTokens: maxTokens,
    responseFormat: responseFormat,
    attempt: 1
  )

proc submitChat*(state: var AgentState; userText: string): string =
  let text = userText.strip()
  if text.len == 0:
    return "input is empty"
  if state.client == nil:
    return "agent is closed"

  state.chatMessages.add userMessageText(text)
  state.chatHistory.add ChatEntry(role: arUser, content: text)
  discard state.enqueue(rkChat, state.chatMessages, state.chatModel,
    800, formatText)
  result = ""

proc enqueueUi*(state: var AgentState; currentDoc: UiDoc): string =
  if state.client == nil:
    return "agent is closed"

  var msgs: seq[ChatMessage]
  msgs.add state.uiSystemMsg
  if state.skillSummary.len > 0:
    msgs.add userMessageText(
      "Available skill files:\n" & state.skillSummary & "\n\n" &
      formatUiUserMsg(state.chatHistory, currentDoc, state.skillSummary))
  else:
    msgs.add userMessageText(
      formatUiUserMsg(state.chatHistory, currentDoc, state.skillSummary))
  discard state.enqueue(rkUi, msgs, state.uiModel, 1200,
    state.uiFormat)
  result = ""

proc findByRequestId(state: AgentState; requestId: int64): int =
  for i, p in state.pending:
    if p.requestId == requestId:
      return i
  result = -1

proc parseResponse(item: RequestResult; kind: RequestKind):
    tuple[ok: bool, text: string, err: string] =
  if item.error.kind != teNone:
    return (false, "", $item.error.kind & ": " & item.error.message)
  if not isHttpSuccess(item.response.code):
    return (false, item.response.body,
      "HTTP " & $item.response.code & ": " & item.response.body)
  var parsed: ChatCreateResult
  if not chatParse(item.response.body, parsed):
    return (false, "", "failed to parse response")
  try:
    result = (true, $parsed.firstText(), "")
  except CatchableError as e:
    result = (false, "", e.msg)

proc isRetriable(item: RequestResult): bool =
  if item.error.kind != teNone:
    return isRetriableTransport(item.error.kind)
  return isRetriableStatus(item.response.code)

proc retryRequest(state: var AgentState; pending: PendingRequest): bool =
  if pending.attempt >= MaxRetries:
    return false
  let nextAttempt = pending.attempt + 1
  discard state.enqueue(pending.kind, pending.savedMessages, pending.model,
    pending.maxTokens, pending.responseFormat)
  state.pending[^1].attempt = nextAttempt
  result = true

proc poll*(state: var AgentState; outResult: var AgentResult): bool =
  if state.client == nil:
    return false

  var item: RequestResult
  if state.client.pollForResult(item):
    let requestId = item.response.request.requestId
    let idx = state.findByRequestId(requestId)
    if idx < 0:
      outResult = AgentResult(kind: resError, error: "unknown request id")
      return true

    let pending = state.pending[idx]
    state.pending.del idx

    let (ok, text, err) = parseResponse(item, pending.kind)
    if not ok:
      if isRetriable(item) and state.retryRequest(pending):
        outResult = AgentResult(kind: resError,
          error: "retrying (" & $pending.attempt & "/" & $MaxRetries & "): " & err,
          text: text)
        return true
      outResult = AgentResult(kind: resError, error: err, text: text)
      return true

    case pending.kind
    of rkChat:
      state.chatMessages.add assistantMessageText(text)
      state.chatHistory.add ChatEntry(role: arAssistant, content: text)
      outResult = AgentResult(kind: resChatText, text: text)
    of rkUi:
      var doc: UiDoc
      var parseErr = ""
      if parseUiDoc(text, doc, parseErr):
        outResult = AgentResult(kind: resUiDoc, text: text, doc: doc)
      else:
        outResult = AgentResult(kind: resError,
          error: "invalid UI document: " & parseErr, text: text)
    return true

  return false


