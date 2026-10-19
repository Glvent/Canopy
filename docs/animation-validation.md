# Animation validation

Executed on 2026-09-05, macOS arm64. Animation is a Canopy extension; this
record does not change Ratatui parity or the Windows runtime acceptance gate.

## Numerical and integration checks

- All 24 native `tests/test_*.nim` files passed under Nim 2.2.0 and 2.2.10,
  with ARC and ORC. All seven examples compiled in each combination.
- After the final transition and lifecycle changes, both animation test files passed
  again in all four combinations, and both affected examples were recompiled.
- `test_animation.nim` uses supplied timestamps for easing/interpolation,
  custom types, rounding/saturation, zero/negative durations, repeat endpoints,
  delayed starts, short deadlines, long gaps, pause/resume, restart/ownership,
  ordered events, nested timelines, stagger, analytical scalar/2D springs,
  velocity-preserving retargets, settling and live reduced motion.
- `test_animation_transitions.nim` compares complete cells and buffers at
  endpoints and intermediate frames. Coverage includes four directions,
  Unicode/CJK/combining/emoji spans, conflicting glyph boundaries, tiny/clipped
  regions, nonzero origins, palettes, seeded dissolve, live destinations and
  resize completion. It also checks zero diffs for unchanged samples and
  terminal recovery after an injected failed flush, with time continuing.
- `tools/animation/pty.py` exercised gallery and dashboard keyboard/mouse
  controls, pause/restart, spring retargeting, reduced motion, continuing job
  progress, idle polling, tiny resizing, Ctrl-C and native mode/cursor/screen
  cleanup. It ran against the final Nim 2.2.10 ORC binaries on macOS. This
  optional harness requires Python; normal library tests remain Nim-only.
- `nimble docs` generated the separate animation API, and `nimble check` passed.
  An offline installation into an isolated Nimble directory passed the package
  consumer with repository/user/parent configurations disabled, including an
  animated value and rendering.

Full-run logs: `build/animation-{220,2210}-{arc,orc}.log`. Final affected-test
output: `build/animation-final-{220,2210}-{arc,orc}-tests.log`. PTY log:
`build/animation-pty-final.log`. These generated files are intentionally ignored.

Reproduce the portable matrix with the selected compiler on `PATH`:

```sh
nim r --mm:arc tools/tester.nim
nim r --mm:arc tools/tester.nim examples
nim r --mm:orc tools/tester.nim
nim r --mm:orc tools/tester.nim examples
python3 tools/animation/pty.py build/2.2.10-orc
nimble docs
nimble bench
```

## Windows boundary

Both animation tests and both affected examples generated Windows amd64 C
successfully under Nim 2.2.0/2.2.10 and ARC/ORC. This is not C linking or runtime
validation. The existing CI matrix includes the new tests and example through
the glob-based runner. No Windows host was available for execution; the existing
[Windows runtime gate](windows-validation.md) remains open. Linux animation
runtime tests were not executed in this change; prior rendering/input Linux
results in the main validation record remain historical.

## Local benchmarks

Release binaries ran sequentially on macOS arm64, Nim 2.2.10, seed 302. Each
reported value is microseconds per iteration from one local run (ARC / ORC):

- Scheduler, 1,000 active tweens, 1,000 updates: **37.769 / 39.073**.
- Fade, 80×24 Unicode region, 100 applications: **597.957 / 593.555**.
- Slide, same region/work count: **631.935 / 635.757**.
- Wipe, same region/work count: **467.691 / 467.854**.
- Dissolve, same region/work count: **487.957 / 485.160**.

Both checksums were `1015478`. Timings include output-buffer construction and
effect application; source capture occurs before measurement. They exclude
terminal output, input polling, and emulator rendering. These measurements are
not comparative performance or end-to-end frame-rate guarantees. Workload:
`benchmarks/animation_benchmarks.nim`; logs: `build/animation-bench-{arc,orc}.log`.
