## Add-only Cassowary tableau, ported from Kasuari 0.4.12 (MIT).
## This is the solver subset used by Ratatui layout: required/weighted
## equalities and inequalities, artificial feasibility, and simplex pivots.
import std/tables

type
  Relation* {.pure.} = enum Equal, LessOrEqual, GreaterOrEqual
  Term* = tuple[variable: int, coefficient: float64]
  Expression* = object
    terms*: seq[Term]
    constant*: float64
  # Symbol 0 is Invalid and doubles as the "no symbol" result of the search helpers below.
  SymbolKind = enum Invalid, External, Slack, Error, Dummy
  Row = object
    ## Tableau row: a constant plus weighted symbols, kept solved for one basic variable.
    cells: OrderedTable[int, float64]
    constant: float64
  Solver* = object
    symbols: seq[SymbolKind]
    variables: Table[int, int]
    rows: OrderedTable[int, Row]
    objective: Row
    artificial: Row
    hasArtificial: bool
  SolverError* = object of CatchableError

const Required* = 1_001_001_000.0 ## Strength at or above which a constraint must hold exactly.

# Kasuari's epsilon; smaller coefficients are dropped so the tableau stays sparse and stable.

func nearZero(value: float64): bool = abs(value) < 1e-8
func variable*(id: int): Expression = Expression(terms: @[(id, 1.0)])
func constant*(value: float64): Expression = Expression(constant: value)
func `*`*(expression: Expression, factor: float64): Expression =
  result.constant = expression.constant * factor
  for term in expression.terms:
    result.terms.add (term.variable, term.coefficient * factor)

func `/`*(expression: Expression, divisor: float64): Expression =
  result.constant = expression.constant / divisor
  for term in expression.terms:
    result.terms.add (term.variable, term.coefficient / divisor)

func `-`*(left, right: Expression): Expression =
  result = left
  result.constant -= right.constant
  for term in right.terms: result.terms.add (term.variable, -term.coefficient)

func `-`*(left: Expression, right: float64): Expression = left - constant(right)

proc initSolver*(): Solver = Solver(symbols: @[Invalid])
proc newSymbol(solver: var Solver, kind: SymbolKind): int =
  result = solver.symbols.len
  solver.symbols.add kind

proc variableSymbol(solver: var Solver, variable: int): int =
  if variable notin solver.variables:
    solver.variables[variable] = solver.newSymbol(External)
  solver.variables[variable]

proc coefficient(row: Row, symbol: int): float64 = row.cells.getOrDefault(symbol)
proc insert(row: var Row, symbol: int, value: float64) =
  let sum = row.coefficient(symbol) + value
  if nearZero(sum): row.cells.del(symbol)
  else: row.cells[symbol] = sum

proc insert(row: var Row, other: Row, coefficient: float64) =
  row.constant += other.constant * coefficient
  for symbol, value in other.cells: row.insert(symbol, value * coefficient)

proc reverse(row: var Row) =
  row.constant = -row.constant
  for value in row.cells.mvalues: value = -value

proc solve(row: var Row, symbol: int) =
  let factor = -1.0 / row.cells[symbol]
  row.cells.del(symbol)
  row.constant *= factor
  for value in row.cells.mvalues: value *= factor

proc solve(row: var Row, left, right: int) =
  row.insert(left, -1.0)
  row.solve(right)

proc substitute(row: var Row, symbol: int, other: Row) =
  if symbol in row.cells:
    let coefficient = row.cells[symbol]
    row.cells.del(symbol)
    row.insert(other, coefficient)

proc substitute(solver: var Solver, symbol: int, row: Row) =
  for other in solver.rows.mvalues: other.substitute(symbol, row)
  solver.objective.substitute(symbol, row)
  if solver.hasArtificial: solver.artificial.substitute(symbol, row)

# Returns the first symbol that can still improve the objective, or 0 when it is optimal.

proc entering(solver: Solver, row: Row): int =
  for symbol, value in row.cells:
    if solver.symbols[symbol] != Dummy and value < 0.0: return symbol

# Simplex loop; External symbols are never chosen as leaving rows because they must stay basic.

