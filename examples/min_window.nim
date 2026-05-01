import uirelays
import uirelays/backend
import widgets/theme

proc main =
  initBackend()
  let win = createWindow(900, 600)
  var screenW = win.width
  var screenH = win.height

  var fm: FontMetrics
  let font = openFont("", 18, fm)
  let theme = catppuccinMocha()
  setWindowTitle("Adaptive UI")

  var running = true
  while running:
    var e = default Event
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent:
        screenW = e.x
        screenH = e.y
      of KeyDownEvent:
        if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
          running = false
      else:
        discard

    fillRect(rect(0, 0, screenW, screenH), theme.bg)
    fillRect(rect(0, 0, screenW, 44), theme.scrollTrackColor)
    discard drawText(font, 14, 12, "Adaptive UI",
      theme.fg[TokenClass.Text], theme.scrollTrackColor)
    discard drawText(font, 14, 64,
      "Bootstrap window. Press Esc or Ctrl+Q to quit.",
      theme.fg[TokenClass.Comment], theme.bg)

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

when isMainModule:
  main()
