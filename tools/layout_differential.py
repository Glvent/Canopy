"""Development-only deterministic mixed layout comparison against pinned Rust."""
import json
import hashlib
from collections import Counter
import pathlib
import random
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(['cargo', 'build', '--quiet', '--manifest-path', 'reference/Cargo.toml', '--locked'], cwd=root, check=True)
oracle_binary = pathlib.Path('/tmp/canopy-layout-oracle')
shutil.copy2(root / 'reference/target/debug/canopy-ratatui-reference', oracle_binary)
rng = random.Random(302)
requests = []
for i in range(int(sys.argv[1]) if len(sys.argv) > 1 else 2000):
    constraints = []
    for _ in range(rng.randrange(9)):
        kind = rng.choice(['length', 'min', 'max', 'percentage', 'ratio', 'fill'])
        constraints.append(dict(kind=kind, numerator=rng.randrange(9), denominator=rng.randrange(9))
                           if kind == 'ratio' else dict(kind=kind, value=rng.choice([0, 1, 2, 3, 5, 10, 33, 50, 100, 200, 32767, 32768, 65535])))
    requests.append(dict(name=f'mixed-{i}', direction=rng.choice(['horizontal', 'vertical']),
                         constraints=constraints, flex=rng.choice(['Legacy', 'Start', 'End', 'Center', 'SpaceBetween', 'SpaceAround', 'SpaceEvenly']),
                         spacing=rng.choice([-100, -5, -1, 0, 1, 3, 100, 32767]),
                         margin=dict(horizontal=rng.randrange(3), vertical=rng.randrange(3)),
                         area=dict(x=rng.choice([0, 1, 7, 65530]), y=rng.choice([0, 1, 7, 65530]), width=rng.choice([0, 1, 3, 7, 11, 23, 100, 65535]), height=rng.choice([0, 1, 3, 7, 11, 23, 100, 65535]))))
oracle = subprocess.run([str(oracle_binary), 'layout-oracle'],
                        cwd=root, input=json.dumps(requests), text=True, capture_output=True, check=True)
expected = json.loads(oracle.stdout)
cases = [dict(name=q['name'], input=q, expected=e['expected']) for q, e in zip(requests, expected)]
def save_cases():
    document = dict(schemaVersion=1, ratatui='0.30.2', ratatuiCore='0.1.2', kasuari='0.4.12',
                    seed=302, initialSamples=1,
                    cargoLockSha256=hashlib.sha256((root / 'reference/Cargo.lock').read_bytes()).hexdigest(), cases=cases)
    (root / 'tools/layout_differential_cases.json').write_text(json.dumps(document, separators=(',', ':')) + '\n')
target = pathlib.Path('/tmp/canopy-layout-differential.json')
target.write_text(json.dumps(cases))
print(f'{len(cases)} seeded cases -> {target}', flush=True)
subprocess.run(['nim', 'c', '-d:release', '--path:src', '--out:/tmp/canopy-layout-compare', 'tools/layout_compare.nim'], cwd=root, check=True)
native_path = '/tmp/canopy-layout-native.json'
comparison = subprocess.run(['/tmp/canopy-layout-compare', str(target), native_path], cwd=root)
native = json.loads(pathlib.Path(native_path).read_text())
mismatches = [i for i, (n, e) in enumerate(zip(native, expected)) if n['expected'] != e['expected']]
if not mismatches:
    save_cases()
    sys.exit(0)
observations = {i: Counter([json.dumps(expected[i]['expected'], sort_keys=True)]) for i in mismatches}
for _ in range(50):
    oracle = subprocess.run([str(oracle_binary), 'layout-oracle'],
                            cwd=root, input=json.dumps([requests[i] for i in mismatches]), text=True, capture_output=True, check=True)
    for i, e in zip(mismatches, json.loads(oracle.stdout)):
        observations[i][json.dumps(e['expected'], sort_keys=True)] += 1
unmatched = 0
for i in mismatches:
    observed = json.dumps(native[i]['expected'], sort_keys=True) in observations[i]
    print(f'{requests[i]["name"]}: {len(observations[i])} distinct upstream results; native observed upstream={observed}')
    unmatched += not observed
    cases[i]['expectedAlternatives'] = [json.loads(value) for value in sorted(observations[i])]
    cases[i]['alternativeSampleCounts'] = [observations[i][value] for value in sorted(observations[i])]
    cases[i]['upstreamSamples'] = 51
print(f'{unmatched} native results not observed in 51 upstream samples; exact first-run mismatches={len(mismatches)}')
save_cases()
sys.exit(1 if unmatched else 0)
