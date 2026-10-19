#!/usr/bin/env python3
"""Regenerate pinned palette-enabled development color fixtures."""
import pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[2]
manifest=root/'tools/colors/reference/Cargo.toml'
subprocess.run(['cargo','build','--locked','--manifest-path',str(manifest)],check=True)
with (root/'tools/colors_fixtures.json').open('w') as output:
    subprocess.run([str(manifest.parent/'target/debug/colors-reference')],stdout=output,check=True)
