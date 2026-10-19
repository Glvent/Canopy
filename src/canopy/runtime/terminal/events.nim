## Terminal input events decoded by `canopy/runtime/terminal/parser`.
import std/options

type
  EventKind* {.pure.} = enum Key, Mouse, Resize, FocusGained, FocusLost, Paste, Unsupported
  KeyCode* {.pure.} = enum Character, Backspace, Enter, Left, Right, Up, Down, Home, End, PageUp, PageDown, Tab, BackTab, Delete, Insert, Escape, Function
  KeyEventKind* {.pure.} = enum Press, Repeat, Release
  KeyModifier* {.pure.} = enum Shift, Control, Alt, Super, Hyper, Meta, CapsLock, NumLock
  KeyModifiers* = set[KeyModifier]
  MouseEventKind* {.pure.} = enum Down, Up, Drag, Moved, ScrollUp, ScrollDown, ScrollLeft, ScrollRight
  MouseButton* {.pure.} = enum Left, Right, Middle, Other
  KeyEvent* = object
    code*: KeyCode
    kind*: KeyEventKind
    text*: string
    functionKey*: int
    modifiers*: KeyModifiers
  MouseEvent* = object
    kind*: MouseEventKind
    button*: Option[MouseButton]
    column*, row*: int
    modifiers*: KeyModifiers
  Event* = object
    ## Only the fields belonging to `kind` are meaningful; `raw` holds the undecoded bytes of an
    ## Unsupported sequence.
    kind*: EventKind
    key*: KeyEvent
    mouse*: MouseEvent
    width*, height*: int
    text*, raw*: string

func keyEvent*(code: KeyCode, text = "", modifiers: KeyModifiers = {}, kind = KeyEventKind.Press, functionKey = 0): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: code, text: text, modifiers: modifiers, kind: kind, functionKey: functionKey))

func unsupportedEvent*(raw: string): Event = Event(kind: EventKind.Unsupported, raw: raw)
func resizeEvent*(width, height: int): Event = Event(kind: EventKind.Resize, width: max(0, width), height: max(0, height))
