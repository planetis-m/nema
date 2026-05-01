import std/[os, strutils]
import jsonx
import relay
import openai/chat
import adaptive_ui/[agent, config, ui_doc, ui_parse, ui_schema]

{.passL: "-lcurl".}

proc main() =
  let cfg = loadConfig("adaptive_ui.json")
  if not cfg.hasKey():
    quit("Set apiKey in adaptive_ui.json or OPENAI_API_KEY.")

  type
    SchemaProp = object
      `type`: string
      description: string

    SimpleSchema = object
      `type`: string
      properties: tuple[answer: SchemaProp]
      required: seq[string]
      additionalProperties: bool

  let simpleFmt = formatJsonSchema("simple_answer", SimpleSchema(
    `type`: "object",
    properties: (
      answer: SchemaProp(`type`: "string", description: "Short answer")
    ),
    required: @["answer"],
    additionalProperties: false
  ))

  let endpoint = OpenAIConfig(url: cfg.apiUrl, apiKey: cfg.apiKey)
  let model =
    if paramCount() > 1: paramStr(2)
    else: cfg.uiModel
  let responseFormat =
    if paramCount() > 0 and paramStr(1) == "simple": simpleFmt
    else: uiDocFmt
  let params = chatCreate(
    model = model,
    messages = @[
      systemMessageText(
        if paramCount() > 0 and paramStr(1) == "simple":
          "Return JSON only."
        else:
          UiBasePrompt
      ),
      userMessageText(
        if paramCount() > 0 and paramStr(1) == "simple":
          "Return a short JSON answer to: what language is Nim?"
        else:
          """
Conversation so far:
- User: Quiz me on Nim fundamentals.
- Assistant: Nim Programming Fundamentals Quiz

Question 1: What is the correct way to declare a mutable variable in Nim?
Next action: choose one
Options:
- let x = 1
- var x = 1
- const x = 1

Current UiDoc JSON:
{"version":1,"title":"Adaptive UI","layout":"| main, * |","areas":[{"name":"main","kind":"text","text":"Start"}],"focus":"main"}

Return the next UiDoc JSON only.
"""
      )
    ],
    temperature = 0.0,
    maxTokens = 800,
    toolChoice = ToolChoice.none,
    responseFormat = responseFormat
  )

  let request = chatRequest(endpoint, params, requestId = 1, timeoutMs = cfg.timeoutMs)
  echo "request response_format contains json_schema: ",
    request.body.contains("\"response_format\":{\"type\":\"json_schema\"")
  echo "request response_format contains legacy json: ",
    request.body.contains("\"response_format\":{\"type\":\"json\"")

  let client = newRelay(maxInFlight = 1, defaultTimeoutMs = cfg.timeoutMs)
  defer: client.close()

  let item = client.makeRequest(request)
  echo "status=", item.response.code, " transport=", item.error.kind
  if item.error.kind != teNone:
    echo item.error.message
  echo item.response.body
  var parsed: ChatCreateResult
  if item.response.code == 200 and chatParse(item.response.body, parsed):
    var doc: UiDoc
    var err = ""
    echo "parseUiDoc=", parseUiDoc($parsed.firstText(), doc, err)
    if err.len > 0:
      echo "parseUiDoc error=", err

when isMainModule:
  main()
