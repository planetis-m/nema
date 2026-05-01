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

proc flowPrompt*(kind: LiveFlowKind; text: string): string =
  let body = text.strip()
  case kind
  of lfAdaptive:
    result = """
Adaptive task mode.
Help with the user's task directly. The task can be notes, planning, coding, math, forms, decisions, study, games, or normal chat.
Keep enough visible task state in the response for the UI subagent to choose an appropriate supported interface.
Do not force the task into a quiz or essay unless the user asks for that.
When the input describes UI values, clicked buttons, selected options, or submitted text, treat that as the user's interaction with the current generated UI.

User input:
""" & body
  of lfChat:
    result = """
Normal chat mode.
Answer conversationally. The UI subagent should usually render this as a transcript or simple text.

User input:
""" & body
  of lfQuiz:
    result = """
Live quiz mode.
Create or continue a quiz one question at a time.
Track score and correct answers in the conversation.
When asking a question, include enough structured detail for the UI subagent to render a radio group and submit button.
When the input describes a selected option or clicked submit button, treat the current UI values as the user's answer.
When grading an answer, compare both the option id and visible label, explain briefly, and then move to the next question or final score.

User input:
""" & body
  of lfEssay:
    result = """
Live essay mode.
Create or continue an essay practice flow.
When starting, provide one essay prompt and a short rubric.
When the input describes submitted text, treat that text as the user's essay answer.
When the user submits an answer, grade it against the rubric and provide concise feedback.
Include enough task state for the UI subagent to render either a text input or feedback screen.

User input:
""" & body

proc uiFlowHint*(kind: LiveFlowKind): string =
  case kind
  of lfAdaptive:
    result = "Current flow: adaptive task. Choose the smallest supported UI that fits the user's task: text, transcript, code, math, radio/buttons for decisions, or textInput for open responses. Do not default to quiz or essay unless requested."
  of lfChat:
    result = "Current flow: normal chat. Prefer transcript or text unless the response clearly asks for interactive controls."
  of lfQuiz:
    result = "Current flow: quiz. Prefer one radio area for answer choices and one buttons area for submit/next/finish actions. Keep option ids stable between grading turns."
  of lfEssay:
    result = "Current flow: essay. Prefer one prompt area, one textInput area for the answer, and one buttons area for submit actions. Use submitLabel on textInput when the input should submit directly."

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
