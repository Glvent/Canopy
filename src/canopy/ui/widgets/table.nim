## Stateful tables with row/column/cell highlighting and native constraint layout.
import std/options

import ../../core/layout/geometry
import ../../core/styling/style
import ../../core/text/index as text
import ../../core/rendering/buffer
import ../../core/layout/index as layout
import "./block"
import ./state
export state, layout

type
  TableCell* = object
    ## A `columnSpan` of 0 skips the cell entirely; spans wider than the remaining columns are
    ## truncated at the last one.
    content*: Text
    style*: Style
    columnSpan*: int
  Row* = object
    cells*: seq[TableCell]
    height*, topMargin*, bottomMargin*: int
    style*: Style
  TableState* = object
    ## Row and column selection are independent; a selected cell is the pair being set.
    ## `offset` is the first visible row and is corrected during render.
    offset*: int
    selected*, selectedColumn*: Option[int]
  Table* = object
    rows*: seq[Row]
    header*, footer*: Option[Row]
    widths*: seq[Constraint]
    columnSpacing*: int
    blockWidget*: Option[Block]
    style*, rowHighlightStyle*, columnHighlightStyle*, cellHighlightStyle*: Style
    highlightSymbol*: Text
    highlightSpacing*: HighlightSpacing
    flex*: Flex

func initTableCell*(content: Text): TableCell = TableCell(content: content, columnSpan: 1)
func initTableCell*(content: string): TableCell = initTableCell(initText(content))
func initTableCell*(content: Line): TableCell = initTableCell(initText([content]))
func initTableCell*(content: Span): TableCell = initTableCell(initLine([content]))
func withContent*(cell: TableCell, content: Text): TableCell =
  result = cell; result.content = content

func withContent*(cell: TableCell, content: string): TableCell = cell.withContent(initText(content))
func withColumnSpan*(cell: TableCell, span: int): TableCell =
  result = cell; result.columnSpan = clamp(span, 0, MaxCoordinate)

func withStyle*(cell: TableCell, style: Style): TableCell =
  result = cell; result.style = style

func initRow*(cells: openArray[TableCell]): Row = Row(cells: @cells, height: 1)
func initRow*(cells: openArray[string]): Row =
  result.height = 1
  for cell in cells: result.cells.add initTableCell(cell)

func withCells*(row: Row, cells: openArray[TableCell]): Row =
  result = row; result.cells = @cells

func withHeight*(row: Row, height: int): Row =
  result = row; result.height = clamp(height, 0, MaxCoordinate)

func withTopMargin*(row: Row, margin: int): Row =
  result = row; result.topMargin = clamp(margin, 0, MaxCoordinate)

func withBottomMargin*(row: Row, margin: int): Row =
  result = row; result.bottomMargin = clamp(margin, 0, MaxCoordinate)

func withStyle*(row: Row, style: Style): Row =
  result = row; result.style = style

func heightWithMargin*(row: Row): int = min(MaxCoordinate,
    row.height+row.topMargin+row.bottomMargin)

func initTableState*(): TableState = TableState()
func withOffset*(s: TableState, offset: int): TableState =
  result = s; result.offset = max(0, offset)

func withSelected*(s: TableState, selected: Option[int]): TableState =
  result = s; result.selected = selected

func withSelected*(s: TableState, selected: int): TableState = s.withSelected(some(max(0, selected)))
func withSelectedColumn*(s: TableState, column: Option[int]): TableState =
  result = s; result.selectedColumn = column

func withSelectedColumn*(s: TableState, column: int): TableState = s.withSelectedColumn(some(max(0, column)))
func withSelectedCell*(s: TableState, cell: Option[tuple[row, column: int]]): TableState =
  result = s
  if cell.isSome:
    result.selected = some(cell.get.row)
    result.selectedColumn = some(cell.get.column)
  else:
    result.selected = none(int)
    result.selectedColumn = none(int)

func withSelectedCell*(s: TableState, cell: tuple[row,
    column: int]): TableState = s.withSelectedCell(some(cell))

func selectedCell*(s: TableState): Option[tuple[row, column: int]] =
  if s.selected.isSome and s.selectedColumn.isSome: some((s.selected.get, s.selectedColumn.get))
  else: none(tuple[row, column: int])

proc select*(s: var TableState, row: Option[int]) =
  s.selected = row
  if row.isNone: s.offset = 0

proc select*(s: var TableState, row: int) = s.select(some(max(0, row)))
proc selectColumn*(s: var TableState, column: Option[int]) = s.selectedColumn = column
proc selectColumn*(s: var TableState, column: int) = s.selectColumn(some(max(0, column)))
proc selectCell*(s: var TableState, cell: Option[tuple[row, column: int]]) =
  s = s.withSelectedCell(cell)
  if cell.isNone: s.offset = 0

