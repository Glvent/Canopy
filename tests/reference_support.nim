import std/[json,options,strutils,unittest]
import canopy/[geometry,style,buffer]
proc referenceRect*(n: JsonNode): Rect = initRect(n["x"].getInt,n["y"].getInt,n["width"].getInt,n["height"].getInt)
proc referenceColor*(n: JsonNode): Color =
  case n["kind"].getStr
  of "named": color(parseEnum[ColorKind](capitalizeAscii(n["name"].getStr)))
  of "indexed": indexedColor(n["index"].getInt)
  of "rgb": rgbColor(n["r"].getInt,n["g"].getInt,n["b"].getInt)
  else: raise newException(ValueError,"Invalid reference color")
proc referenceModifiers*(n: JsonNode): Modifiers =
  for m in n: result.incl(parseEnum[Modifier](capitalizeAscii(m.getStr)))
proc referenceStyle*(n: JsonNode): Style =
  if n.hasKey("fg") and n["fg"].kind != JNull: result.fg = some(referenceColor(n["fg"]))
  if n.hasKey("bg") and n["bg"].kind != JNull: result.bg = some(referenceColor(n["bg"]))
  if n.hasKey("underlineColor") and n["underlineColor"].kind != JNull: result.underlineColor = some(referenceColor(n["underlineColor"]))
  if n.hasKey("addModifiers"): result.addModifiers = referenceModifiers(n["addModifiers"])
  if n.hasKey("subModifiers"): result.subModifiers = referenceModifiers(n["subModifiers"])
proc referenceCell*(n: JsonNode): Cell =
  result = initCell(n["symbol"].getStr)
  result.fg = referenceColor(n["fg"])
  result.bg = referenceColor(n["bg"])
  result.underlineColor = referenceColor(n["underlineColor"])
  result.modifiers = referenceModifiers(n["modifiers"])
  result.skip = n["skip"].getBool
  if n.hasKey("diffOption"):
    case n["diffOption"]["kind"].getStr
    of "none": discard
    of "skip": result.diffKind = CellDiffKind.Skip
    of "alwaysUpdate": result.diffKind = CellDiffKind.AlwaysUpdate
    of "forcedWidth":
      result.diffKind = CellDiffKind.ForcedWidth
      result.forcedWidth = n["diffOption"]["width"].getInt
    else: raise newException(ValueError,"Unknown diff kind")
proc checkReferenceBuffer*(actual: Buffer, expected: JsonNode, name: string) =
  checkpoint name
  check actual.area == referenceRect(expected["area"])
  check actual.content.len == expected["cells"].len
  for i,cell in actual.content:
    let reference = referenceCell(expected["cells"][i])
    if cell != reference:
      checkpoint name & " at " & $actual.posOf(i)
      check cell == reference
