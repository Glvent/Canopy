# Development reference oracle

This crate pins Ratatui 0.30.2 and regenerates the checked-in compatibility fixtures used by Nim tests. Its `canopy-chart-reference` binary produces the Canvas and Chart fixtures (see [`../chart/README.md`](../chart/README.md)).

```sh
cargo run --manifest-path tools/reference/Cargo.toml --locked -- generate
```

Do not link this crate into Canopy or invoke it from installation, runtime, or ordinary tests. See [`docs/reference.md`](../../docs/reference.md) for the schema, provenance, and differential layout oracle.
