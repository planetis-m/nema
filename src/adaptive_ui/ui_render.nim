import std/[strutils, tables]
import uirelays
import uirelays/layout
import widgets/synedit
import ./[components, ui_doc]

const
  Pad = 8

let
  bgColor = color(28, 30, 34)
  panelColor = color(247, 248, 250)
  borderColor = color(190, 196, 206)
  textColor = color(28, 31, 36)
  accentColor = color(42, 105, 210)
  selectedColor = color(222, 235, 255)
  dangerColor = color(180, 48, 64)

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

proc languageFor(name: string): SourceLanguage =
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
  else:
    langNone

proc ensureEditor(rt: var UiRuntime; area: UiArea; font: Font): string =
  let key = componentKey(area)
  if not rt.components.hasKey(key):
    rt.components[key] = ComponentState(textBufferId: key)
  if not rt.components[key].hasEditor:
    rt.components[key].editor = createSynEdit(font)
    rt.components[key].hasEditor = true
  result = key

proc syncReadOnlyEditor(rt: var UiRuntime; area: UiArea; font: Font) =
  let key = rt.ensureEditor(area, font)
  let lang =
    case area.kind
    of ukCode:
      languageFor(area.language)
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
    focused: bool; font: Font): UiEvent =
  rt.syncReadOnlyEditor(area, font)
  let key = componentKey(area)
  fillRect(r, panelColor)
  drawBorder(r, borderColor)
  discard rt.components[key].editor.draw(e, r.inset(Pad), focused)
  result = noUiEvent()

proc optionRect(r: Rect; fm: FontMetrics; index: int): Rect =
  let rowH = max(fm.lineHeight + 10, 28)
  rect(r.x + Pad, r.y + Pad + index * rowH, max(0, r.w - Pad * 2), rowH - 4)

proc renderRadio(rt: var UiRuntime; area: UiArea; e: Event; r: Rect;
    fm: FontMetrics; font: Font): UiEvent =
  fillRect(r, panelColor)
  drawBorder(r, borderColor)

  var selected = rt.selectedOption(area)
  result = noUiEvent()

  for i, option in area.options:
    let row = optionRect(r, fm, i)
    let isSelected = option.id == selected
    fillRect(row, if isSelected: selectedColor else: panelColor)
    drawBorder(row, if isSelected: accentColor else: borderColor)

    let marker = if isSelected: "(*) " else: "( ) "
    discard drawText(font, row.x + 8, row.y + 5,
      marker & option.label, textColor, if isSelected: selectedColor else: panelColor)

    if e.kind == MouseDownEvent and e.button == LeftButton and
        row.contains(point(e.x, e.y)):
      rt.setSelected(area, option.id)
      selected = option.id
      result = eventForSelect(area, option.id)

proc buttonRect(r: Rect; font: Font; label: string; x: var int): Rect =
  let textW = measureText(font, label).w
  let w = max(92, textW + 28)
  result = rect(x, r.y + Pad, w, max(28, r.h - Pad * 2))
  x += w + 8

proc renderButtons(area: UiArea; e: Event; r: Rect; font: Font): UiEvent =
  fillRect(r, panelColor)
  drawBorder(r, borderColor)
  result = noUiEvent()

  var x = r.x + Pad
  for option in area.options:
    let b = buttonRect(r, font, option.label, x)
    fillRect(b, accentColor)
    drawBorder(b, accentColor)
    discard drawText(font, b.x + 14, b.y + max(4, (b.h - fontLineSkip(font)) div 2),
      option.label, color(255, 255, 255), accentColor)
    if e.kind == MouseDownEvent and e.button == LeftButton and
        b.contains(point(e.x, e.y)):
      result = eventForClick(area, option.id)

proc renderTextInput(rt: var UiRuntime; area: UiArea; e: Event; r: Rect;
    focused: bool; font: Font): UiEvent =
  let key = rt.ensureEditor(area, font)
  if rt.components[key].lastKind != ukTextInput:
    rt.components[key].editor.lang = langNone
    rt.components[key].editor.showLineNumbers = false
    if area.text.len > 0:
      rt.components[key].editor.setText(area.text)
    rt.components[key].lastKind = ukTextInput

  fillRect(r, panelColor)
  drawBorder(r, if focused: accentColor else: borderColor)

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

proc resolvedCells(doc: UiDoc; rt: var UiRuntime; area: Rect;
    lineHeight: int; renderDoc: var UiDoc): Table[string, Rect] =
  try:
    let parsed = parseLayout(doc.layout)
    result = parsed.resolve(area.w, area.h, lineHeight, gap = 2)
    renderDoc = doc
  except CatchableError:
    rt.status = "layout error: " & getCurrentExceptionMsg()
    renderDoc = fallbackUiDoc("The generated UI layout could not be rendered.")
    result = parseLayout(renderDoc.layout).resolve(area.w, area.h, lineHeight, gap = 2)

  for name, r in result.mpairs:
    r = r.offset(area)

proc renderUiDoc*(doc: UiDoc; rt: var UiRuntime; e: Event; area: Rect;
    font: Font; fm: FontMetrics): UiEvent =
  var renderDoc: UiDoc
  var cells = resolvedCells(doc, rt, area, fm.lineHeight, renderDoc)
  fillRect(area, bgColor)

  if rt.focus.len == 0 and renderDoc.focus.len > 0:
    rt.setFocus(renderDoc.focus)

  if e.kind == MouseDownEvent:
    let hit = cells.hitTest(e.x, e.y)
    if hit.name.len > 0:
      rt.setFocus(hit.name)

  result = noUiEvent()
  for areaDef in renderDoc.areas:
    if not cells.hasKey(areaDef.name):
      continue

    let r = cells[areaDef.name]
    let focused = rt.focus == areaDef.name
    let routedEvent = if focused: e else: default Event
    let ev =
      case areaDef.kind
      of ukText, ukTranscript, ukCode, ukMath:
        renderTextArea(rt, areaDef, routedEvent, r, focused, font)
      of ukRadio:
        renderRadio(rt, areaDef, routedEvent, r, fm, font)
      of ukButtons:
        renderButtons(areaDef, routedEvent, r, font)
      of ukTextInput:
        renderTextInput(rt, areaDef, routedEvent, r, focused, font)

    if ev.kind != ueNone:
      result = ev

  if renderDoc.areas.len == 0:
    discard drawText(font, area.x + Pad, area.y + Pad,
      "No UI areas to render.", dangerColor, bgColor)
