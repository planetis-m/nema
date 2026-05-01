import std/os
import jsonx

type
  AppConfig* = object
    apiUrl*: string
    apiKeyEnv*: string
    chatModel*: string
    uiModel*: string
    timeoutMs*: int
    skillRoots*: seq[string]

proc defaultSkillRoots*(): seq[string] =
  let home = getHomeDir()
  result = @[
    home / ".agents" / "skills",
    home / ".codex" / "skills"
  ]

proc initAppConfig*(): AppConfig =
  AppConfig(
    apiUrl: "https://api.openai.com/v1/chat/completions",
    apiKeyEnv: "OPENAI_API_KEY",
    chatModel: "gpt-4.1-mini",
    uiModel: "gpt-4.1-mini",
    timeoutMs: 30000,
    skillRoots: defaultSkillRoots()
  )

proc parseConfig*(text: string; cfg: var AppConfig; err: var string): bool =
  try:
    cfg = fromJson(text, AppConfig)
    err = ""
    result = true
  except CatchableError as e:
    err = e.msg
    result = false

proc configJson*(cfg: AppConfig): string =
  toJson(cfg)

proc loadConfig*(path: string; cfg: var AppConfig; err: var string): bool =
  if fileExists(path):
    result = parseConfig(readFile(path), cfg, err)
  else:
    cfg = initAppConfig()
    err = ""
    result = true

proc saveConfig*(path: string; cfg: AppConfig; err: var string): bool =
  try:
    writeFile(path, configJson(cfg))
    err = ""
    result = true
  except CatchableError as e:
    err = e.msg
    result = false
