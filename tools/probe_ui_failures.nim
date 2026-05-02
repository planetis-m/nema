import std/strutils
import relay
import openai/chat
import adaptive_ui/[
  agent, config, turn_extract, ui_compile, ui_doc
]

{.passL: "-lcurl".}

type
  TurnInput = object
    name: string
    text: string

  TurnResult = object
    name: string
    userText: string
    chatStatus: int
    chatTransport: string
    chatOutput: string
    chatError: string
    uiOutput: string
    uiCompiledOk: bool
    uiCompileError: string
    adaptiveKind: string
    hasAdaptiveControl: bool
    bottomInputAvailable: bool

const
  NationPrompt = """
You are a deterministic nation-simulation game engine.

Your role:

Guide me through creating and managing a country.
Build the world dynamically based on my answers.
Simulate other nations and global events.
Keep mechanics simple, consistent, and turn-based.
Game structure:

=== PHASE 1: NATION CREATION === Ask me ONE question at a time to define my country. Each question must:

Offer 3-5 clear options
Have meaningful gameplay impact
Cover areas like: - Geography (island, continent, climate) - Government (democracy, dictatorship, monarchy) - Economy (industrial, agricultural, resource-based) - Military doctrine (defensive, expansionist, naval, etc.) - Culture/diplomacy style
After each answer:

Update my country profile (internally)
Move to the next question
When finished:

Present a structured summary of my nation: Name: Government: Economy: Military: Strengths: Weaknesses:
=== PHASE 2: GAME LOOP ===

Each turn follows this exact structure:

WORLD UPDATE
Current turn number
3-5 global events (wars, trade shifts, alliances, crises)
Status of 3-5 major AI nations (short, consistent summaries)
PLAYER STATUS
Show my nation stats: Economy (0-100) Stability (0-100) Military (0-100) Diplomacy (0-100)
Show any ongoing effects (war, alliances, crises)
PLAYER DECISION Give me exactly 3-4 actions to choose from. Each option must:
Be concrete and different
Show expected tradeoffs (e.g., +Economy, -Stability)
Example: A) Invest in industry (+Economy, -Stability) B) Expand military (+Military, -Economy) C) Improve relations with X (+Diplomacy)

RESOLUTION
Apply effects deterministically
Update stats clearly
Briefly explain consequences
Rules:

No randomness; outcomes must logically follow choices
Keep responses structured and concise
Maintain internal consistency across turns
Avoid storytelling fluff; prioritize gameplay clarity
Goal:

Grow and sustain my nation over time
Start by asking the first nation-creation question.
"""

let turns = @[
  TurnInput(name: "start_game", text: NationPrompt),
  TurnInput(name: "answer_geography", text: "A"),
  TurnInput(name: "answer_government", text: "B"),
  TurnInput(name: "answer_economy", text: "C"),
  TurnInput(name: "answer_military", text: "A"),
  TurnInput(name: "answer_culture", text: "D"),
  TurnInput(name: "accept_summary", text: "Yes"),
  TurnInput(name: "turn_one_action", text: "A")
]

proc initialDoc(): UiDoc =
  textUiDoc("Adaptive UI", "Start")

proc requestTimeout(cfg: AppConfig): int =
  max(cfg.timeoutMs, 120000)

proc firstResponseText(response: RequestResult; text: var string;
    error: var string): bool =
  if response.error.kind != teNone:
    error = response.error.message
    return false
  if not isHttpSuccess(response.response.code):
    error = apiErrorMessage(response.response.code, response.response.body)
    return false

  var parsed: ChatCreateResult
  if not chatParse(response.response.body, parsed):
    error = "failed to parse chat response"
    return false

  try:
    text = $parsed.firstText()
    result = true
  except ValueError:
    error = "response has no text content: " & getCurrentExceptionMsg()

proc runChat(client: Relay; cfg: AppConfig; messages: seq[ChatMessage];
    text: var string; status: var int; transport: var string;
    error: var string): bool =
  let endpoint = OpenAIConfig(url: cfg.apiUrl, apiKey: cfg.apiKey)
  let response = client.makeRequest(chatRequest(endpoint, chatCreate(
    model = cfg.chatModel,
    messages = messages,
    temperature = 0.2,
    maxTokens = 1200,
    toolChoice = ToolChoice.none,
    responseFormat = formatText
  ), requestId = 1, timeoutMs = cfg.requestTimeout))

  status = response.response.code
  transport = $response.error.kind
  result = firstResponseText(response, text, error)

proc runUiLocal(chatOutput: string; item: var TurnResult; nextDoc: var UiDoc) =
  try:
    var visible = ""
    let command = uiCommandFromText(chatOutput, visible)
    nextDoc = compileUiCommand(visible, command)
    item.uiOutput = $nextDoc
    item.uiCompiledOk = true
    for area in nextDoc.areas:
      if area.kind == ukRadio or area.kind == ukTextInput:
        item.hasAdaptiveControl = true
        item.adaptiveKind = $area.kind
    item.bottomInputAvailable = true
  except CatchableError:
    item.uiCompileError = getCurrentExceptionMsg()

proc runTurn(client: Relay; cfg: AppConfig; input: TurnInput;
    chatMessages: var seq[ChatMessage]; currentDoc: var UiDoc): TurnResult =
  result.name = input.name
  result.userText = input.text.strip()

  let requestMessages = chatMessages & @[userMessageText(input.text)]
  let ok = runChat(client, cfg, requestMessages, result.chatOutput,
    result.chatStatus, result.chatTransport, result.chatError)
  if not ok:
    return

  chatMessages = requestMessages & @[assistantMessageText(result.chatOutput)]

  var nextDoc = currentDoc
  runUiLocal(result.chatOutput, result, nextDoc)
  if result.uiCompiledOk:
    currentDoc = nextDoc

proc printBlock(label, text: string) =
  echo label, ":"
  echo "```text"
  echo text.strip()
  echo "```"

proc printResult(item: TurnResult) =
  echo "## ", item.name
  echo "chatStatus: ", item.chatStatus, " chatTransport: ", item.chatTransport
  if item.chatError.len > 0:
    echo "chatError: ", item.chatError
  echo "uiPath: directive"
  echo "uiCompiledOk: ", item.uiCompiledOk
  if item.uiCompileError.len > 0:
    echo "uiCompileError: ", item.uiCompileError
  echo "adaptiveKind: ", item.adaptiveKind
  echo "hasAdaptiveControl: ", item.hasAdaptiveControl
  echo "bottomInputAvailable: ", item.bottomInputAvailable
  echo "canProgress: ", item.uiCompiledOk and item.bottomInputAvailable
  printBlock("userInput", item.userText)
  printBlock("chatOutput", item.chatOutput)
  echo "uiOutput:"
  echo "```json"
  echo item.uiOutput.strip()
  echo "```"
  echo ""

proc main() =
  let cfg = loadConfig("adaptive_ui.json")
  if not cfg.hasKey():
    quit("Set apiKey in adaptive_ui.json or OPENAI_API_KEY.")

  let client = newRelay(maxInFlight = 1, defaultTimeoutMs = cfg.requestTimeout)
  defer: client.close()

  var chatMessages = @[systemMessageText(ChatBasePrompt)]
  var currentDoc = initialDoc()

  for input in turns:
    printResult(runTurn(client, cfg, input, chatMessages, currentDoc))

when isMainModule:
  main()
