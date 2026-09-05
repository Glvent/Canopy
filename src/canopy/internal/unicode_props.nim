## Unicode 17 properties and strict, progress-guaranteed UTF-8 decoding.
import unicode_tables

type
  GraphemeCategory* = enum
    gcAny, gcCR, gcControl, gcExtend, gcExtendedPictographic, gcInCBConsonant,
    gcL, gcLF, gcLV, gcLVT, gcPrepend, gcRegionalIndicator, gcSpacingMark,
    gcT, gcV, gcZWJ
  DecodedRune* = object
    code*, first*, last*: int
    property*: UnicodeProperty

proc properties*(code: int): UnicodeProperty =
  var lo = 0
  var hi = unicodeProperties.high
  while lo <= hi:
    let mid = (lo + hi) shr 1
    if code < unicodeProperties[mid].first: hi = mid - 1
    elif code > unicodeProperties[mid].last: lo = mid + 1
    else: return unicodeProperties[mid]
  result = (0, 0, 1, 0, 0, 0, 0)

proc decode*(s: string): seq[DecodedRune] =
  ## Each invalid byte is interpreted as U+FFFD while original bytes are retained.
  var i = 0
  while i < s.len:
    let first = i
    let b = ord(s[i])
    var code = 0xFFFD
    var count = 1
    if b < 0x80: code = b
    else:
      let n = if b in 0xC2..0xDF: 2 elif b in 0xE0..0xEF: 3
              elif b in 0xF0..0xF4: 4 else: 0
      if n > 0 and i + n <= s.len:
        var valid = true
        var value = b and (0x7F shr n)
        for j in 1..<n:
          let continuation = ord(s[i+j])
          if continuation notin 0x80..0xBF: valid = false
          value = (value shl 6) or (continuation and 0x3F)
        if valid and value <= 0x10FFFF and value notin 0xD800..0xDFFF and
            ((n == 2 and value >= 0x80) or (n == 3 and value >= 0x800) or
             (n == 4 and value >= 0x10000)):
          code = value
          count = n
    i += count
    result.add DecodedRune(code: code, first: first, last: i,
      property: properties(code))
