import std/[os, strutils, tables]
import jsonx
import relay
import openai/chat
import ./[config, skill_files, ui_doc, ui_parse]

{.passL: "-lcurl".}

const
  UiContractPrompt = """
UiDoc contract:
- Return JSON only.
- version must be 1.
- layout must be a uirelays markdown table.
- Every area name must exist in layout.
- Supported kinds: text, code, radio, buttons, textInput, math, transcript.
- radio/buttons require id and non-empty options.
- textInput requires id and may use placeholder and submitLabel.
"""

  DefaultUiSystemPrompt = """
You are the UI subagent for a Nim desktop app. Return only one valid UiDoc JSON
object. Use only supported area kinds and keep the layout compact.
"""

  ChatSystemPrompt = """
You are the chat agent for an adaptive Nim desktop app. Answer the user plainly.
When a learning, quiz, essay, or decision flow is active, keep enough task state
in your response for a separate UI subagent to render the next screen.
"""

type
  AgentRole* = enum
    amUser,
    amAssistant

  AgentMessage* = object
    role*: AgentRole
    content*: string

  AgentRequestKind* = enum
    arChat,
    arUi

  AgentResultKind* = enum
    agNone,
    agChatText,
    agUiDoc,
    agError

  AgentResult* = object
    kind*: AgentResultKind
    requestId*: int64
    text*: string
    doc*: UiDoc
    error*: string

  AgentRuntime* = object
    cfg*: AppConfig
    skills*: SkillLibrary
    history*: seq[AgentMessage]
    lastStatus*: string
    uiSystemPrompt*: string
    endpoint: OpenAIConfig
    client: Relay
    nextRequestId: int64
    pending: Table[int64, AgentRequestKind]

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
        "text",
        "code",
        "radio",
        "buttons",
        "textInput",
        "math",
        "transcript"
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

proc loadUiSystemPrompt*(path = "prompts/ui-subagent-system.md"): string =
  if fileExists(path):
    result = readFile(path)
  else:
    result = DefaultUiSystemPrompt

proc initAgentRuntime*(cfg: AppConfig; skills = SkillLibrary();
    uiSystemPrompt = loadUiSystemPrompt()): AgentRuntime =
  result.cfg = cfg
  result.skills = skills
  result.uiSystemPrompt = uiSystemPrompt
  result.endpoint = OpenAIConfig(
    url: cfg.apiUrl,
    apiKey: getEnv(cfg.apiKeyEnv)
  )
  result.client = newRelay(
    maxInFlight = 2,
    defaultTimeoutMs = cfg.timeoutMs,
    maxRedirects = 5
  )
  result.nextRequestId = 1
  result.pending = initTable[int64, AgentRequestKind]()
  if result.endpoint.apiKey.len == 0:
    result.lastStatus = "API key missing in " & cfg.apiKeyEnv
  else:
    result.lastStatus = "Agent runtime ready"

proc close*(rt: var AgentRuntime) =
  if rt.client != nil:
    rt.client.close()
    rt.client = nil

proc hasLiveConfig*(rt: AgentRuntime): bool =
  rt.endpoint.apiKey.len > 0

proc buildChatSystemPrompt*(skills: SkillLibrary): string =
  result = ChatSystemPrompt.strip()
  let summary = skills.skillSummary()
  if summary.len > 0:
    result.add "\n\nAvailable SKILL files:\n"
    result.add summary

proc roleName(role: AgentRole): string =
  case role
  of amUser:
    "user"
  of amAssistant:
    "assistant"

proc toChatMessage(msg: AgentMessage): ChatMessage =
  case msg.role
  of amUser:
    userMessageText(msg.content)
  of amAssistant:
    assistantMessageText(msg.content)

proc buildChatMessages*(history: openArray[AgentMessage]; skills: SkillLibrary;
    userText: string): seq[ChatMessage] =
  result.add systemMessageText(buildChatSystemPrompt(skills))
  for msg in history:
    result.add toChatMessage(msg)
  result.add userMessageText(userText)

proc buildUiPrompt*(history: openArray[AgentMessage]; currentDoc: UiDoc;
    skills: SkillLibrary; uiHint = ""): string =
  result = UiContractPrompt.strip()
  result.add "\n\nConversation so far:\n"
  if history.len == 0:
    result.add "(empty)\n"
  else:
    for msg in history:
      result.add "- "
      result.add roleName(msg.role)
      result.add ": "
      result.add msg.content
      result.add "\n"

  if uiHint.strip().len > 0:
    result.add "\nUI context:\n"
    result.add uiHint.strip()
    result.add "\n"

  let summary = skills.skillSummary()
  if summary.len > 0:
    result.add "\nAvailable SKILL files:\n"
    result.add summary
    result.add "\n"

  result.add "\nCurrent UiDoc JSON:\n"
  result.add toJson(currentDoc)
  result.add "\n\nReturn the next UiDoc JSON only."

