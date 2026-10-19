"""Extract unchanged Ratatui 0.30.2 canvas map tables."""
import pathlib
import re
import sys

upstream = pathlib.Path(sys.argv[1])
out = pathlib.Path(__file__).resolve().parent.parent / 'src/canopy/internal/widgets/canvas_tables.nim'
lines = ['## Generated from Ratatui 0.30.2 (MIT); see licenses/canvas-NOTICE.md.', 'const']
content = (upstream / 'ratatui-widgets/src/canvas/world.rs').read_text()
for name in ['WORLD_HIGH_RESOLUTION', 'WORLD_LOW_RESOLUTION']:
    body = re.search(rf'pub static {name}:.*?= \[(.*?)\];', content, re.S)[1]
    points = re.findall(r'\(-?\d+\.\d+,\s*-?\d+\.\d+\)', body)
    assert len(points) == (5125 if name == 'WORLD_HIGH_RESOLUTION' else 1166)
    lines.append(f'  {name}* = [\n    ' + ',\n    '.join(points) + '\n  ]')
out.write_text('\n'.join(lines) + '\n')
print(out)
