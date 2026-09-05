## Backend-wide terminal operation types.
import ../../core/layout/geometry
export geometry

type
  ClearType* {.pure.} = enum All, AfterCursor, BeforeCursor, CurrentLine, UntilNewLine
  ## Values map to DEC erase sequences used by viewport clearing fallbacks.
  WindowSize* = object
    columnsRows*: Size
    pixels*: Size
