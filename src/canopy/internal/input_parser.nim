## Incremental VT input decoder. Incomplete UTF-8 and escape sequences stay buffered.
import std/[options, parseutils, strutils]

type
  EventKind* {.pure.}=enum Key,Mouse,Resize,FocusGained,FocusLost,Paste,Unsupported
  KeyCode* {.pure.}=enum Character,Backspace,Enter,Left,Right,Up,Down,Home,End,PageUp,PageDown,Tab,BackTab,Delete,Insert,Escape,Function
  KeyEventKind* {.pure.}=enum Press,Repeat,Release
  KeyModifier* {.pure.}=enum Shift,Control,Alt,Super,Hyper,Meta,CapsLock,NumLock
  KeyModifiers* = set[KeyModifier]
  MouseEventKind* {.pure.}=enum Down,Up,Drag,Moved,ScrollUp,ScrollDown,ScrollLeft,ScrollRight
  MouseButton* {.pure.}=enum Left,Right,Middle,Other
  KeyEvent* = object
    code*:KeyCode
    kind*:KeyEventKind
    text*:string
    functionKey*:int
    modifiers*:KeyModifiers
  MouseEvent* = object
    kind*:MouseEventKind
    button*:Option[MouseButton]
    column*,row*:int
    modifiers*:KeyModifiers
  Event* = object
    kind*:EventKind
    key*:KeyEvent
    mouse*:MouseEvent
    width*,height*:int
    text*,raw*:string
  InputParser* = object
    pending*:string
    queued:seq[Event]
    pasteMode:bool

func keyEvent*(code:KeyCode,text="",modifiers:KeyModifiers={},kind=KeyEventKind.Press,functionKey=0):Event =
  Event(kind:EventKind.Key,key:KeyEvent(code:code,text:text,modifiers:modifiers,kind:kind,functionKey:functionKey))
func unsupportedEvent*(raw:string):Event = Event(kind:EventKind.Unsupported,raw:raw)
func resizeEvent*(width,height:int):Event = Event(kind:EventKind.Resize,width:max(0,width),height:max(0,height))
func initInputParser*():InputParser = InputParser()
func pendingBytes*(parser:InputParser):int = parser.pending.len
func hasEvents*(parser:InputParser):bool = parser.queued.len>0

proc consume(s:var string,count:int) =
  if count>=s.len:s.setLen(0)
  else:s=s[count..^1]

proc nextEvent*(parser:var InputParser):Option[Event] =
  if parser.queued.len==0:return none(Event)
  result=some(parser.queued[0]); parser.queued.delete(0)
proc drain*(parser:var InputParser):seq[Event] =
  result=parser.queued; parser.queued.setLen(0)
proc pushResize*(parser:var InputParser,width,height:int) = parser.queued.add resizeEvent(width,height)

func xtermModifiers(value:int):KeyModifiers =
  let bits=max(0,value-1)
  if (bits and 1)!=0:result.incl KeyModifier.Shift
  if (bits and 2)!=0:result.incl KeyModifier.Alt
  if (bits and 4)!=0:result.incl KeyModifier.Control
  if (bits and 8)!=0:result.incl KeyModifier.Meta
  if (bits and 16)!=0:result.incl KeyModifier.CapsLock
  if (bits and 32)!=0:result.incl KeyModifier.NumLock

func mouseModifiers(value:int):KeyModifiers =
  if (value and 4)!=0:result.incl KeyModifier.Shift
  if (value and 8)!=0:result.incl KeyModifier.Alt
  if (value and 16)!=0:result.incl KeyModifier.Control

func utf8Length(first:int):int =
  if first<0x80:1 elif first in 0xC2..0xDF:2 elif first in 0xE0..0xEF:3 elif first in 0xF0..0xF4:4 else:0

func validUtf8At(s:string,length:int):bool =
  if length<=1:return length==1
  for i in 1..<length:
    if (ord(s[i]) and 0xC0)!=0x80:return false
  let a=ord(s[0]); let b=ord(s[1])
  if a==0xE0 and b<0xA0:return false
  if a==0xED and b>=0xA0:return false
  if a==0xF0 and b<0x90:return false
  if a==0xF4 and b>=0x90:return false
  true

func parseNumber(s:string,default=0):int =
  if s.len==0:return default
  var consumed=parseInt(s,result)
  if consumed!=s.len:return default

