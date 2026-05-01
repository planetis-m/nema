import std/[strutils, tables]
import uirelays
import uirelays/layout
import widgets/synedit
import widgets/theme
import ./[components, markdown_view, math_view, ui_doc]

const
  Pad = 8

proc noUiEvent(): UiEvent =
  UiEvent(kind: ueNone)

proc inset(r: Rect; pad: int): Rect =
  rect(r.x + pad, r.y + pad, max(0, r.w - pad * 2), max(0, r.h - pad * 2))

proc offset(r: Rect; parent: Rect): Rect =
  rect(parent.x + r.x, parent.y + r.y, r.w, r.h)

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0:
    return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc sourceLanguageFor*(name: string): SourceLanguage =
  case name.normalize.toLowerAscii
  of "nim", ".nim", "nims", ".nims":
    langNim
  of "c", ".c":
    langC
  of "cpp", ".cpp", "c++", "hpp", ".hpp":
    langCpp
  of "js", ".js", "javascript":
    langJs
  of "html", ".html", "htm", ".htm":
    langHtml
  of "xml", ".xml":
    langXml
  of "console", "transcript":
    langConsole
  of "text", ".txt", "plain", "plaintext":
    langNone
  else:
    langNone

proc displayArea(area: UiArea): UiArea =
  result = area
  case area.kind
  of ukText, ukTranscript:
    result.text = formatMarkdownText(area.text)
  of ukMath:
    result.text = formatMathText(area.text)
  of ukCode, ukRadio, ukButtons, ukTextInput:
    discard

proc ensureEditor(rt: var UiRuntime; area: UiArea; font: Font;
    theme: Theme): string =
  let key = componentKey(area)
  if not rt.components.hasKey(key):
    rt.components[key] = ComponentState(textBufferId: key)
  if not rt.components[key].hasEditor:
    rt.components[key].editor = createSynEdit(font, theme)
    rt.components[key].hasEditor = true
  result = key

proc syncReadOnlyEditor(rt: var UiRuntime; area: UiArea; font: Font;
    theme: Theme) =
  let key = rt.ensureEditor(area, font, theme)
  rt.components[key].editor.theme = theme
  let lang =
    case area.kind
    of ukCode:
      sourceLanguageFor(area.language)
    of ukTranscript:
      langConsole
    else:
      langNone

  if rt.components[key].lastText != area.text or
      rt.components[key].lastLanguage != area.language or
      rt.components[key].lastKind != area.kind:
    rt.components[key].editor.lang = lang
    rt.components[key].editor.showLineNumbers = area.kind == ukCode
    rt.components[key].editor.setLabel(area.text)
    rt.components[key].lastText = area.text
    rt.components[key].lastLanguage = area.language
    rt.components[key].lastKind = area.kind

proc renderTextArea(rt: var UiRuntime; area: UiArea; e: Event; r: Rect;
    focused: bool; font: Font; theme: Theme): UiEvent =
  rt.syncReadOnlyEditor(area, font, theme)
  let key = componentKey(area)
  fillRect(r, theme.bg)
  drawBorder(r, if focused: theme.fg[TokenClass.Operator] else: theme.scrollTrackColor)
  discard rt.components[key].editor.draw(e, r.inset(Pad), focused)
  result = noUiEvent()

proc optionRect(r: Rect; fm: FontMetrics; index: int): Rect =
  let rowH = max(fm.lineHeight + 10, 28)
  rect(r.x + Pad, r.y + Pad + index * rowH, max(0, r.w - Pad * 2), rowH - 4)

proc radioHitEvent*(rt: var UiRuntime; area: UiArea; e: Event; r: Rect;
    fm: FontMetrics): UiEvent =
  result = noUiEvent()
  if e.kind != MouseDownEvent or e.button != LeftButton:
    return

  for i, option in area.options:
    if optionRect(r, fm, i).contains(point(e.x, e.y)):
      rt.setSelected(area, option.id)
      return eventForSelect(area, option.id)

proc renderRadio(rt: var UiRuntime; area: UiArea; e: Event; r: Rect;
    fm: FontMetrics; font: Font; theme: Theme): UiEvent =
  fillRect(r, theme.bg)
  drawBorder(r, theme.scrollTrackColor)

  var selected = rt.selectedOption(area)
  result = noUiEvent()

  for i, option in area.options:
    let row = optionRect(r, fm, i)
    let isSelected = option.id == selected
    let rowBg = if isSelected: theme.selBg else: theme.bg
    let rowBorder =
      if isSelected: theme.fg[TokenClass.Operator]
      else: theme.scrollTrackColor
    fillRect(row, rowBg)
    drawBorder(row, rowBorder)

    let marker = if isSelected: "(*) " else: "( ) "
    discard drawText(font, row.x + 8, row.y + 5,
      marker & option.label, theme.fg[TokenClass.Text], rowBg)

  result = radioHitEvent(rt, area, e, r, fm)

