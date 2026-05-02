import std/[os, strutils]
import jsonx
import adaptive_ui/config

block defaults:
  let cfg = initAppConfig()
  doAssert cfg.apiUrl == "https://api.openai.com/v1/chat/completions"
  doAssert cfg.chatModel == "gpt-4.1-mini"
  doAssert cfg.timeoutMs == 30000

block parsePartialKeepsDefaults:
  let cfg = parseConfig("""{"chatModel":"custom-chat"}""")
  doAssert cfg.apiUrl == "https://api.openai.com/v1/chat/completions"
  doAssert cfg.chatModel == "custom-chat"

block parseFileKeyOverridesDefault:
  let cfg = parseConfig("""{"apiKey":"file-key"}""")
  doAssert cfg.apiKey == "file-key"

block loadMissingUsesDefaults:
  let cfg = loadConfig("/tmp/adaptive-ui-missing-config.json")
  doAssert cfg.apiUrl == "https://api.openai.com/v1/chat/completions"
  doAssert cfg.chatModel == "gpt-4.1-mini"

block saveAndLoad:
  let path = getTempDir() / "adaptive-ui-config-test.json"
  let cfg = AppConfig(
    apiUrl: "http://localhost:9000/v1",
    apiKey: "sk-secret",
    chatModel: "chat",
    timeoutMs: 1000
  )

  saveConfig(path, cfg)

  let saved = readFile(path)
  doAssert "sk-secret" notin saved

  let loaded = loadConfig(path)
  doAssert loaded.apiUrl == cfg.apiUrl
  doAssert loaded.chatModel == cfg.chatModel
  doAssert loaded.timeoutMs == cfg.timeoutMs
  doAssert loaded.apiKey.len == 0

  if fileExists(path):
    removeFile(path)

block invalidJsonRaises:
  var raised = false
  try:
    discard parseConfig("""{"apiUrl":""")
  except CatchableError:
    raised = true
  doAssert raised

block jsonxShape:
  let cfg = initAppConfig()
  let parsed = fromJson(toJson(cfg), AppConfig)
  doAssert parsed.apiUrl == cfg.apiUrl