func keyFromFinal(final:char,mods:KeyModifiers={}):Event =
  case final
  of 'A':keyEvent(KeyCode.Up,modifiers=mods)
  of 'B':keyEvent(KeyCode.Down,modifiers=mods)
  of 'C':keyEvent(KeyCode.Right,modifiers=mods)
  of 'D':keyEvent(KeyCode.Left,modifiers=mods)
  of 'H':keyEvent(KeyCode.Home,modifiers=mods)
  of 'F':keyEvent(KeyCode.End,modifiers=mods)
  of 'Z':keyEvent(KeyCode.BackTab,modifiers=mods+{KeyModifier.Shift})
  else:unsupportedEvent("")

func tildeKey(code:int,mods:KeyModifiers={}):Event =
  case code
  of 1,7:keyEvent(KeyCode.Home,modifiers=mods)
  of 2:keyEvent(KeyCode.Insert,modifiers=mods)
  of 3:keyEvent(KeyCode.Delete,modifiers=mods)
  of 4,8:keyEvent(KeyCode.End,modifiers=mods)
  of 5:keyEvent(KeyCode.PageUp,modifiers=mods)
  of 6:keyEvent(KeyCode.PageDown,modifiers=mods)
  of 11..15:keyEvent(KeyCode.Function,modifiers=mods,functionKey=code-10)
  of 17..21:keyEvent(KeyCode.Function,modifiers=mods,functionKey=code-11)
  of 23..24:keyEvent(KeyCode.Function,modifiers=mods,functionKey=code-12)
  of 25,26:keyEvent(KeyCode.Function,modifiers=mods,functionKey=code-12)
  of 28,29:keyEvent(KeyCode.Function,modifiers=mods,functionKey=code-13)
  of 31..34:keyEvent(KeyCode.Function,modifiers=mods,functionKey=code-14)
  else:unsupportedEvent("")

func codepointUtf8(code:int):string =
  if code<0 or code>0x10FFFF or code in 0xD800..0xDFFF:return "�"
  if code<0x80:return $char(code)
  if code<0x800:return $char(0xC0 or code shr 6) & $char(0x80 or code and 0x3F)
  if code<0x10000:return $char(0xE0 or code shr 12) & $char(0x80 or code shr 6 and 0x3F) & $char(0x80 or code and 0x3F)
  $char(0xF0 or code shr 18) & $char(0x80 or code shr 12 and 0x3F) & $char(0x80 or code shr 6 and 0x3F) & $char(0x80 or code and 0x3F)

func enhancedKey(code:int,mods:KeyModifiers,kind:KeyEventKind):Event =
  case code
  of 57344:keyEvent(KeyCode.Escape,modifiers=mods,kind=kind)
  of 57345:keyEvent(KeyCode.Enter,modifiers=mods,kind=kind)
  of 57346:keyEvent(KeyCode.Tab,modifiers=mods,kind=kind)
  of 57347:keyEvent(KeyCode.Backspace,modifiers=mods,kind=kind)
  of 13:keyEvent(KeyCode.Enter,modifiers=mods,kind=kind)
  of 27:keyEvent(KeyCode.Escape,modifiers=mods,kind=kind)
  of 9:keyEvent(KeyCode.Tab,modifiers=mods,kind=kind)
  of 127:keyEvent(KeyCode.Backspace,modifiers=mods,kind=kind)
  of 57348:keyEvent(KeyCode.Insert,modifiers=mods,kind=kind)
  of 57349:keyEvent(KeyCode.Delete,modifiers=mods,kind=kind)
  of 57350:keyEvent(KeyCode.Left,modifiers=mods,kind=kind)
  of 57351:keyEvent(KeyCode.Right,modifiers=mods,kind=kind)
  of 57352:keyEvent(KeyCode.Up,modifiers=mods,kind=kind)
  of 57353:keyEvent(KeyCode.Down,modifiers=mods,kind=kind)
  of 57354:keyEvent(KeyCode.PageUp,modifiers=mods,kind=kind)
  of 57355:keyEvent(KeyCode.PageDown,modifiers=mods,kind=kind)
  of 57356:keyEvent(KeyCode.Home,modifiers=mods,kind=kind)
  of 57357:keyEvent(KeyCode.End,modifiers=mods,kind=kind)
  of 57364..57387:keyEvent(KeyCode.Function,modifiers=mods,kind=kind,functionKey=code-57363)
  else:keyEvent(KeyCode.Character,codepointUtf8(code),mods,kind)