proc buttonRect(r: Rect; font: Font; label: string; x: var int): Rect =
  let textW = measureText(font, label).w
  let w = max(92, textW + 28)
  result = rect(x, r.y + Pad, w, max(28, r.h - Pad * 2))
  x += w + 8

proc buttonHitEvent*(area: UiArea; e: Event; r: Rect; font: Font): UiEvent =
  result = noUiEvent()
  if e.kind != MouseDownEvent or e.button != LeftButton:
    return

  var x = r.x + Pad
  for option in area.options:
    let b = buttonRect(r, font, option.label, x)
    if b.contains(point(e.x, e.y)):
      return eventForClick(area, option.id)

proc renderButtons(area: UiArea; e: Event; r: Rect; font: Font;
    theme: Theme): UiEvent =
  fillRect(r, theme.bg)
  drawBorder(r, theme.scrollTrackColor)
  result = noUiEvent()

  var x = r.x + Pad
  for option in area.options:
    let b = buttonRect(r, font, option.label, x)
    fillRect(b, theme.selBg)
    drawBorder(b, theme.fg[TokenClass.Operator])
    discard drawText(font, b.x + 14, b.y + max(4, (b.h - fontLineSkip(font)) div 2),
      option.label, theme.fg[TokenClass.Text], theme.selBg)
  result = buttonHitEvent(area, e, r, font)

proc renderTextInput(rt: var UiRuntime; area: UiArea; e: Event; r: Rect;
    focused: bool; font: Font; theme: Theme): UiEvent =
  let key = rt.ensureEditor(area, font, theme)
  rt.components[key].editor.theme = theme
  if rt.components[key].lastKind != ukTextInput:
    rt.components[key].editor.lang = langNone
    rt.components[key].editor.showLineNumbers = false
    if area.text.len > 0:
      rt.components[key].editor.setText(area.text)
    rt.components[key].lastKind = ukTextInput

  fillRect(r, theme.bg)
  drawBorder(r, if focused: theme.fg[TokenClass.Operator] else: theme.scrollTrackColor)

  var drawEvent = e
  var submit = false
  if focused and e.kind == KeyDownEvent and e.key == KeyEnter and
      (CtrlPressed in e.mods or GuiPressed in e.mods):
    submit = true
    drawEvent = default Event

  discard rt.components[key].editor.draw(drawEvent, r.inset(Pad), focused)
  rt.setText(area, rt.components[key].editor.fullText)

  if submit:
    result = eventForSubmit(area, rt.components[key].editor.fullText)
  else:
    result = noUiEvent()

proc resolveUiDocCells*(doc: UiDoc; rt: var UiRuntime; area: Rect;
    lineHeight: int; renderDoc: var UiDoc): Table[string, Rect] =
  try:
    let parsed = parseLayout(doc.layout)
    result = parsed.resolve(area.w, area.h, lineHeight, gap = 2)
    if result.len == 0:
      raise newException(ValueError, "layout produced no cells")
    renderDoc = doc
  except CatchableError:
    rt.status = "layout error: " & getCurrentExceptionMsg()
    renderDoc = fallbackUiDoc("The generated UI layout could not be rendered.")
    result = parseLayout(renderDoc.layout).resolve(area.w, area.h, lineHeight, gap = 2)

  for name, r in result.mpairs:
    r = r.offset(area)

proc renderUiDoc*(doc: UiDoc; rt: var UiRuntime; e: Event; area: Rect;
    font: Font; fm: FontMetrics; theme: Theme = catppuccinMocha()): UiEvent =
  var renderDoc: UiDoc
  var cells = resolveUiDocCells(doc, rt, area, fm.lineHeight, renderDoc)
  fillRect(area, theme.bg)

  if rt.focus.len == 0 and renderDoc.focus.len > 0:
    rt.setFocus(renderDoc.focus)

  if e.kind == MouseDownEvent:
    let hit = cells.hitTest(e.x, e.y)
    if hit.name.len > 0:
      rt.setFocus(hit.name)

  result = noUiEvent()
  for areaDef in renderDoc.areas:
    if not cells.hasKey(areaDef.name):
      discard
    else:
      let areaView = displayArea(areaDef)
      let r = cells[areaView.name]
      let focused = rt.focus == areaView.name
      let routedEvent = if focused: e else: default Event
      let ev =
        case areaView.kind
        of ukText, ukTranscript, ukCode, ukMath:
          renderTextArea(rt, areaView, routedEvent, r, focused, font, theme)
        of ukRadio:
          renderRadio(rt, areaView, routedEvent, r, fm, font, theme)
        of ukButtons:
          renderButtons(areaView, routedEvent, r, font, theme)
        of ukTextInput:
          renderTextInput(rt, areaView, routedEvent, r, focused, font, theme)

      if ev.kind != ueNone:
        result = ev

  if renderDoc.areas.len == 0:
    discard drawText(font, area.x + Pad, area.y + Pad,
      "No UI areas to render.", theme.fg[TokenClass.Red], theme.bg)
