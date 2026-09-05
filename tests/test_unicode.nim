import std/[unittest, strutils, os]
import canopy/unicode

proc unhex(s: string): string =
  var i = 0
  while i < s.len:
    result.add char(parseHexInt(s[i..i+1]))
    i += 2

suite "Unicode 17 pinned native compatibility":
  test "every official extended grapheme test":
    var count = 0
    for line in lines(currentSourcePath.parentDir / "unicode/graphemes.tsv"):
      if line.startsWith("#"): continue
      let fields = line.split('\t')
      var expected: seq[string]
      for cluster in fields[1].split(' '): expected.add unhex(cluster)
      let actual = graphemes(unhex(fields[0]))
      if actual != expected:
        checkpoint "grapheme input " & fields[0]
        check actual == expected
      inc count
    check count == 766
  test "upstream contextual width and emoji tests":
    var count = 0
    for line in lines(currentSourcePath.parentDir / "unicode/width.tsv"):
      if line.startsWith("#"): continue
      let fields = line.split('\t')
      let actual = displayWidth(unhex(fields[0]))
      let expected = parseInt(fields[1])
      if actual != expected:
        checkpoint "width input " & fields[0]
        check actual == expected
      inc count
    check count > 20_000
  test "invalid UTF-8 always advances and preserves bytes":
    for s in ["\xFF\xFE", "\xC0\x80", "\xED\xA0\x80", "\xF4\x90\x80\x80", "\xE2\x82", "a\x80b"]:
      check graphemes(s).join == s
      check displayWidth(s) == s.len
      check graphemes(s).len == s.len
    check displayWidth("\xF0\x9F\x92\xA9") == 2
  test "clipping retains clusters and contextual width":
    check truncateWidth("a👩‍🔬中", 3) == "a👩‍🔬"
    check truncateWidth("éx", 1) == "é"
    check truncateWidth("👩‍🔬", 1) == ""
    check truncateWidth("\u0301x", 0) == "\u0301"
    check truncateWidth("abc", -1) == ""
    check truncateWidth("لا", 1) == "لا"
  test "Ratatui cell-width halfwidth marks":
    check displayWidth("ｶﾞ") == 1
    check cellWidth("ｶﾞ") == 2
    check cellWidth("ﾞﾟ") == 2
