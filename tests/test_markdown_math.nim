import std/strutils
import adaptive_ui/[markdown_view, math_view, ui_render]
import widgets/synedit

block markdownHeadings:
  let text = formatMarkdownText("# Title\n\n## Section\nBody")
  doAssert text.startsWith("Title")
  doAssert "##" notin text
  doAssert "Section" in text

block markdownBulletsAndQuotes:
  let text = formatMarkdownText("* item\n- other\n> quoted")
  doAssert "- item" in text
  doAssert "- other" in text
  doAssert "| quoted" in text

block markdownFences:
  let text = formatMarkdownText("```nim\nlet x = 1\n```")
  doAssert "[code: nim]" in text
  doAssert "let x = 1" in text
  doAssert "[/code]" in text

block mathDelimiters:
  doAssert formatMathLine("$x^2 + y^2$") == "x^2 + y^2"
  doAssert formatMathLine("$$x \\times y$$") == "x * y"
  doAssert formatMathLine("\\[a \\le b\\]") == "a <= b"

block mathFrac:
  doAssert formatMathLine("\\frac{a+b}{c}") == "(a+b)/(c)"

block languageMapping:
  doAssert sourceLanguageFor("nim") == langNim
  doAssert sourceLanguageFor(".cpp") == langCpp
  doAssert sourceLanguageFor("javascript") == langJs
  doAssert sourceLanguageFor("text") == langNone
  doAssert sourceLanguageFor("unknown") == langNone
