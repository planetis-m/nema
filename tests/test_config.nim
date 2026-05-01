import std/[os, strutils]
import jsonx
import adaptive_ui/config

block defaults:
  let cfg = initAppConfig()
  doAssert cfg.apiUrl == "https://api.openai.com/v1/chat/completions"
  doAssert cfg.timeoutMs == 30000
  doAssert cfg.skillRoots.len == 1

block roundtrip:
  let cfg = AppConfig(
    apiUrl: "http://localhost:8080/v1",
    apiKey: "",
    chatModel: "chat-model",
    uiModel: "ui-model",
    timeoutMs: 9000,
    skillRoots: @["tests/fixtures/skills"]
  )
  let text = toJson(cfg)
  doAssert "\"chatModel\":\"chat-model\"" in text

  var parsed: AppConfig
  var err = ""
  doAssert parseConfig(text, parsed, err), err
  doAssert parsed.chatModel == "chat-model"
  doAssert parsed.skillRoots == @["tests/fixtures/skills"]

block loadMissingUsesDefaults:
  var cfg: AppConfig
  var err = ""
  doAssert loadConfig("/tmp/adaptive-ui-missing-config.json", cfg, err), err

block saveAndLoad:
  let path = getTempDir() / "adaptive-ui-config-test.json"
  let cfg = AppConfig(
    apiUrl: "http://localhost:9000/v1",
    apiKey: "sk-secret",
    chatModel: "chat",
    uiModel: "ui",
    timeoutMs: 1000,
    skillRoots: @["a", "b"]
  )

  var err = ""
  doAssert saveConfig(path, cfg, err), err

  let saved = readFile(path)
  doAssert "sk-secret" notin saved

  var loaded: AppConfig
  doAssert loadConfig(path, loaded, err), err
  doAssert loaded.apiUrl == cfg.apiUrl
  doAssert loaded.skillRoots == @["a", "b"]

  if fileExists(path):
    removeFile(path)

block invalidJson:
  var cfg: AppConfig
  var err = ""
  doAssert not parseConfig("""{"apiUrl":""", cfg, err)
  doAssert err.len > 0

block jsonxShape:
  let cfg = initAppConfig()
  let parsed = fromJson(toJson(cfg), AppConfig)
  doAssert parsed.apiUrl == cfg.apiUrl
