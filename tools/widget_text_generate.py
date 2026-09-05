#!/usr/bin/env python3
"""Generate text-widget matrix using the pinned reference build's Rust rlibs.
Run cargo build --locked --manifest-path reference/Cargo.toml first.
"""
import pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]
deps=root/"reference/target/debug/deps"
with tempfile.TemporaryDirectory() as temp:
    binary=pathlib.Path(temp)/"widget-text-oracle"
    command=["rustc","--edition=2024","-Awarnings",str(root/"tools/widget_text_oracle.rs"),"-L",f"dependency={deps}","-o",str(binary)]
    for crate in ("ratatui","serde_json"):
        library=max(deps.glob(f"lib{crate}-*.rlib"),key=lambda p:p.stat().st_mtime_ns)
        command.extend(["--extern",f"{crate}={library}"])
    subprocess.run(command,check=True)
    destination=root/"tests/fixtures/widget_text_matrix.json"
    with destination.open("w") as output: subprocess.run([str(binary)],stdout=output,check=True)
    print(f"Generated {destination.relative_to(root)} ({destination.stat().st_size} bytes)")
