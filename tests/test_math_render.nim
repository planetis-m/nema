import adaptive_ui/[math_view, ui_render]
import widgets/synedit

block mathDelimiters:
  doAssert formatMathLine("$x^2 + y^2$") == "x^2 + y^2"
  doAssert formatMathLine("$$x \\times y$$") == "x * y"
  doAssert formatMathLine("\\[a \\le b\\]") == "a <= b"

block mathFrac:
  doAssert formatMathLine("\\frac{a+b}{c}") == "(a+b)/(c)"
  doAssert formatMathLine("\\frac{a+b}") == "\\frac{a+b}"

block languageMapping:
  doAssert sourceLanguageFor("nim") == langNim
  doAssert sourceLanguageFor(".cpp") == langCpp
  doAssert sourceLanguageFor("javascript") == langJs
  doAssert sourceLanguageFor("text") == langNone
  doAssert sourceLanguageFor("unknown") == langNone
