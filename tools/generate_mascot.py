"""Development-only extraction of the MIT Ratatui mascot pixel data."""
import pathlib, re, sys, textwrap, json
source = pathlib.Path(sys.argv[1]).read_text()
art = re.search(r'const RATATUI_MASCOT: &str = indoc::indoc! \{"\n(.*?)"\n\};', source, re.S).group(1)
lines = textwrap.dedent(art).splitlines()
target = pathlib.Path('src/canopy/internal/widgets/mascot_data.nim')
target.write_text('## Ratatui 0.30.2 mascot pixel data (MIT, licenses/ratatui.txt).\nconst MascotPixels* = [\n' + ',\n'.join('  ' + json.dumps(line, ensure_ascii=False) for line in lines) + '\n]\n')
