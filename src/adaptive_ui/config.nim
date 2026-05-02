import std/[os, paths]
import jsonx

const
  ApiKeyEnv = "OPENAI_API_KEY"
  DefaultApiUrl = "https://api.openai.com/v1/chat/completions"
  DefaultModel = "gpt-4.1-mini"
  DefaultTimeoutMs = 30000

type
  AppConfig* = object
    apiUrl*: string
    apiKey*: string
    chatModel*: string
    timeoutMs*: int

proc initAppConfig*(): AppConfig =
  AppConfig(
    apiUrl: DefaultApiUrl,
    apiKey: getEnv(ApiKeyEnv),
    chatModel: DefaultModel,
    timeoutMs: DefaultTimeoutMs
  )

proc parseConfig*(text: string): AppConfig =
  result = initAppConfig()
  fromJson(text, result)

proc loadConfig*(path: string): AppConfig =
  result = initAppConfig()
  if fileExists(path):
    fromFile(Path(path), result)

proc hasKey*(cfg: AppConfig): bool =
  cfg.apiKey.len > 0

proc saveConfig*(path: string; cfg: AppConfig) =
  var saved = cfg
  saved.apiKey = ""
  writeFile(path, toJson(saved))
