# Canvas and Chart provenance

`src/canopy/ui/widgets/canvas.nim` and `chart.nim` port the algorithms in
Ratatui tag `ratatui-v0.30.2` (`ratatui-widgets` 0.3.2). Ratatui is MIT licensed;
the complete upstream license is retained in `licenses/ratatui.txt`.

`src/canopy/internal/widgets/canvas_tables.nim` contains the unchanged world coordinates
from `ratatui-widgets/src/canvas/world.rs`: 5,125 high-resolution points and
1,166 low-resolution points. Upstream attributes its low-resolution map to
<http://www.gnuplotting.org/plotting-the-world-revisited>. The generated file
retains the Ratatui license attribution. To regenerate from the tagged checkout:

```sh
python3 tools/chart/canvas_tables.py /path/to/ratatui-ratatui-v0.30.2
```

Line clipping ports `line-clipping` 0.3.8's Cohen–Sutherland implementation,
including its region priority and floating-point evaluation order. That crate
is available under MIT OR Apache-2.0. Complete notices are retained in
`line-clipping-MIT.txt` and `line-clipping-APACHE.txt` in this directory.

Marker lookup arrays come from Canopy's shared `core/rendering/symbols.nim`, which separately
retains its upstream attribution. No Rust code, Rust library, subprocess, or
third-party package is required by the Nim runtime. Circle coordinates use the
platform C math library's fused multiply-add, matching Rust's `f64::mul_add`.