proc selectCell*(s: var TableState, cell: tuple[row, column: int]) = s.selectCell(some(cell))
proc selectNext*(s: var TableState) = s.select(if s.selected.isSome: min(s.selected.get,
    int.high-1)+1 else: 0)
proc selectPrevious*(s: var TableState) = s.select(if s.selected.isSome: max(0,
    s.selected.get-1) else: int.high)
proc selectNextColumn*(s: var TableState) = s.selectColumn(if s.selectedColumn.isSome: min(
    s.selectedColumn.get, int.high-1)+1 else: 0)
proc selectPreviousColumn*(s: var TableState) = s.selectColumn(if s.selectedColumn.isSome: max(0,
    s.selectedColumn.get-1) else: int.high)
proc selectFirst*(s: var TableState) = s.select(0)
proc selectLast*(s: var TableState) = s.select(int.high)
proc selectFirstColumn*(s: var TableState) = s.selectColumn(0)
proc selectLastColumn*(s: var TableState) = s.selectColumn(int.high)
proc scrollDownBy*(s: var TableState, amount: int) = s.select(min(s.selected.get(0), int.high-max(0,
    amount))+max(0, amount))
proc scrollUpBy*(s: var TableState, amount: int) = s.select(max(0, s.selected.get(0)-max(0, amount)))
proc scrollRightBy*(s: var TableState, amount: int) = s.selectColumn(min(s.selectedColumn.get(0),
    int.high-max(0, amount))+max(0, amount))
proc scrollLeftBy*(s: var TableState, amount: int) = s.selectColumn(max(0, s.selectedColumn.get(
    0)-max(0, amount)))

# Percentages are validated at construction so the error names the table rather than surfacing as
# a surprising layout result.
func checkedWidths(widths: openArray[Constraint]): seq[Constraint] =
  for c in widths:
    if c.kind == ConstraintKind.Percentage and c.value > 100:
      raise newException(ValueError, "Percentages should be between 0 and 100 inclusively.")
  @widths

func initTable*(rows: openArray[Row], widths: openArray[Constraint] = []): Table =
  Table(rows: @rows, widths: checkedWidths(widths), columnSpacing: 1, flex: Flex.Start)

func withRows*(table: Table, rows: openArray[Row]): Table =
  result = table; result.rows = @rows

func withHeader*(table: Table, header: Row): Table =
  result = table; result.header = some(header)

func withFooter*(table: Table, footer: Row): Table =
  result = table; result.footer = some(footer)

func withWidths*(table: Table, widths: openArray[Constraint]): Table =
  result = table; result.widths = checkedWidths(widths)

func withColumnSpacing*(table: Table, spacing: int): Table =
  result = table; result.columnSpacing = clamp(spacing, 0, MaxCoordinate)

func withBlock*(table: Table, b: Block): Table =
  result = table; result.blockWidget = some(b)

func withStyle*(table: Table, style: Style): Table =
  result = table; result.style = style

func withRowHighlightStyle*(table: Table, style: Style): Table =
  result = table; result.rowHighlightStyle = style

func withHighlightStyle*(table: Table, style: Style): Table = table.withRowHighlightStyle(style)
func withColumnHighlightStyle*(table: Table, style: Style): Table =
  result = table; result.columnHighlightStyle = style

func withCellHighlightStyle*(table: Table, style: Style): Table =
  result = table; result.cellHighlightStyle = style

func withHighlightSymbol*(table: Table, symbol: Text): Table =
  result = table; result.highlightSymbol = symbol

func withHighlightSymbol*(table: Table, symbol: string): Table = table.withHighlightSymbol(initText(symbol))
func withHighlightSpacing*(table: Table, spacing: HighlightSpacing): Table =
  result = table; result.highlightSpacing = spacing

func withFlex*(table: Table, flex: Flex): Table =
  result = table; result.flex = flex

proc render*(cell: TableCell, area: Rect, buf: var Buffer) =
  buf.setStyle(area, cell.style)
  cell.content.render(area, buf)

func columnCount(table: Table): int =
  for row in table.rows: result = max(result, row.cells.len)
  if table.header.isSome: result = max(result, table.header.get.cells.len)
  if table.footer.isSome: result = max(result, table.footer.get.cells.len)

# Row window for the given height, grown and then scrolled until the selected row fits.

