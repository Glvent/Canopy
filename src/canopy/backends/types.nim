## Backend-wide terminal operation types.
import ../geometry
export geometry

type
  ClearType* {.pure.}=enum All,AfterCursor,BeforeCursor,CurrentLine,UntilNewLine
  WindowSize* = object
    columnsRows*:Size
    pixels*:Size
