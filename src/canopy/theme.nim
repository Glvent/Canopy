## Portable theme JSON: object mapping application names to Style objects.
import std/[tables,json]
import ./style
export tables,style
type Theme* = Table[string,Style]
proc toJson*(theme:Theme): JsonNode =
  result = newJObject()
  for name,style in theme: result[name] = style.toJson
proc themeFromJson*(node:JsonNode): Theme =
  if node.kind != JObject: raise newException(ValueError,"Theme must be an object")
  for name,style in node: result[name] = styleFromJson(style)
proc loadTheme*(path:string): Theme = themeFromJson(parseFile(path))
proc saveTheme*(theme:Theme,path:string) = writeFile(path,pretty(theme.toJson)&"\n")
