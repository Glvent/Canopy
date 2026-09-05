import std/[unittest,strutils]
import canopy/[text,buffer,geometry]
import canopy/widgets/paragraph
import canopy/internal/reflow

proc wrapped(s: string, width: int, trim = true): seq[string] =
  for line in initText(s).lines:
    for outLine in wrapLine(line,initStyle(),Alignment.Left,width,trim):
      var s = ""
      for g in outLine.graphemes: s.add g.symbol
      result.add s

suite "Paragraph and upstream reflow edge cases":
  test "long words split and ordinary words move intact":
    check wrapped("abcd efghij klmnopabcdefghijklmnopabcdefghijkl mnopab cdefghi j klmno",20) ==
      @["abcd efghij","klmnopabcdefghijklmn","opabcdefghijkl","mnopab cdefghi j","klmno"]
  test "whitespace trimming and incidental trailing empty line":
    check wrapped(repeat(' ',69),20) == @[""]
    check wrapped("a" & repeat(' ',69),20) == @["a",""]
    check wrapped("AAAAAAAAAAAAAAAAAAAA    AAA",20) == @["AAAAAAAAAAAAAAAAAAAA","AAA"]
    check wrapped("AAAAAAAAAAAAAAAAAAAA    AAA",20,false) == @["AAAAAAAAAAAAAAAAAAAA","   AAA"]
    check wrapped("               4 Indent\n                 must wrap!",10,false) ==
      @["          ","    4","Indent","          ","      must","wrap!"]
  test "NBSP joins a word and ZWSP is whitespace":
    check wrapped("AAAAAAAAAAAAAAA AAAA\u00A0AAA",20) == @["AAAAAAAAAAAAAAA","AAAA\u00A0AAA"]
    check wrapped("AAAAAAAAAAAAAAA AAAA AAA",20) == @["AAAAAAAAAAAAAAA AAAA","AAA"]
    check wrapped("foo\u200B",3) == @["foo"]
  test "wide glyphs never split and too-wide glyphs are skipped":
    check wrapped("コンピュータ上で文字を扱う場合、典型的には文字による通信を行う場合にその両端点では、",20) ==
      @["コンピュータ上で文字","を扱う場合、典型的に","は文字による通信を行","う場合にその両端点で","は、"]
    check wrapped("中\naaa\na中",1) == @["","a","a","a","a"]
    # Upstream's pending-word algorithm emits this overwidth line unchanged.
    check wrapped("é👩‍🔬x",2) == @["é","👩‍🔬x"]
  test "horizontal scrolling retains partial wide glyph and alignment ignores horizontal scroll":
    let line = truncateLine(initLine("中ab"),initStyle(),Alignment.Left,3,1)
    check line.graphemes[0].symbol == "中"
    check line.width == 3
    var buf = initBuffer(initRect(0,0,5,1))
    initParagraph("abc").centered.withScroll(0,2).render(buf.area,buf)
    check buf == initBuffer([" abc "])
  test "wrap ignores horizontal scroll; vertical scroll counts wrapped lines":
    var buf = initBuffer(initRect(0,0,3,2))
    initParagraph("abc def ghi").withWrap(true).withScroll(1,99).render(buf.area,buf)
    check buf == initBuffer(["def","ghi"])
  test "zero area preserves buffer":
    var buf = initBuffer(["keep"])
    initParagraph("change").render(initRect(0,0,0,1),buf)
    check buf == initBuffer(["keep"])
