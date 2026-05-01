import std/strutils
import ./ui_doc

type
  LiveFlowKind* = enum
    lfAdaptive,
    lfChat,
    lfQuiz,
    lfEssay

  LiveCommandKind* = enum
    lcNone,
    lcAdaptive,
    lcChat,
    lcQuiz,
    lcEssay,
    lcDebug

  LiveCommand* = object
    kind*: LiveCommandKind
    text*: string

proc commandPayload(input, command: string): string =
  let trimmed = input.strip()
  if trimmed.len == command.len:
    result = ""
  elif trimmed.len > command.len and trimmed[command.len] == ' ':
    result = trimmed[command.len + 1 .. ^1].strip()
  else:
    result = ""

proc parseLiveCommand*(input: string): LiveCommand =
  let trimmed = input.strip()
  let lowered = trimmed.toLowerAscii()
  if lowered == "/adaptive" or lowered.startsWith("/adaptive "):
    result = LiveCommand(
      kind: lcAdaptive,
      text: commandPayload(trimmed, "/adaptive")
    )
  elif lowered == "/chat" or lowered.startsWith("/chat "):
    result = LiveCommand(kind: lcChat, text: commandPayload(trimmed, "/chat"))
  elif lowered == "/quiz" or lowered.startsWith("/quiz "):
    result = LiveCommand(kind: lcQuiz, text: commandPayload(trimmed, "/quiz"))
  elif lowered == "/essay" or lowered.startsWith("/essay "):
    result = LiveCommand(kind: lcEssay, text: commandPayload(trimmed, "/essay"))
  elif lowered == "/debug":
    result = LiveCommand(kind: lcDebug)
  else:
    result = LiveCommand(kind: lcNone, text: trimmed)

proc flowForCommand*(kind: LiveCommandKind): LiveFlowKind =
  case kind
  of lcNone, lcAdaptive, lcDebug:
    lfAdaptive
  of lcChat:
    lfChat
  of lcQuiz:
    lfQuiz
  of lcEssay:
    lfEssay

proc flowTitle*(kind: LiveFlowKind): string =
  case kind
  of lfAdaptive:
    "Adaptive"
  of lfChat:
    "Chat"
  of lfQuiz:
    "Quiz"
  of lfEssay:
    "Essay"

proc flowIntroDoc*(kind: LiveFlowKind): UiDoc =
  case kind
  of lfAdaptive:
    UiDoc(
      version: 1,
      title: "Adaptive UI",
      layout: """
| title, 2 lines |
| overview, * | examples, * |
| actions, 3 lines |
""",
      areas: @[
        UiArea(
          name: "title",
          kind: ukText,
          text: "Adaptive UI"
        ),
        UiArea(
          name: "overview",
          kind: ukText,
          text: "Ask for any task. The generated surface can become notes, code review, a decision prompt, a form, a study aid, math text, or a normal transcript."
        ),
        UiArea(
          name: "examples",
          kind: ukText,
          text: "- Plan a weekend trip\n- Compare two design options\n- Explain code with examples\n- Make a checklist\n- Run a quiz only when requested"
        ),
        UiArea(
          name: "actions",
          kind: ukButtons,
          id: "intro_actions",
          options: @[
            UiOption(id: "chat", label: "Chat"),
            UiOption(id: "quiz", label: "Quiz"),
            UiOption(id: "essay", label: "Essay")
          ]
        )
      ],
      focus: "overview"
    )
  of lfChat:
    textUiDoc("Chat", "Normal chat mode. Type /adaptive to return to adaptive task mode.")
  of lfQuiz:
    textUiDoc("Quiz", "Type a quiz topic, or answer the generated question.")
  of lfEssay:
    textUiDoc("Essay", "Type an essay topic, or submit the generated answer.")
