#!/usr/bin/env python3
"""Compile the independent pinned block oracle and save development fixtures."""
import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[2]
deps=root/'tools/reference/target/debug/deps'
with tempfile.TemporaryDirectory() as tmp:
    binary=pathlib.Path(tmp)/'block-oracle'
    command=['rustc','--edition=2024','-Awarnings',str(root/'tools/block/oracle.rs'),'-L',f'dependency={deps}','-o',str(binary)]
    for crate in ('ratatui','serde_json'):
        library=max(deps.glob(f'lib{crate}-*.rlib'),key=lambda p:p.stat().st_mtime_ns)
        command.extend(['--extern',f'{crate}={library}'])
    subprocess.run(command,check=True)
    path=root/'tests/fixtures/block_matrix.json'
    with path.open('w') as out:subprocess.run([str(binary)],stdout=out,check=True)
    print(f'Generated {path.relative_to(root)} ({path.stat().st_size} bytes)')
