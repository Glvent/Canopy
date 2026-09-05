## Shared selection-spacing policy for List and Table.
type HighlightSpacing* {.pure.} = enum WhenSelected, Always, Never

func shouldAdd*(spacing: HighlightSpacing, selected: bool): bool =
  spacing == HighlightSpacing.Always or (spacing == HighlightSpacing.WhenSelected and selected)
