# Canvas and Chart compatibility

The native implementation targets Ratatui 0.30.2, `ratatui-core` 0.1.2 and
`ratatui-widgets` 0.3.2. The independent development oracle has a checked-in
Cargo.lock at `tools/reference/Cargo.lock`. Fixture metadata records its
SHA-256 and random seed 302.

## Public contracts

Import `canopy/ui/widgets/canvas` for `Canvas`, `CanvasContext`, `Painter`,
`CanvasLine`, `FilledLine`, `Points`, `Rectangle`, `Circle`, `Map`, and
`MapResolution.Low/High`. `CanvasLine` avoids colliding with the text `Line`.
`CanvasPoint` is `(x, y: float64)` and `CanvasBounds` is `array[2, float64]`.

Constructors are `initCanvas`, `initCanvasLine`, `initFilledLine`, `initPoints`,
`initRectangle`, `initCircle`, and `initMap`. Shape fields are public. Canvas
builders are `withBlock`, `withXBounds`, `withYBounds`, `withPaint`,
`withBackgroundColor`, and `withMarker`. Render with `canvas.render(area, buf)`.
`initCanvas` defaults to Braille, Reset background, zero bounds, and no callback.

`CanvasPaint` is an owned closure `proc(context: var CanvasContext)`. Use
`context.draw(shape)`, `context.layer()`, `context.setMarker(marker)`, and
`context.print(x, y, textLineOrString)`. A custom shape implements
`draw(shape: YourShape, painter: var Painter)`; the generic context method calls
that overload. `initPainter(context)` borrows the mutable context: a painter
must not outlive it. `painter.bounds`, `getPoint`, and `paint` expose the shape
protocol. Prefer `context.draw` for custom shapes; it marks the layer dirty.
Explicit `layer()` also saves direct painter writes. Labels always render after
all layers, in insertion order. Changing the marker saves a dirty layer first.

All nine stable markers are supported: Dot, Block, Bar, Braille, HalfBlock,
Quadrant, Sextant, Octant, and Custom. Custom uses
`withMarker(Marker.Custom, "*")` or `setMarker(Marker.Custom, "*")` with exactly
one Unicode scalar, including a wide scalar. The scalar is stored separately
in `customSymbol`; Canvas/context marker setters and grid construction reject
invalid strings with `ValueError`. Dataset construction defers that check until rendering.

Import `canopy/ui/widgets/chart` for `Axis`, `Dataset`, `Chart`, `GraphType`, and
`LegendPosition`. All configuration fields are public, with value-returning
builders. Axis supports title (string or text Line), bounds, labels (strings or
Lines), style, and labels alignment. Dataset supports optional name (string or
Line), owned point data, marker/customSymbol, graph type, style, and `fillToY`.
Graph types are Scatter, Line, Bar, and Area. Bar uses the zero baseline; Area
uses `fillToY`, clipped to the Y bounds. Points render for every graph type.

Chart supports datasets, optional Block, X/Y axes, style,
`hiddenLegendConstraints: (width, height: Constraint)`, and optional legend
position. Positions are Top, TopRight, TopLeft, Left, Right, Bottom, BottomRight,
and BottomLeft. Pass `none(LegendPosition)` to suppress the legend.
`initDataset` defaults to Dot/Scatter, zero baseline, no name/data/style.
`initAxis` defaults to zero bounds, Left labels alignment, no labels/title/style.
`initChart` defaults to TopRight legend and `(ratio(1,4), ratio(1,4))` maximum
legend size. The constructors establish upstream defaults; a raw Nim object
literal instead uses Nim's zero defaults. Full styles are accepted by
`withStyle`, and `patchStyle` composes them.

Coordinates are relative to Cartesian bounds; Y increases upward. Drawing uses
rounded raster coordinates and line clipping; labels use truncated cell
coordinates. The renderer intersects its area with the buffer for safe native
buffer access. API dimensions outside the unsigned-16-bit domain clamp in
`initCanvasContext`, consistent with Canopy's geometry convention.

## Reproducible checks

```sh
python3 tools/chart/fixture_gen.py
nim c -r --mm:arc --path:src tests/widgets/test_canvas.nim
nim c -r --mm:arc --path:src tests/widgets/test_chart.nim
nim c -r --mm:orc --path:src tests/widgets/test_canvas.nim
nim c -r --mm:orc --path:src tests/widgets/test_chart.nim
```

The development-only generator builds `tools/reference/src/bin/canopy-chart-reference.rs` against locked
upstream dependencies and writes 277 Canvas and 230 Chart fixtures. Native tests
consume checked-in JSON; they do not invoke Rust. Each expected cell includes
symbol, foreground, background, underline color, all modifier bits, skip flag,
and diff option. The suites compare every cell and the full buffer area.

Canvas coverage includes all markers and shape types, all 592 bit patterns
across four patterned grids, HalfBlock color combinations, maps at both
resolutions, clipping, fractional/negative/reversed/zero bounds, layer and
marker changes, custom wide markers, labels and style precedence, nonzero
origins, and tiny/zero dimensions. Another 120 seeded cases mix shapes,
floating-point clipping, circle rasterization, fill baselines, colors, and
layers.

Chart coverage includes every marker/graph combination, every legend position
with each axis-title combination, all label alignments across seven sizes,
wide/combining/ZWJ labels, multiple label counts, every constraint kind,
optional/default/empty data, blocks, and 80 seeded cases mixing multiple
datasets, random floats, baseline fills, names, titles, labels, and small areas.

These are exact-cell regression checks, not a proof for every floating-point
input or terminal font. Like upstream, octant/sextant/custom symbols depend on
terminal glyph support. Non-finite floating-point inputs are outside the JSON
oracle corpus. Layout's separately documented upstream tie alternatives still
apply to general constraint solving; no alternative output was needed for
these Canvas or Chart fixtures.
