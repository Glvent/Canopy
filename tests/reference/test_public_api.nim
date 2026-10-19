## Public module export surface tests.
import std/[unittest, json, options]

import canopy

static:
  doAssert not declared(Input)
  doAssert not declared(InputParser)
  doAssert not declared(Animator)
  doAssert not declared(initTween)

suite "public construction and styling":
  test "style shortcuts compose on strings, text, styles and widgets":
    let span = "hello".red().bold().onBlue().notItalic()
    check span.style.fg == some(color(ColorKind.Red))
    check span.style.bg == some(color(ColorKind.Blue))
    check Modifier.Bold in span.style.addModifiers
    check Modifier.Italic in span.style.subModifiers
    check initStyle().red().notBold().fg == some(color(ColorKind.Red))
    check initParagraph("hello").cyan().bold().style.fg == some(color(ColorKind.Cyan))
    check initLine("line").green().style.fg == some(color(ColorKind.Green))
    check initFill(".").withSymbol("#").symbol == "#"
    check initScrollbar().withSymbols(ScrollbarHorizontal).thumbSymbol == ScrollbarHorizontal.thumb
  test "theme and color serialization are explicit and reversible":
    var theme: Theme
    theme["selection"] = initStyle().withFg(rgbColor(12, 34, 56)).withBg(indexedColor(240)).bold()
    theme["reset"] = resetStyle()
    check themeFromJson(theme.toJson) == theme
    for color in [color(ColorKind.Reset), color(ColorKind.LightCyan), indexedColor(240), rgbColor(
        12, 34, 56)]:
      check parseColor($color) == color
    expect ValueError: discard themeFromJson(parseJson("[]"))
  test "rectangle helpers saturate while retaining size":
    let area = initRect(3, 4, 5, 6)
    check area + initOffset(int.high, int.high) == initRect(65530, 65529, 5, 6)
    check area - initOffset(int.low, int.low) == initRect(65530, 65529, 5, 6)
    check area + initOffset(int.low, int.low) == initRect(0, 0, 5, 6)
    check initRect(0, 0, 10, 8).centered(length(4), length(2)) == initRect(3, 3, 4, 2)
    check layout[2](area, horizontal([fill(), fill()])).len == 2
    check tryLayout[1](area, horizontal([fill(), fill()])).isNone
  test "text recognizes CRLF while retaining a lone final carriage return":
    check $initLine("a\r\nb\n") == "ab"
    check initLine("").spans.len == 0
    check $initText("a\r\nb\r") == "a\nb\r"
    check $initText("a\r\n") == "a"
    check $initText("\r") == "\r"
