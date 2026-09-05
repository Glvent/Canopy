# Unicode port

Runtime is native Nim, with checked-in tables. Normal builds and tests do not
invoke Python, Rust, Cargo, or network services.

- `unicode-segmentation` **1.13.3**, Unicode **17.0.0**: extended grapheme rules
  GB3–GB999 and exact grapheme/Indic properties from `src/tables.rs`.
- `unicode-width` **0.2.2**, Unicode **17.0.0**: non-CJK reverse string-width
  state machine and exact width/emoji/ligature properties from `src/tables.rs`.
- `cellWidth` adds Ratatui's U+FF9E/U+FF9F terminal adjustments separately.

`generate.py` compiles a temporary development-only Rust program against the
pinned crate sources. It evaluates all scalar property lookups and coalesces
identical adjacent properties into 2,567 ranges, then writes native Nim tables.
The contextual algorithms remain readable Nim in `core/text/unicode.nim` and
`internal/unicode/width.nim`; those algorithms never call Rust.

`fixtures.py` runs upstream non-CJK width tests and records observed string
inputs/expected widths. Three exhaustive scalar loops are reduced to every
property range boundary and its neighbors (6,466 probes); remaining tests,
including the complete upstream emoji file, execute unchanged. Fixtures contain
36,001 distinct width cases. Grapheme fixtures contain all 766 official Unicode
17 extended grapheme cases in upstream's `TEST_SAME` and extended `TEST_DIFF`.

Regenerate from downloaded crates (defaults to the first Cargo registry source):

```sh
python3 tools/unicode/generate.py [registry-source-directory]
python3 tools/unicode/fixtures.py [registry-source-directory]
nim c -r --path:src --mm:arc tests/test_unicode.nim
nim c -r --path:src --mm:orc tests/test_unicode.nim
```

Each malformed UTF-8 byte is interpreted as U+FFFD for measurement and property
lookup. Grapheme output and truncation retain the original bytes. This policy
is Canopy-specific because Rust strings cannot contain malformed UTF-8.
Control characters use upstream *string* width (one, except CRLF is one total);
renderers decide separately whether to filter controls. `truncateWidth` checks
whole-cluster prefixes and permits contextual width reductions such as Arabic
lam-alef. Prefix checking is quadratic in input length; regular measurement and
segmentation are linear in input length with binary-search property lookup.

Source notices: `licenses/unicode/`. Unicode data license:
https://www.unicode.org/license.txt. Development source paths are pinned in
`reference/Cargo.lock`; no runtime dependency is added.
