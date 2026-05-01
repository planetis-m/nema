import std/os
import jsonx

const
  ApiKeyEnv = "OPENAI_API_KEY"

type
  AppConfig* = object
    apiUrl*: string
    apiKey*: string
    chatModel*: string
    uiModel*: string
    timeoutMs*: int

proc initAppConfig*(): AppConfig =
  AppConfig(
    apiUrl: "https://api.openai.com/v1/chat/completions",
    apiKey: getEnv(ApiKeyEnv),
    chatModel: "gpt-4.1-mini",
    uiModel: "gpt-4.1-mini",
    timeoutMs: 30000
  )

proc parseConfig*(text: string; cfg: var AppConfig; err: var string): bool =
  try:
    cfg = fromJson(text, AppConfig)
    if cfg.apiKey.len == 0:
      cfg.apiKey = getEnv(ApiKeyEnv)
    err = ""
    result = true
  except CatchableError as e:
    err = e.msg
    result = false

proc hasKey*(cfg: AppConfig): bool =
  cfg.apiKey.len > 0

proc loadConfig*(path: string; cfg: var AppConfig; err: var string): bool =
  if fileExists(path):
    result = parseConfig(readFile(path), cfg, err)
  else:
    cfg = initAppConfig()
    err = ""
    result = true

proc saveConfig*(path: string; cfg: AppConfig; err: var string): bool =
  try:
    var saveCfg = cfg
    saveCfg.apiKey = ""
    writeFile(path, toJson(saveCfg))
    err = ""
    result = true
  except CatchableError as e:
    err = e.msg
    result = false
