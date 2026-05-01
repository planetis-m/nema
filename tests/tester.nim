import std/[os, strutils]

const
  TestFiles = [
    "tests/test_agent_runtime.nim",
    "tests/test_config.nim",
    "tests/test_control_events.nim",
    "tests/test_debug_log.nim",
    "tests/test_interaction.nim",
    "tests/test_learning_flow.nim",
    "tests/test_live_flow.nim",
    "tests/test_markdown_math.nim",
    "tests/test_skill_files.nim",
    "tests/test_transcript.nim",
    "tests/test_ui_doc_parse.nim",
    "tests/test_ui_render_state.nim"
  ]

  ExampleFiles = [
    "examples/adaptive_app.nim",
    "examples/adaptive_gallery.nim",
    "examples/learning_demo.nim",
    "examples/min_window.nim"
  ]

proc binaryPath(path: string): string =
  if path.endsWith(".nim"):
    result = path[0 ..< path.len - 4]
  else:
    result = path

proc cleanup(path: string) =
  let bin = binaryPath(path)
  if fileExists(bin):
    removeFile(bin)

proc run(cmd: string) =
  echo cmd
  if execShellCmd(cmd) != 0:
    quit "failed: " & cmd, 1

proc compileAndRun(path: string) =
  run "nim c -d:sdl3 -r " & quoteShell(path)
  cleanup(path)

proc compileOnly(path: string) =
  run "nim c -d:sdl3 " & quoteShell(path)
  cleanup(path)

for path in TestFiles:
  compileAndRun(path)

for path in ExampleFiles:
  compileOnly(path)

echo "All SDL3 tests and examples completed."
