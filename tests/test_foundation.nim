import std/[unittest, json]
import canopy/[geometry, style, text, buffer]

suite "foundation":
  test "geometry saturates, clips and preserves origins":
    check initRect(65530,65530,20,20) == initRect(65530,65530,5,5)
    check initRect(2,3,5,4).intersection(initRect(4,4,8,2)) == initRect(4,4,3,2)
    check initRect(1,2,4,3).inner(initMargin(1,1)) == initRect(2,3,2,1)
    check initRect(0,0,65535,2).inner(initMargin(65535,0)) == initRect(65535,0,0,2)
  test "style composition and reset are explicit":
    let s = initStyle().withFg(ColorKind.Red).bold().italic()
    let p = s.patch(initStyle().withBg(ColorKind.Blue).withRemoveModifier(Modifier.Bold))
    check p.fg.get == color(ColorKind.Red)
    check p.bg.get == color(ColorKind.Blue)
    check p.addModifiers == {Modifier.Italic}
    check p.subModifiers == {Modifier.Bold}
    var c = initCell("x")
    c.setStyle(p)
    c.setStyle(resetStyle())
    check c == initCell("x")
  test "JSON round trip retains inheritance and rejects malformed values":
    let s = initStyle().withFg(rgbColor(1,2,3)).withBg(indexedColor(42)).bold().withRemoveModifier(Modifier.Italic)
    check styleFromJson(s.toJson) == s
    check styleFromJson(%*{}) == initStyle()
    expect ValueError: discard colorFromJson(%*{"rgb":[256,0,0]})
    expect ValueError: discard styleFromJson(%*{"addModifiers":["Bold"],"subModifiers":["Bold"]})
  test "styled text width and lines":
    let t = initText("hello\r\n世界\n")
    check t.height == 2
    check t.width == 5
    check $t == "hello\n世界"
    check initLine([initSpan("a"),initSpan("界")]).width == 3
  test "writes preserve graphemes, clip and reset wide continuations":
    var b = initBuffer(initRect(3,2,5,1),initCell("x"))
    b.setStringn(3,2,"é界z",3,initStyle().withFg(ColorKind.Red))
    check b[3,2].symbol == "é"
    check b[4,2].symbol == "界"
    check b[5,2] == initCell()
    check b[6,2].symbol == "x"
    b.setString(7,2,"界")
    check b[7,2].symbol == "x"
    b.setString(3,9,"outside")
  test "wide diff and unchanged frames":
    var old = initBuffer(initRect(0,0,4,1))
    old.setString(0,0,"界",initStyle().withBg(ColorKind.Blue))
    var next = initBuffer(old.area)
    next.setString(0,0,"a")
    let changes = diff(old,next)
    check changes.len == 2
    check changes[1].x == 1
    check diff(next,next).len == 0
    check diff(next,old).len == 1
  test "VS16 explicitly clears old trailing symbols":
    let old = initBuffer(["ab"])
    var next = initBuffer(old.area)
    next.setString(0,0,"❤️")
    check diff(old,next).len == 2
  test "buffer copies do not alias and merge retains positions":
    var a = initBuffer(["abc"])
    var b = a
    b[0,0].symbol = "z"
    check a[0,0].symbol == "a"
    var overlay = initBuffer(initRect(2,0,2,1))
    overlay.setString(2,0,"XY")
    a.merge(overlay)
    check a.area == initRect(0,0,4,1)
    check a[2,0].symbol == "X"
    check a[3,0].symbol == "Y"
