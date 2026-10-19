# Native color conversions

`canopy/core/styling/colors` exposes `colorFromU32(uint32)`, `colorFromHsl(hue,saturation,lightness)`
and `colorFromHsluv(hue,saturation,lightness)`. They return ordinary `Color`
values; no Rust runtime, FFI or external native library is used.

The palette-enabled reference pins `ratatui-core` 0.1.2 and `palette` 0.7.7 in
`colors_reference/Cargo.lock`. Algorithm ports follow palette's `rgb/rgb.rs`,
`angle.rs`, `lchuv.rs`, `luv_bounds.rs`, `luv.rs`, `xyz.rs`, `encoding/srgb.rs`
and `stimulus.rs`. Palette is dual MIT/Apache-2.0; this port uses its MIT
permission and retains the notice in `licenses/palette.txt`. Ratatui attribution
is in `licenses/ratatui.txt`.

Hue inputs are degrees. HSL saturation/lightness clamp to 0..1; HSLuv clamps
to 0..100. Inputs and ordinary color calculations use float32, matching the
default Rust palette types. The HSLuv gamut-bound calculation uses float64
internally, exactly where palette does. HSL normalizes hue; HSLuv preserves
the raw angle for trigonometry. Byte conversion rounds ties to even. NaN and
infinity follow palette's channel-specific arithmetic and clamping behavior,
rather than throwing an argument error or silently substituting black.

Regenerate development fixtures:

```sh
python3 tools/colors_generate.py
nim c -r --mm:arc --path:src tests/test_colors.nim
nim c -r --mm:orc --path:src tests/test_colors.nim
```

The native test reads checked-in `tools/colors_fixtures.json`, so consumer
tests need no Rust toolchain. It checks 31,347 exact RGB outputs: 24,000 seeded
cases, 6,072 boundary combinations (including non-finite components), and
1,275 cases around all 255 grayscale byte rounding transitions. Packed RGB
cases verify high-byte discard. Input float bit patterns preserve NaNs and
precise f32 neighbors in JSON. The suite prints the actual memory manager.

These finite checks do not prove equality for every possible floating-point
input or every platform math library; they cover the upstream arithmetic,
representative gamut boundaries and final byte rounding directly.
