`src/canopy/internal/solver.nim` ports the add-only Cassowary tableau operations
used by layout from Kasuari 0.4.12, copyright Dylan Ede and The Ratatui Developers,
under its MIT license. The MIT and alternative Apache-2.0 texts are retained here.

`src/canopy/layout.nim` ports Ratatui 0.30.2 / ratatui-core 0.1.2 layout constraint
construction. `tools/layout_upstream_cases.json` is extracted from its upstream
layout unit tests. Ratatui's MIT notice is retained with the project's notices.

Runtime uses native Nim, without linking or executing Rust. The solver does not
expose editing/removal because layout builds a fresh system and only adds
constraints. Rows use insertion order for deterministic simplex pivot ties;
Kasuari uses hashbrown iteration. Underconstrained systems can admit multiple
equally optimal solutions, so compatibility is checked against exact upstream
cases and a separate development oracle.