proc optimize(solver: var Solver, artificial = false) =
  while true:
    let entry = solver.entering(if artificial: solver.artificial else: solver.objective)
    if entry == 0: return
    var ratio = Inf
    var leaving = 0
    for symbol, row in solver.rows:
      if solver.symbols[symbol] != External:
        let coefficient = row.coefficient(entry)
        if coefficient < 0.0:
          let candidate = -row.constant / coefficient
          if candidate < ratio:
            ratio = candidate
            leaving = symbol
    if leaving == 0: raise newException(SolverError, "Cassowary objective is unbounded")
    var row = solver.rows[leaving]
    solver.rows.del(leaving)
    row.solve(leaving, entry)
    solver.substitute(entry, row)
    solver.rows[entry] = row

# Phase-one feasibility: minimize an artificial variable, then drop it from the tableau.
# False means the required constraint cannot be satisfied.

proc artificial(solver: var Solver, source: Row): bool =
  let art = solver.newSymbol(Slack)
  solver.rows[art] = source
  solver.artificial = source
  solver.hasArtificial = true
  solver.optimize(true)
  result = nearZero(solver.artificial.constant)
  solver.hasArtificial = false
  if art in solver.rows:
    var row = solver.rows[art]
    solver.rows.del(art)
    if row.cells.len == 0: return
    var entry = 0
    for symbol in row.cells.keys:
      if solver.symbols[symbol] in {Slack, Error}:
        entry = symbol
        break
    if entry == 0: return false
    row.solve(art, entry)
    solver.substitute(entry, row)
    solver.rows[entry] = row
  for row in solver.rows.mvalues: row.cells.del(art)
  solver.objective.cells.del(art)

proc addConstraint*(solver: var Solver, expression: Expression,
                    relation: Relation, strength = Required) =
  ## Adds a constraint and re-optimizes; required rows use artificial variables when they are
  ## infeasible at insert time.
  var row = Row(constant: expression.constant)
  for term in expression.terms:
    if not nearZero(term.coefficient):
      let symbol = solver.variableSymbol(term.variable)
      if symbol in solver.rows: row.insert(solver.rows[symbol], term.coefficient)
      else: row.insert(symbol, term.coefficient)
  var marker, other: int
  if relation != Relation.Equal:
    let coefficient = if relation == Relation.LessOrEqual: 1.0 else: -1.0
    marker = solver.newSymbol(Slack)
    row.insert(marker, coefficient)
    if strength < Required:
      other = solver.newSymbol(Error)
      row.insert(other, -coefficient)
      solver.objective.insert(other, strength)
  elif strength < Required:
    marker = solver.newSymbol(Error)
    other = solver.newSymbol(Error)
    row.insert(marker, -1.0)
    row.insert(other, 1.0)
    solver.objective.insert(marker, strength)
    solver.objective.insert(other, strength)
  else:
    marker = solver.newSymbol(Dummy)
    row.insert(marker, 1.0)
  # The simplex invariant requires a nonnegative constant.
  if row.constant < 0.0: row.reverse()
  var subject = 0
  for symbol in row.cells.keys:
    if solver.symbols[symbol] == External:
      subject = symbol
      break
  if subject == 0:
    if solver.symbols[marker] in {Slack, Error} and row.coefficient(marker) < 0.0:
      subject = marker
    elif solver.symbols[other] in {Slack, Error} and row.coefficient(other) < 0.0:
      subject = other
  if subject == 0:
    var allDummies = true
    for symbol in row.cells.keys:
      if solver.symbols[symbol] != Dummy: allDummies = false
    if allDummies:
      if not nearZero(row.constant):
        raise newException(SolverError, "Unsatisfiable required constraint")
      subject = marker
  if subject == 0:
    # No external variable to pivot on; try artificial feasibility before rejecting.
    if not solver.artificial(row):
      raise newException(SolverError, "Unsatisfiable required constraint")
  else:
    row.solve(subject)
    solver.substitute(subject, row)
    solver.rows[subject] = row
  solver.optimize()

proc value*(solver: Solver, variable: int): float64 =
  let symbol = solver.variables.getOrDefault(variable)
  if symbol in solver.rows: solver.rows[symbol].constant else: 0.0
