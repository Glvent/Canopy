import std/[unittest,json,os]
import canopy/symbols
let matrix=parseFile(currentSourcePath.parentDir / "fixtures/block_matrix.json")
include block_symbol_catalog
suite "Ratatui symbol merge exhaustive compatibility":
  test "all box drawing pairs plus unknown and multicharacter symbols":
    var index=0
    for strategy in MergeStrategy:
      for a in matrix["symbols"]:
        for b in matrix["symbols"]:
          let actual=mergeSymbol(a.getStr,b.getStr,strategy)
          let expected=matrix["merges"][index].getStr
          if actual!=expected:
            checkpoint $strategy & " " & a.getStr & " + " & b.getStr
            check actual==expected
          inc index
    check index==53067
  test "complete marker arrays and stable catalog":
    checkCatalog(matrix["catalog"])
    check Braille.len==256
    check Quadrants.len==16
    check Sextants.len==64
    check Octants.len==256
    check Braille[0]=="⠀"
    check Braille[255]=="⣿"
    check Quadrants[15]=="█"
    check Sextants[63]=="█"
    check Octants[255]=="█"
    check BorderPlain==PlainBorder
    check BarThreeLevels==ThreeLevels
