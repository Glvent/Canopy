# Shared interfaces (integrated)

All runtime modules live under `src/canopy/`; `src/canopy.nim` re-exports rendering modules, never input. Imports may use `canopy/[geometry, style, text, buffer, unicode]`. Public objects use value semantics. Coordinates/lengths use `int`, constrained to nonnegative u16 range at geometry boundaries. Nim 2.2.0+, no runtime Rust/C dependency beyond standard OS APIs.

## Geometry (lead)
`Rect = object x,y,width,height: int`; `Position = object x,y: int`; `Size = object width,height: int`; `Margin = object horizontal,vertical: int`.
`initRect(x,y,width,height)`, `initPosition(x,y)`, `initSize(width,height)`, `initMargin(horizontal,vertical)`; `right`, `bottom`, `area`, `isEmpty`, `contains`, `intersection`, `union`, `inner(rect,margin)`.
Pure enums `Direction.Horizontal/Vertical`, `Alignment.Left/Center/Right`, `VerticalAlignment.Top/Center/Bottom`.

## Unicode (Unicode worker)
`proc graphemes*(s: string): seq[string]` (extended grapheme clusters); `proc displayWidth*(s: string): int` (unicode-width non-CJK behavior); `proc graphemeWidth*(s: string): int`; `proc truncateWidth*(s: string, maxWidth: int): string`. Invalid UTF-8 must never crash or loop; document handling. Expose pinned Unicode/dependency version constants. Generation allowed in development; checked-in tables required.

## Style (lead)
Pure `ColorKind` enum: Reset, Black, Red, Green, Yellow, Blue, Magenta, Cyan, Gray, DarkGray, LightRed, LightGreen, LightYellow, LightBlue, LightMagenta, LightCyan, White, Indexed, Rgb.
`Color` object: `kind: ColorKind`, `index,r,g,b: uint8`; `color(kind)`, `indexedColor(n)`, `rgbColor(r,g,b)`.
Pure `Modifier` enum: Bold, Dim, Italic, Underlined, SlowBlink, RapidBlink, Reversed, Hidden, CrossedOut; `Modifiers = set[Modifier]`.
`Style` object: `fg,bg,underlineColor: Option[Color]`; `addModifiers,subModifiers: Modifiers`.
`initStyle()`, `resetStyle()`, `patch(base,overlay)`, `withFg`, `withBg`, `withUnderlineColor`, `withAddModifier`, `withRemoveModifier`. `std/options` re-exported by style.

## Text (lead)
`Span` object `content: string, style: Style`; `Line` object `spans: seq[Span], style: Style, alignment: Option[Alignment]`; `Text` object `lines: seq[Line], style: Style, alignment: Option[Alignment]`.
`initSpan(string, style=initStyle())`, `initLine(string)` / `initLine(openArray[Span])`, `initText(string)` / `initText(openArray[Line])`; `width`, `height(Text)`, `withStyle`, `withAlignment`; no implicit string converters.

## Buffer (lead)
`Cell` has a string `symbol` getter/setter, `symbolSet: bool`, `fg,bg,underlineColor: Color`, `modifiers: Modifiers`, legacy `skip: bool`, `diffKind: CellDiffKind`, and `forcedWidth: int`. `CellDiffKind` is `Normal/Skip/AlwaysUpdate/ForcedWidth`. Unset symbols display as a space while retaining the provenance required by border merging; equality compares visible cell values.
`Buffer` object `area: Rect, content: seq[Cell]`; `CellUpdate = tuple[x,y:int,cell:Cell]`.
`initCell()` is unset; `initCell(string)` is explicit. `initBuffer(Rect,cell=initCell())`; mutable/read `buffer[x,y]` or `buffer[position]`; `setStyle(cell,Style)`, `reset(cell)`, `setSymbol(cell,string)`, `setDiffOption`, `mergeSymbol`; `setString(buffer,x,y,string,Style=initStyle()): Position` and `setStringn(...,maxWidth:int,Style=initStyle()): Position` discardable; `setLine(...,Line,maxWidth): Position`; `setStyle(buffer,Rect,Style)`; `reset`, `resize`, `merge`, `diff(previous,next): seq[CellUpdate]`. Buffer writes clip to area. `setStringn` resets wide continuations. Widgets may assign cells directly but must clip render area using intersection.