proc nextId(rt: var AgentRuntime): int64 =
  result = rt.nextRequestId
  inc rt.nextRequestId

proc fail(err: var string; message: string): bool =
  err = message
  result = false

proc ensureCanRequest(rt: AgentRuntime; err: var string): bool =
  if rt.client == nil:
    result = fail(err, "agent runtime is closed")
  elif not rt.hasLiveConfig():
    result = fail(err, "API key missing in " & rt.cfg.apiKeyEnv)
  else:
    err = ""
    result = true

proc enqueue(rt: var AgentRuntime; kind: AgentRequestKind;
    messages: seq[ChatMessage]; model: string; maxTokens: int;
    responseFormat: ResponseFormat): int64 =
  result = rt.nextId()
  var batch: RequestBatch
  chatAdd(
    batch = batch,
    cfg = rt.endpoint,
    params = chatCreate(
      model = model,
      messages = messages,
      temperature = 0.2,
      maxTokens = maxTokens,
      toolChoice = ToolChoice.none,
      responseFormat = responseFormat
    ),
    requestId = result,
    timeoutMs = rt.cfg.timeoutMs
  )
  rt.client.startRequests(batch)
  rt.pending[result] = kind

proc submitUserText*(rt: var AgentRuntime; text: string; err: var string;
    displayText = ""): bool =
  let userText = text.strip()
  if userText.len == 0:
    return fail(err, "input is empty")
  if not rt.ensureCanRequest(err):
    return false

  let historyText =
    if displayText.strip().len > 0: displayText.strip()
    else: userText

  let requestId = rt.enqueue(
    kind = arChat,
    messages = buildChatMessages(rt.history, rt.skills, userText),
    model = rt.cfg.chatModel,
    maxTokens = 800,
    responseFormat = formatText
  )
  rt.history.add AgentMessage(role: amUser, content: historyText)
  rt.lastStatus = "queued chat request " & $requestId
  err = ""
  result = true

proc enqueueUiDoc*(rt: var AgentRuntime; currentDoc: UiDoc;
    err: var string; uiHint = ""): bool =
  if not rt.ensureCanRequest(err):
    return false

  let requestId = rt.enqueue(
    kind = arUi,
    messages = @[
      systemMessageText(rt.uiSystemPrompt),
      userMessageText(buildUiPrompt(rt.history, currentDoc, rt.skills, uiHint))
    ],
    model = rt.cfg.uiModel,
    maxTokens = 1200,
    responseFormat = uiDocResponseFormat()
  )
  rt.lastStatus = "queued UI request " & $requestId
  err = ""
  result = true

proc parseChatText(item: RequestResult; text, err: var string): bool =
  var parsed: ChatCreateResult
  if not chatParse(item.response.body, parsed):
    return fail(err, "failed to parse chat response")

  try:
    text = $parsed.firstText()
    err = ""
    result = true
  except CatchableError as e:
    result = fail(err, e.msg)

proc failResult(requestId: int64; message: string; text = ""): AgentResult =
  AgentResult(kind: agError, requestId: requestId, error: message, text: text)

proc parseResult(rt: var AgentRuntime; item: RequestResult;
    kind: AgentRequestKind): AgentResult =
  let requestId = item.response.request.requestId
  result.requestId = requestId

  if item.error.kind != teNone:
    return failResult(requestId, $item.error.kind & ": " & item.error.message)
  if not isHttpSuccess(item.response.code):
    return failResult(requestId, "HTTP " & $item.response.code & ": " &
      item.response.body, item.response.body)

  var text = ""
  var err = ""
  if not parseChatText(item, text, err):
    return failResult(requestId, err)

  case kind
  of arChat:
    rt.history.add AgentMessage(role: amAssistant, content: text)
    result = AgentResult(
      kind: agChatText,
      requestId: requestId,
      text: text
    )
  of arUi:
    var doc: UiDoc
    if parseUiDoc(text, doc, err):
      result = AgentResult(
        kind: agUiDoc,
        requestId: requestId,
        text: text,
        doc: doc
      )
    else:
      result = failResult(requestId, "invalid UI document: " & err, text)

proc pollAgent*(rt: var AgentRuntime; outResult: var AgentResult): bool =
  if rt.client == nil:
    return false

  var item: RequestResult
  if rt.client.pollForResult(item):
    let requestId = item.response.request.requestId
    if rt.pending.hasKey(requestId):
      let kind = rt.pending[requestId]
      rt.pending.del requestId
      outResult = rt.parseResult(item, kind)
    else:
      outResult = failResult(requestId, "unknown request id")

    case outResult.kind
    of agError:
      rt.lastStatus = outResult.error
    of agChatText:
      rt.lastStatus = "chat response received"
    of agUiDoc:
      rt.lastStatus = "UI document received"
    of agNone:
      discard
    result = true
  else:
    result = false

proc pendingRequests*(rt: AgentRuntime): int =
  rt.pending.len