proc visibleRows(table: Table, state: TableState, area: Rect): tuple[first, last: int] =
  result.first = clamp(state.offset, 0, table.rows.high)
  if state.selected.isSome: result.first = min(result.first, state.selected.get)
  result.last = result.first
  var height = 0
  for i in result.first..<table.rows.len:
    if height+table.rows[i].height > area.height: break
    height += table.rows[i].heightWithMargin
    inc result.last
  if state.selected.isSome:
    let selected = min(state.selected.get, table.rows.high)
    while selected >= result.last:
      height += table.rows[result.last].heightWithMargin
      inc result.last
      while height > area.height:
        height = max(0, height-table.rows[result.first].heightWithMargin)
        inc result.first
  if height < area.height and result.last < table.rows.len: inc result.last

proc renderFixed(row: Option[Row], area: Rect, columns: seq[Rect], buf: var Buffer) =
  if row.isNone: return
  buf.setStyle(area, row.get.style)
  for i in 0..<min(columns.len, row.get.cells.len):
    row.get.cells[i].render(initRect(area.x+columns[i].x, area.y, columns[i].width, area.height), buf)

proc render*(table: Table, area: Rect, buf: var Buffer, state: var TableState) =
  let area = area.intersection(buf.area)
  buf.setStyle(area, table.style)
  table.blockWidget.render(area, buf)
  let inner = table.blockWidget.inner(area)
  if inner.isEmpty: return
  if state.selected.isSome: state.select(clamp(state.selected.get, 0, max(0, table.rows.high)))
  if table.rows.len == 0: state.select(none(int))
  let count = table.columnCount
  if state.selectedColumn.isSome: state.selectColumn(clamp(state.selectedColumn.get, 0, max(0, count-1)))
  if count == 0: state.selectColumn(none(int))
  let selectionWidth = if table.highlightSpacing.shouldAdd(state.selected.isSome): min(
      MaxCoordinate, table.highlightSymbol.width) else: 0
  var widths = table.widths
  if widths.len == 0:
    for i in 0..<count: widths.add length(inner.width div max(1, count))
  # Column positions are solved in a zero-based strip so they can be reused for the header,
  # footer, and every row; the selection symbol takes its width off the left first.
  let columnsArea = initLayout(Direction.Horizontal, [length(selectionWidth), fill(0)]).split(
      initRect(0, 0, inner.width, 1))[1]
  let columns = initLayout(Direction.Horizontal, widths).withFlex(table.flex).withSpacing(
      table.columnSpacing).split(columnsArea)
  let header = table.header.get(Row())
  let footer = table.footer.get(Row())
  # Header and footer keep fixed heights; the rows take whatever is left.
  let areas = initLayout(Direction.Vertical, [length(header.topMargin), length(header.height),
      length(header.bottomMargin),
    minLength(0), length(footer.topMargin), length(footer.height), length(
        footer.bottomMargin)]).split(inner)
  renderFixed(table.header, areas[1], columns, buf)
  let rowsArea = areas[3]
  if table.rows.len > 0:
    let bounds = table.visibleRows(state, rowsArea)
    state.offset = bounds.first
    var yOffset = 0
    var selectedRow = none(Rect)
    for i in bounds.first..<bounds.last:
      let row = table.rows[i]
      let y = rowsArea.y+yOffset+row.topMargin
      let height = max(0, min(y+row.height, rowsArea.bottom)-y)
      let rowArea = initRect(rowsArea.x, y, rowsArea.width, height)
      buf.setStyle(rowArea, row.style)
      let selected = state.selected == some(i)
      if selected and selectionWidth > 0:
        let selection = initRect(rowArea.x, rowArea.y, selectionWidth, rowArea.height)
        buf.setStyle(selection, row.style)
        table.highlightSymbol.render(selection, buf)
      var column = 0
      for cell in row.cells:
        if cell.columnSpan == 0 or column >= columns.len: continue
        let first = column
        let last = min(columns.len, column+cell.columnSpan)
        var width = 0
        while column < last:
          width += columns[column].width
          inc column
        # A spanning cell also covers the spacing between the columns it merges.
        width += (last-first-1)*table.columnSpacing
        cell.render(initRect(rowArea.x+columns[first].x, rowArea.y, width, rowArea.height), buf)
      if selected: selectedRow = some(rowArea)
      yOffset += row.heightWithMargin
    if selectedRow.isSome: buf.setStyle(selectedRow.get, table.rowHighlightStyle)
    if state.selectedColumn.isSome and state.selectedColumn.get < columns.len:
      let col = columns[state.selectedColumn.get]
      let colArea = initRect(rowsArea.x+col.x, rowsArea.y, col.width, rowsArea.height)
      buf.setStyle(colArea, table.columnHighlightStyle)
      if selectedRow.isSome: buf.setStyle(selectedRow.get.intersection(colArea),
          table.cellHighlightStyle)
  renderFixed(table.footer, areas[5], columns, buf)

proc render*(table: Table, area: Rect, buf: var Buffer) =
  var state = initTableState()
  table.render(area, buf, state)