func parseMouse(body:string,release:bool):Event =
  let fields=body.split(';')
  if fields.len!=3:return unsupportedEvent("\e[<"&body&(if release:"m" else:"M"))
  let flags=parseNumber(fields[0],-1); let x=parseNumber(fields[1],0)-1; let y=parseNumber(fields[2],0)-1
  if flags<0 or x<0 or y<0:return unsupportedEvent("\e[<"&body&(if release:"m" else:"M"))
  let base=flags and 3; let mods=mouseModifiers(flags)
  var mouse=MouseEvent(column:x,row:y,modifiers:mods)
  if (flags and 64)!=0:
    case base
    of 0:mouse.kind=MouseEventKind.ScrollUp
    of 1:mouse.kind=MouseEventKind.ScrollDown
    of 2:mouse.kind=MouseEventKind.ScrollLeft
    else:mouse.kind=MouseEventKind.ScrollRight
  elif release:mouse.kind=MouseEventKind.Up
  elif (flags and 32)!=0:
    mouse.kind=if base==3:MouseEventKind.Moved else:MouseEventKind.Drag
  else:mouse.kind=MouseEventKind.Down
  if (flags and 128)!=0:mouse.button=some(MouseButton.Other)
  elif base<3:mouse.button=some([MouseButton.Left,MouseButton.Middle,MouseButton.Right][base])
  Event(kind:EventKind.Mouse,mouse:mouse)

func parseCsi(raw:string):Event =
  let final=raw[^1]; let body=raw[2..^2]
  if body=="200" and final=='~':return unsupportedEvent(raw) # handled before this function
  if body.len>0 and body[0]=='<' and final in {'M','m'}:return parseMouse(body[1..^1],final=='m')
  if final=='I' and body.len==0:return Event(kind:EventKind.FocusGained)
  if final=='O' and body.len==0:return Event(kind:EventKind.FocusLost)
  let fields=body.split(';')
  if final=='u':
    let code=parseNumber(fields[0].split(':')[0],-1)
    if code<0:return unsupportedEvent(raw)
    var mods:KeyModifiers; var kind=KeyEventKind.Press
    if fields.len>1:
      let detail=fields[1].split(':'); mods=xtermModifiers(parseNumber(detail[0],1))
      if detail.len>1:
        case parseNumber(detail[1],1)
        of 2:kind=KeyEventKind.Repeat
        of 3:kind=KeyEventKind.Release
        else:kind=KeyEventKind.Press
    return enhancedKey(code,mods,kind)
  if final=='~':
    if fields.len>=3 and fields[0]=="27":return enhancedKey(parseNumber(fields[2],-1),xtermModifiers(parseNumber(fields[1],1)),KeyEventKind.Press)
    result=tildeKey(parseNumber(fields[0],-1),if fields.len>1:xtermModifiers(parseNumber(fields[^1],1)) else:{})
  elif final in {'A','B','C','D','H','F','Z'}:
    result=keyFromFinal(final,if fields.len>1:xtermModifiers(parseNumber(fields[^1],1)) else:{})
  elif final in {'P','Q','R','S'} and fields.len>1 and fields[0]=="1":
    result=keyEvent(KeyCode.Function,modifiers=xtermModifiers(parseNumber(fields[^1],1)),functionKey=ord(final)-ord('P')+1)
  else:result=unsupportedEvent(raw)
  if result.kind==EventKind.Unsupported:result.raw=raw

