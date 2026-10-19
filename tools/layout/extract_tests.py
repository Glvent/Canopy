"""Extract literal upstream letter tests; development-only, no runtime dependency."""
import json
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
cases = []
for flex, width, constraints, expected in re.findall(
    r'#\[case\(Flex::(\w+),\s*(\d+),\s*&\[(.*?)\],\s*"(.*?)"\s*\)\]', source
):
    values = []
    for kind, arguments in re.findall(r'(\w+)\(([^)]*)\)', constraints):
        values.append([kind, *[int(v.strip()) for v in arguments.split(',')]])
    cases.append(dict(flex=flex, width=int(width), constraints=values, expected=expected))
target = pathlib.Path(__file__).resolve().parents[2] / 'tools/layout_upstream_cases.json'
target.write_text(json.dumps(cases, indent=2) + '\n')
print(f'{len(cases)} literal upstream cases -> {target}')
