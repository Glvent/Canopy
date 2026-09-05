# Development reference oracle

This crate is the only Rust code in Canopy. It pins Ratatui 0.30.2 and regenerates the checked-in compatibility fixtures used by Nim tests.

```sh
cargo run --manifest-path reference/Cargo.toml --locked -- generate
```

Do not link this crate into Canopy or invoke it from installation, runtime, or ordinary tests. See [`../docs/reference.md`](../docs/reference.md) for the schema, provenance, and differential layout oracle.