## Layout (layout worker)
Pure `ConstraintKind.Length/Min/Max/Percentage/Ratio/Fill`; `Constraint` object `kind`, `value,numerator,denominator:int`. Constructors `length`, `minLength`, `maxLength`, `percentage`, `ratio`, `fill` (default weight 1).
Pure `Flex.Legacy/Start/End/Center/SpaceBetween/SpaceAround/SpaceEvenly`.
`Layout` object `direction: Direction, constraints: seq[Constraint], margin: Margin, spacing: int, flex: Flex`.
`initLayout(direction=Direction.Vertical, constraints: openArray[Constraint]=[])`, `withDirection`, `withConstraints`, `withMargin`, `withSpacing` (negative = overlap), `withFlex`; `split(Layout,Rect): seq[Rect]`; `splitWithSpacers(...): tuple[segments,spacers:seq[Rect]]`; cache sizing/clearing public helpers. Follow pinned reference semantics; do not replace solver with a heuristic.

## Widgets (subsequent assignments)
Every widget implements `proc render*(widget: T, area: Rect, buffer: var Buffer)`; stateful overload adds final `state: var State`. Public constructors `initBlock`, `initParagraph`, etc. Chainable `withX` takes/returns a value; rendering preserves value configuration. Stateful selection uses `Option[int]` and clamps according to reference. Shared Block implementation will be established before widget delegation.

## Backend and terminal (subsequent assignments)
Backend generic contract: `draw(var B, openArray[CellUpdate])`, `flush(var B)`, `size(var B): Size`, `getCursorPosition(var B): Position`, `setCursorPosition(var B, Position)`, `hideCursor`, `showCursor`, `clear`, `scrollRegionUp/Down(var B, top,bottom,lines:int)` (bottom exclusive), `appendLines(var B,int)`. Raise on errors. `init`/`restore` manage modes explicitly. Terminal commits previous buffer only after all draw/flush/cursor operations succeed. Backends must not import widgets/terminal.

`canopy/backends/types` exports `ClearType.All/AfterCursor/BeforeCursor/CurrentLine/UntilNewLine` and `WindowSize(columnsRows:Size,pixels:Size)`. Built-in backends additionally implement `clearRegion(var B,ClearType)`, `clearRegion(var B,Rect)`, and `windowSize(var B): WindowSize`. Terminal uses those capabilities when available, with drawing/cell-size fallbacks for custom backends. The custom-backend example demonstrates the required contract.

`initTerminal(backend,options=TerminalOptions())` initializes the backend. `TerminalOptions.viewport` uses `fullscreenViewport()`, `fixedViewport(Rect)`, or `inlineViewport(height)`. `withTerminal(name,backend[,options])` scopes restoration in `finally`. `Terminal[B]` exposes `backend`, `viewportArea` and `frameCount`; `draw` takes `proc(frame:var Frame)` and returns an owning `CompletedFrame`.

`Frame` exposes `area`, `count`, and `buffer:ptr Buffer`, plus generic widget renderers and `setCursorPosition`. Keep a frame within its borrow scope. `CompletedFrame.buffer` is the rendered viewport; `CompletedFrame.area` is the last terminal area (the fixed area for a fixed viewport). Count starts at zero and wraps as uint64.

`draw` resets/autoresizes before rendering; `applyBuffer`/`applyBufferWithCursor` present the existing current buffer. Both commit only after successful output. `getFrame`, `currentBufferMut`, `flush`, and `swapBuffers` support manual presentation: terminal `flush` emits differences only, backend `flush` flushes output, and `swapBuffers` commits without counting a frame. Cursor access, `size`, `windowSize`, `resize`, `autoresize`, `clear`, `invalidate`, and inline `insertBefore(height,proc(buffer:var Buffer))` are public. Initial blank buffers emit only actual differences, matching upstream; `invalidate` requests an explicit repaint.

## Optional input
`canopy/input` exports `Input`, `InputParser`, `Event`, keyboard/mouse enums, and `InputCapabilities`. `initInput`, `init`/`restore` and `withInput` manage native modes and event reporting. `read` blocks; `poll(timeoutMs)` returns `Option[Event]` (zero nonblocking, negative blocking). `feed`, `nextEvent` and `drain` expose the incremental parser. Unsupported sequences retain their raw bytes. See [input](input.md) for event and capability semantics.

## Reference schema (reference worker)
Checked-in JSON fixtures: versioned root with pinned dependencies and cases. Each case has `name`, `kind`, `input`, and `expected`. Rendering expected includes `area`, row-major complete cells (`symbol`, named/tagged colors, modifiers, `skip`), `cursor` nullable, and `state` when applicable. Layout expected includes segments and spacers. Unicode expected includes graphemes and width. Define exact serialization in `docs/reference.md`; reference adapter tests translate JSON explicitly, independent of runtime JSON format.
