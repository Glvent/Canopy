#!/usr/bin/env python3
"""Verify literal calendar dimensions independently through the pinned Rust build."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
subprocess.run(["cargo", "build", "--locked", "--manifest-path", str(root / "tools/reference/Cargo.toml")], check=True)
deps = root / "tools/reference/target/debug/deps"
with tempfile.TemporaryDirectory() as temp:
    binary = pathlib.Path(temp) / "calendar-metrics"
    command = ["rustc", "--edition=2024", str(root / "tools/calendar/oracle.rs"),
               "-L", f"dependency={deps}", "-o", str(binary)]
    for crate in ("ratatui", "time"):
        library = max(deps.glob(f"lib{crate}-*.rlib"), key=lambda p: p.stat().st_mtime_ns)
        command.extend(["--extern", f"{crate}={library}"])
    subprocess.run(command, check=True)
    actual = subprocess.check_output([str(binary)], text=True).strip()
expected = (root / "tests/test_calendar_metrics.nim").read_text().split("const metricCases = [\n", 1)[1].split("\n]", 1)[0].strip()
if actual != expected:
    raise SystemExit("Calendar metric literals differ from the pinned Rust oracle")
print(f"Verified {len(actual.splitlines())} upstream calendar dimensions")