proc parsePending(parser:var InputParser) =
  while parser.pending.len>0:
    if parser.pasteMode:
      let finish=parser.pending.find("\e[201~")
      if finish<0:return
      parser.queued.add Event(kind:EventKind.Paste,text:parser.pending[0..<finish])
      parser.pending.consume(finish+6); parser.pasteMode=false
      continue
    let first=ord(parser.pending[0])
    if first!=27:
      case first
      of 0:parser.queued.add keyEvent(KeyCode.Character," ",{KeyModifier.Control}); parser.pending.consume(1)
      of 1..7,11,12,14..26:
        parser.queued.add keyEvent(KeyCode.Character,$char(ord('a')+first-1),{KeyModifier.Control}); parser.pending.consume(1)
      of 8,127:parser.queued.add keyEvent(KeyCode.Backspace); parser.pending.consume(1)
      of 9:parser.queued.add keyEvent(KeyCode.Tab); parser.pending.consume(1)
      of 10,13:parser.queued.add keyEvent(KeyCode.Enter); parser.pending.consume(1)
      else:
        let length=utf8Length(first)
        if length==0:parser.queued.add keyEvent(KeyCode.Character,"�"); parser.pending.consume(1)
        elif parser.pending.len<length:return
        elif not validUtf8At(parser.pending,length):parser.queued.add keyEvent(KeyCode.Character,"�"); parser.pending.consume(1)
        else:parser.queued.add keyEvent(KeyCode.Character,parser.pending[0..<length]); parser.pending.consume(length)
      continue
    if parser.pending.len==1:return
    if parser.pending.startsWith("\e[200~"):
      parser.pending.consume(6); parser.pasteMode=true; continue
    if parser.pending.startsWith("\e[M"):
      if parser.pending.len<6:return
      let flags=ord(parser.pending[3])-32; let x=ord(parser.pending[4])-33; let y=ord(parser.pending[5])-33
      if flags<0 or x<0 or y<0:parser.queued.add unsupportedEvent(parser.pending[0..<6])
      else:
        var mouse=MouseEvent(column:x,row:y,modifiers:mouseModifiers(flags)); let base=flags and 3
        if (flags and 64)!=0:mouse.kind=if base==0:MouseEventKind.ScrollUp else:MouseEventKind.ScrollDown
        elif base==3:mouse.kind=MouseEventKind.Up
        elif (flags and 32)!=0:mouse.kind=MouseEventKind.Drag; mouse.button=some([MouseButton.Left,MouseButton.Middle,MouseButton.Right][base])
        else:mouse.kind=MouseEventKind.Down; mouse.button=some([MouseButton.Left,MouseButton.Middle,MouseButton.Right][base])
        parser.queued.add Event(kind:EventKind.Mouse,mouse:mouse)
      parser.pending.consume(6); continue
    if parser.pending[1]=='[':
      var finish = -1
      for i in 2..<parser.pending.len:
        if ord(parser.pending[i]) in 0x40..0x7E:finish=i;break
      if finish<0:return
      let raw=parser.pending[0..finish]; parser.pending.consume(finish+1); parser.queued.add parseCsi(raw); continue
    if parser.pending[1]=='O':
      if parser.pending.len<3:return
      let final=parser.pending[2]
      var event:Event
      case final
      of 'P':event=keyEvent(KeyCode.Function,functionKey=1)
      of 'Q':event=keyEvent(KeyCode.Function,functionKey=2)
      of 'R':event=keyEvent(KeyCode.Function,functionKey=3)
      of 'S':event=keyEvent(KeyCode.Function,functionKey=4)
      else:event=keyFromFinal(final)
      parser.queued.add(if event.kind==EventKind.Unsupported:unsupportedEvent(parser.pending[0..<3]) else:event); parser.pending.consume(3);continue
    let length=utf8Length(ord(parser.pending[1]))
    if length==0:parser.queued.add keyEvent(KeyCode.Escape);parser.pending.consume(1);continue
    if parser.pending.len<1+length:return
    if validUtf8At(parser.pending[1..^1],length):
      parser.queued.add keyEvent(KeyCode.Character,parser.pending[1..length],{KeyModifier.Alt});parser.pending.consume(length+1)
    else:parser.queued.add keyEvent(KeyCode.Escape);parser.pending.consume(1)

proc feed*(parser:var InputParser,data:string) = parser.pending.add(data);parser.parsePending()
proc feed*(parser:var InputParser,data:openArray[byte]) =
  var text=newString(data.len);for i,b in data:text[i]=char(b)
  parser.feed(text)

proc finishEscape*(parser:var InputParser) =
  if parser.pending=="\e":parser.pending.setLen(0);parser.queued.add keyEvent(KeyCode.Escape)

proc finish*(parser:var InputParser) =
  ## Resolve buffered bytes when their source has reached EOF.
  if parser.pasteMode:
    parser.queued.add unsupportedEvent("\e[200~" & parser.pending)
    parser.pending.setLen(0);parser.pasteMode=false
  elif parser.pending=="\e":parser.finishEscape()
  elif parser.pending.len>0:
    if parser.pending[0]=='\e':parser.queued.add unsupportedEvent(parser.pending)
    else:parser.queued.add keyEvent(KeyCode.Character,"�")
    parser.pending.setLen(0)
