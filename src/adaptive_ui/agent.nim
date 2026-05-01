import std/[random, strutils, times]
import jsonx
import relay
import openai/chat
import openai/retry
import ./[config, live_flow, skill_files, ui_doc, ui_parse, ui_schema]

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

  AgentPhase = enum
    apIdle,
    apWaitingChat,
    apWaitingUi

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

  AgentState* = object
    client*: Relay
    endpoint: OpenAIConfig
    cfg*: AppConfig
    chatMessages: seq[ChatMessage]
    chatHistory*: seq[ChatEntry]
    uiSystemMsg: ChatMessage
    uiFormat: ResponseFormat
    skillSummary: string
    phase: AgentPhase
    attempt: int
    pendingDoc: UiDoc
    nextId: int64
    rng: Rand

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
    uiFormat: uiDocFmt,
    skillSummary: skills.skillSummary(),
    nextId: 1,
    rng: initRand(epochTime().int64)
  )

proc close*(state: var AgentState) =
  if state.client != nil:
    state.client.close()
    state.client = nil

proc hasPending*(state: AgentState): bool =
  state.phase != apIdle

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
  state.phase = apIdle
  state.attempt = 0

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
  let userText = formatUiUserMsg(state.chatHistory, state.pendingDoc,
    state.skillSummary)
  if state.skillSummary.len > 0:
    result.add userMessageText(
      "Available skill files:\n" & state.skillSummary & "\n\n" & userText)
  else:
    result.add userMessageText(userText)

proc submitChat*(state: var AgentState; userText: string): string =
  let text = userText.strip()
  if text.len == 0:
    return "input is empty"
  if state.client == nil:
    return "agent is closed"
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
      "HTTP " & $item.response.code & ": " & item.response.body)
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
    case phase
    of apWaitingChat:
      state.chatMessages.add assistantMessageText(text)
      state.chatHistory.add ChatEntry(role: arAssistant, content: text)
      outResult = AgentResult(kind: resChatText, text: text)
    of apWaitingUi:
      var doc: UiDoc
      var parseErr = ""
      if parseUiDoc(text, doc, parseErr):
        outResult = AgentResult(kind: resUiDoc, text: text, doc: doc)
      else:
        outResult = AgentResult(kind: resError,
          error: "invalid UI document: " & parseErr, text: text)
    else:
      outResult = AgentResult(kind: resError, error: "unexpected phase")
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
